#!/bin/bash
################################################################################
# menus/addon_webui.sh - "Web UI" addon: installs webui/ (a small Node/
# Express app) as a systemd service running as $KIOSK_USER, giving a
# browser-based editor for Sites & Page Timing, Display & Interaction,
# and Password Protection & Lockout - config.json read/write only, no
# sudo needed, since that file is already owned by $KIOSK_USER.
#
# Installed by default during first-time provisioning now
# (lib/provision.sh's provision_configure_webui, which calls the same
# install helpers this file defines) - this menu remains here for
# reconfiguring the port, restarting the service, or reinstalling it on
# a kiosk provisioned before this change.
#
# Also lets the web UI trigger a fixed, vetted set of privileged actions
# - install/reconfigure CUPS/LMS/Squeezelite/Asterisk Intercom, and
# Update - through a narrow, allow-listed root helper
# (webui_write_helper_script below), rather than by giving the service
# itself any elevated privilege. The helper is reachable only via a
# single-path passwordless sudo rule (webui_write_sudoers_file) and
# re-checks its own fixed action allow-list before dispatching anything,
# even though the sudoers rule alone already restricts which script can
# run - defense in depth. Each allow-listed action is the exact same
# interactive `action_*` function the terminal menu already uses,
# driven by piping the right answers on stdin, the same technique this
# project's own bash tests already use (see webui/lib/actions.js and
# webui/test/*.test.js). No prompt/mutation refactor of any addon file
# was needed for this to work. Everything else (WiFi, Timezone, Power/
# Display/Quiet Hours, Complete Uninstall, Remote Access, Authelia,
# Factory Reset, Virtual Consoles, Emergency Hotspot, Clone Settings)
# stays terminal-only for now.
#
# No login of its own, by design: this addon assumes it'll be put behind
# a reverse proxy (e.g. Caddy) with Authelia forward-auth in front, the
# same way other self-hosted apps get protected - Authelia integration
# is explicitly out of scope for this repo (Authelia runs elsewhere).
# Direct LAN access with no proxy in front has no authentication at all -
# treat it the same as SSH access to this kiosk, which is also the
# access level the privileged helper effectively grants if reached
# without a proxy in front: bounded to its fixed action list, not a
# root shell, but real system mutation all the same.
#
# webui/'s own app-level logic (config.json schema/merge, API
# validation, the action allow-list/stdin synthesis, the job/SSE
# system) lives and is tested entirely under webui/ - this file only
# wires it up as a system service plus the privileged helper, and never
# touches config.json itself.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

webui_is_installed() {
    [[ -f "$SYSTEMD_DIR/kiosk-webui.service" ]]
}

webui_is_active() {
    systemctl is-active --quiet kiosk-webui
}

webui_port() {
    if sudo test -f "$WEBUI_ENV_DIR/webui.env" 2>/dev/null; then
        sudo grep -oP '^PORT=\K.*' "$WEBUI_ENV_DIR/webui.env" 2>/dev/null || echo "8090"
    else
        echo "8090"
    fi
}

addon_webui_status() {
    if webui_is_installed && webui_is_active; then
        echo "Web UI: running at http://$(get_ip_address):$(webui_port)"
    elif webui_is_installed; then
        echo "Web UI: installed but not running"
    else
        echo "Web UI: not installed"
    fi
}

addon_webui_menu_builder() {
    if webui_is_installed; then
        MENU_LABELS=("Change port" "Restart service" "Uninstall")
        MENU_HANDLERS=(action_webui_reconfigure action_webui_restart action_webui_uninstall)
    else
        MENU_LABELS=("Install Web UI")
        MENU_HANDLERS=(action_webui_install)
    fi
}

addon_webui_menu() {
    run_menu "WEB UI" addon_webui_menu_builder addon_webui_status
}

################################################################################
# Shared install helpers
################################################################################

# Copies webui/ from this checkout onto the kiosk and installs its npm
# dependencies as $KIOSK_USER - same shape as provision_install_app in
# lib/provision.sh, but addon-scoped (opt-in) rather than core. Every
# critical step is individually guarded (matches menus/addon_cups.sh's
# action_install_cups) rather than relying on set -e to stop a bare
# sequence - menu actions are always invoked via run_menu's
# `"${MENU_HANDLERS[...]}" "$choice" || true` dispatch, which already
# exempts everything they do from set -e for the whole call, so a bare
# unguarded sequence here would silently continue past a real failure
# (e.g. attempting npm install into a directory `cp` never populated).
webui_install_app_files() {
    if ! sudo mkdir -p "$WEBUI_DIR"; then
        log_error "Could not create $WEBUI_DIR"
        return 1
    fi
    if ! sudo cp -r "$SCRIPT_DIR/webui/." "$WEBUI_DIR/"; then
        log_error "Could not copy Web UI app files"
        return 1
    fi
    sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$WEBUI_DIR"
    if ! sudo -u "$KIOSK_USER" bash -lc "cd '$WEBUI_DIR' && npm install --omit=dev --unsafe-perm"; then
        log_error "npm install failed"
        return 1
    fi
}

