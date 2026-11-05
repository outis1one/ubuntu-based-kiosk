#!/bin/bash
################################################################################
# menus/addon_remote_access.sh - "Remote Access" addon (VNC, WireGuard,
# Tailscale, Netbird).
#
# Third Addon migrated, and the biggest so far in scope (4 sub-areas).
# All four genuinely mutate real system state at fixed paths this project
# doesn't own the layout of (apt packages, /etc/wireguard, real VPN
# client CLIs) - same risk class as CUPS. Only $WIREGUARD_DIR and
# $SYSTEMD_DIR (lib/config.sh) are parameterized, since those are the
# only paths this file itself writes to; every command (apt, systemctl,
# wg, tailscale, netbird, x11vnc) gets full stubbing in every test.
#
# Tailscale and Netbird install themselves via `curl -fsSL <vendor
# url> | sh` - the vendors' own documented install method, preserved as-
# is rather than redesigned. This is NEVER allowed to run for real in
# any test: curl itself is stubbed, not just sudo, so there is no path
# by which a test could reach the network.
#
# None of x11vnc/wg/tailscale/netbird are installed in a fresh
# environment, so their "not installed" detection is real/unstubbed and
# safe to exercise end-to-end - only the "install" actions need stubs.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

# Also read by iso/offline/build-bundle.sh to bundle them for offline
# installs. (Tailscale/Netbird aren't bundled: they install from their
# vendors' scripts and need their vendors' servers to work anyway.)
VNC_APT_PACKAGES=(x11vnc)
WIREGUARD_APT_PACKAGES=(wireguard wireguard-tools)

remote_access_status() {
    echo "VNC:       $(is_service_active x11vnc && echo "running" || echo "not installed")"
    echo "WireGuard: $(wireguard_connected && echo "connected" || (command -v wg &>/dev/null && echo "installed, not connected" || echo "not installed"))"
    echo "Tailscale: $(command -v tailscale &>/dev/null && echo "installed" || echo "not installed")"
    echo "Netbird:   $(command -v netbird &>/dev/null && echo "installed" || echo "not installed")"
}

remote_access_menu_builder() {
    MENU_LABELS=("VNC Remote Desktop" "WireGuard VPN" "Tailscale VPN" "Netbird VPN")
    MENU_HANDLERS=(vnc_menu wireguard_menu tailscale_menu netbird_menu)
}

remote_access_menu() {
    run_menu "REMOTE ACCESS" remote_access_menu_builder remote_access_status
}

################################################################################
# VNC (x11vnc)
################################################################################

vnc_status() {
    if is_service_active x11vnc; then
        echo "VNC: running - connect to $(get_ip_address):5900"
    else
        echo "VNC: not installed"
    fi
}

vnc_menu_builder() {
    if is_service_active x11vnc; then
        MENU_LABELS=("Reconfigure password" "Uninstall")
        MENU_HANDLERS=(action_vnc_change_password action_vnc_uninstall)
    else
        MENU_LABELS=("Install x11vnc")
        MENU_HANDLERS=(action_vnc_install)
    fi
}

vnc_menu() {
    run_menu "VNC REMOTE DESKTOP" vnc_menu_builder vnc_status
}

action_vnc_install() {
    echo
    ask_yes_no "Install x11vnc?" "n" || { echo "Cancelled"; return; }

    if ! run_with_offline_fallback sudo apt install -y "${VNC_APT_PACKAGES[@]}"; then
        log_error "x11vnc installation failed"
        return 1
    fi

    local vnc_pass
    read -r -s -p "VNC password: " vnc_pass
    echo
    if [[ -z "$vnc_pass" ]]; then
        log_error "No password provided - cancelled"
        return 1
    fi

    sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.vnc"
    sudo -u "$KIOSK_USER" x11vnc -storepasswd "$vnc_pass" "$KIOSK_HOME/.vnc/passwd"

    sudo tee "$SYSTEMD_DIR/x11vnc.service" > /dev/null <<EOF
[Unit]
Description=x11vnc Remote Desktop
After=lightdm.service

[Service]
Type=simple
User=${KIOSK_USER}
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -rfbauth ${KIOSK_HOME}/.vnc/passwd -forever -loop -noxdamage -repeat -shared
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    if enable_and_start_units x11vnc; then
        sudo ufw allow 5900/tcp comment 'VNC' 2>/dev/null || true
        log_success "VNC installed - connect to $(get_ip_address):5900"
    else
        log_warning "x11vnc installed but systemctl enable/start failed - check 'systemctl status x11vnc'"
    fi
}

