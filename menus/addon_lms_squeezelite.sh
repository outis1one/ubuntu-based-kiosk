#!/bin/bash
################################################################################
# menus/addon_lms_squeezelite.sh - "LMS Server / Squeezelite Player" addon.
#
# Two independent pieces sharing one menu, same as the legacy code: an LMS
# (Lyrion/Logitech Media Server) server the kiosk can host, and a
# Squeezelite player the kiosk can run to play music from any LMS server
# (this one or another one on the LAN). LMS itself is a real apt-managed
# subsystem with its own fixed paths (repo file, GPG keyring, ufw rules,
# /etc/squeezeboxserver) - like CUPS, those get full command-level `sudo`/
# `wget`/`apt` stubbing in tests rather than relocation. Squeezelite's own
# start script and systemd unit are ours to place, so - like power_schedule
# and the other addons - they go through $BIN_DIR/$SYSTEMD_DIR (lib/
# config.sh) instead of hardcoded /usr/local/bin and /etc/systemd/system,
# so tests can point them at a scratch directory.
#
# LMS ships under two package/service names depending on version -
# "logitechmediaserver" (older) and "lyrionmusicserver" (the project's
# current name after its rename) - so detection and every service call
# has to check both.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

lms_service_name() {
    if systemctl list-unit-files 2>/dev/null | grep -q "lyrionmusicserver.service"; then
        echo "lyrionmusicserver"
    elif systemctl list-unit-files 2>/dev/null | grep -q "logitechmediaserver.service"; then
        echo "logitechmediaserver"
    fi
}

lms_is_installed() {
    is_service_active logitechmediaserver || is_service_enabled logitechmediaserver || \
        is_service_active lyrionmusicserver || is_service_enabled lyrionmusicserver
}

lms_is_running() {
    is_service_active logitechmediaserver || is_service_active lyrionmusicserver
}

squeezelite_is_installed() {
    is_service_active squeezelite || is_service_enabled squeezelite
}

addon_lms_squeezelite_status() {
    if lms_is_installed; then
        echo "LMS Server: Installed"
        if lms_is_running; then
            echo "  Status: Running"
        else
            echo "  Status: Stopped"
        fi
        echo "  Web: http://$(get_ip_address):9000"
        echo
    fi

    if squeezelite_is_installed; then
        local player_name="Unknown"
        if [[ -f "$BIN_DIR/squeezelite-start.sh" ]]; then
            player_name=$(grep '^PLAYER_NAME=' "$BIN_DIR/squeezelite-start.sh" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "Unknown")
        fi
        echo "Squeezelite Player: Installed"
        if is_service_active squeezelite; then
            echo "  Status: Running"
        else
            echo "  Status: Stopped"
        fi
        echo "  Name: $player_name"
        echo
    fi

    echo "ℹ A server is needed to stream music. The kiosk can run the"
    echo "  server (if sufficient resources) or connect to another server."
}

addon_lms_squeezelite_menu_builder() {
    MENU_LABELS=("Install/Configure LMS Server" "Install/Configure Squeezelite Player")
    MENU_HANDLERS=(action_install_lms action_install_squeezelite)

    if lms_is_installed; then
        MENU_LABELS+=("Uninstall LMS Server")
        MENU_HANDLERS+=(action_uninstall_lms)
    fi

    if squeezelite_is_installed; then
        MENU_LABELS+=("Uninstall Squeezelite Player")
        MENU_HANDLERS+=(action_uninstall_squeezelite)
    fi
}

addon_lms_squeezelite_menu() {
    run_menu "LMS SERVER / SQUEEZELITE PLAYER" addon_lms_squeezelite_menu_builder addon_lms_squeezelite_status
}

################################################################################
# Actions - LMS Server
################################################################################

