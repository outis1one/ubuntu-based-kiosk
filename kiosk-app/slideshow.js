// Folder slideshow support for main.js.
//
// A site whose URL is a local folder (file:///home/kiosk/photos, entered
// in the Sites menu or Web UI as /home/kiosk/photos/) is shown as a
// full-screen slideshow of the images in it, instead of Chromium's
// directory listing. main.js swaps the folder URL for slideshow.html via
// resolveSiteUrl(), then hands the page its image list with attach() -
// the page itself has no filesystem access (contextIsolation, no Node).
// The folder is re-read every minute, so images added or removed show up
// without restarting the kiosk.
//
// Optional slideshow.json in the folder (all keys optional):
//   { "interval": 10,        seconds per image (default 10, minimum 2)
//     "shuffle": false,      random order instead of by file name
//     "fit": "contain",      "contain" (whole image, letterboxed) or
//                            "cover" (fill the screen, cropped)
//     "transition": 1,       crossfade seconds (0 = instant cut)
//     "recursive": false }   include images in subfolders

const fs = require('fs');
const path = require('path');
const { fileURLToPath, pathToFileURL } = require('url');

const SLIDESHOW_PAGE = path.join(__dirname, 'slideshow.html');
const IMAGE_EXT = new Set(['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.avif']);
const REFRESH_MS = 60000;
const DEFAULTS = { interval: 10, shuffle: false, fit: 'contain', transition: 1, recursive: false };

// The folder path a site URL points at, or null if it isn't a slideshow.
// A file:// URL counts when it's an existing directory, or ends in "/"
// (so a folder that isn't there yet - e.g. a USB stick not plugged in -
// still shows the slideshow's "no images" message, not an error page).
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
    try {
        const user = JSON.parse(fs.readFileSync(path.join(dir, 'slideshow.json'), 'utf8'));
        if (Number(user.interval) > 0) opts.interval = Math.max(2, Number(user.interval));
        if (typeof user.shuffle === 'boolean') opts.shuffle = user.shuffle;
        if (user.fit === 'contain' || user.fit === 'cover') opts.fit = user.fit;
        if (Number(user.transition) >= 0) opts.transition = Math.min(Number(user.transition), opts.interval / 2);
        if (typeof user.recursive === 'boolean') opts.recursive = user.recursive;
    } catch (e) {
        // No (or unreadable) slideshow.json - defaults.
    }
    return opts;
}

function listImages(dir, recursive, depth = 0) {
    let entries;
    try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
        return [];
    }
    const out = [];
    for (const e of entries) {
        if (e.name.startsWith('.')) continue;
        const full = path.join(dir, e.name);
        if (e.isDirectory()) {
            if (recursive && depth < 8) out.push(...listImages(full, recursive, depth + 1));
        } else if (IMAGE_EXT.has(path.extname(e.name).toLowerCase())) {
            out.push(full);
        }
    }
    return out;
}

function snapshot(dir) {
    const options = readOptions(dir);
    const files = listImages(dir, options.recursive)
        .sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));
    return {
        dir,
        exists: fs.existsSync(dir),
        options,
        images: files.map((f) => pathToFileURL(f).href),
    };
}

// Feed a view's slideshow page its image list now and every REFRESH_MS
// while it stays on a slideshow. Call once per view (main.js does, right
// after creating it); safe on views that never show a slideshow.
function attach(webContents) {
    let lastSent = '';
    const send = (force) => {
        if (webContents.isDestroyed()) return;
        const current = webContents.getURL();
        if (!current.startsWith(pathToFileURL(SLIDESHOW_PAGE).href)) return;
        const dir = new URL(current).searchParams.get('dir');
        if (!dir) return;
        const payload = JSON.stringify(snapshot(dir));
        if (!force && payload === lastSent) return;
        lastSent = payload;
        webContents.executeJavaScript(`window.kioskSlideshow&&window.kioskSlideshow.update(${payload})`)
            .catch(() => {});
    };
    webContents.on('did-finish-load', () => send(true));
    const timer = setInterval(() => send(false), REFRESH_MS);
    webContents.once('destroyed', () => clearInterval(timer));
}

module.exports = { resolveSiteUrl, slideshowDir, attach, snapshot };
