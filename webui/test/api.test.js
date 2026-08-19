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
                ],
            }),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.strictEqual(body.tabs[0].url, 'https://example.com');
        assert.strictEqual(body.tabs[1].url, 'http://192.168.1.50');
        assert.strictEqual(body.tabs[2].url, 'https://already.example.com');
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