action_install_lms() {
    echo
    if lms_is_installed; then
        echo "LMS is already installed."
        if ask_yes_no "Reconfigure port?" "n"; then
            local new_port
            new_port=$(ask_integer "New HTTP port" 9000 1 65535)
            sudo sed -i "s/httpport:.*/httpport: $new_port/" /etc/squeezeboxserver/prefs/server.prefs 2>/dev/null || true
            sudo systemctl restart lyrionmusicserver 2>/dev/null || sudo systemctl restart logitechmediaserver 2>/dev/null || true
            log_success "LMS reconfigured on port $new_port"
        fi
        pause
        return
    fi

    echo "Installing Lyrion Music Server..."

    # Try the repository method first.
    if wget -qO - https://debian.slimdevices.com/debian/squeezebox-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/lms-keyring.gpg 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/lms-keyring.gpg] http://debian.slimdevices.com/debian stable main" | sudo tee /etc/apt/sources.list.d/lms.list
        # `|| true`: a bare, unguarded `apt update` failing here (bad
        # mirror, no network) would otherwise crash the whole session
        # under set -e instead of falling through to the direct-download
        # fallback below, which is exactly the degrade path this is
        # supposed to hit when the repository route doesn't work.
        sudo apt update 2>/dev/null || true
        if sudo apt install -y logitechmediaserver 2>/dev/null; then
            log_success "LMS installed via repository"
        else
            log_warning "Repository install failed, trying direct download..."
        fi
    fi

    # Fall back to a direct .deb download if the repository didn't produce
    # either possible package.
    if ! command -v logitechmediaserver &>/dev/null && ! command -v lyrionmusicserver &>/dev/null; then
        local lms_deb="/tmp/lms.deb"
        echo "Downloading LMS v9.0.3..."
        if wget -q https://downloads.lms-community.org/LyrionMusicServer_v9.0.3/lyrionmusicserver_9.0.3_amd64.deb -O "$lms_deb"; then
            echo "Installing LMS package..."
            if sudo apt install -y "$lms_deb"; then
                log_success "LMS installed via direct download"
            else
                log_error "Failed to install LMS package"
                rm -f "$lms_deb"
                pause
                return 1
            fi
            rm -f "$lms_deb"
        else
            log_error "Failed to download LMS from lms-community.org"
            pause
            return 1
        fi
    fi

    local service_name
    service_name=$(lms_service_name)

    if [[ -z "$service_name" ]]; then
        log_warning "Service file not found, checking installed files..."
        service_name=$(dpkg -L lyrionmusicserver logitechmediaserver 2>/dev/null | grep -m1 '\.service$' | xargs -r basename | sed 's/\.service$//' || echo "")
    fi

    if [[ -z "$service_name" ]]; then
        log_error "Could not detect LMS service name"
        echo "Manual steps:"
        echo "  1. Find service: systemctl list-unit-files | grep -i lms"
        echo "  2. Enable: sudo systemctl enable SERVICE_NAME"
        echo "  3. Start: sudo systemctl start SERVICE_NAME"
        pause
        return 1
    fi

    log_info "Using service: $service_name"
    # enable_and_start_units, not a bare `sudo systemctl enable ... | tee`
    # pipe: the legacy version's `2>&1 | tee /tmp/lms-enable.log` made the
    # whole statement's exit status depend on `tee` (always 0) rather than
    # `systemctl enable`, so a real enable/start failure was silently
    # swallowed instead of falling through to the warning below.
    if enable_and_start_units "$service_name"; then
        sudo ufw allow 9000/tcp comment 'LMS-HTTP' 2>/dev/null || true
        sudo ufw allow 3483/tcp comment 'LMS-SlimProto' 2>/dev/null || true
        sudo ufw allow 3483/udp comment 'LMS-Discovery' 2>/dev/null || true

        log_success "LMS installed"
        echo "  Web interface: http://$(get_ip_address):9000"
    else
        log_warning "LMS installed, but systemctl enable/start failed - check 'systemctl status $service_name'"
    fi

    pause
}

action_uninstall_lms() {
    echo
    ask_yes_no "Remove LMS Server?" "n" || { echo "Cancelled"; pause; return; }
    lms_do_uninstall ask
    pause
}

# The actual removal, no confirmation prompt - shared with Complete
# Uninstall so that operation doesn't need to re-implement LMS teardown a
# second time. $1: "ask" to prompt about data removal interactively (the
# normal case), "purge" to remove data without asking (Complete Uninstall).
lms_do_uninstall() {
    local data_choice="${1:-ask}"

    local service_name
    service_name=$(lms_service_name)

    if [[ -n "$service_name" ]]; then
        echo "Stopping $service_name..."
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
    fi

    # Try to remove both possible package names - only one will actually
    # be installed, the other is a harmless no-op.
    sudo apt remove -y lyrionmusicserver 2>/dev/null || true
    sudo apt remove -y logitechmediaserver 2>/dev/null || true

    sudo rm -f /etc/apt/sources.list.d/lms.list
    sudo rm -f /usr/share/keyrings/lms-keyring.gpg

    local purge_data=false
    if [[ "$data_choice" == "purge" ]]; then
        purge_data=true
    elif [[ "$data_choice" == "ask" ]] && ask_yes_no "Remove LMS data and configuration?" "n"; then
        purge_data=true
    fi

    if $purge_data; then
        sudo rm -rf /var/lib/squeezeboxserver
        sudo rm -rf /etc/squeezeboxserver
        log_success "LMS and data removed"
    else
        log_success "LMS removed (data preserved)"
    fi
}