action_vnc_change_password() {
    echo
    local vnc_pass
    read -r -s -p "New VNC password: " vnc_pass
    echo
    if [[ -z "$vnc_pass" ]]; then
        log_error "No password provided - cancelled"
        return 1
    fi

    sudo -u "$KIOSK_USER" x11vnc -storepasswd "$vnc_pass" "$KIOSK_HOME/.vnc/passwd"
    if sudo systemctl restart x11vnc 2>/dev/null; then
        log_success "VNC password updated"
    else
        log_warning "Password file updated, but restarting x11vnc failed - check 'systemctl status x11vnc'"
    fi
}

action_vnc_uninstall() {
    echo
    ask_yes_no "Remove VNC?" "n" || { echo "Cancelled"; return; }
    vnc_do_uninstall
}

# Shared with Complete Uninstall - same reasoning as cups_do_uninstall.
vnc_do_uninstall() {
    sudo systemctl stop x11vnc 2>/dev/null || true
    sudo systemctl disable x11vnc 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR/x11vnc.service"
    sudo apt remove -y x11vnc 2>/dev/null || true
    log_success "VNC removed"
}

################################################################################
# WireGuard
################################################################################

wireguard_connected() {
    command -v wg &>/dev/null && sudo wg show 2>/dev/null | grep -q interface
}

wireguard_status() {
    if wireguard_connected; then
        echo "WireGuard: connected"
        sudo wg show 2>/dev/null | grep -E "interface:|endpoint:|allowed ips:" | sed 's/^/  /' || true
    elif command -v wg &>/dev/null; then
        echo "WireGuard: installed, not connected"
    else
        echo "WireGuard: not installed"
    fi
}

wireguard_menu_builder() {
    if wireguard_connected; then
        MENU_LABELS=("Show full config" "Paste new config" "Uninstall")
        MENU_HANDLERS=(action_wireguard_show_config action_wireguard_paste_config action_wireguard_uninstall)
    elif command -v wg &>/dev/null; then
        MENU_LABELS=("Paste config" "Uninstall")
        MENU_HANDLERS=(action_wireguard_paste_config action_wireguard_uninstall)
    else
        MENU_LABELS=("Install WireGuard")
        MENU_HANDLERS=(action_wireguard_install)
    fi
}

wireguard_menu() {
    run_menu "WIREGUARD VPN" wireguard_menu_builder wireguard_status
}

action_wireguard_install() {
    echo
    ask_yes_no "Install WireGuard?" "n" || { echo "Cancelled"; return; }

    if ! run_with_offline_fallback sudo apt install -y "${WIREGUARD_APT_PACKAGES[@]}"; then
        log_error "WireGuard installation failed"
        return 1
    fi
    log_success "WireGuard installed"

    echo
    if ask_yes_no "Paste a config now?" "n"; then
        action_wireguard_paste_config
    fi
}

action_wireguard_show_config() {
    echo
    sudo wg show all
}

