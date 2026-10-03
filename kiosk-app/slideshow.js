// Folder slideshow support for main.js.
//
// A site whose URL is a local folder (file:///home/kiosk/photos, entered
// in the Sites menu or Web UI as /home/kiosk/photos/) is shown as a
// full-screen slideshow of the images and Word documents (.docx) in it,
// instead of Chromium's directory listing. main.js swaps the folder URL
// for slideshow.html via resolveSiteUrl(), then attach() hands the page
// its item list - the page itself has no filesystem access
// (contextIsolation, no Node). The folder is re-read every minute, so
// files added, removed or changed show up without restarting the kiosk.
//
// Images load directly by file:// URL. A document's bytes are fetched on
// demand: the page sets its title to TITLE_REQUEST + the document's URL,
// and attach() answers via kioskSlideshow.docData() - but only for a
// .docx in that slideshow's own current item list, so a page can't use
// this to read anything else on disk.
//
// Optional slideshow.json in the folder (all keys optional):
//   { "interval": 10,        seconds per image (default 10, minimum 2)
//     "docInterval": 20,     seconds per document (default 2x interval,
//                            minimum 5); a document longer than the
//                            screen scrolls slowly top to bottom in it
//     "shuffle": false,      random order instead of by file name
//     "fit": "contain",      images: "contain" (whole image, letterboxed)
//                            or "cover" (fill the screen, cropped)
//     "transition": 1,       crossfade seconds (0 = instant cut)
//     "recursive": false }   include files in subfolders

const fs = require('fs');
const path = require('path');
const { fileURLToPath, pathToFileURL } = require('url');

const SLIDESHOW_PAGE = path.join(__dirname, 'slideshow.html');
const IMAGE_EXT = new Set(['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.avif']);
const DOC_EXT = new Set(['.docx']);
const REFRESH_MS = 60000;
const MAX_DOC_BYTES = 50 * 1024 * 1024;
const TITLE_REQUEST = 'kiosk-slideshow-need:';
const DEFAULTS = { interval: 10, docInterval: null, shuffle: false, fit: 'contain', transition: 1, recursive: false };

// The folder path a site URL points at, or null if it isn't a slideshow.
// A file:// URL counts when it's an existing directory, or ends in "/"
// (so a folder that isn't there yet - e.g. a USB stick not plugged in -
// still shows the slideshow's "nothing to show" message, not an error).
function slideshowDir(url) {
    if (typeof url !== 'string' || !url.startsWith('file://')) return null;
    let p;
    try {
        p = fileURLToPath(url);
    } catch (e) {
        return null;
    }
    if (url.endsWith('/')) return p;
    try {
        return fs.statSync(p).isDirectory() ? p : null;
    } catch (e) {
        return null;
    }
}

// What a view should actually load for a configured site URL.
function resolveSiteUrl(url) {
    const dir = slideshowDir(url);
    if (!dir) return url;
    const u = pathToFileURL(SLIDESHOW_PAGE);
    u.searchParams.set('dir', dir);
    return u.href;
}

function readOptions(dir) {
    const opts = { ...DEFAULTS };
    let user = {};
    try {
        user = JSON.parse(fs.readFileSync(path.join(dir, 'slideshow.json'), 'utf8'));
    } catch (e) {
        // No (or unreadable) slideshow.json - defaults.
    }
    if (Number(user.interval) > 0) opts.interval = Math.max(2, Number(user.interval));
    opts.docInterval = Number(user.docInterval) > 0 ? Math.max(5, Number(user.docInterval)) : opts.interval * 2;
    if (typeof user.shuffle === 'boolean') opts.shuffle = user.shuffle;
    if (user.fit === 'contain' || user.fit === 'cover') opts.fit = user.fit;
    if (Number(user.transition) >= 0) opts.transition = Math.min(Number(user.transition), opts.interval / 2);
    if (typeof user.recursive === 'boolean') opts.recursive = user.recursive;
    return opts;
}

function listItems(dir, recursive, depth = 0) {
    let entries;
    try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
        return [];
    }
    const out = [];
    for (const e of entries) {
        // Skip hidden files and Word's "~$name.docx" lock files.
        if (e.name.startsWith('.') || e.name.startsWith('~$')) continue;
        const full = path.join(dir, e.name);
        const ext = path.extname(e.name).toLowerCase();
        if (e.isDirectory()) {
            if (recursive && depth < 8) out.push(...listItems(full, recursive, depth + 1));
        } else if (IMAGE_EXT.has(ext)) {
            out.push({ path: full, type: 'image' });
        } else if (DOC_EXT.has(ext)) {
            let mtime = 0;
            try { mtime = fs.statSync(full).mtimeMs; } catch (err) { /* listed but gone */ }
            out.push({ path: full, type: 'docx', mtime });
        }
    }
    return out;
}

function snapshot(dir) {
    const options = readOptions(dir);
    const items = listItems(dir, options.recursive)
        .sort((a, b) => a.path.localeCompare(b.path, undefined, { numeric: true, sensitivity: 'base' }))
        .map((it) => ({ url: pathToFileURL(it.path).href, type: it.type, ...(it.mtime ? { mtime: it.mtime } : {}) }));
    return { dir, exists: fs.existsSync(dir), options, items };
}

function readDoc(fileUrl) {
    try {
        const file = fileURLToPath(fileUrl);
        const st = fs.statSync(file);
        if (st.size > MAX_DOC_BYTES) return { error: `too large (${Math.round(st.size / 1048576)} MB)` };
        return { mtime: st.mtimeMs, data: fs.readFileSync(file).toString('base64') };
    } catch (e) {
        return { error: e.code === 'ENOENT' ? 'file not found' : e.message };
    }
}

// Feed a view's slideshow page its item list now and every REFRESH_MS
// while it stays on a slideshow, and answer its document requests. Call
// once per view (main.js does, right after creating it); safe on views
// that never show a slideshow.
function attach(webContents) {
    const pagePrefix = pathToFileURL(SLIDESHOW_PAGE).href;
    let lastSent = '';
    let current = null; // latest snapshot sent to the page

    const onSlideshow = () => !webContents.isDestroyed() && webContents.getURL().startsWith(pagePrefix);

    const send = (force) => {
        if (!onSlideshow()) return;
        const dir = new URL(webContents.getURL()).searchParams.get('dir');
        if (!dir) return;
        const snap = snapshot(dir);
        const payload = JSON.stringify(snap);
        if (!force && payload === lastSent) return;
        lastSent = payload;
        current = snap;
        webContents.executeJavaScript(`window.kioskSlideshow&&window.kioskSlideshow.update(${payload})`)
            .catch(() => {});
    };

    webContents.on('did-finish-load', () => send(true));
    webContents.on('page-title-updated', (event, title) => {
        if (!title.startsWith(TITLE_REQUEST) || !onSlideshow() || !current) return;
        const url = title.slice(TITLE_REQUEST.length);
        if (!current.items.some((it) => it.type === 'docx' && it.url === url)) return;
        const doc = readDoc(url);
        webContents.executeJavaScript(
            `window.kioskSlideshow&&window.kioskSlideshow.docData(${JSON.stringify(url)},${JSON.stringify(doc)})`,
        ).catch(() => {});
    });
    const timer = setInterval(() => send(false), REFRESH_MS);
    webContents.once('destroyed', () => clearInterval(timer));
}

module.exports = { resolveSiteUrl, slideshowDir, attach, snapshot, TITLE_REQUEST };
