'use strict';

// webui/public/app.js - vanilla JS, no framework/build step. Every
// user-controlled value (site URL/name/username, addon form fields) is
// set via .value or .textContent, never innerHTML, so nothing typed
// into a form can execute as markup - the one new attack surface a
// browser-based config UI has that the terminal menus never did.

const msgEl = document.getElementById('msg');
let currentConfig = null;

function showMessage(text, isError) {
    msgEl.textContent = text;
    msgEl.hidden = false;
    msgEl.className = 'banner ' + (isError ? 'error' : 'success');
    clearTimeout(showMessage._t);
    showMessage._t = setTimeout(() => { msgEl.hidden = true; }, 5000);
}

/* ---------------------------------------------------------------------- */
/* Sidebar navigation                                                     */
/* ---------------------------------------------------------------------- */

document.querySelectorAll('.nav-item').forEach((btn) => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
        document.querySelectorAll('.page').forEach((p) => p.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(`page-${btn.dataset.page}`).classList.add('active');
    });
});

document.getElementById('brand-sub').textContent = location.host || 'this kiosk';

/* ---------------------------------------------------------------------- */
/* Config API (Sites / Display / Lockout)                                 */
/* ---------------------------------------------------------------------- */

async function apiGet() {
    const res = await fetch('/api/config');
    if (!res.ok) throw new Error('Failed to load configuration');
    return res.json();
}

async function apiPut(patch) {
    const res = await fetch('/api/config', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || 'Save failed');
    return data;
}

/* ---------------------------------------------------------------------- */
/* Sites & Page Timing                                                    */
/* ---------------------------------------------------------------------- */

const sitesList = document.getElementById('sites-list');
const siteRowTemplate = document.getElementById('site-row-template');

function renderSites(tabs) {
    sitesList.textContent = '';
    tabs.forEach((tab, idx) => sitesList.appendChild(buildSiteRow(tab, idx)));
    if (tabs.length === 0) {
        const p = document.createElement('p');
        p.className = 'hint';
        p.textContent = 'No pages configured yet.';
        sitesList.appendChild(p);
    }
}

function buildSiteRow(tab, idx) {
    const node = siteRowTemplate.content.firstElementChild.cloneNode(true);
    node.dataset.index = String(idx);

    node.querySelector('.site-url').value = tab.url || '';
    node.querySelector('.site-name').value = tab.name || '';
    node.querySelector('.site-duration').value = tab.duration ?? 180;

    const authEnable = node.querySelector('.site-auth-enable');
    const authUser = node.querySelector('.site-auth-username');
    const authState = node.querySelector('.auth-state');
    const hasAuth = !!(tab.username || tab.hasPassword);
    authEnable.checked = hasAuth;
    authUser.value = tab.username || '';
    authState.textContent = hasAuth ? '(enabled)' : '(disabled)';

    node.querySelector('.remove-site').addEventListener('click', () => {
        node.remove();
        if (!sitesList.querySelector('.site-row')) renderSites([]);
    });

    return node;
}

document.getElementById('add-site').addEventListener('click', () => {
    if (sitesList.querySelector('.hint')) sitesList.textContent = '';
    sitesList.appendChild(buildSiteRow({ url: '', name: '', duration: 180, username: '', hasPassword: false }, sitesList.children.length));
    updateHomeTabOptions(collectTabs());
});
document.getElementById('save-sites').addEventListener('click', saveSites);

function collectTabs() {
    return Array.from(sitesList.querySelectorAll('.site-row')).map((row) => {
        const tab = {
            url: row.querySelector('.site-url').value.trim(),
            name: row.querySelector('.site-name').value.trim(),
            duration: parseInt(row.querySelector('.site-duration').value, 10),
        };
        const authEnabled = row.querySelector('.site-auth-enable').checked;
        if (authEnabled) {
            tab.username = row.querySelector('.site-auth-username').value;
            const newPass = row.querySelector('.site-auth-password').value;
            if (newPass) tab.password = newPass;
        } else {
            tab.username = '';
            tab.password = '';
        }
        return tab;
    });
}

