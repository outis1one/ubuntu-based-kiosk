// Word document (.docx) support for main.js.
//
// A site whose URL is a local .docx file (file:///home/kiosk/docs/menu.docx,
// entered in the Sites menu or Web UI as /home/kiosk/docs/menu.docx) is
// rendered with docx-preview (an npm dependency of this app - pure
// JavaScript, works offline) instead of Chromium offering to download it.
// main.js swaps the file URL for docview.html via resolveSiteUrl(), then
// attach() hands the page the file's bytes - the page itself has no
// filesystem access (contextIsolation, no Node). The file is re-checked
// every minute and re-rendered if it changed, so replacing the document
// on disk updates the kiosk without a restart.
//
// Only .docx (Word 2007+). Old binary .doc and LibreOffice .odt aren't
// supported by docx-preview - save those as .docx or PDF.

const fs = require('fs');
const path = require('path');
const { fileURLToPath, pathToFileURL } = require('url');

const VIEWER_PAGE = path.join(__dirname, 'docview.html');
const REFRESH_MS = 60000;
const MAX_BYTES = 50 * 1024 * 1024;

// The .docx path a site URL points at, or null.
function docxPath(url) {
    if (typeof url !== 'string' || !url.startsWith('file://')) return null;
    let p;
    try {
        p = fileURLToPath(url);
    } catch (e) {
        return null;
    }
    return path.extname(p).toLowerCase() === '.docx' ? p : null;
}

// What a view should actually load for a configured site URL.
function resolveSiteUrl(url) {
    const file = docxPath(url);
    if (!file) return url;
    const u = pathToFileURL(VIEWER_PAGE);
    u.searchParams.set('file', file);
    return u.href;
}

function readDoc(file) {
    try {
        const st = fs.statSync(file);
        if (st.size > MAX_BYTES) return { file, error: `Document is too large to show (${Math.round(st.size / 1048576)} MB).` };
        return { file, mtime: st.mtimeMs, data: fs.readFileSync(file).toString('base64') };
    } catch (e) {
        return { file, error: e.code === 'ENOENT' ? `File not found: ${file}` : `Can't read ${file}: ${e.message}` };
    }
}

// Feed a view's viewer page the document now and again whenever the file
// changes. Call once per view; safe on views that never show a document.
function attach(webContents) {
    let lastKey = '';
    const send = (force) => {
        if (webContents.isDestroyed()) return;
        const current = webContents.getURL();
        if (!current.startsWith(pathToFileURL(VIEWER_PAGE).href)) return;
        const file = new URL(current).searchParams.get('file');
        if (!file) return;
        let key;
        try {
            const st = fs.statSync(file);
            key = `${st.mtimeMs}:${st.size}`;
        } catch (e) {
            key = 'missing';
        }
        if (!force && key === lastKey) return;
        lastKey = key;
        webContents.executeJavaScript(`window.kioskDocView&&window.kioskDocView.show(${JSON.stringify(readDoc(file))})`)
            .catch(() => {});
    };
    webContents.on('did-finish-load', () => send(true));
    const timer = setInterval(() => send(false), REFRESH_MS);
    webContents.once('destroyed', () => clearInterval(timer));
}

module.exports = { resolveSiteUrl, docxPath, attach };