# Reads a WireGuard config from stdin until EOF (Ctrl+D on a real
# terminal) - same as the legacy addon. Writes to $WIREGUARD_DIR rather
# than a hardcoded /etc/wireguard, so tests can point it at scratch space
# and verify the written content without touching the real directory.
action_wireguard_paste_config() {
    echo
    echo "Paste your WireGuard config (Ctrl+D when done):"
    local config
    config=$(cat)

    if [[ -z "$config" ]]; then
        log_error "No config provided"
        return 1
    fi

    local wg_name
    wg_name=$(ask_text "Config name" "wg0")

    sudo mkdir -p "$WIREGUARD_DIR"
    echo "$config" | sudo tee "$WIREGUARD_DIR/${wg_name}.conf" > /dev/null
    sudo chmod 600 "$WIREGUARD_DIR/${wg_name}.conf"

    if enable_and_start_units "wg-quick@${wg_name}"; then
        log_success "WireGuard configured: $wg_name"
    else
        log_warning "Config written, but systemctl enable/start failed - check 'systemctl status wg-quick@${wg_name}'"
    fi
}

action_wireguard_uninstall() {
    echo
    ask_yes_no "Remove WireGuard?" "n" || { echo "Cancelled"; return; }
    wireguard_do_uninstall
}

# Shared with Complete Uninstall - same reasoning as cups_do_uninstall.
wireguard_do_uninstall() {
    sudo systemctl stop 'wg-quick@*' 2>/dev/null || true
    sudo systemctl disable 'wg-quick@*' 2>/dev/null || true
    sudo apt remove -y wireguard wireguard-tools 2>/dev/null || true
    log_success "WireGuard removed"
}

################################################################################
# Tailscale
################################################################################

tailscale_backend_state() {
    tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown"
}

tailscale_status() {
    if ! command -v tailscale &>/dev/null; then
        echo "Tailscale: not installed"
        return
    fi

    if [[ "$(tailscale_backend_state)" == "Running" ]]; then
        echo "Tailscale: connected"
        echo "  SSH:      $(tailscale_ssh_enabled && echo "enabled" || echo "disabled")"
        echo "  Hostname: $(tailscale status --json 2>/dev/null | jq -r '.Self.HostName // "unknown"')"
        echo "  IP:       $(tailscale ip -4 2>/dev/null)"
    else
        echo "Tailscale: installed, not connected"
    fi
}

# Tailscale SSH: tailscaled itself answers SSH on this machine's tailnet
# address, authenticated by tailnet identity - no keys to manage. Which
# users may log in as whom is set by the tailnet's ACL "ssh" rules in the
# Tailscale admin console (https://login.tailscale.com/admin/acls).
tailscale_ssh_enabled() {
    [[ "$(tailscale debug prefs 2>/dev/null | jq -r '.RunSSH // false' 2>/dev/null)" == "true" ]]
}

# Echoes "--ssh" when the user wants Tailscale SSH, nothing otherwise.
tailscale_ask_ssh_flag() {
    if ask_yes_no "Enable Tailscale SSH (log in over the tailnet, no SSH keys)?" "y" >&2; then
        echo "--ssh"
    fi
}

action_tailscale_toggle_ssh() {
    echo
    if [[ "$(tailscale_backend_state)" != "Running" ]]; then
        log_error "Connect Tailscale first (Connect, above)"
        return 1
    fi
    if tailscale_ssh_enabled; then
        ask_yes_no "Tailscale SSH is ENABLED. Disable it?" "n" || { echo "Cancelled"; return; }
        sudo tailscale set --ssh=false && log_success "Tailscale SSH disabled"
    else
        sudo tailscale set --ssh=true && log_success "Tailscale SSH enabled"
        echo "Allow it in your tailnet ACL (\"ssh\" rules): https://login.tailscale.com/admin/acls"
    fi
}

tailscale_menu_builder() {
    if command -v tailscale &>/dev/null; then
        MENU_LABELS=("Connect (interactive)" "Connect with auth key" "Enable/disable Tailscale SSH" "Show status" "Uninstall")
        MENU_HANDLERS=(action_tailscale_connect_interactive action_tailscale_connect_authkey action_tailscale_toggle_ssh action_tailscale_show_status action_tailscale_uninstall)
    else
        MENU_LABELS=("Install Tailscale")
        MENU_HANDLERS=(action_tailscale_install)
    fi
}

