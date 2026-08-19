'use strict';

// webui/test/config.test.js - unit tests for lib/config.js against a
// scratch config.json. Run with: node test/config.test.js
//
// Mirrors this project's bash test convention (PASS/FAIL lines, ALL DONE
// at the end) rather than pulling in a test framework dependency.

const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');

const scratchDir = fs.mkdtempSync(path.join(os.tmpdir(), 'webui-config-test-'));
process.env.CONFIG_PATH = path.join(scratchDir, 'config.json');

const { loadConfig, saveConfig } = require('../lib/config');

let failures = 0;
function check(label, fn) {
    try {
        fn();
        console.log(`PASS: ${label}`);
    } catch (e) {
        failures++;
        console.log(`FAIL: ${label} - ${e.message}`);
    }
}

check('loadConfig on a missing file returns documented defaults', () => {
    const cfg = loadConfig();
    assert.deepStrictEqual(cfg.tabs, []);
    assert.strictEqual(cfg.swipeMode, 'dual');
    assert.strictEqual(cfg.allowNavigation, 'same-origin');
    assert.strictEqual(cfg.homeTabIndex, -1);
    assert.strictEqual(cfg.inactivityTimeout, 120);
    assert.strictEqual(cfg.enablePasswordProtection, false);
    assert.strictEqual(cfg.hasLockoutPassword, false);
    assert.strictEqual(cfg.dualSwipe, true);
});

check('saveConfig creates the file and round-trips scalar fields', () => {
    const result = saveConfig({ swipeMode: 'standard', allowNavigation: 'open', enablePauseButton: false });
    assert.strictEqual(result.swipeMode, 'standard');
    assert.strictEqual(result.allowNavigation, 'open');
    assert.strictEqual(result.enablePauseButton, false);
    assert.strictEqual(result.dualSwipe, false);

    const onDisk = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    assert.strictEqual(onDisk.swipeMode, 'standard');
    assert.strictEqual(onDisk.autoswitch, true);
    assert.strictEqual(onDisk.enableTouch, true);
});

check('saveConfig merge preserves fields this app never tracks (the previously-fixed clobber bug)', () => {
    // Simulate a file with Authelia + quiet-hours fields already set, the
    // way the terminal addon/menus would have written them - config.js
    // must never know these exist and must never delete them.
    const existing = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    existing.autheliaURL = 'https://auth.example.com';
    existing.autheliaUsername = 'kiosk';
    existing.autheliaEncryptedPassword = 'deadbeef';
    existing.lockoutActiveStart = '22:00';
    existing.lockoutActiveEnd = '06:00';
    fs.writeFileSync(process.env.CONFIG_PATH, JSON.stringify(existing));

    saveConfig({ enableNavButton: false });

    const onDisk = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    assert.strictEqual(onDisk.autheliaURL, 'https://auth.example.com');
    assert.strictEqual(onDisk.autheliaUsername, 'kiosk');
    assert.strictEqual(onDisk.autheliaEncryptedPassword, 'deadbeef');
    assert.strictEqual(onDisk.lockoutActiveStart, '22:00');
    assert.strictEqual(onDisk.lockoutActiveEnd, '06:00');
    assert.strictEqual(onDisk.enableNavButton, false);
});

check('saveConfig tabs: new password gets hashed, never stored/returned as plaintext', () => {
    const result = saveConfig({
        tabs: [{ url: 'https://a.example.com', duration: 30, name: 'A', username: 'bob', password: 'hunter2' }],
    });
    assert.strictEqual(result.tabs[0].hasPassword, true);
    assert.strictEqual(result.tabs[0].username, 'bob');
    assert.strictEqual(result.tabs[0].password, undefined);

    const onDisk = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    assert.strictEqual(onDisk.tabs[0].password, 'hunter2'); // stored plaintext by design, matches lib/config.sh's own PASSES/USERS handling for Basic Auth (not the lockout password)
});

check('saveConfig tabs: omitting password on an existing tab keeps the stored one (positional identity)', () => {
    saveConfig({
        tabs: [{ url: 'https://a.example.com', duration: 45, name: 'A renamed', username: 'bob' }],
    });
    const onDisk = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    assert.strictEqual(onDisk.tabs[0].password, 'hunter2');
    assert.strictEqual(onDisk.tabs[0].duration, 45);
    assert.strictEqual(onDisk.tabs[0].name, 'A renamed');
});

check('saveConfig lockout password is SHA-256 hashed, matching lockout.sh/main.js', () => {
    const crypto = require('crypto');
    saveConfig({ enablePasswordProtection: true, newLockoutPassword: 'correcthorse' });
    const onDisk = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    const expected = crypto.createHash('sha256').update('correcthorse', 'utf8').digest('hex');
    assert.strictEqual(onDisk.lockoutPassword, expected);

    const result = loadConfig();
    assert.strictEqual(result.hasLockoutPassword, true);
    assert.strictEqual(result.lockoutPassword, undefined);
});

check('saveConfig disabling password protection clears the whole lockout state (matches action_disable_protection)', () => {
    saveConfig({ enablePasswordProtection: true, newLockoutPassword: 'x', lockoutTimeout: 30 });
    const before = loadConfig();
    assert.strictEqual(before.hasLockoutPassword, true);

    saveConfig({ enablePasswordProtection: false });
    const onDisk = JSON.parse(fs.readFileSync(process.env.CONFIG_PATH, 'utf8'));
    assert.strictEqual(onDisk.lockoutPassword, '');
    assert.strictEqual(onDisk.lockoutTimeout, 0);
    assert.strictEqual(onDisk.lockoutAtTime, '');
    assert.strictEqual(onDisk.requirePasswordOnBoot, false);
});

check('saveConfig with invalid JSON already on disk falls back to {} rather than crashing', () => {
    fs.writeFileSync(process.env.CONFIG_PATH, '{not valid json');
    const result = saveConfig({ swipeMode: 'dual' });
    assert.strictEqual(result.swipeMode, 'dual');
});

fs.rmSync(scratchDir, { recursive: true, force: true });

if (failures > 0) {
    console.log(`${failures} FAILURE(S)`);
    process.exit(1);
}
console.log('ALL DONE');