################################################################################
# Actions - Squeezelite Player
################################################################################

action_install_squeezelite() {
    echo
    if squeezelite_is_installed; then
        echo "Squeezelite is already installed."
        ask_yes_no "Reconfigure?" "n" || { pause; return; }
    fi

    if ! command -v squeezelite &>/dev/null; then
        if ! sudo apt install -y squeezelite; then
            log_error "squeezelite package installation failed"
            pause
            return 1
        fi
    fi

    local player_name
    player_name=$(ask_text "Player name" "Kiosk")

    echo
    echo "LMS Server Configuration:"
    echo "  Enter IP:PORT of your LMS server"
    echo "  Leave blank for auto-discovery on LAN"
    echo
    local lms_server
    lms_server=$(ask_text "LMS Server (e.g., 192.168.1.100:3483)" "")

    sudo tee "$BIN_DIR/squeezelite-start.sh" > /dev/null <<SQSTART
#!/bin/bash

PLAYER_NAME="$player_name"
LMS_SERVER="$lms_server"

for i in {1..20}; do
    pactl info >/dev/null 2>&1 && break
    sleep 1
done

if ! pactl info >/dev/null 2>&1; then
    logger "ERROR: Squeezelite - PipeWire not available"
    exit 1
fi

if [[ -n "\$LMS_SERVER" ]]; then
    exec /usr/bin/squeezelite -n "\$PLAYER_NAME" -s "\$LMS_SERVER" -o pulse -a 80:4:: -b 512:1024 -C 5
else
    exec /usr/bin/squeezelite -n "\$PLAYER_NAME" -o pulse -a 80:4:: -b 512:1024 -C 5
fi
SQSTART

    sudo chmod +x "$BIN_DIR/squeezelite-start.sh"

    local kiosk_uid
    kiosk_uid=$(id -u "$KIOSK_USER")

    sudo tee "$SYSTEMD_DIR/squeezelite.service" > /dev/null <<EOF
[Unit]
Description=Squeezelite
After=sound.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$KIOSK_USER
Environment="XDG_RUNTIME_DIR=/run/user/$kiosk_uid"
ExecStartPre=/bin/sleep 10
ExecStart=${BIN_DIR}/squeezelite-start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload 2>/dev/null || true
    # Enable only, not start: squeezelite needs the kiosk user's real
    # session (PipeWire, XDG_RUNTIME_DIR) up first, which is why a reboot
    # is required below rather than starting it immediately.
    if ! sudo systemctl enable squeezelite 2>/dev/null; then
        log_warning "Squeezelite files written, but 'systemctl enable' failed - check 'systemctl status squeezelite'"
    fi

    log_success "Squeezelite installed: $player_name"
    if [[ -n "$lms_server" ]]; then
        echo "  Server: $lms_server"
    else
        echo "  Server: Auto-discovery"
    fi
    echo
    echo "⚠️  IMPORTANT: Squeezelite requires a reboot to work properly"
    echo
    if ask_yes_no "Reboot now?" "n"; then
        echo "Rebooting in 5 seconds..."
        sleep 5
        sudo reboot
    else
        echo "⚠️  Remember to reboot before using Squeezelite"
        echo "  Command: sudo reboot"
    fi

    pause
}

action_uninstall_squeezelite() {
    echo
    ask_yes_no "Remove Squeezelite Player?" "n" || { echo "Cancelled"; pause; return; }
    squeezelite_do_uninstall
    pause
}

# Shared with Complete Uninstall - same reasoning as lms_do_uninstall.
squeezelite_do_uninstall() {
    sudo systemctl stop squeezelite 2>/dev/null || true
    sudo systemctl disable squeezelite 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR/squeezelite.service"
    sudo rm -f "$BIN_DIR/squeezelite-start.sh"
    sudo apt remove -y squeezelite 2>/dev/null || true
    log_success "Squeezelite removed"
}
