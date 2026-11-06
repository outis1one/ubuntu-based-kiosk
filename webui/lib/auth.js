'use strict';

// webui/lib/auth.js - login for the Web UI, using the SAME code the kiosk's
// lock screen uses (Core Settings -> Password Protection & Lockout: a PIN or
// a password).
//
// Only when the kiosk's password protection is on. With it off, the Web UI
// is open as before (it is meant for a trusted LAN, or behind a reverse
// proxy with its own login - see server.js).
//
// A correct code gives the browser a random session cookie (kept in memory;
// a restart of the service logs everyone out). Wrong codes are slowed down
// the same way the lock screen does it: after 5 wrong tries in a row, a
// wait of 30 s that doubles up to 5 minutes. Changing the kiosk's code logs
// every browser out, because sessions are tied to the stored code.

const crypto = require('crypto');
const { readLockSettings, hashPassword } = require('./config');

const COOKIE = 'kioskwebui';
const SESSION_MS = 12 * 60 * 60 * 1000; // 12 hours
const FREE_TRIES = 5;
const BASE_WAIT_S = 30;
const MAX_WAIT_S = 300;

const sessions = new Map(); // token -> { expires, fp }
let failures = 0;
let blockedUntil = 0;

// A short fingerprint of the stored code: sessions stop working when it changes.
const fingerprint = (hash) => crypto.createHash('sha256').update('fp:' + hash).digest('hex');

function parseCookies(header) {
    const out = {};
    for (const part of String(header || '').split(';')) {
        const i = part.indexOf('=');
        if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
    }
    return out;
}

function currentSession(req, lock) {
    const token = parseCookies(req.headers.cookie)[COOKIE];
    if (!token) return null;
    const s = sessions.get(token);
    if (!s) return null;
    if (s.expires < Date.now() || s.fp !== fingerprint(lock.hash)) {
        sessions.delete(token);
        return null;
    }
    return token;
}

function setCookie(res, token, maxAgeS) {
    // HttpOnly + SameSite=Strict: not readable by page scripts, and not sent
    // on requests that start from another site. No Secure flag - this is
    // normally plain http on a LAN.
    res.setHeader('Set-Cookie', `${COOKIE}=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${maxAgeS}`);
}

function issueSession(res, lock) {
    for (const [t, s] of sessions) if (s.expires < Date.now()) sessions.delete(t);
    const token = crypto.randomBytes(32).toString('hex');
    sessions.set(token, { expires: Date.now() + SESSION_MS, fp: fingerprint(lock.hash) });
    setCookie(res, token, SESSION_MS / 1000);
}

function codeMatches(code, hash) {
    const a = Buffer.from(hashPassword(code), 'hex');
    const b = Buffer.from(hash, 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// POST /api/login  { code }
function login(req, res) {
    const lock = readLockSettings();
    if (!lock.enabled) return res.json({ ok: true, required: false });

    const wait = Math.ceil((blockedUntil - Date.now()) / 1000);
    if (wait > 0) {
        return res.status(429).json({ ok: false, waitSeconds: wait, error: `Too many wrong tries - wait ${wait}s` });
    }
    const code = req.body && typeof req.body.code === 'string' ? req.body.code : '';
    if (code && codeMatches(code, lock.hash)) {
        failures = 0;
        issueSession(res, lock);
        return res.json({ ok: true });
    }
    failures++;
    const what = lock.codeType === 'pin' ? 'PIN' : 'password';
    if (failures >= FREE_TRIES) {
        const waitS = Math.min(MAX_WAIT_S, BASE_WAIT_S * 2 ** (failures - FREE_TRIES));
        blockedUntil = Date.now() + waitS * 1000;
        return res.status(429).json({ ok: false, waitSeconds: waitS, error: `Too many wrong tries - wait ${waitS}s` });
    }
    return res.status(401).json({ ok: false, error: `Incorrect ${what}` });
}

// POST /api/logout
function logout(req, res) {
    const token = parseCookies(req.headers.cookie)[COOKIE];
    if (token) sessions.delete(token);
    setCookie(res, '', 0);
    res.json({ ok: true });
}

// GET /api/auth - open to everyone: tells the page whether to show a login.
function status(req, res) {
    const lock = readLockSettings();
    res.json({
        required: lock.enabled,
        authed: !lock.enabled || !!currentSession(req, lock),
        codeType: lock.codeType,
    });
}

// Gate for everything else. With protection off it lets everything through.
// Without a session: API calls get a 401, page requests get the login page.
function requireLogin(loginPage) {
    return (req, res, next) => {
        const lock = readLockSettings();
        if (!lock.enabled) return next();
        if (currentSession(req, lock)) return next();

        // The few things the login page itself needs.
        if (req.path === '/api/login' || req.path === '/api/auth' || req.path === '/style.css') return next();
        if (req.path.startsWith('/api/')) {
            return res.status(401).json({ error: 'Login required', loginRequired: true });
        }
        res.status(401).sendFile(loginPage);
    };
}

// After a successful save that left protection on (e.g. the code was just
// set or changed), keep the person who saved it logged in.
function keepLoggedInAfterSave(res) {
    const lock = readLockSettings();
    if (lock.enabled) issueSession(res, lock);
}

module.exports = { requireLogin, login, logout, status, keepLoggedInAfterSave, _sessions: sessions };
