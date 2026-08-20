'use strict';

// webui/test/jobs.test.js - integration test for the addon-install job
// system (/api/actions/*, /api/addons/status) against a fake helper
// script (test/fixtures/fake-helper.sh) instead of the real, root-owned
// kiosk-webui-helper - no real root, apt, or system mutation involved,
// matching this project's rule of never touching real system state in
// tests. Run with: node test/jobs.test.js

const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');

const scratchDir = fs.mkdtempSync(path.join(os.tmpdir(), 'webui-jobs-test-'));
process.env.CONFIG_PATH = path.join(scratchDir, 'config.json');
process.env.HELPER_PATH = path.join(__dirname, 'fixtures', 'fake-helper.sh');
process.env.SUDO_CMD = ''; // run the fake helper directly, no real sudo

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

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForDone(base, jobId, timeoutMs = 3000) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
        const res = await fetch(`${base}/api/actions/jobs/${jobId}`);
        const body = await res.json();
        if (body.status !== 'running') return body;
        await sleep(20);
    }
    throw new Error('timed out waiting for job to finish');
}

async function main() {
    const server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const port = server.address().port;
    const base = `http://127.0.0.1:${port}`;

    await check('GET /api/actions lists the allow-listed actions with their fields', async () => {
        const res = await fetch(`${base}/api/actions`);
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        const names = body.map((a) => a.name);
        assert.ok(names.includes('install_cups'));
        assert.ok(names.includes('configure_asterisk_intercom'));
        const asterisk = body.find((a) => a.name === 'configure_asterisk_intercom');
        assert.ok(asterisk.fields.includes('serverIp'));
    });

    await check('GET /api/addons/status returns the fake helper\'s status_all JSON', async () => {
        // fake-helper.sh doesn't implement status_all specially - it just
        // echoes/exits 0 with non-JSON text, so this exercises the
        // malformed-response error path rather than a real status shape.
        const res = await fetch(`${base}/api/addons/status`);
        assert.strictEqual(res.status, 500);
    });

    let jobId;
    await check('POST /api/actions/install_cups/run starts a job and returns its id', async () => {
        const res = await fetch(`${base}/api/actions/install_cups/run`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({}),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        assert.ok(body.jobId);
        assert.strictEqual(body.status, 'running');
        jobId = body.jobId;
    });

    await check('a second action while one is running is rejected with 409', async () => {
        const res = await fetch(`${base}/api/actions/reconfigure_cups/run`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({}),
        });
        assert.strictEqual(res.status, 409);
    });

    await check('the job completes successfully and the log shows what the helper received', async () => {
        const body = await waitForDone(base, jobId);
        assert.strictEqual(body.status, 'success');
        assert.strictEqual(body.exitCode, 0);
        assert.ok(body.log.includes('fake-helper: action=action_install_cups'), body.log);
        assert.ok(body.log.includes('fake-helper: stdin-bytes='), body.log);
        assert.ok(body.log.includes('fake-helper: done'), body.log);
    });

    await check('after completion, a new action is accepted again (not stuck busy)', async () => {
        const res = await fetch(`${base}/api/actions/reconfigure_cups/run`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({}),
        });
        assert.strictEqual(res.status, 200);
        const body = await res.json();
        await waitForDone(base, body.jobId);
    });

    await check('unknown action name is rejected with 400, no job created', async () => {
        const res = await fetch(`${base}/api/actions/definitely_not_real/run`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({}),
        });
        assert.strictEqual(res.status, 400);
    });

    await check('missing required field is rejected with 400 before spawning anything', async () => {
        const res = await fetch(`${base}/api/actions/configure_asterisk_intercom/run`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ alreadyInstalled: false, extension: '201', password: 'x' }),
        });
        assert.strictEqual(res.status, 400);
        const body = await res.json();
        assert.ok(/serverIp/.test(body.error), body.error);
    });

    await check('a failing helper is reflected as status failed with the real exit code', async () => {
        process.env.FAKE_HELPER_EXIT_CODE = '1';
        // jobs.js reads process.env.HELPER_PATH/SUDO_CMD once at module
        // load, but FAKE_HELPER_EXIT_CODE is read fresh by the spawned
        // shell script every time, so no re-require needed here.
        const res = await fetch(`${base}/api/actions/reconfigure_cups/run`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({}),
        });
        const { jobId: failId } = await res.json();
        const body = await waitForDone(base, failId);
        assert.strictEqual(body.status, 'failed');
        assert.strictEqual(body.exitCode, 1);
        delete process.env.FAKE_HELPER_EXIT_CODE;
    });

    await check('GET /api/actions/jobs/:id/stream (SSE) replays the log and sends a final done event', async () => {
        const res = await fetch(`${base}/api/actions/install_lms/run`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ alreadyInstalled: false }),
        });
        const { jobId: streamJobId } = await res.json();

        const streamRes = await fetch(`${base}/api/actions/jobs/${streamJobId}/stream`);
        assert.strictEqual(streamRes.status, 200);
        assert.strictEqual(streamRes.headers.get('content-type'), 'text/event-stream');

        const reader = streamRes.body.getReader();
        const decoder = new TextDecoder();
        let raw = '';
        const deadline = Date.now() + 3000;
        while (!raw.includes('event: done') && Date.now() < deadline) {
            const { value, done } = await reader.read();
            if (done) break;
            raw += decoder.decode(value, { stream: true });
        }
        assert.ok(raw.includes('event: log'), raw);
        assert.ok(raw.includes('fake-helper: action=action_install_lms'), raw);
        assert.ok(raw.includes('event: done'), raw);
        assert.ok(/data: \{"status":"success","exitCode":0\}/.test(raw), raw);
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
