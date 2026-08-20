#!/bin/bash
################################################################################
# menus/complete_uninstall.sh - "Complete Uninstall" (Core Settings): full
# teardown, returning the machine to its pre-kiosk state.
#
# Composed from every other addon's own silent uninstall helper
# (cups_do_uninstall, vnc_do_uninstall, wireguard_do_uninstall,
# tailscale_do_uninstall, netbird_do_uninstall, lms_do_uninstall,
# squeezelite_do_uninstall, asterisk_intercom_do_uninstall,
# webui_do_uninstall, power_schedule_do_remove_all,
# emergency_hotspot_do_disable) instead of
# re-implementing removal logic for each addon a second time here - if an
# addon's uninstall logic changes, this picks it up automatically. Only
# the pieces no single addon owns - the kiosk user/files, Node.js/
# LightDM/Openbox, polkit rules, leftover systemd units - are handled
# directly below, same as the legacy script.
#
# Ordering matters: every addon teardown runs before the kiosk user is
# removed, because asterisk_intercom_do_uninstall still needs
# `id -u "$KIOSK_USER"` to resolve that user's systemd --user session.
#
# After this runs, the kiosk user (and therefore is_kiosk_installed) is
# gone - install.sh itself will refuse to start against this machine
# again until a fresh install re-provisions it. That's intentional:
# there is nothing left here for this tool to manage.
#
# Depends on: lib/menu.sh, lib/config.sh, and every menus/addon_*.sh /
# menus/power_schedule.sh / menus/advanced_emergency_hotspot.sh being
# sourced first (for the *_do_uninstall helpers above).
################################################################################

complete_uninstall_status() {
    echo "⚠ Removes the kiosk user, every addon, and returns this machine"
    echo "  to its pre-kiosk state. Cannot be undone."
}

complete_uninstall_menu_builder() {
    MENU_LABELS=("Completely uninstall the kiosk")
    MENU_HANDLERS=(action_complete_uninstall)
}

complete_uninstall_menu() {
    run_menu "COMPLETE UNINSTALL" complete_uninstall_menu_builder complete_uninstall_status
}

################################################################################
# Actions
################################################################################

action_complete_uninstall() {
    echo
    echo "⚠️  This will COMPLETELY REMOVE:"
    echo "  • Kiosk user and all data"
    echo "  • All kiosk configuration and sites"
    echo "  • All Electron/Node.js installations"
    echo "  • All browser caches and data"
    echo "  • CUPS printer system"
    echo "  • Squeezelite and LMS (Lyrion Music Server)"
    echo "  • Remote access (VNC, WireGuard, Tailscale, Netbird)"
    echo "  • Asterisk Intercom (Baresip)"
    echo "  • Web UI"
    echo "  • LightDM and Openbox"
    echo "  • All kiosk schedules and services"
    echo "  • Emergency hotspot configuration"
    echo
    echo "⚠️  This CANNOT be undone!"
    echo
    local confirm
    confirm=$(ask_text "Type UNINSTALL to confirm" "")
    if [[ "$confirm" != "UNINSTALL" ]]; then
        echo "Cancelled"
        pause
        return
    fi

    echo
    echo "Beginning complete uninstall..."

    echo "[1/12] Stopping kiosk display..."
    sudo systemctl stop lightdm 2>/dev/null || true

    echo "[2/12] Removing addons..."
    cups_do_uninstall
    vnc_do_uninstall
    wireguard_do_uninstall
    tailscale_do_uninstall
    netbird_do_uninstall
    lms_do_uninstall purge
    squeezelite_do_uninstall
    asterisk_intercom_do_uninstall purge
    webui_do_uninstall

    echo "[3/12] Removing schedules and emergency hotspot..."
    power_schedule_do_remove_all
    emergency_hotspot_do_disable

    # Must come after every addon teardown above - Asterisk Intercom's
    # helper still needs this user to resolve its systemd --user session.
    echo "[4/12] Removing kiosk user..."
    if id "$KIOSK_USER" &>/dev/null; then
        sudo pkill -u "$KIOSK_USER" 2>/dev/null || true
        sudo userdel -r "$KIOSK_USER" 2>/dev/null || true
        log_success "Kiosk user removed"
    fi

    echo "[5/12] Removing kiosk files..."
    sudo rm -rf "$KIOSK_DIR"
    sudo rm -rf "$KIOSK_HOME"

    echo "[6/12] Removing remaining systemd units..."
    sudo rm -f "$SYSTEMD_DIR"/kiosk-*.service
    sudo rm -f "$SYSTEMD_DIR"/kiosk-*.timer
    sudo systemctl daemon-reload 2>/dev/null || true

    echo "[7/12] Removing remaining scripts..."
    sudo rm -f "$BIN_DIR"/kiosk-*
    sudo rm -f /etc/udev/rules.d/99-kiosk-hotplug.rules
    sudo udevadm control --reload-rules 2>/dev/null || true

    echo "[8/12] Removing Node.js..."
    sudo apt-get purge -y nodejs npm 2>/dev/null || true
    sudo rm -rf /usr/local/lib/node_modules
    sudo rm -rf /usr/local/bin/node
    sudo rm -rf /usr/local/bin/npm

    echo "[9/12] Removing LightDM and Openbox..."
    sudo systemctl disable lightdm 2>/dev/null || true
    sudo apt-get purge -y lightdm openbox 2>/dev/null || true

    echo "[10/12] Removing polkit rules..."
    sudo rm -f "$POLKIT_DIR/kiosk-power.pkla"
    sudo rm -f "$POLKIT_DIR/kiosk-printing.pkla"

    echo "[11/12] Re-enabling virtual consoles..."
    for i in {1..8}; do
        sudo systemctl unmask "getty@tty${i}.service" 2>/dev/null || true
    done
    sudo systemctl daemon-reload 2>/dev/null || true

    echo "[12/12] Cleaning up packages..."
    sudo apt-get autoremove -y 2>/dev/null || true
    sudo apt-get autoclean 2>/dev/null || true

    echo
    log_success "Kiosk completely uninstalled"
    echo "The system has been returned to its pre-kiosk state."
    echo "You may want to reboot to ensure all changes take effect."
    echo
    if ask_yes_no "Reboot now?" "n"; then
        echo "Rebooting in 3 seconds..."
        sleep 3
        sudo reboot
    fi
}
