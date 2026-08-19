'use strict';

// webui/server.js - Kiosk Web UI: browser-based config editor for Sites &
// Page Timing, Display & Interaction, and Password Protection & Lockout -
// the three Core Settings menus that are pure config.json read/write with
// no privileged system mutation involved (see menus/addon_webui.sh's
// header for why the rest of Core Settings/Addons/Advanced aren't here).
//
// No login of its own by design: Authelia runs elsewhere, and the admin
// site goes behind the user's own Caddy reverse proxy with Authelia
// forward-auth in front of it, the same way every other self-hosted app
// they run is protected. This process only binds where it's told to
// (BIND_ADDR/PORT below) and trusts whatever's in front of it.
//
// Runs as $KIOSK_USER (see the systemd unit menus/addon_webui.sh
// installs) - the same user Electron runs as, and the owner of
// config.json - so it never needs sudo.

const path = require('path');
const express = require('express');
const { loadConfig, saveConfig } = require('./lib/config');

const app = express();
app.use(express.json({ limit: '256kb' }));
app.use(express.static(path.join(__dirname, 'public')));

const SWIPE_MODES = ['dual', 'standard'];
const NAV_MODES = ['restricted', 'same-origin', 'open'];
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

// Same normalization rule as menus/sites.sh's sites_parse_url(): bare
// host -> https://, bare IPv4 -> http://, else passed through as-is.
function parseUrl(raw) {
    if (/^https?:\/\//.test(raw)) return raw;
    if (/^\d+\.\d+\.\d+\.\d+/.test(raw)) return `http://${raw}`;
    return `https://${raw}`;
}

function badRequest(res, message) {
    res.status(400).json({ error: message });
}

app.get('/api/config', (req, res) => {
    res.json(loadConfig());
});

app.put('/api/config', (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const patch = {};

    if (body.swipeMode !== undefined) {
        if (!SWIPE_MODES.includes(body.swipeMode)) return badRequest(res, 'swipeMode must be "dual" or "standard"');
        patch.swipeMode = body.swipeMode;
    }
    if (body.allowNavigation !== undefined) {
        if (!NAV_MODES.includes(body.allowNavigation)) {
            return badRequest(res, 'allowNavigation must be "restricted", "same-origin", or "open"');
        }
        patch.allowNavigation = body.allowNavigation;
    }
    if (body.enablePauseButton !== undefined) patch.enablePauseButton = !!body.enablePauseButton;
    if (body.enableKeyboardButton !== undefined) patch.enableKeyboardButton = !!body.enableKeyboardButton;
    if (body.enableNavButton !== undefined) patch.enableNavButton = !!body.enableNavButton;

    let tabCount;
    if (body.tabs !== undefined) {
        if (!Array.isArray(body.tabs)) return badRequest(res, 'tabs must be an array');
        for (const t of body.tabs) {
            if (!t || typeof t.url !== 'string' || t.url.trim() === '') return badRequest(res, 'Every site needs a URL');
            const dur = Number(t.duration);
            if (!Number.isInteger(dur) || dur < -1 || dur > 86400) {
                return badRequest(res, 'Duration must be a whole number between -1 and 86400');
            }
        }
        patch.tabs = body.tabs.map((t) => ({ ...t, url: parseUrl(t.url.trim()) }));
        tabCount = patch.tabs.length;
    }

    if (body.homeTabIndex !== undefined) {
        const idx = Number(body.homeTabIndex);
        const count = tabCount !== undefined ? tabCount : loadConfig().tabs.length;
        if (!Number.isInteger(idx) || idx < -1 || idx >= count) return badRequest(res, 'homeTabIndex is out of range');
        patch.homeTabIndex = idx;
    }

    if (body.inactivityTimeoutMinutes !== undefined) {
        const min = Number(body.inactivityTimeoutMinutes);
        if (!Number.isInteger(min) || min < 1 || min > 240) return badRequest(res, 'Inactivity timeout must be 1-240 minutes');
        patch.inactivityTimeout = min * 60;
    }

    if (body.enablePasswordProtection !== undefined) patch.enablePasswordProtection = !!body.enablePasswordProtection;

    if (body.lockoutTimeoutMinutes !== undefined) {
        const min = Number(body.lockoutTimeoutMinutes);
        if (!Number.isInteger(min) || min < 0 || min > 1440) return badRequest(res, 'Lockout timeout must be 0-1440 minutes');
        patch.lockoutTimeout = min;
    }

    if (body.lockoutAtTime !== undefined) {
        if (body.lockoutAtTime !== '' && !TIME_RE.test(body.lockoutAtTime)) {
            return badRequest(res, 'lockoutAtTime must be HH:MM (24-hour) or empty');
        }
        patch.lockoutAtTime = body.lockoutAtTime;
    }

    if (body.requirePasswordOnBoot !== undefined) patch.requirePasswordOnBoot = !!body.requirePasswordOnBoot;

    if (body.newLockoutPassword !== undefined) {
        if (typeof body.newLockoutPassword !== 'string' || body.newLockoutPassword.length === 0) {
            return badRequest(res, 'Password cannot be empty');
        }
        patch.newLockoutPassword = body.newLockoutPassword;
    }

    // Mirrors action_enable_protection() always requiring a password up
    // front - lockout.sh has no path that enables protection without one.
    if (patch.enablePasswordProtection === true) {
        const hasNewPassword = typeof patch.newLockoutPassword === 'string' && patch.newLockoutPassword.length > 0;
        if (!hasNewPassword && !loadConfig().hasLockoutPassword) {
            return badRequest(res, 'Set a lockout password before enabling password protection');
        }
    }

    try {
        res.json(saveConfig(patch));
    } catch (e) {
        console.error('saveConfig failed:', e);
        res.status(500).json({ error: 'Failed to save configuration' });
    }
});

const PORT = process.env.PORT || 8090;
const BIND_ADDR = process.env.BIND_ADDR || '0.0.0.0';

if (require.main === module) {
    app.listen(PORT, BIND_ADDR, () => {
        console.log(`Kiosk Web UI listening on ${BIND_ADDR}:${PORT}`);
    });
}

module.exports = app;
