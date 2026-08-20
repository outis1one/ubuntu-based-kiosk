#!/bin/bash
################################################################################
# lib/provision.sh - First-time kiosk provisioning: turns a bare Ubuntu
# Server box into a working kiosk. This is the piece the modular tool
# never had - everything else in menus/*.sh only manages a kiosk that
# already exists.
#
# The legacy ubuntu-based-kiosk.sh did this in one ~4,000-line function
# (first_time_install) that mixed three different things together:
#   1. ~2,900 lines of embedded app source (main.js, preload.js, 4 HTML
#      dialogs, package.json, start.sh), written via `sudo tee ... <<'EOF'`.
#   2. A few hundred more lines of embedded system scripts/units/configs
#      (HDMI mirroring, audio routing, hotplug udev rules, power button
#      handling, etc), written the same way.
#   3. The actual provisioning logic - roughly 1,000 lines once (1) and
#      (2) are out of the way.
#
# Every one of those embedded files used a quoted heredoc delimiter
# (<<'EOF', not <<EOF) - meaning none of them did variable substitution
# at write time - so they've been extracted byte-for-byte into real
# files: the app source under kiosk-app/, everything else under
# provision/files/ (mirroring its real destination path, e.g.
# provision/files/etc/X11/xorg.conf.d/foo.conf -> /etc/X11/xorg.conf.d/foo.conf).
# This function copies them into place instead of re-embedding them, and
# calls straight into the Core Settings / Addons / Advanced menus this
# tool already has for configuration - sites, timezone, touch/nav
# settings, password protection, WiFi, schedules, emergency hotspot, and
# virtual consoles are NOT reimplemented a third time here.
#
# One known, deliberate limitation carried over unchanged: several of
# the extracted system scripts (start.sh, kiosk-hotplug.sh, the power
# button handler) hardcode the username "kiosk" rather than using
# $KIOSK_USER, exactly as the legacy heredocs did (quoted heredocs can't
# substitute at write time either way). Fine for the common case since
# $KIOSK_USER is virtually never overridden outside this project's own
# tests, but a real gap if someone ever does. Not fixed here - fixing it
# means moving those scripts off static templates onto generated ones,
# which is more risk than this pass should take on.
#
# Depends on: lib/menu.sh, lib/config.sh, lib/electron.sh being sourced
# first, and every menus/*.sh this calls into for configuration
# (including menus/addon_webui.sh, for provision_configure_webui below).
################################################################################

PROVISION_FILES="$SCRIPT_DIR/provision/files"
KIOSK_APP_SRC="$SCRIPT_DIR/kiosk-app"

# provision_install_file SRC_REL DEST [MODE]
# Copies a template from provision/files/SRC_REL to the real system path
# DEST (creating parent directories as needed) as root, mode 644 unless
# overridden - pass 755 for scripts, 750 for the openbox autostart.
provision_install_file() {
    local src_rel="$1" dest="$2" mode="${3:-644}"
    sudo install -D -m "$mode" "$PROVISION_FILES/$src_rel" "$dest"
}

provision_install_packages() {
    echo "[1/10] Installing packages..."
    sudo apt update
    sudo apt install -y \
      xorg openbox lightdm unclutter screen curl git build-essential \
      ca-certificates gnupg lsb-release jq ufw x11-xserver-utils xinput \
      vainfo mesa-utils libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers \
      libva2 libva-drm2 libva-x11-2 mesa-va-drivers \
      libegl-mesa0 libegl1-mesa-dev libgles2-mesa-dev \
      pipewire pipewire-pulse pipewire-alsa wireplumber pipewire-audio-client-libraries alsa-utils libnotify-bin \
      gstreamer1.0-pipewire libspa-0.2-bluetooth \
      systemd-timesyncd acpid xbindkeys xdotool python3-evdev unzip \
      net-tools ncdu evtest

    if lspci | grep -i "VGA.*Intel" >/dev/null 2>&1; then
        sudo apt install -y intel-gpu-tools xserver-xorg-video-intel \
          i965-va-driver intel-media-va-driver
        provision_install_file "etc/X11/xorg.conf.d/20-intel.conf" /etc/X11/xorg.conf.d/20-intel.conf
    fi

    sudo systemctl enable systemd-timesyncd
    sudo systemctl start systemd-timesyncd
    log_success "Packages installed, NTP time sync enabled"
}