async function saveSites() {
    const tabs = collectTabs();
    if (tabs.some((t) => !t.url)) {
        showMessage('Every site needs a URL', true);
        return;
    }
    try {
        currentConfig = await apiPut({ tabs });
        showMessage('Sites saved');
        renderSites(currentConfig.tabs);
        populateAll(currentConfig);
    } catch (e) {
        showMessage(e.message, true);
    }
}

sitesList.addEventListener('change', () => { updateHomeTabOptions(collectTabs()); });

/* ---------------------------------------------------------------------- */
/* Display & Interaction                                                  */
/* ---------------------------------------------------------------------- */

const displayForm = document.getElementById('display-form');
const homeTabSelect = document.getElementById('home-tab-select');

function updateHomeTabOptions(tabs) {
    const previous = homeTabSelect.value;
    homeTabSelect.textContent = '';
    const disabledOpt = document.createElement('option');
    disabledOpt.value = '-1';
    disabledOpt.textContent = 'Disabled';
    homeTabSelect.appendChild(disabledOpt);
    tabs.forEach((tab, idx) => {
        const opt = document.createElement('option');
        opt.value = String(idx);
        opt.textContent = tab.name || tab.url || `Page ${idx + 1}`;
        homeTabSelect.appendChild(opt);
    });
    const stillValid = Array.from(homeTabSelect.options).some((o) => o.value === previous);
    homeTabSelect.value = stillValid ? previous : '-1';
}

displayForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const fd = new FormData(displayForm);
    const patch = {
        swipeMode: fd.get('swipeMode'),
        allowNavigation: fd.get('allowNavigation'),
        enablePauseButton: fd.get('enablePauseButton') === 'on',
        enableKeyboardButton: fd.get('enableKeyboardButton') === 'on',
        enableNavButton: fd.get('enableNavButton') === 'on',
        homeTabIndex: parseInt(fd.get('homeTabIndex'), 10),
        inactivityTimeoutMinutes: parseInt(fd.get('inactivityTimeoutMinutes'), 10),
    };
    try {
        currentConfig = await apiPut(patch);
        showMessage('Display & Interaction saved');
        populateAll(currentConfig);
    } catch (err) {
        showMessage(err.message, true);
    }
});

/* ---------------------------------------------------------------------- */
/* Password Protection & Lockout                                          */
/* ---------------------------------------------------------------------- */

const lockoutForm = document.getElementById('lockout-form');
const lockoutEnabled = document.getElementById('lockout-enabled');
const lockoutFields = document.getElementById('lockout-fields');
const dailyLockEnabled = document.getElementById('daily-lock-enabled');
const lockoutAtTime = document.getElementById('lockout-at-time');
const passwordLabel = document.getElementById('password-label');

function refreshLockoutFieldVisibility() {
    lockoutFields.hidden = !lockoutEnabled.checked;
}
lockoutEnabled.addEventListener('change', refreshLockoutFieldVisibility);

dailyLockEnabled.addEventListener('change', () => {
    lockoutAtTime.disabled = !dailyLockEnabled.checked;
    if (!dailyLockEnabled.checked) lockoutAtTime.value = '';
});

lockoutForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const fd = new FormData(lockoutForm);
    const enable = fd.get('enablePasswordProtection') === 'on';
    const newPassword = fd.get('newLockoutPassword') || '';
    const confirmPassword = document.getElementById('lockout-password-confirm').value;

    if (newPassword && newPassword !== confirmPassword) {
        showMessage("Passwords don't match", true);
        return;
    }
    if (enable && !newPassword && !(currentConfig && currentConfig.hasLockoutPassword)) {
        showMessage('Set a lockout password before enabling password protection', true);
        return;
    }

    const patch = { enablePasswordProtection: enable };
    if (enable) {
        if (newPassword) patch.newLockoutPassword = newPassword;
        patch.lockoutTimeoutMinutes = parseInt(fd.get('lockoutTimeoutMinutes'), 10);
        patch.lockoutAtTime = dailyLockEnabled.checked ? fd.get('lockoutAtTime') : '';
        patch.requirePasswordOnBoot = fd.get('requirePasswordOnBoot') === 'on';
    }

    try {
        currentConfig = await apiPut(patch);
        showMessage('Password Protection & Lockout saved');
        populateAll(currentConfig);
        lockoutForm.querySelector('[name=newLockoutPassword]').value = '';
        document.getElementById('lockout-password-confirm').value = '';
    } catch (err) {
        showMessage(err.message, true);
    }
});