tailscale_menu() {
    run_menu "TAILSCALE VPN" tailscale_menu_builder tailscale_status
}

# $1 = "noconfirm" skips the "Install?" question (first-time install
# has already asked).
action_tailscale_install() {
    echo
    if [[ "${1:-}" != "noconfirm" ]]; then
        ask_yes_no "Install Tailscale?" "n" || { echo "Cancelled"; return; }
    fi

    if ! curl -fsSL https://tailscale.com/install.sh | sh; then
        log_error "Tailscale installation failed"
        return 1
    fi
    log_success "Tailscale installed"

    echo
    echo "Options:"
    echo "  1. Connect now (interactive)"
    echo "  2. Connect with auth key"
    echo "  3. Connect later"
    local choice
    choice=$(ask_integer "Choose" "3" 1 3)
    case "$choice" in
        1) action_tailscale_connect_interactive ;;
        2) action_tailscale_connect_authkey ;;
    esac
}

action_tailscale_connect_interactive() {
    echo
    local ssh_flag
    ssh_flag=$(tailscale_ask_ssh_flag)
    # shellcheck disable=SC2086 # ssh_flag is empty or exactly "--ssh"
    if sudo tailscale up $ssh_flag; then
        log_success "Tailscale connected"
    else
        log_error "Tailscale connection failed"
    fi
}

action_tailscale_connect_authkey() {
    echo
    echo "Get an auth key from: https://login.tailscale.com/admin/settings/keys"
    local authkey
    read -r -p "Enter auth key: " authkey
    if [[ -z "$authkey" ]]; then
        echo "Cancelled"
        return
    fi

    local ssh_flag
    ssh_flag=$(tailscale_ask_ssh_flag)
    # shellcheck disable=SC2086 # ssh_flag is empty or exactly "--ssh"
    if sudo tailscale up --authkey="$authkey" $ssh_flag; then
        log_success "Tailscale connected"
    else
        log_error "Tailscale connection failed"
    fi
}

action_tailscale_show_status() {
    echo
    tailscale status
}

action_tailscale_uninstall() {
    echo
    ask_yes_no "Remove Tailscale?" "n" || { echo "Cancelled"; return; }
    tailscale_do_uninstall
}

# Shared with Complete Uninstall - same reasoning as cups_do_uninstall.
tailscale_do_uninstall() {
    sudo tailscale down 2>/dev/null || true
    sudo apt remove -y tailscale 2>/dev/null || true
    log_success "Tailscale removed"
}

################################################################################
# Netbird
################################################################################

netbird_connected() {
    [[ "$(netbird status 2>/dev/null | grep "Status:" | awk '{print $2}')" == "Connected" ]]
}

netbird_status() {
    if ! command -v netbird &>/dev/null; then
        echo "Netbird: not installed"
        return
    fi

    if netbird_connected; then
        echo "Netbird: connected"
        echo "  SSH:      $(netbird_ssh_enabled && echo "enabled" || echo "disabled")"
        netbird status 2>/dev/null | grep -E "NetBird IP:|Public key:" | sed 's/^/  /' || true
    else
        echo "Netbird: installed, not connected"
    fi
}

# Netbird's built-in SSH server listens on port 22022 on the Netbird
# interface (wt0). ufw's default-deny-incoming (lib/provision.sh) would
# block it, so open that port on wt0 only.
netbird_ssh_enabled() {
    netbird status 2>/dev/null | grep -qiE '^SSH Server:.*(enabled|true)' ||
        sudo -n grep -qE '"ServerSSHAllowed": *true' /var/lib/netbird/default.json 2>/dev/null
}

netbird_open_ssh_firewall() {
    if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        sudo ufw allow in on wt0 to any port 22022 proto tcp >/dev/null &&
            log_info "Firewall: allowed Netbird SSH (22022) on wt0 only"
    fi
}