provision_create_kiosk_user() {
    echo "[2/10] Creating kiosk user..."
    if ! id "$KIOSK_USER" &>/dev/null; then
        sudo useradd -m -s /bin/bash -G audio,video,input,plugdev,netdev "$KIOSK_USER"
        echo "$KIOSK_USER:kiosk" | sudo chpasswd
        log_success "Kiosk user created (default password: kiosk - change it)"
    else
        log_success "Kiosk user already exists"
    fi

    sudo mkdir -p "$KIOSK_DIR"
    sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME"

    sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.config/pipewire/pipewire.conf.d"
    provision_install_file "pipewire/99-noise-cancellation.conf" \
        "$KIOSK_HOME/.config/pipewire/pipewire.conf.d/99-noise-cancellation.conf"
    sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"
}

provision_install_nodejs() {
    echo "[3/10] Installing Node.js..."
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt install -y nodejs
    fi
    echo "Node.js: $(node -v)"
}

provision_install_app() {
    echo "[4/10] Installing kiosk app..."
    sudo cp "$KIOSK_APP_SRC"/*.js "$KIOSK_APP_SRC"/*.html "$KIOSK_APP_SRC/package.json" "$KIOSK_APP_SRC/start.sh" "$KIOSK_DIR/"
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"/*.js "$KIOSK_DIR"/*.html "$KIOSK_DIR/package.json" "$KIOSK_DIR/start.sh"
    sudo chmod +x "$KIOSK_DIR/start.sh"

    echo "Installing npm dependencies (Electron ~120MB - may take several minutes)..."
    sudo -u "$KIOSK_USER" bash -lc "
        npm config set fetch-timeout 600000
        npm config set fetch-retries 5
        npm config set fetch-retry-mintimeout 30000
        npm config set fetch-retry-maxtimeout 300000
    "
    if ! sudo -u "$KIOSK_USER" bash -lc "cd '$KIOSK_DIR' && npm install --unsafe-perm"; then
        log_error "npm install failed"
        return 1
    fi

    electron_install_binary
}

# Not moved to lib/electron.sh or anywhere else - this is the one piece
# of first-time setup with no modular equivalent to call into, and
# nothing else needs it.
provision_configure_lightdm_autologin() {
    sudo mkdir -p /etc/lightdm/lightdm.conf.d
    # nopasswdlogin is checked by PAM on Ubuntu 24.04; autologin group for older versions
    sudo groupadd -f nopasswdlogin
    sudo groupadd -f autologin
    sudo usermod -aG nopasswdlogin,autologin "$KIOSK_USER"
    # [Seat:*] works on all LightDM versions; [SeatDefaults] is ignored on newer Ubuntu
    sudo tee /etc/lightdm/lightdm.conf.d/10-kiosk.conf > /dev/null <<EOF
[Seat:*]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=openbox
autologin-session=openbox
greeter-hide-users=true
greeter-show-manual-login=false
allow-guest=false
EOF
}

provision_configure_display() {
    echo "[5/10] Configuring display (LightDM/Openbox/touch/video)..."

    sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.config/openbox" "$KIOSK_HOME/.config/pulse"
    sudo mkdir -p /etc/X11/xorg.conf.d

    # Touch screens always use libinput (proper multitouch for Chromium
    # gestures) and virtual consoles start enabled - matches the choice
    # a fresh kiosk ships with; menus/advanced_virtual_consoles.sh can
    # flip this later, and does below if declined at the end of setup.
    provision_install_file "etc/X11/xorg.conf.d/99-finger-libinput.conf" /etc/X11/xorg.conf.d/99-finger-libinput.conf
    provision_install_file "etc/X11/xorg.conf.d/10-serverflags.conf" /etc/X11/xorg.conf.d/10-serverflags.conf

    provision_install_file "usr/local/bin/kiosk-mirror-display.sh" /usr/local/bin/kiosk-mirror-display.sh 755
    provision_install_file "usr/local/bin/kiosk-audio-route.sh" /usr/local/bin/kiosk-audio-route.sh 755

    provision_install_file "openbox/autostart" "$KIOSK_HOME/.config/openbox/autostart" 750
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config/openbox/autostart"
    sudo -u "$KIOSK_USER" touch "$KIOSK_HOME/.xbindkeysrc"

    # HDMI hotplug: re-mirror any newly connected external display without
    # waiting for the next login, triggered by udev on DRM "change" events.
    provision_install_file "usr/local/bin/kiosk-hotplug.sh" /usr/local/bin/kiosk-hotplug.sh 755
    provision_install_file "etc/systemd/system/kiosk-hotplug.service" /etc/systemd/system/kiosk-hotplug.service
    provision_install_file "etc/udev/rules.d/99-kiosk-hotplug.rules" /etc/udev/rules.d/99-kiosk-hotplug.rules
    sudo systemctl daemon-reload
    sudo udevadm control --reload-rules

    provision_configure_lightdm_autologin

    log_success "Display configured"
}

provision_configure_firewall() {
    echo "[6/10] Configuring firewall..."
    sudo ufw --force enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    log_success "Firewall configured (SSH allowed, incoming denied by default)"
}

provision_configure_power_management() {
    echo "[7/10] Configuring power management..."
    sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
    provision_install_file "etc/polkit-1/localauthority/50-local.d/kiosk-power.pkla" /etc/polkit-1/localauthority/50-local.d/kiosk-power.pkla

    provision_install_file "usr/local/bin/kiosk-volume-up" /usr/local/bin/kiosk-volume-up 755
    provision_install_file "usr/local/bin/kiosk-volume-down" /usr/local/bin/kiosk-volume-down 755

    provision_install_file "usr/local/bin/kiosk-power-button.sh" /usr/local/bin/kiosk-power-button.sh 755
    # Backwards-compatible second location some older docs/scripts reference.
    sudo cp /usr/local/bin/kiosk-power-button.sh "$KIOSK_HOME/trigger-power-menu.sh"
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/trigger-power-menu.sh"
    provision_install_file "usr/local/bin/test-power-button" /usr/local/bin/test-power-button 755

    sudo rm -f /etc/acpi/events/powerbtn* /etc/acpi/events/power* 2>/dev/null || true
    provision_install_file "etc/acpi/events/kiosk-power-button" /etc/acpi/events/kiosk-power-button
    provision_install_file "etc/acpi/events/kiosk-power-pbtn" /etc/acpi/events/kiosk-power-pbtn
    provision_install_file "etc/acpi/events/kiosk-power-pwr" /etc/acpi/events/kiosk-power-pwr

    sudo mkdir -p /etc/systemd/logind.conf.d
    provision_install_file "etc/systemd/logind.conf.d/power-button.conf" /etc/systemd/logind.conf.d/power-button.conf

    sudo systemctl daemon-reload
    sudo systemctl restart systemd-logind
    sudo systemctl enable acpid
    sudo systemctl restart acpid

    sleep 2
    if systemctl is-active --quiet acpid; then
        log_success "Power button configured"
    else
        log_warning "acpid may not be running properly - check: sudo systemctl status acpid"
    fi
}

# Installed by default now, not opt-in - reuses menus/addon_webui.sh's
# own install helpers directly rather than duplicating them, with a
# fixed default port and no prompt (first-time install already has
# plenty). See that file's header for the privilege model (a narrow
# allow-listed root helper, not the service itself running as root) and
# why this exists at all: browser-based config editing, and - via that
# helper - install/reconfigure for CUPS/LMS/Squeezelite/Asterisk
# Intercom and Update, none of which are reimplemented here.
provision_configure_webui() {
    echo "[8/10] Installing Web UI..."
    if ! webui_install_app_files; then
        log_warning "Web UI install failed - configure later: Addons -> Web UI"
        return 0
    fi

    local port="8090"
    webui_write_env_file "$port"
    webui_write_unit_file
    webui_write_helper_script
    if ! webui_write_sudoers_file; then
        log_warning "Web UI installed but its addon-install/Update helper could not be granted permission - configure later: Addons -> Web UI"
        return 0
    fi

    if enable_and_start_units kiosk-webui; then
        sudo ufw allow "${port}/tcp" comment 'Kiosk Web UI' 2>/dev/null || true
        log_success "Web UI installed: http://$(get_ip_address):${port}"
    else
        log_warning "Web UI installed but failed to start - check: sudo journalctl -u kiosk-webui -n 50"
    fi
}

# Configuration from here on is NOT reimplemented - it's the exact same
# Core Settings / Advanced menus this tool already uses to manage a
# kiosk after install, called directly instead of duplicated.
provision_configure_kiosk_settings() {
    echo "[9/10] Configuring kiosk settings..."
    echo "Core Settings is next - sites, timezone, touch/navigation,"
    echo "password protection, WiFi, and schedules. Skip and configure"
    echo "later via ./install.sh if you'd rather do this after reboot."
    echo
    if ask_yes_no "Configure Core Settings now?" "y"; then
        core_settings_menu
    fi

    echo
    echo "Emergency Hotspot auto-starts a WiFi hotspot if no internet is"
    echo "detected after boot, so you can connect and reconfigure remotely."
    if ask_yes_no "Configure emergency hotspot now?" "n"; then
        action_configure_emergency_hotspot
    else
        log_info "Configure later: Advanced -> Emergency Hotspot"
    fi

    echo
    echo "Virtual consoles (Ctrl+Alt+F1-F8) are ENABLED by default."
    if ! ask_yes_no "Keep virtual consoles enabled?" "y"; then
        action_disable_virtual_consoles
    fi
}

provision_finish() {
    echo "[10/10] Done."
    echo
    log_success "Core installation complete!"
    echo
    echo "Run ./install.sh again anytime to configure Core Settings, Addons"
    echo "(CUPS, LMS/Squeezelite, Remote Access, Authelia, Asterisk Intercom),"
    echo "or Advanced options."
    echo
    if ask_yes_no "Reboot now to start the kiosk?" "y"; then
        echo "Rebooting in 3 seconds..."
        sleep 3
        sudo reboot
    else
        log_warning "Remember to reboot before the kiosk will start: sudo reboot"
    fi
}

run_first_time_install() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   Ubuntu Based Kiosk - First-Time Installation"
    echo "════════════════════════════════════════════════════════════"
    echo
    echo "This will install a HEADLESS KIOSK (no desktop environment):"
    echo
    echo "CORE:"
    echo "  - Kiosk user with auto-login"
    echo "  - LightDM + Openbox (minimal window manager)"
    echo "  - Electron browser"
    echo "  - Multi-site rotation with touch controls"
    echo "  - Hardware video acceleration"
    echo "  - Audio support (PipeWire)"
    echo "  - Time synchronization (NTP)"
    echo "  - Web UI (browser-based Sites/Display/Lockout editor, plus"
    echo "    addon install/reconfigure and Update - no login of its own,"
    echo "    see Addons -> Web UI)"
    echo
    echo "OPTIONAL (configure after install, via Addons):"
    echo "  - Lyrion Music Server (LMS) / Squeezelite"
    echo "  - CUPS printing"
    echo "  - Remote desktop (VNC), VPN (WireGuard/Tailscale/Netbird)"
    echo "  - Authelia auto-login, Asterisk Intercom"
    echo
    ask_yes_no "Proceed with installation?" "y" || { echo "Cancelled"; return 1; }

    # Cache sudo credentials upfront so they don't expire mid-install.
    sudo -v

    provision_install_packages
    provision_create_kiosk_user
    provision_install_nodejs
    # Bare call, not `if ! provision_install_app; then ...`: testing a
    # multi-statement function's result as an if-condition exempts
    # everything *inside* that function from set -e for the duration -
    # an early step failing (e.g. the `cp` before npm install even
    # runs) would silently not stop the later steps. provision_install_app
    # already reports its own npm-install failure via a guarded
    # single-command `if`, which doesn't have this problem; letting its
    # overall exit status propagate here as a bare statement preserves
    # real fail-fast for every step in between.
    provision_install_app
    provision_configure_display
    provision_configure_firewall
    provision_configure_power_management
    provision_configure_webui
    provision_configure_kiosk_settings
    provision_finish
    return 0
}