function populateAll(config) {
    displayForm.elements.swipeMode.value = config.swipeMode;
    displayForm.elements.allowNavigation.value = config.allowNavigation;
    displayForm.elements.enablePauseButton.checked = !!config.enablePauseButton;
    displayForm.elements.enableKeyboardButton.checked = !!config.enableKeyboardButton;
    displayForm.elements.enableNavButton.checked = !!config.enableNavButton;
    updateHomeTabOptions(config.tabs);
    homeTabSelect.value = String(config.homeTabIndex);
    displayForm.elements.inactivityTimeoutMinutes.value = Math.round(config.inactivityTimeout / 60);

    lockoutEnabled.checked = !!config.enablePasswordProtection;
    passwordLabel.textContent = config.hasLockoutPassword ? 'New password (leave blank to keep the current one)' : 'Set lockout password';
    lockoutForm.elements.lockoutTimeoutMinutes.value = config.lockoutTimeout;
    dailyLockEnabled.checked = !!config.lockoutAtTime;
    lockoutAtTime.disabled = !config.lockoutAtTime;
    lockoutAtTime.value = config.lockoutAtTime || '';
    lockoutForm.elements.requirePasswordOnBoot.checked = !!config.requirePasswordOnBoot;
    refreshLockoutFieldVisibility();
}

/* ---------------------------------------------------------------------- */
/* Shared: run a privileged action and stream its log via SSE             */
/* ---------------------------------------------------------------------- */

// jobPanelEls = { panel, status, log }. Returns a promise resolving to
// {status, exitCode} once the job finishes (or rejects on a request-level
// error before a job even started, e.g. validation).
async function runAction(actionName, fields, jobPanelEls) {
    const res = await fetch(`/api/actions/${actionName}/run`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(fields || {}),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || 'Could not start action');

    jobPanelEls.panel.classList.add('open');
    jobPanelEls.log.textContent = '';
    setJobStatus(jobPanelEls.status, 'running');

    return new Promise((resolve, reject) => {
        const source = new EventSource(`/api/actions/jobs/${body.jobId}/stream`);
        source.addEventListener('log', (ev) => {
            jobPanelEls.log.textContent += JSON.parse(ev.data);
            jobPanelEls.log.scrollTop = jobPanelEls.log.scrollHeight;
        });
        source.addEventListener('done', (ev) => {
            const result = JSON.parse(ev.data);
            setJobStatus(jobPanelEls.status, result.status);
            source.close();
            resolve(result);
        });
        source.onerror = () => {
            source.close();
            reject(new Error('Lost connection to the log stream'));
        };
    });
}

function setJobStatus(el, status) {
    el.className = `job-status ${status}`;
    if (status === 'running') {
        el.innerHTML = '';
        const spinner = document.createElement('span');
        spinner.className = 'spinner';
        el.appendChild(spinner);
        el.appendChild(document.createTextNode('Running'));
    } else {
        el.textContent = status === 'success' ? 'Success' : 'Failed';
    }
}

/* ---------------------------------------------------------------------- */
/* Addons                                                                 */
/* ---------------------------------------------------------------------- */

const addonsList = document.getElementById('addons-list');
const addonCardTemplate = document.getElementById('addon-card-template');

const ICONS = {
    printer: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9V3h12v6M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="7"/></svg>',
    music: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>',
    speaker: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="2" width="16" height="20" rx="2"/><circle cx="12" cy="14" r="4"/><circle cx="12" cy="6" r="1"/></svg>',
    phone: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3.1-8.7A2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .3 2 .6 2.9a2 2 0 0 1-.5 2.1L8 9.9a16 16 0 0 0 6 6l1.2-1.2a2 2 0 0 1 2.1-.5c.9.3 1.9.5 2.9.6a2 2 0 0 1 1.8 2Z"/></svg>',
};

