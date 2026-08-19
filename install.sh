#!/bin/bash
################################################################################
# install.sh - Modular management entry point for Ubuntu Based Kiosk.
#
# This is NOT yet the full system installer - that is still the big
# single-file script (ubuntu-based-kiosk.sh) documented in Readme.md, and
# first-time provisioning of a new kiosk still goes through it. That file
# still also contains its own (unmigrated, unmodified) copies of every
# menu below - both copies coexist deliberately until enough of Core
# Settings/Addons/Advanced has moved over to retire the old ones in one
# pass. This entry point is the modular replacement, one menus/*.sh file
# at a time, so a change to (say) the Sites menu can't accidentally break
# WiFi setup or the uninstaller three thousand lines away.
#
# Migrated so far, grouped the same way the legacy menu groups them:
#   Core Settings: Sites & Page Timing, Display & Interaction, Timezone,
#     Hidden Site PIN, Password Protection & Lockout, WiFi,
#     Power/Display/Quiet Hours.
#   Addons: CUPS Printing (menus/addon_cups.sh), Authelia Auto-Login
#     (menus/addon_authelia.sh), Remote Access - VNC/WireGuard/
#     Tailscale/Netbird (menus/addon_remote_access.sh), LMS Server /
#     Squeezelite Player (menus/addon_lms_squeezelite.sh), Asterisk
#     Intercom - SIP extension client (menus/addon_asterisk_intercom.sh).
#   Advanced: Diagnostics (menus/diagnostics.sh - system status/logs/
#     audio/network), Electron Maintenance (menus/advanced_electron.sh -
#     manual update, fix blank screen), Factory Reset
#     (menus/advanced_factory_reset.sh), Virtual Consoles
#     (menus/advanced_virtual_consoles.sh), Emergency Hotspot
#     (menus/advanced_emergency_hotspot.sh).
#
# Usage (once the kiosk has already been installed):
#   git clone <repo>
#   cd ubuntu-based-kiosk
#   ./install.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/menu.sh
source "$SCRIPT_DIR/lib/menu.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=menus/sites.sh
source "$SCRIPT_DIR/menus/sites.sh"
# shellcheck source=menus/display.sh
source "$SCRIPT_DIR/menus/display.sh"
# shellcheck source=menus/timezone.sh
source "$SCRIPT_DIR/menus/timezone.sh"
# shellcheck source=menus/hidden_pin.sh
source "$SCRIPT_DIR/menus/hidden_pin.sh"
# shellcheck source=menus/lockout.sh
source "$SCRIPT_DIR/menus/lockout.sh"
# shellcheck source=menus/wifi.sh
source "$SCRIPT_DIR/menus/wifi.sh"
# shellcheck source=menus/power_schedule.sh
source "$SCRIPT_DIR/menus/power_schedule.sh"
# shellcheck source=menus/diagnostics.sh
source "$SCRIPT_DIR/menus/diagnostics.sh"
# shellcheck source=menus/addon_cups.sh
source "$SCRIPT_DIR/menus/addon_cups.sh"
# shellcheck source=menus/addon_authelia.sh
source "$SCRIPT_DIR/menus/addon_authelia.sh"
# shellcheck source=menus/addon_remote_access.sh
source "$SCRIPT_DIR/menus/addon_remote_access.sh"
# shellcheck source=menus/addon_lms_squeezelite.sh
source "$SCRIPT_DIR/menus/addon_lms_squeezelite.sh"
# shellcheck source=menus/addon_asterisk_intercom.sh
source "$SCRIPT_DIR/menus/addon_asterisk_intercom.sh"
# shellcheck source=menus/advanced_electron.sh
source "$SCRIPT_DIR/menus/advanced_electron.sh"
# shellcheck source=menus/advanced_factory_reset.sh
source "$SCRIPT_DIR/menus/advanced_factory_reset.sh"
# shellcheck source=menus/advanced_virtual_consoles.sh
source "$SCRIPT_DIR/menus/advanced_virtual_consoles.sh"
# shellcheck source=menus/advanced_emergency_hotspot.sh
source "$SCRIPT_DIR/menus/advanced_emergency_hotspot.sh"

################################################################################
# Preflight
################################################################################

if [[ "$(whoami)" == "kiosk" ]]; then
    log_error "Cannot run as user 'kiosk'"
    exit 1
fi

if [[ $EUID -eq 0 ]]; then
    log_error "Run as a regular user with sudo privileges, not as root"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed. Run: sudo apt-get install -y jq"
    exit 1
fi

if ! is_kiosk_installed; then
    echo
    log_error "No installed kiosk found at ${KIOSK_DIR}."
    echo
    echo "This tool manages an already-installed kiosk. To provision a new"
    echo "one for the first time, use the full installer instead - see"
    echo "Readme.md ('Quick Install') for the current download command."
    echo
    exit 1
fi

################################################################################
# Top-level menu - grouped the same way the legacy menu groups them
# (Core Settings / Addons / Advanced), so the structure stays familiar
# and the flat list doesn't grow unwieldy as more menus migrate in.
################################################################################

core_settings_menu_builder() {
    MENU_LABELS=(
        "Sites & Page Timing"
        "Display & Interaction"
        "Timezone"
        "Hidden Site PIN"
        "Password Protection & Lockout"
        "WiFi"
        "Power/Display/Quiet Hours"
    )
    MENU_HANDLERS=(
        sites_menu
        display_menu
        timezone_menu
        hidden_pin_menu
        lockout_menu
        wifi_menu
        power_schedule_menu
    )
}

core_settings_menu() {
    run_menu "CORE SETTINGS" core_settings_menu_builder
}

addons_menu_builder() {
    MENU_LABELS=("CUPS Printing" "Authelia Auto-Login" "Remote Access" "LMS Server / Squeezelite Player" "Asterisk Intercom (SIP Extension)")
    MENU_HANDLERS=(addon_cups_menu addon_authelia_menu remote_access_menu addon_lms_squeezelite_menu addon_asterisk_intercom_menu)
}

addons_menu() {
    run_menu "ADDONS" addons_menu_builder
}

advanced_menu_builder() {
    MENU_LABELS=("Diagnostics" "Electron Maintenance" "Factory Reset" "Virtual Consoles" "Emergency Hotspot")
    MENU_HANDLERS=(diagnostics_menu advanced_electron_menu advanced_factory_reset_menu advanced_virtual_consoles_menu advanced_emergency_hotspot_menu)
}

advanced_menu() {
    run_menu "ADVANCED" advanced_menu_builder
}

main_menu_builder() {
    MENU_LABELS=("Core Settings" "Addons" "Advanced")
    MENU_HANDLERS=(core_settings_menu addons_menu advanced_menu)
}

main_menu_status() {
    echo "Managing kiosk at: ${KIOSK_DIR}"
}

run_menu "UBUNTU BASED KIOSK - MANAGEMENT" main_menu_builder main_menu_status "Exit"