action_netbird_toggle_ssh() {
    echo
    if ! netbird_connected; then
        log_error "Connect Netbird first (Connect, above)"
        return 1
    fi
    if netbird_ssh_enabled; then
        ask_yes_no "Netbird SSH is ENABLED. Disable it?" "n" || { echo "Cancelled"; return; }
        sudo netbird up --allow-server-ssh=false && log_success "Netbird SSH disabled"
    else
        sudo netbird up --allow-server-ssh && log_success "Netbird SSH enabled" &&
            netbird_open_ssh_firewall
        echo "Connect from another Netbird peer: ssh <user>@<netbird-ip> (port 22022 if your client needs it)"
    fi
}

netbird_menu_builder() {
    if command -v netbird &>/dev/null; then
        MENU_LABELS=("Connect with setup key" "Enable/disable Netbird SSH" "Show status" "Uninstall")
        MENU_HANDLERS=(action_netbird_connect action_netbird_toggle_ssh action_netbird_show_status action_netbird_uninstall)
    else
        MENU_LABELS=("Install Netbird")
        MENU_HANDLERS=(action_netbird_install)
    fi
}

netbird_menu() {
    run_menu "NETBIRD VPN" netbird_menu_builder netbird_status
}

# $1 = "noconfirm" skips the "Install?" question (first-time install
# has already asked).
action_netbird_install() {
    echo
    if [[ "${1:-}" != "noconfirm" ]]; then
        ask_yes_no "Install Netbird?" "n" || { echo "Cancelled"; return; }
    fi

    if ! curl -fsSL https://pkgs.netbird.io/install.sh | sh; then
        log_error "Netbird installation failed"
        return 1
    fi
    log_success "Netbird installed"

    echo
    if ask_yes_no "Connect with a setup key now?" "n"; then
        action_netbird_connect
    fi
}

action_netbird_connect() {
    echo
    echo "Get a setup key from the Netbird dashboard"
    local setup_key
    read -r -p "Enter setup key: " setup_key
    if [[ -z "$setup_key" ]]; then
        echo "Cancelled"
        return
    fi

    local ssh_flag=()
    if ask_yes_no "Enable Netbird SSH (log in over the Netbird network)?" "y"; then
        ssh_flag=(--allow-server-ssh)
    fi
    if sudo netbird up --setup-key "$setup_key" "${ssh_flag[@]}"; then
        log_success "Netbird connected"
        if [[ ${#ssh_flag[@]} -gt 0 ]]; then netbird_open_ssh_firewall; fi
    else
        log_error "Netbird connection failed"
    fi
}

action_netbird_show_status() {
    echo
    netbird status
}

action_netbird_uninstall() {
    echo
    ask_yes_no "Remove Netbird?" "n" || { echo "Cancelled"; return; }
    netbird_do_uninstall
}

# Shared with Complete Uninstall - same reasoning as cups_do_uninstall.
netbird_do_uninstall() {
    sudo netbird down 2>/dev/null || true
    sudo apt remove -y netbird 2>/dev/null || true
    log_success "Netbird removed"
}

################################################################################
# First-time install hook (called from lib/provision.sh): offer to set up
# one of the two mesh-VPN providers with SSH enabled, so the kiosk is
# reachable remotely right after install.
################################################################################
remote_ssh_first_time_setup() {
    echo
    echo "Remote SSH access over a mesh VPN lets you manage the kiosk from"
    echo "anywhere with no port forwarding:"
    echo "  1. Tailscale (with Tailscale SSH)"
    echo "  2. Netbird   (with Netbird SSH)"
    echo "  3. Skip (configure later: Addons -> Remote Access)"
    local choice
    choice=$(ask_integer "Choose" "3" 1 3)
    case "$choice" in
        1) action_tailscale_install noconfirm ;;
        2) action_netbird_install noconfirm ;;
        *) log_info "Configure later: Addons -> Remote Access" ;;
    esac
}