function pillHtml(state) {
    if (state === true) return '<span class="pill installed">Installed</span>';
    if (state === false) return '<span class="pill not-installed">Not installed</span>';
    return '<span class="pill unknown">Unknown</span>';
}

let addonStatus = {};

async function loadAddonStatus() {
    try {
        const res = await fetch('/api/addons/status');
        if (res.ok) addonStatus = await res.json();
    } catch (e) {
        // leave addonStatus as-is (pills show "Unknown"); not fatal to the page
    }
}

// Keyed by addon, so a single card can be refreshed in place after its
// own job finishes (see refreshAddonCard) without touching the other
// three, and - critically - without recreating the job-panel/log the
// user is currently looking at. An earlier version called the full
// renderAddons() rebuild after every successful job "to update the
// pill"; that raced (and usually lost to) the same success/log state it
// had just written a moment earlier, since rebuilding the whole list
// replaces the job-panel node with a fresh empty one. Caught by an
// actual headless-browser run, not just reading the code - the log
// looked fine reading it, but watching it in Chromium showed the
// "Success" state flash and vanish.
const ADDON_RECIPES = {};

function buildAddonCard(recipe) {
    ADDON_RECIPES[recipe.key] = recipe;
    const node = addonCardTemplate.content.firstElementChild.cloneNode(true);
    node.dataset.addon = recipe.key;
    fillAddonCard(node, recipe);
    return node;
}

// (Re)fills everything in a card EXCEPT the job-panel/log, which is
// left exactly as it is - so refreshing a card's install-state after a
// job finishes doesn't erase the result the user just watched stream in.
function fillAddonCard(node, { key, title, desc, icon, buildForm }) {
    node.querySelector('.addon-icon').innerHTML = ICONS[icon];
    node.querySelector('.addon-name').textContent = title;
    node.querySelector('.addon-desc').textContent = desc;
    node.querySelector('.pill').outerHTML = pillHtml(addonStatus[key]);

    const actionsEl = node.querySelector('.addon-actions');
    const formEl = node.querySelector('.addon-form');
    actionsEl.textContent = '';
    formEl.textContent = '';
    formEl.className = 'addon-form';

    const jobPanelEls = {
        panel: node.querySelector('.job-panel'),
        status: node.querySelector('.job-status'),
        log: node.querySelector('.job-log'),
    };
    buildForm({ node, actionsEl, formEl, jobPanelEls, installed: addonStatus[key] === true });
}

// Called after one addon's own job finishes - refreshes just that
// card's pill/buttons/form (e.g. "Install" -> "Reconfigure") in place.
async function refreshAddonCard(key) {
    await loadAddonStatus();
    const node = addonsList.querySelector(`[data-addon="${key}"]`);
    if (node) fillAddonCard(node, ADDON_RECIPES[key]);
}

function addSubmitAction(formEl, jobPanelEls, actionName, collectFields, onDone) {
    formEl.addEventListener('submit', async (e) => {
        e.preventDefault();
        const submitBtn = formEl.querySelector('button[type=submit]');
        submitBtn.disabled = true;
        try {
            const result = await runAction(actionName, collectFields(), jobPanelEls);
            if (result.status === 'success') {
                showMessage('Done');
                if (onDone) await onDone();
            } else {
                showMessage('Action failed - see the log below', true);
            }
        } catch (err) {
            showMessage(err.message, true);
        } finally {
            submitBtn.disabled = false;
        }
    });
}

