#!/bin/bash
################################################################################
# menus/advanced_factory_reset.sh - "Factory Reset" (Advanced): wipe
# config.json back to script defaults without touching anything else.
#
# Deliberately narrow - this only removes $CONFIG_PATH. Installed addons
# (CUPS, LMS, VPNs, etc.), the kiosk user, and the system itself are left
# alone; that's what Complete Uninstall is for.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

advanced_factory_reset_status() {
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        echo "Config: $CONFIG_PATH exists"
    else
        echo "Config: not found (already at defaults)"
    fi
}

advanced_factory_reset_menu_builder() {
    MENU_LABELS=("Reset configuration to defaults")
    MENU_HANDLERS=(action_factory_reset)
}

advanced_factory_reset_menu() {
    run_menu "FACTORY RESET" advanced_factory_reset_menu_builder advanced_factory_reset_status
}

################################################################################
# Actions
################################################################################

action_factory_reset() {
    echo
    echo "This resets $CONFIG_PATH to defaults - sites, schedules,"
    echo "password protection, and every other setting stored there are"
    echo "cleared. Installed addons (CUPS, LMS, VPNs, etc.) are not touched."
    echo
    ask_yes_no "Continue?" "n" || { echo "Cancelled"; pause; return; }

    sudo -u "$KIOSK_USER" rm -f "$CONFIG_PATH"
    log_success "Configuration reset - reconfigure via Core Settings"

    pause
}