webui_write_env_file() {
    local port="$1"
    sudo mkdir -p "$WEBUI_ENV_DIR"
    sudo tee "$WEBUI_ENV_DIR/webui.env" > /dev/null <<EOF
PORT=${port}
BIND_ADDR=0.0.0.0
CONFIG_PATH=${CONFIG_PATH}
HELPER_PATH=${WEBUI_HELPER_PATH}
EOF
}

# Writes the one root-owned script the Web UI is ever allowed to reach
# via sudo (see the sudoers rule webui_write_sudoers_file writes right
# after this). Sources the exact same files install.sh does - full path
# list baked in at generation time from $SCRIPT_DIR, so the generated
# script has no runtime dependency on where it happens to be invoked
# from. The fixed ALLOWED_ACTIONS allow-list inside the script itself is
# the real gate (checked in addition to, not instead of, the sudoers
# rule only permitting this one script path) - a request that reaches
# this script can only ever trigger one of these exact, already-tested
# interactive `action_*` functions, driven the same way this project's
# own bash tests already drive them: real answers piped in on stdin, in
# the exact order the function's own prompts expect them. No prompt/
# mutation refactor of any addon file needed for this to work.
webui_write_helper_script() {
    sudo mkdir -p "$(dirname "$WEBUI_HELPER_PATH")"
    sudo tee "$WEBUI_HELPER_PATH" > /dev/null <<EOF
#!/bin/bash
set -euo pipefail

# lib/provision.sh reads \$SCRIPT_DIR directly at source time (no
# fallback default, unlike the lib/config.sh path vars) - must be a real
# exported variable here, not just used to interpolate the source paths
# below, or it's unbound under set -u.
export SCRIPT_DIR="$SCRIPT_DIR"

source "$SCRIPT_DIR/lib/menu.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/electron.sh"
source "$SCRIPT_DIR/menus/sites.sh"
source "$SCRIPT_DIR/menus/display.sh"
source "$SCRIPT_DIR/menus/timezone.sh"
source "$SCRIPT_DIR/menus/hidden_pin.sh"
source "$SCRIPT_DIR/menus/lockout.sh"
source "$SCRIPT_DIR/menus/wifi.sh"
source "$SCRIPT_DIR/menus/power_schedule.sh"
source "$SCRIPT_DIR/menus/diagnostics.sh"
source "$SCRIPT_DIR/menus/addon_cups.sh"
source "$SCRIPT_DIR/menus/addon_authelia.sh"
source "$SCRIPT_DIR/menus/addon_remote_access.sh"
source "$SCRIPT_DIR/menus/addon_lms_squeezelite.sh"
source "$SCRIPT_DIR/menus/addon_asterisk_intercom.sh"
source "$SCRIPT_DIR/menus/addon_webui.sh"
source "$SCRIPT_DIR/menus/advanced_electron.sh"
source "$SCRIPT_DIR/menus/advanced_upgrade.sh"
source "$SCRIPT_DIR/menus/advanced_factory_reset.sh"
source "$SCRIPT_DIR/menus/advanced_virtual_consoles.sh"
source "$SCRIPT_DIR/menus/advanced_emergency_hotspot.sh"
source "$SCRIPT_DIR/menus/complete_uninstall.sh"
source "$SCRIPT_DIR/menus/clone_settings.sh"
source "$SCRIPT_DIR/lib/provision.sh"

# Read-only status wrappers, not addon logic of their own - just a
# single fixed-shape JSON line so the web UI can show "Install" vs.
# "Reconfigure" per addon in one round trip. None of the underlying
# checks (dpkg query, systemctl is-active/is-enabled, a file-existence
# test under \$KIOSK_HOME) need root, but this script is still only
# reachable via the same sudo-gated path as everything else here - one
# access path is simpler to reason about than two, and the extra sudo
# call for a read-only check is negligible.
status_all() {
    echo "{\"cups\":\$(cups_is_installed && echo true || echo false),\"lms\":\$(lms_is_installed && echo true || echo false),\"squeezelite\":\$(squeezelite_is_installed && echo true || echo false),\"asterisk_intercom\":\$(baresip_is_installed && echo true || echo false)}"
}

ALLOWED_ACTIONS=(
    action_install_cups
    action_reconfigure_cups
    action_install_lms
    action_install_squeezelite
    action_configure_asterisk_intercom
    action_upgrade
    status_all
)

action="\${1:-}"
allowed=false
for a in "\${ALLOWED_ACTIONS[@]}"; do
    [[ "\$a" == "\$action" ]] && allowed=true && break
done

if ! \$allowed; then
    echo "kiosk-webui-helper: action not permitted: \$action" >&2
    exit 1
fi

"\$action"
EOF
    sudo chown root:root "$WEBUI_HELPER_PATH"
    sudo chmod 750 "$WEBUI_HELPER_PATH"
}

