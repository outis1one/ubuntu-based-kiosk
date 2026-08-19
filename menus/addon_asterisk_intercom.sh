#!/bin/bash
################################################################################
# menus/addon_asterisk_intercom.sh - "Asterisk Intercom" addon: connect the
# kiosk as a SIP extension to an *existing* Asterisk server.
#
# The legacy addon offered three options: Client Only (a Baresip SIP
# client - what this file is), Server Only, and Full (server + client).
# Server/Full downloaded and ran a third-party installer from a separate
# "Easy Asterisk" repository to stand up a whole Asterisk PBX. That
# repository has since gone through a major rework upstream, so wiring a
# full PBX install through it here no longer makes sense to maintain -
# and most kiosk deployments don't need this device to *be* the PBX
# anyway. This addon now does only the client/endpoint piece: install
# Baresip and register it as one extension against an Asterisk server
# the user already has running somewhere else. It never installs or
# manages Asterisk itself.
#
# Two other things fixed while narrowing the scope:
# - The legacy client path tracked its own version by calling out to the
#   (now-reworked) Easy Asterisk repo's GitHub API and stamping a
#   "<repo-version>-client" string in a side file. That coupling is
#   exactly what's being dropped, so version tracking now just reads the
#   real installed `baresip` package version via dpkg - one less network
#   dependency and one less thing to keep in sync with an external repo.
# - The legacy addon had no uninstall option for the client at all -
#   added below.
#
# Real system state: apt package, a per-user config directory under
# $KIOSK_HOME, and a systemd --user unit for $KIOSK_USER (not a system
# service - Baresip needs the desktop session's PulseAudio/PipeWire
# socket). Every write goes through `sudo`/`sudo -u "$KIOSK_USER"`, all
# stubbed at the command level in tests - there's no real D-Bus user
# session to target in a test container regardless.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

BARESIP_CONFIG_DIR="${KIOSK_HOME}/.baresip"
BARESIP_USER_SERVICE_DIR="${KIOSK_HOME}/.config/systemd/user"

# Runs `systemctl --user ...` as $KIOSK_USER with the runtime dir/D-Bus
# address it needs to find that user's session. Always call from an
# `if`/`&&`/`||` context - see run_menu's own comment on why a bare call
# that can legitimately fail must never be a standalone statement.
baresip_systemctl_user() {
    local kiosk_uid
    kiosk_uid=$(id -u "$KIOSK_USER" 2>/dev/null) || return 1
    sudo -u "$KIOSK_USER" \
        XDG_RUNTIME_DIR="/run/user/${kiosk_uid}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${kiosk_uid}/bus" \
        systemctl --user "$@"
}

baresip_installed_version() {
    dpkg-query -W -f='${Version}' baresip 2>/dev/null || true
}

# "Installed" means both the package and a written account - a bare
# `apt install baresip` with no configured extension isn't something
# this menu should call done.
baresip_is_installed() {
    command -v baresip &>/dev/null && [[ -f "$BARESIP_CONFIG_DIR/accounts" ]]
}

baresip_is_running() {
    baresip_systemctl_user is-active --quiet baresip.service 2>/dev/null
}

addon_asterisk_intercom_status() {
    if baresip_is_installed; then
        local ver
        ver=$(baresip_installed_version)
        if baresip_is_running; then
            echo "Asterisk Intercom: Installed (v${ver:-unknown}) - Running"
        else
            echo "Asterisk Intercom: Installed (v${ver:-unknown}) - Not running"
        fi
        if [[ -f "$BARESIP_CONFIG_DIR/accounts" ]]; then
            local account
            account=$(head -1 "$BARESIP_CONFIG_DIR/accounts" 2>/dev/null)
            local extension="${account#<sip:}"
            extension="${extension%%@*}"
            [[ -n "$extension" ]] && echo "  Extension: $extension"
        fi
    else
        echo "Asterisk Intercom: Not installed"
    fi
    echo "ℹ Connects this kiosk as a SIP extension to an Asterisk server"
    echo "  you already have running elsewhere - it does not install or"
    echo "  manage Asterisk itself."
}

addon_asterisk_intercom_menu_builder() {
    if baresip_is_installed; then
        MENU_LABELS=("Reconfigure (new server/extension)" "Uninstall")
        MENU_HANDLERS=(action_configure_asterisk_intercom action_uninstall_asterisk_intercom)
    else
        MENU_LABELS=("Connect to an Asterisk server")
        MENU_HANDLERS=(action_configure_asterisk_intercom)
    fi
}

addon_asterisk_intercom_menu() {
    run_menu "ASTERISK INTERCOM (SIP EXTENSION)" addon_asterisk_intercom_menu_builder addon_asterisk_intercom_status
}

################################################################################
# Actions
################################################################################

