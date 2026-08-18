#!/bin/bash
################################################################################
# install.sh - Modular management entry point for Ubuntu Based Kiosk.
#
# This is NOT yet the full system installer - that is still the big
# single-file script (ubuntu-based-kiosk-v1.0.3.sh etc) documented in
# Readme.md, and first-time provisioning of a new kiosk still goes through
# it. This entry point is the start of pulling the *menu system* out of
# that 12k-line file into small, independently editable modules under
# lib/ and menus/, so a change to (say) the Sites menu can't accidentally
# break WiFi setup or the uninstaller three thousand lines away.
#
# Today this only wires up the Sites & Page Timing menu (menus/sites.sh)
# as a working proof of concept. The rest of Core Settings/Addons/Advanced
# will move over the same way, one menus/*.sh file at a time.
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
    MENU_LABELS=("Sites & Page Timing")
    MENU_HANDLERS=(sites_menu)
}

main_menu_status() {
    echo "Managing kiosk at: ${KIOSK_DIR}"
}

run_menu "UBUNTU BASED KIOSK - MANAGEMENT" main_menu_builder main_menu_status "Exit"
