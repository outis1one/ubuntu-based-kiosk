'use strict';

// webui/lib/config.js - config.json read/write for the web UI.
//
// Mirrors lib/config.sh's load_existing_config()/save_config() contract
// exactly, in JS instead of jq, so the web UI and the terminal menus stay
// in sync against the same file without either one going through the
// other. kiosk-app/main.js already reads this same config.json directly
// in JS (its own fs.readFileSync/JSON.parse, no bash involved) - this is
// established precedent in this repo, not a new pattern.
//
// Tracks exactly the fields Sites & Page Timing (menus/sites.sh),
// Display & Interaction (menus/display.sh), and Password Protection &
// Lockout (menus/lockout.sh) track. lockoutActiveStart/lockoutActiveEnd
// are deliberately excluded, matching lockout.sh's own header comment:
// "the app doesn't act on them... lib/config.sh just carries whatever is
// already in config.json through unchanged." Anything else present in an
// existing file (autheliaURL, autheliaUsername,
// autheliaEncryptedPassword, lockoutActiveStart/End, or any future field)
// is opaque passthrough data - saveConfig() merges onto it, never
// rebuilds from nothing, so none of it is ever silently deleted. That
// exact failure mode was a real, previously-fixed bug in lib/config.sh's
// own history (see its header/body comments) and must not be
// reintroduced here.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CONFIG_PATH = process.env.CONFIG_PATH;
if (!CONFIG_PATH) {
    throw new Error("CONFIG_PATH environment variable is required (path to the kiosk app's config.json)");
}

const SCALAR_DEFAULTS = {
    swipeMode: 'dual',
    allowNavigation: 'same-origin',
    homeTabIndex: -1,
    inactivityTimeout: 120,
    enablePauseButton: true,
    enableKeyboardButton: true,
    enableNavButton: true,
    enablePasswordProtection: false,
    lockoutTimeout: 0,
    lockoutAtTime: '',
    requirePasswordOnBoot: false,
};

function readExisting() {
    try {
        const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
    } catch (e) {
        // Missing file or invalid JSON - same fallback save_config() uses
        // in lib/config.sh ("{}" when the file is absent/unparsable).
    }
    return {};
}

function normalizeTab(t) {
    return {
        url: typeof t.url === 'string' ? t.url : '',
        duration: Number.isFinite(Number(t.duration)) ? Number(t.duration) : 0,
        username: typeof t.username === 'string' ? t.username : '',
        password: typeof t.password === 'string' ? t.password : '',
        name: typeof t.name === 'string' ? t.name : '',
    };
}

function hashPassword(plaintext) {
    return crypto.createHash('sha256').update(plaintext, 'utf8').digest('hex');
}

// Mirrors load_existing_config(). Never returns a site's Basic Auth
// password or the lockout password hash - both are write-only from here,
// same as the terminal menus, which never display a stored password back
// either (sites.sh's edit_page_status only ever shows the username;
// lockout.sh has no "show current password" path at all).
function loadConfig() {
    const existing = readExisting();
    const tabs = Array.isArray(existing.tabs) ? existing.tabs.map(normalizeTab) : [];

    const out = {
        tabs: tabs.map((t) => ({
            url: t.url,
            duration: t.duration,
            username: t.username,
            hasPassword: t.password.length > 0,
            name: t.name,
        })),
    };
    for (const [key, def] of Object.entries(SCALAR_DEFAULTS)) {
        out[key] = key in existing ? existing[key] : def;
    }
    out.hasLockoutPassword = typeof existing.lockoutPassword === 'string' && existing.lockoutPassword.length > 0;
    out.dualSwipe = out.swipeMode === 'dual';
    return out;
}

// Mirrors save_config(): merge known fields onto whatever's already on
// disk (see file header). `patch` fields are applied only when present -
// omitting a field means "leave it as it is", so each frontend section
// (Sites / Display / Lockout) can PUT just the fields it owns.
function saveConfig(patch) {
    const existing = readExisting();
    const merged = { ...existing };

    for (const [key, def] of Object.entries(SCALAR_DEFAULTS)) {
        if (!(key in merged)) merged[key] = def;
    }
    for (const key of Object.keys(SCALAR_DEFAULTS)) {
        if (key in patch) merged[key] = patch[key];
    }

    // Password: only touched when the caller explicitly provides a new
    // plaintext value to hash. Disabling protection clears the whole
    // lockout state, mirroring lockout.sh's action_disable_protection()
    // exactly (not just the enabled flag - the password/timeout/daily
    // lock time too).
    if (!('lockoutPassword' in merged)) merged.lockoutPassword = '';
    if (typeof patch.newLockoutPassword === 'string' && patch.newLockoutPassword.length > 0) {
        merged.lockoutPassword = hashPassword(patch.newLockoutPassword);
    }
    if (patch.enablePasswordProtection === false) {
        merged.lockoutPassword = '';
        merged.lockoutTimeout = 0;
        merged.lockoutAtTime = '';
        merged.requirePasswordOnBoot = false;
    }

    if (Array.isArray(patch.tabs)) {
        const existingTabs = Array.isArray(existing.tabs) ? existing.tabs.map(normalizeTab) : [];
        merged.tabs = patch.tabs.map((t, i) => {
            const norm = normalizeTab(t);
            if (typeof t.password !== 'string') {
                // No new password supplied for this tab - keep whatever
                // was already stored at this position (tabs are
                // positional, not ID-based, matching the bash arrays).
                norm.password = existingTabs[i] ? existingTabs[i].password : '';
            }
            return norm;
        });
    } else if (!Array.isArray(merged.tabs)) {
        merged.tabs = [];
    }

    merged.autoswitch = true;
    merged.enableTouch = true;
    merged.dualSwipe = merged.swipeMode === 'dual';

    const dir = path.dirname(CONFIG_PATH);
    fs.mkdirSync(dir, { recursive: true });
    const tmp = path.join(dir, `.config.json.tmp-${process.pid}-${Date.now()}`);
    fs.writeFileSync(tmp, JSON.stringify(merged, null, 2) + '\n', { mode: 0o644 });
    fs.renameSync(tmp, CONFIG_PATH);

    return loadConfig();
}

module.exports = { loadConfig, saveConfig, CONFIG_PATH, SCALAR_DEFAULTS };