action_configure_asterisk_intercom() {
    echo
    if baresip_is_installed; then
        echo "Asterisk Intercom is already configured."
        ask_yes_no "Reconfigure with a different server/extension?" "n" || { pause; return; }
    fi

    echo "Enter the details of the Asterisk server this kiosk should"
    echo "register to as an extension (these must match what's already"
    echo "configured on that server)."
    echo

    local server_ip=""
    while [[ -z "$server_ip" ]]; do
        server_ip=$(ask_text "Server IP or hostname" "")
        [[ -z "$server_ip" ]] && log_error "Server address is required"
    done

    local server_port
    server_port=$(ask_integer "Server port" 5060 1 65535)

    local extension=""
    while [[ -z "$extension" ]]; do
        extension=$(ask_text "Extension number (e.g. 201)" "")
        [[ -z "$extension" ]] && log_error "Extension is required"
    done

    local password=""
    while [[ -z "$password" ]]; do
        read -r -s -p "SIP password: " password
        echo
        [[ -z "$password" ]] && log_error "Password is required"
    done

    local answermode="manual"
    if ask_yes_no "Auto-answer incoming calls (intercom mode)?" "n"; then
        answermode="auto"
    fi

    local transport="udp"
    local media_enc=""
    if ask_yes_no "Use TLS encryption?" "n"; then
        transport="tls"
        media_enc=";mediaenc=srtp"
        if [[ "$server_port" == "5060" ]]; then
            server_port=5061
            echo "Note: port changed to 5061 for TLS"
        fi
    fi

    echo
    echo "Configuration summary:"
    echo "  Server:    ${server_ip}:${server_port}"
    echo "  Extension: ${extension}"
    echo "  Answer:    $([[ "$answermode" == "auto" ]] && echo "Auto" || echo "Manual")"
    echo "  TLS:       $([[ "$transport" == "tls" ]] && echo "Yes" || echo "No")"
    echo
    ask_yes_no "Proceed with installation?" "y" || { echo "Cancelled"; pause; return; }

    echo
    echo "Installing Baresip..."
    if ! command -v baresip &>/dev/null; then
        if ! sudo apt install -y baresip; then
            log_error "Failed to install baresip package"
            pause
            return 1
        fi
    fi
    sudo apt install -y pulseaudio-utils pipewire-pulse 2>/dev/null || true

    sudo mkdir -p "$BARESIP_CONFIG_DIR"

    sudo tee "$BARESIP_CONFIG_DIR/accounts" > /dev/null <<EOF
<sip:${extension}@${server_ip}:${server_port};transport=${transport}>;auth_pass=${password};answermode=${answermode}${media_enc}
EOF

    if [[ ! -f "$BARESIP_CONFIG_DIR/config" ]]; then
        sudo tee "$BARESIP_CONFIG_DIR/config" > /dev/null <<'BARESIPCONFIG'
# Baresip configuration for Asterisk Intercom

# Audio settings
audio_player             pulse,default
audio_source              pulse,default
audio_alert               pulse,default

# Call settings
call_local_timeout       120
call_max_calls           4

# Network settings
net_interface

# SIP settings
sip_trans_bsize          128
sip_verify_server        no

# Module loading
module                   pulse.so
module                   account.so
module                   contact.so
module                   menu.so
module                   stdio.so
module                   uuid.so
module                   debug_cmd.so
BARESIPCONFIG
    fi

    sudo chown -R "${KIOSK_USER}:${KIOSK_USER}" "$BARESIP_CONFIG_DIR"
    sudo chmod 600 "$BARESIP_CONFIG_DIR/accounts"

    sudo mkdir -p "$BARESIP_USER_SERVICE_DIR"
    sudo tee "$BARESIP_USER_SERVICE_DIR/baresip.service" > /dev/null <<'BARESIPUNIT'
[Unit]
Description=Baresip SIP Client
After=pipewire.service pipewire-pulse.service
Wants=pipewire-pulse.service

[Service]
Type=simple
ExecStart=/usr/bin/baresip -f %h/.baresip
Restart=always
RestartSec=5
Environment=PULSE_SERVER=unix:/run/user/%U/pulse/native

[Install]
WantedBy=default.target
BARESIPUNIT
    sudo chown -R "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config"

    if baresip_systemctl_user daemon-reload 2>/dev/null && \
       baresip_systemctl_user enable baresip.service 2>/dev/null && \
       baresip_systemctl_user start baresip.service 2>/dev/null; then
        log_success "Baresip service enabled and started"
    else
        log_warning "Baresip files written, but enabling/starting the user service failed - it will start automatically on next login. Check: systemctl --user status baresip"
    fi

    echo
    log_success "Asterisk Intercom configured"
    echo "  Config dir: ${BARESIP_CONFIG_DIR}"
    echo "  Server:     ${server_ip}:${server_port}"
    echo "  Extension:  ${extension}"
    echo
    echo "Management commands (as $KIOSK_USER):"
    echo "  Check status: systemctl --user status baresip"
    echo "  Restart:      systemctl --user restart baresip"
    echo "  View logs:    journalctl --user -u baresip -f"

    pause
}

action_uninstall_asterisk_intercom() {
    echo
    ask_yes_no "Remove Asterisk Intercom (Baresip)?" "n" || { echo "Cancelled"; pause; return; }
    asterisk_intercom_do_uninstall ask
    pause
}

# The actual removal, no confirmation prompt - shared with Complete
# Uninstall so that operation doesn't need to re-implement this teardown
# a second time. $1: "ask" to prompt about config removal interactively
# (the normal case), "purge" to remove config without asking (Complete
# Uninstall).
asterisk_intercom_do_uninstall() {
    local data_choice="${1:-ask}"

    baresip_systemctl_user stop baresip.service 2>/dev/null || true
    baresip_systemctl_user disable baresip.service 2>/dev/null || true
    sudo rm -f "$BARESIP_USER_SERVICE_DIR/baresip.service"
    sudo apt remove -y baresip 2>/dev/null || true

    local purge_config=false
    if [[ "$data_choice" == "purge" ]]; then
        purge_config=true
    elif [[ "$data_choice" == "ask" ]] && ask_yes_no "Remove saved SIP configuration too?" "n"; then
        purge_config=true
    fi

    if $purge_config; then
        sudo rm -rf "$BARESIP_CONFIG_DIR"
        log_success "Asterisk Intercom removed (configuration deleted)"
    else
        log_success "Asterisk Intercom removed (configuration preserved)"
    fi
}
