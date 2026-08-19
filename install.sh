#!/bin/bash
################################################################################
# install.sh - Ubuntu Based Kiosk: install and manage, one entry point.
#
# On a bare Ubuntu Server box with no kiosk installed, this provisions
# one (lib/provision.sh) - packages, kiosk user, LightDM/Openbox, the
# Electron app, audio/video/power hardware setup - then hands off to the
# same Core Settings/Addons/Advanced menus below for initial
# configuration. On a machine that already has a kiosk, it skips
# straight to those menus. Same entry point either way.
#
# ubuntu-based-kiosk.sh, the original single-file installer, still
# exists and still works, but is no longer the only way to provision a
# new kiosk. Upgrade (Advanced -> Upgrade) is now here too, but not a
# port of the legacy version - that one re-extracted heredocs on every
# run; kiosk-app/ and provision/files/ are real files in this git
# checkout, so the modular Upgrade is `git pull` + re-running the same
# provisioning steps, reused rather than reimplemented (see
# menus/advanced_upgrade.sh). Full Reinstall is deliberately not
# carried forward - it never worked reliably in the legacy script, and
# the same outcome is already available here, more reliably, as two
# already-tested pieces run back to back: Complete Uninstall (Core
# Settings), then ./install.sh again to provision fresh.
#
# Migrated so far, grouped the same way the legacy menu groups them:
#   Core Settings: Sites & Page Timing, Display & Interaction, Timezone,
#     Hidden Site PIN, Password Protection & Lockout, WiFi,
#     Power/Display/Quiet Hours, Complete Uninstall
#     (menus/complete_uninstall.sh - composed from every addon's own
#     uninstall helper rather than re-implementing removal a second time).
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
#     (menus/advanced_emergency_hotspot.sh), Clone Settings
#     (menus/clone_settings.sh - export/apply portable settings across
#     several kiosks; deliberately excludes machine-bound credentials
#     like Authelia/WireGuard/Asterisk Intercom - see the file header),
#     Upgrade (menus/advanced_upgrade.sh - git pull + re-provision, plus
#     an on-demand Electron version check).
#
# Usage (works whether or not a kiosk is already installed):
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
# shellcheck source=lib/electron.sh
source "$SCRIPT_DIR/lib/electron.sh"
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
# shellcheck source=menus/advanced_upgrade.sh
# Depends on action_update_electron above and the provision_* functions
# sourced later (lib/provision.sh) - safe either way, bash resolves
# function calls at run time, not source time.
source "$SCRIPT_DIR/menus/advanced_upgrade.sh"
# shellcheck source=menus/advanced_factory_reset.sh
source "$SCRIPT_DIR/menus/advanced_factory_reset.sh"
# shellcheck source=menus/advanced_virtual_consoles.sh
source "$SCRIPT_DIR/menus/advanced_virtual_consoles.sh"
# shellcheck source=menus/advanced_emergency_hotspot.sh
source "$SCRIPT_DIR/menus/advanced_emergency_hotspot.sh"
# shellcheck source=menus/complete_uninstall.sh
# Sourced last among menus/*.sh: composes the *_do_uninstall/
# *_do_remove_all/*_do_disable helpers defined in every file above it.
source "$SCRIPT_DIR/menus/complete_uninstall.sh"
# shellcheck source=menus/clone_settings.sh
# Also composes detection helpers (*_is_installed) from every addon above.
source "$SCRIPT_DIR/menus/clone_settings.sh"
# shellcheck source=lib/provision.sh
# Sourced last of all: calls into core_settings_menu and the Advanced
# actions below during first-time setup, so everything they depend on
# must already be defined by the time it actually runs (not merely
# sourced - bash resolves function calls at run time either way).
source "$SCRIPT_DIR/lib/provision.sh"

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
        "Complete Uninstall"
    )
    MENU_HANDLERS=(
        sites_menu
        display_menu
        timezone_menu
        hidden_pin_menu
        lockout_menu
        wifi_menu
        power_schedule_menu
        complete_uninstall_menu
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
    MENU_LABELS=("Diagnostics" "Electron Maintenance" "Factory Reset" "Virtual Consoles" "Emergency Hotspot" "Clone Settings" "Upgrade")
    MENU_HANDLERS=(diagnostics_menu advanced_electron_menu advanced_factory_reset_menu advanced_virtual_consoles_menu advanced_emergency_hotspot_menu clone_settings_menu advanced_upgrade_menu)
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

################################################################################
# Provision if there's nothing here yet, otherwise go straight to management.
################################################################################

if ! is_kiosk_installed; then
    echo
    echo "No installed kiosk found at ${KIOSK_DIR}."
    echo "This will provision a new one on this machine."
    echo
    # Bare call, not `if run_first_time_install; then ...`: this is a
    # large multi-step function, and testing it as an if-condition would
    # exempt every step inside it from set -e for the duration - see the
    # comment at its own call to provision_install_app for why that
    # matters. Called bare, a real failure anywhere inside it halts the
    # whole script immediately (set -e's normal behavior); reaching the
    # lines below is itself proof every step succeeded. A declined
    # install prints "Cancelled" from inside the function and returns
    # non-zero, which the same bare-statement rule turns into a normal
    # exit here - nothing further to print either way.
    run_first_time_install
    echo
    echo "Run ./install.sh again to manage this kiosk."
    exit 0
fi

run_menu "UBUNTU BASED KIOSK - MANAGEMENT" main_menu_builder main_menu_status "Exit"
