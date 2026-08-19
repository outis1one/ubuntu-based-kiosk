'use strict';

// webui/public/app.js - vanilla JS, no framework/build step. Every
// user-controlled value (site URL/name/username) is set via .value or
// .textContent, never innerHTML, so nothing typed into a site name or
// URL can execute as markup - the one new attack surface a browser-based
// config UI has that the terminal menus never did.

const msgEl = document.getElementById('msg');
let currentConfig = null;

function showMessage(text, isError) {
    msgEl.textContent = text;
    msgEl.hidden = false;
    msgEl.className = 'banner ' + (isError ? 'error' : 'success');
    clearTimeout(showMessage._t);
    showMessage._t = setTimeout(() => { msgEl.hidden = true; }, 5000);
}

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
            // else: omit `password` entirely - server keeps the existing one.
        } else {
            tab.username = '';
            tab.password = '';
        }
        return tab;
    });
}

// A "Save" per row would be simpler individually, but sites.sh's own
// save_config always rewrites the whole tabs array too - this mirrors
// that, saving all sites (and the home-page selection they feed into)
// together whenever anything in the Sites section changes.
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

/* ---------------------------------------------------------------------- */
/* Populate forms from a config snapshot                                  */
/* ---------------------------------------------------------------------- */

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

async function init() {
    try {
        currentConfig = await apiGet();
        renderSites(currentConfig.tabs);
        populateAll(currentConfig);
    } catch (e) {
        showMessage(e.message, true);
    }
}

init();
