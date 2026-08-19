#!/bin/bash
################################################################################
# menus/addon_webui.sh - "Web UI" addon: installs webui/ (a small Node/
# Express app) as a systemd service running as $KIOSK_USER, giving a
# browser-based editor for Sites & Page Timing, Display & Interaction,
# and Password Protection & Lockout - the three Core Settings menus that
# are pure config.json read/write with no privileged system mutation
# involved. The remaining Core Settings/Addons/Advanced menus (WiFi,
# Timezone, Power/Display/Quiet Hours, Complete Uninstall, every other
# addon, everything in Advanced) stay terminal-only for now - a
# network-facing process shouldn't be handed sudo-level system mutation
# without a lot more thought than this first pass gives it.
#
# No login of its own, by design: this addon assumes it'll be put behind
# a reverse proxy (e.g. Caddy) with Authelia forward-auth in front, the
# same way other self-hosted apps get protected - Authelia integration
# is explicitly out of scope for this repo (Authelia runs elsewhere).
# Direct LAN access with no proxy in front has no authentication at all -
# treat it the same as SSH access to this kiosk.
#
# webui/'s own app-level logic (config.json schema/merge, API validation)
# lives and is tested entirely under webui/ - this file only wires it up
# as a system service and never touches config.json itself.
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
EOF
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
    echo "browser. It has no login of its own - put it behind your own"
    echo "reverse proxy (e.g. Caddy + Authelia) if it needs to be reachable"
    echo "beyond a trusted LAN."
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
    sudo rm -rf "$WEBUI_DIR" "$WEBUI_ENV_DIR"
    log_success "Web UI removed"
}