# Grants $KIOSK_USER passwordless sudo on exactly this one script path -
# no argument wildcarding at the sudoers level, since the script's own
# ALLOWED_ACTIONS check above is the real gate. Validated with
# `visudo -c -f` on a temp file before it's moved into place: a
# malformed sudoers snippet can break sudo system-wide, so this step is
# never skipped.
webui_write_sudoers_file() {
    local tmp
    tmp=$(mktemp)
    echo "${KIOSK_USER} ALL=(root) NOPASSWD: ${WEBUI_HELPER_PATH}" > "$tmp"

    if ! sudo visudo -c -f "$tmp" &>/dev/null; then
        log_error "Generated sudoers rule failed validation - not installed"
        rm -f "$tmp"
        return 1
    fi

    sudo mkdir -p "$SUDOERS_D_DIR"
    sudo install -m 0440 -o root -g root "$tmp" "$SUDOERS_D_DIR/kiosk-webui"
    rm -f "$tmp"
}

webui_write_unit_file() {
    sudo tee "$SYSTEMD_DIR/kiosk-webui.service" > /dev/null <<EOF
[Unit]
Description=Kiosk Web UI
After=network.target

[Service]
Type=simple
User=${KIOSK_USER}
WorkingDirectory=${WEBUI_DIR}
EnvironmentFile=${WEBUI_ENV_DIR}/webui.env
ExecStart=/usr/bin/node ${WEBUI_DIR}/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

################################################################################
# Actions
################################################################################

action_webui_install() {
    echo
    echo "This installs a small web app for editing Sites & Page Timing,"
    echo "Display & Interaction, and Password Protection & Lockout from a"
    echo "browser - plus installing/reconfiguring CUPS, LMS/Squeezelite,"
    echo "and Asterisk Intercom, and checking for updates. It has no login"
    echo "of its own - put it behind your own reverse proxy (e.g. Caddy +"
    echo "Authelia) if it needs to be reachable beyond a trusted LAN."
    echo
    ask_yes_no "Install the Web UI?" "n" || { echo "Cancelled"; return; }

    local port
    port=$(ask_integer "Port to listen on" "8090" 1024 65535)

    echo "Installing app files and npm dependencies..."
    if ! webui_install_app_files; then
        log_error "Web UI install failed"
        return 1
    fi

    webui_write_env_file "$port"
    webui_write_unit_file
    webui_write_helper_script
    if ! webui_write_sudoers_file; then
        log_error "Web UI install failed - could not grant the addon-install/Update helper permission"
        return 1
    fi

    if enable_and_start_units kiosk-webui; then
        sudo ufw allow "${port}/tcp" comment 'Kiosk Web UI' 2>/dev/null || true
        log_success "Web UI installed: http://$(get_ip_address):${port}"
    else
        log_error "Web UI installed but failed to start - check: sudo journalctl -u kiosk-webui -n 50"
        return 1
    fi
}

action_webui_reconfigure() {
    echo
    local current_port
    current_port=$(webui_port)
    local port
    port=$(ask_integer "Port to listen on" "$current_port" 1024 65535)

    if [[ "$port" == "$current_port" ]]; then
        echo "No change"
        return
    fi

    webui_write_env_file "$port"
    sudo systemctl restart kiosk-webui
    sudo ufw allow "${port}/tcp" comment 'Kiosk Web UI' 2>/dev/null || true
    log_success "Web UI now listening on port ${port}"
}

action_webui_restart() {
    sudo systemctl restart kiosk-webui
    sleep 1
    if webui_is_active; then
        log_success "Web UI restarted"
    else
        log_error "Web UI failed to restart - check: sudo journalctl -u kiosk-webui -n 50"
        return 1
    fi
}

action_webui_uninstall() {
    echo
    ask_yes_no "Uninstall the Web UI?" "n" || { echo "Cancelled"; return; }
    webui_do_uninstall
}

# The actual removal, no prompt - shared with Complete Uninstall so that
# operation doesn't need to re-implement Web UI teardown a second time.
# No `ufw delete` - matches every other addon's uninstall in this
# codebase, which never removes its own firewall rule either.
webui_do_uninstall() {
    sudo systemctl stop kiosk-webui 2>/dev/null || true
    sudo systemctl disable kiosk-webui 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR/kiosk-webui.service"
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo rm -f "$SUDOERS_D_DIR/kiosk-webui" "$WEBUI_HELPER_PATH"
    sudo rm -rf "$WEBUI_DIR" "$WEBUI_ENV_DIR"
    log_success "Web UI removed"
}