function renderAddons() {
    addonsList.textContent = '';

    // CUPS: no fields at all - the button itself is the whole form.
    addonsList.appendChild(buildAddonCard({
        key: 'cups', title: 'CUPS Printing', desc: 'Network printer sharing', icon: 'printer',
        buildForm({ actionsEl, formEl, jobPanelEls, installed }) {
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.textContent = installed ? 'Reconfigure for network access' : 'Install CUPS Printing';
            btn.addEventListener('click', async () => {
                btn.disabled = true;
                try {
                    const action = installed ? 'reconfigure_cups' : 'install_cups';
                    const result = await runAction(action, {}, jobPanelEls);
                    if (result.status === 'success') { showMessage('Done'); await refreshAddonCard('cups'); }
                    else showMessage('Action failed - see the log below', true);
                } catch (err) {
                    showMessage(err.message, true);
                } finally {
                    btn.disabled = false;
                }
            });
            actionsEl.appendChild(btn);
        },
    }));

    // LMS Server: fresh install has no fields; once installed, an
    // optional port-reconfigure field.
    addonsList.appendChild(buildAddonCard({
        key: 'lms', title: 'LMS Server', desc: 'Lyrion / Logitech Media Server', icon: 'music',
        buildForm({ actionsEl, formEl, jobPanelEls, installed }) {
            if (!installed) {
                const btn = document.createElement('button');
                btn.type = 'button';
                btn.textContent = 'Install LMS Server';
                btn.addEventListener('click', async () => {
                    btn.disabled = true;
                    try {
                        const result = await runAction('install_lms', { alreadyInstalled: false }, jobPanelEls);
                        if (result.status === 'success') { showMessage('Done'); await refreshAddonCard('lms'); }
                        else showMessage('Action failed - see the log below', true);
                    } catch (err) {
                        showMessage(err.message, true);
                    } finally {
                        btn.disabled = false;
                    }
                });
                actionsEl.appendChild(btn);
                return;
            }
            const toggleBtn = document.createElement('button');
            toggleBtn.type = 'button';
            toggleBtn.className = 'secondary';
            toggleBtn.textContent = 'Reconfigure port';
            toggleBtn.addEventListener('click', () => formEl.classList.toggle('open'));
            actionsEl.appendChild(toggleBtn);

            const portLabel = document.createElement('label');
            portLabel.innerHTML = 'New HTTP port';
            const portInput = document.createElement('input');
            portInput.type = 'number'; portInput.min = '1'; portInput.max = '65535'; portInput.value = '9000';
            portLabel.appendChild(portInput);
            formEl.appendChild(portLabel);
            const submitBtn = document.createElement('button');
            submitBtn.type = 'submit';
            submitBtn.textContent = 'Apply new port';
            formEl.appendChild(submitBtn);

            addSubmitAction(formEl, jobPanelEls, 'install_lms', () => ({
                alreadyInstalled: true, reconfigurePort: true, newPort: parseInt(portInput.value, 10),
            }), () => refreshAddonCard('lms'));
        },
    }));

    // Squeezelite: player name + LMS server, both for install and
    // reconfigure - the form is the same either way.
    addonsList.appendChild(buildAddonCard({
        key: 'squeezelite', title: 'Squeezelite Player', desc: 'Turns this kiosk into an LMS-connected speaker', icon: 'speaker',
        buildForm({ actionsEl, formEl, jobPanelEls, installed }) {
            formEl.classList.add('open');

            const nameLabel = document.createElement('label');
            nameLabel.textContent = 'Player name';
            const nameInput = document.createElement('input');
            nameInput.type = 'text'; nameInput.value = 'Kiosk'; nameInput.placeholder = 'Kiosk';
            nameLabel.appendChild(nameInput);
            formEl.appendChild(nameLabel);

            const serverLabel = document.createElement('label');
            serverLabel.innerHTML = 'LMS server <span class="hint">(IP:PORT, blank for auto-discovery)</span>';
            const serverInput = document.createElement('input');
            serverInput.type = 'text'; serverInput.placeholder = '192.168.1.100:3483';
            serverLabel.appendChild(serverInput);
            formEl.appendChild(serverLabel);

            const rebootHint = document.createElement('p');
            rebootHint.className = 'hint';
            rebootHint.textContent = 'A reboot is required after install/reconfigure before Squeezelite starts.';
            formEl.appendChild(rebootHint);

            const submitBtn = document.createElement('button');
            submitBtn.type = 'submit';
            submitBtn.textContent = installed ? 'Reconfigure Squeezelite' : 'Install Squeezelite';
            formEl.appendChild(submitBtn);

            addSubmitAction(formEl, jobPanelEls, 'install_squeezelite', () => ({
                alreadyInstalled: installed, reconfigure: true,
                playerName: nameInput.value.trim(), lmsServer: serverInput.value.trim(),
            }), () => refreshAddonCard('squeezelite'));
        },
    }));

    // Asterisk Intercom: server/extension/password/options, always shown.
    addonsList.appendChild(buildAddonCard({
        key: 'asterisk_intercom', title: 'Asterisk Intercom', desc: 'SIP extension client (Baresip)', icon: 'phone',
        buildForm({ actionsEl, formEl, jobPanelEls, installed }) {
            formEl.classList.add('open');

            const mk = (label, type, opts) => {
                const l = document.createElement('label');
                l.textContent = label;
                const i = document.createElement('input');
                i.type = type;
                Object.assign(i, opts || {});
                l.appendChild(i);
                formEl.appendChild(l);
                return i;
            };
            const ip = mk('Server IP or hostname', 'text', { placeholder: '10.0.0.5' });
            const port = mk('Server port', 'number', { placeholder: '5060', min: '1', max: '65535' });
            const ext = mk('Extension number', 'text', { placeholder: '201' });
            const pass = mk('SIP password', 'password', { autocomplete: 'new-password' });

            const autoAnswerLabel = document.createElement('label');
            autoAnswerLabel.className = 'checkbox';
            const autoAnswer = document.createElement('input');
            autoAnswer.type = 'checkbox';
            autoAnswerLabel.appendChild(autoAnswer);
            autoAnswerLabel.appendChild(document.createTextNode('Auto-answer incoming calls (intercom mode)'));
            formEl.appendChild(autoAnswerLabel);

            const tlsLabel = document.createElement('label');
            tlsLabel.className = 'checkbox';
            const useTls = document.createElement('input');
            useTls.type = 'checkbox';
            tlsLabel.appendChild(useTls);
            tlsLabel.appendChild(document.createTextNode('Use TLS encryption'));
            formEl.appendChild(tlsLabel);

            const submitBtn = document.createElement('button');
            submitBtn.type = 'submit';
            submitBtn.textContent = installed ? 'Reconfigure Asterisk Intercom' : 'Connect to Asterisk server';
            formEl.appendChild(submitBtn);

            addSubmitAction(formEl, jobPanelEls, 'configure_asterisk_intercom', () => ({
                alreadyInstalled: installed, reconfigure: true,
                serverIp: ip.value.trim(), serverPort: port.value ? parseInt(port.value, 10) : undefined,
                extension: ext.value.trim(), password: pass.value,
                autoAnswer: autoAnswer.checked, useTls: useTls.checked,
            }), () => refreshAddonCard('asterisk_intercom'));
        },
    }));
}

/* ---------------------------------------------------------------------- */
/* Update                                                                 */
/* ---------------------------------------------------------------------- */

document.getElementById('run-upgrade').addEventListener('click', async (e) => {
    const btn = e.currentTarget;
    btn.disabled = true;
    try {
        const result = await runAction('upgrade', {}, {
            panel: document.getElementById('job-panel-upgrade'),
            status: document.getElementById('job-status-upgrade'),
            log: document.getElementById('job-log-upgrade'),
        });
        showMessage(result.status === 'success' ? 'Update finished' : 'Update failed - see the log below', result.status !== 'success');
    } catch (err) {
        showMessage(err.message, true);
    } finally {
        btn.disabled = false;
    }
});

/* ---------------------------------------------------------------------- */
/* Init                                                                    */
/* ---------------------------------------------------------------------- */

async function init() {
    try {
        currentConfig = await apiGet();
        renderSites(currentConfig.tabs);
        populateAll(currentConfig);
    } catch (e) {
        showMessage(e.message, true);
    }
    await loadAddonStatus();
    renderAddons();
}

init();
