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
# Migrated so far: Sites & Page Timing (menus/sites.sh), Display &
# Interaction (menus/display.sh), Timezone (menus/timezone.sh), Hidden
# Site PIN (menus/hidden_pin.sh), Password Protection & Lockout
# (menus/lockout.sh), WiFi (menus/wifi.sh), Power/Display/Quiet Hours
# (menus/power_schedule.sh).
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
# Top-level menu
################################################################################

main_menu_builder() {
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

main_menu_status() {
    echo "Managing kiosk at: ${KIOSK_DIR}"
}

run_menu "UBUNTU BASED KIOSK - MANAGEMENT" main_menu_builder main_menu_status "Exit"
