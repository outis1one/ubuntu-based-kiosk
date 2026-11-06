'use strict';

// webui/test/auth.test.js - the Web UI login: with the kiosk's password
// protection off the UI is open; with it on, everything needs the kiosk's
// PIN/password. Starts the real server on a random port against a scratch
// config.json. Run with: node test/auth.test.js

const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');

const scratchDir = fs.mkdtempSync(path.join(os.tmpdir(), 'webui-auth-test-'));
process.env.CONFIG_PATH = path.join(scratchDir, 'config.json');
process.env.SUDO_CMD = '';

const app = require('../server');
const { saveConfig } = require('../lib/config');

let failures = 0;
async function check(label, fn) {
    try {
        await fn();
        console.log(`PASS: ${label}`);
    } catch (e) {
        failures++;
        console.log(`FAIL: ${label} - ${e.message}`);
    }
}

async function main() {
    const server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    const post = (url, body, cookie) => fetch(base + url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(cookie ? { cookie } : {}) },
        body: JSON.stringify(body || {}),
    });
    const get = (url, cookie) => fetch(base + url, { headers: cookie ? { cookie } : {} });
    const cookieOf = (res) => (res.headers.get('set-cookie') || '').split(';')[0];

    await check('protection off: no login needed, /api/auth says so', async () => {
        assert.strictEqual((await get('/api/config')).status, 200);
        const a = await (await get('/api/auth')).json();
        assert.strictEqual(a.required, false);
        assert.strictEqual(a.authed, true);
    });

    saveConfig({ enablePasswordProtection: true, newLockoutPassword: 'hunter22' });

    await check('protection on: API calls are refused without a login', async () => {
        const res = await get('/api/config');
        assert.strictEqual(res.status, 401);
        assert.strictEqual((await res.json()).loginRequired, true);
        assert.strictEqual((await post('/api/actions/anything/run')).status, 401);
    });

    await check('protection on: pages get the login screen, not the app', async () => {
        const res = await get('/');
        assert.strictEqual(res.status, 401);
        const html = await res.text();
        assert.ok(html.includes('id="code"'));
        assert.ok(!html.includes('nav-item'));
        assert.strictEqual((await get('/app.js')).status, 401);
    });

    await check('/api/auth reports a login is required, and the code type', async () => {
        const a = await (await get('/api/auth')).json();
        assert.strictEqual(a.required, true);
        assert.strictEqual(a.authed, false);
        assert.strictEqual(a.codeType, 'password');
    });

    await check('a wrong code is refused and gives no session', async () => {
        const res = await post('/api/login', { code: 'nope' });
        assert.strictEqual(res.status, 401);
        assert.strictEqual(res.headers.get('set-cookie'), null);
    });

    let cookie = '';
    await check('the right code gives an HttpOnly session that unlocks the API', async () => {
        const res = await post('/api/login', { code: 'hunter22' });
        assert.strictEqual(res.status, 200);
        const raw = res.headers.get('set-cookie');
        assert.ok(/HttpOnly/i.test(raw) && /SameSite=Strict/i.test(raw));
        cookie = cookieOf(res);
        assert.strictEqual((await get('/api/config', cookie)).status, 200);
        assert.strictEqual((await get('/', cookie)).status, 200);
        assert.strictEqual((await (await get('/api/auth', cookie)).json()).authed, true);
    });

    await check('the stored code hash is never sent to the browser', async () => {
        const text = await (await get('/api/config', cookie)).text();
        assert.ok(!text.includes('lockoutPassword"'));
        assert.ok(!/[0-9a-f]{64}/.test(text));
    });

    await check('saving settings keeps you signed in', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', cookie },
            body: JSON.stringify({ enableNavButton: false }),
        });
        assert.strictEqual(res.status, 200);
    });

    await check('changing the kiosk code signs every browser out', async () => {
        saveConfig({ newLockoutPassword: 'another-one' });
        assert.strictEqual((await get('/api/config', cookie)).status, 401);
        assert.strictEqual((await post('/api/login', { code: 'hunter22' })).status, 401);
        const ok = await post('/api/login', { code: 'another-one' });
        assert.strictEqual(ok.status, 200);
        cookie = cookieOf(ok);
    });

    await check('setting a new code from the Web UI keeps that browser signed in', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', cookie },
            body: JSON.stringify({ newLockoutPassword: 'third-code' }),
        });
        assert.strictEqual(res.status, 200);
        const fresh = cookieOf(res);
        assert.ok(fresh && fresh !== cookie);
        assert.strictEqual((await get('/api/config', fresh)).status, 200);
        assert.strictEqual((await get('/api/config', cookie)).status, 401);
        cookie = fresh;
    });

    await check('sign out ends the session', async () => {
        assert.strictEqual((await post('/api/logout', {}, cookie)).status, 200);
        assert.strictEqual((await get('/api/config', cookie)).status, 401);
    });

    await check('five wrong codes in a row slow logins down - even the right code waits', async () => {
        let last;
        for (let i = 0; i < 5; i++) last = await post('/api/login', { code: 'wrong' + i });
        assert.strictEqual(last.status, 429);
        assert.ok((await last.json()).waitSeconds >= 30);
        assert.strictEqual((await post('/api/login', { code: 'third-code' })).status, 429);
    });

    server.close();
    fs.rmSync(scratchDir, { recursive: true, force: true });
    if (failures > 0) {
        console.log(`${failures} FAILURE(S)`);
        process.exit(1);
    }
    console.log('ALL DONE');
}

main();
