'use strict';

// webui/test/api.test.js - integration test: starts the real server.js
// app on a random port against a scratch config.json and hits GET/PUT
// /api/config with real HTTP requests (Node's built-in fetch). Run with:
// node test/api.test.js

const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');

const scratchDir = fs.mkdtempSync(path.join(os.tmpdir(), 'webui-api-test-'));
process.env.CONFIG_PATH = path.join(scratchDir, 'config.json');

const app = require('../server');

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
    const port = server.address().port;
    const base = `http://127.0.0.1:${port}`;

    await check('GET /api/config returns defaults on a fresh install', async () => {
        const res = await fetch(`${base}/api/config`);
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.deepStrictEqual(body.tabs, []);
        assert.strictEqual(body.swipeMode, 'dual');
    });

    await check('PUT /api/config saves and round-trips display settings', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ swipeMode: 'standard', allowNavigation: 'restricted', enableNavButton: false }),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.swipeMode, 'standard');
        assert.strictEqual(body.allowNavigation, 'restricted');
        assert.strictEqual(body.enableNavButton, false);
    });

    await check('PUT rejects an invalid allowNavigation value', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ allowNavigation: 'wide-open' }),
        });
        assert.strictEqual(res.status, 400);
    });

    await check('PUT rejects a duration out of range', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ tabs: [{ url: 'example.com', duration: 999999 }] }),
        });
        assert.strictEqual(res.status, 400);
    });

    await check('PUT normalizes bare hostnames/IPs the same way sites_parse_url does', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                tabs: [
                    { url: 'example.com', duration: 30, name: 'bare host' },
                    { url: '192.168.1.50', duration: 30, name: 'bare ip' },
                    { url: 'https://already.example.com', duration: 30, name: 'already a url' },
                    { url: '/home/kiosk/docs/menu #2.pdf', duration: 30, name: 'local path' },
                    { url: 'file:///srv/kiosk/index.html', duration: 30, name: 'already a file url' },
                ],
            }),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.tabs[0].url, 'https://example.com');
        assert.strictEqual(body.tabs[1].url, 'http://192.168.1.50');
        assert.strictEqual(body.tabs[2].url, 'https://already.example.com');
        assert.strictEqual(body.tabs[3].url, 'file:///home/kiosk/docs/menu%20%232.pdf');
        assert.strictEqual(body.tabs[4].url, 'file:///srv/kiosk/index.html');
    });

    await check('PUT rejects homeTabIndex out of range', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ homeTabIndex: 99 }),
        });
        assert.strictEqual(res.status, 400);
    });

    await check('PUT accepts a valid homeTabIndex and converts inactivity minutes to stored seconds', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ homeTabIndex: 1, inactivityTimeoutMinutes: 5 }),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.homeTabIndex, 1);
        assert.strictEqual(body.inactivityTimeout, 300);

        const onDisk = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
        assert.strictEqual(onDisk.inactivityTimeout, 300);
    });

    await check('PUT rejects enabling password protection with no password set', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ enablePasswordProtection: true }),
        });
        assert.strictEqual(res.status, 400);
    });

    await check('PUT enables password protection when a new password is supplied, and never echoes it back', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ enablePasswordProtection: true, newLockoutPassword: 'hunter2', lockoutTimeoutMinutes: 15 }),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.enablePasswordProtection, true);
        assert.strictEqual(body.hasLockoutPassword, true);
        assert.strictEqual(body.lockoutPassword, undefined);
        assert.strictEqual(JSON.stringify(body).includes('hunter2'), false);
    });

    const put = (body) => fetch(`${base}/api/config`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
    });
    const onDisk = () => JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    const sha = (v) => require('crypto').createHash('sha256').update(v).digest('hex');

    await check('PUT rejects switching to a PIN without a new code', async () => {
        const res = await put({ lockoutCodeType: 'pin' });
        assert.strictEqual(res.status, 400);
        assert.strictEqual(onDisk().lockoutCodeType || 'password', 'password');
    });

    await check('PUT rejects a PIN that is not 4-8 digits', async () => {
        for (const pin of ['123', '123456789', '12a4']) {
            const res = await put({ lockoutCodeType: 'pin', newLockoutPassword: pin });
            assert.strictEqual(res.status, 400, pin);
        }
    });

    await check('PUT switches the unlock code to a 4-digit PIN', async () => {
        const res = await put({ lockoutCodeType: 'pin', newLockoutPassword: '4821' });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.lockoutCodeType, 'pin');
        assert.strictEqual(onDisk().lockoutPassword, sha('4821'));
    });

    await check('PUT sets a separate boot password, never echoed back', async () => {
        let res = await put({ requirePasswordOnBoot: true, bootCodeMode: 'separate', bootCodeType: 'password' });
        assert.strictEqual(res.status, 400, 'separate boot code without one entered');
        res = await put({ requirePasswordOnBoot: true, bootCodeMode: 'separate', bootCodeType: 'password', newBootPassword: 'boot pass!' });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.hasBootPassword, true);
        assert.strictEqual(body.bootCodeType, 'password');
        assert.strictEqual(JSON.stringify(body).includes('boot pass!'), false);
        assert.strictEqual(onDisk().bootPassword, sha('boot pass!'));
        assert.strictEqual(onDisk().lockoutPassword, sha('4821'), 'unlock PIN untouched');
    });

    await check('PUT keeps the boot code when saved again without a new one', async () => {
        const res = await put({ bootCodeMode: 'separate', bootCodeType: 'password' });
        assert.strictEqual(res.status, 200);
        assert.strictEqual(onDisk().bootPassword, sha('boot pass!'));
    });

    await check('PUT requires a new boot code when its type changes, and checks PIN format', async () => {
        let res = await put({ bootCodeMode: 'separate', bootCodeType: 'pin' });
        assert.strictEqual(res.status, 400);
        res = await put({ bootCodeMode: 'separate', bootCodeType: 'pin', newBootPassword: '12' });
        assert.strictEqual(res.status, 400);
        res = await put({ bootCodeMode: 'separate', bootCodeType: 'pin', newBootPassword: '90210777' });
        assert.strictEqual(res.status, 200);
        assert.strictEqual(onDisk().bootCodeType, 'pin');
        assert.strictEqual(onDisk().bootPassword, sha('90210777'));
    });

    await check('PUT bootCodeMode "same" clears the separate boot code', async () => {
        const res = await put({ bootCodeMode: 'same' });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.hasBootPassword, false);
        assert.strictEqual(onDisk().bootPassword, '');
    });

    await check('PUT disabling protection clears PIN type and boot code too', async () => {
        await put({ bootCodeMode: 'separate', bootCodeType: 'pin', newBootPassword: '5555' });
        const res = await put({ enablePasswordProtection: false });
        assert.strictEqual(res.status, 200);
        const d = onDisk();
        assert.strictEqual(d.lockoutPassword, '');
        assert.strictEqual(d.lockoutCodeType, 'password');
        assert.strictEqual(d.bootPassword, '');
        // back to the state the next test expects
        await put({ enablePasswordProtection: true, newLockoutPassword: 'hunter2', lockoutTimeoutMinutes: 15 });
    });

    await check('PUT rejects a malformed lockoutAtTime', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ lockoutAtTime: '25:99' }),
        });
        assert.strictEqual(res.status, 400);
    });

    await check('PUT re-enabling protection without a new password succeeds once one is already set', async () => {
        const res = await fetch(`${base}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ enablePasswordProtection: true, lockoutTimeoutMinutes: 20 }),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.lockoutTimeout, 20);
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
