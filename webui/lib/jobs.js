'use strict';

// webui/lib/jobs.js - runs one privileged action at a time via the
// allow-listed root helper (menus/addon_webui.sh's kiosk-webui-helper),
// and keeps an in-memory log so /api/actions/:name/run's caller and any
// number of SSE stream reconnects all see the same output. No database -
// this tool manages one kiosk, a Map is plenty.
//
// HELPER_PATH and SUDO_CMD are both overridable via environment (see
// webui/test/jobs.test.js): tests point HELPER_PATH at a small fake
// script and clear SUDO_CMD, so the real test suite never needs actual
// root or a real addon install - the same principle as every stubbed
// bash test in this project, just on the Node side.

const { spawn } = require('child_process');
const { randomUUID } = require('crypto');
const { getAction } = require('./actions');

const HELPER_PATH = process.env.HELPER_PATH || '/usr/local/bin/kiosk-webui-helper';
const SUDO_CMD = process.env.SUDO_CMD !== undefined ? process.env.SUDO_CMD : 'sudo';

const jobs = new Map();
let activeJobId = null;

function startJob(actionName, fields) {
    const action = getAction(actionName);
    if (!action) {
        const err = new Error(`Unknown action: ${actionName}`);
        err.status = 400;
        throw err;
    }
    if (activeJobId) {
        const err = new Error('Another action is already running - wait for it to finish first');
        err.status = 409;
        throw err;
    }

    // buildStdin() validates its own required fields and throws a plain
    // Error with a human-readable message on bad input - treated as a
    // 400 here, before anything is spawned.
    let stdin;
    try {
        stdin = action.buildStdin(fields || {});
    } catch (e) {
        e.status = 400;
        throw e;
    }

    const jobId = randomUUID();
    const job = {
        id: jobId,
        name: actionName,
        label: action.label,
        status: 'running',
        log: [],
        exitCode: null,
        listeners: new Set(),
    };
    jobs.set(jobId, job);
    activeJobId = jobId;

    const child = SUDO_CMD
        ? spawn(SUDO_CMD, [HELPER_PATH, action.helperAction])
        : spawn(HELPER_PATH, [action.helperAction]);

    const appendLine = (chunk) => {
        const text = chunk.toString();
        job.log.push(text);
        for (const listener of job.listeners) listener(text);
    };
    child.stdout.on('data', appendLine);
    child.stderr.on('data', appendLine);

    const finish = (status, exitCode) => {
        if (job.status !== 'running') return; // 'error' and 'close' can both fire
        job.status = status;
        job.exitCode = exitCode;
        for (const listener of job.listeners) listener(null);
        if (activeJobId === jobId) activeJobId = null;
    };
    child.on('close', (code) => finish(code === 0 ? 'success' : 'failed', code));
    child.on('error', (err) => {
        job.log.push(`\n[error] ${err.message}\n`);
        finish('failed', null);
    });

    child.stdin.write(stdin);
    child.stdin.end();

    return job;
}

function getJob(jobId) {
    return jobs.get(jobId);
}

module.exports = { startJob, getJob };
