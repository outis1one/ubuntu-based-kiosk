#!/bin/bash
################################################################################
###   Ubuntu Based Kiosk (UBK) v0.9.5-10         ###
################################################################################
#
# RELEASE v0.9.5-10 - Enhanced Password Lockout Security
#
# What's NEW in v0.9.5-10:
# - SECURITY FIX: Browser views now completely hidden when locked
#   * All browser views detached from mainWindow during lockout
#   * Prevents content visibility when password screen is active
#   * Users cannot see any URLs or content until password is entered
# - IMPROVED: Power menu displays on solid black screen when locked
#   * Power menu now shows on lockoutWindow instead of mainWindow
#   * No content visible behind power menu when system is locked
# - SIMPLIFIED: Removed time-based lockout restrictions
#   * Eliminated "Only enforce lockout during specific hours?" prompt
#   * Password protection now always active when enabled
#   * More reliable and predictable security behavior
# - All fixes from v0.9.5-9 included
#
# RELEASE v0.9.5-9 - CRITICAL Inactivity Lockout Fix (Simplified)
#
# What was in v0.9.5-9:
# - CRITICAL FIX: Inactivity lockout now works (was never triggering)
#   * Removed lockoutActivityTime reset from markActivity() function
#   * markActivity() was being called on EVERY mouse move, click, keyboard press
#   * This constantly reset the lockout timer, preventing it from ever triggering
#   * Now lockout timer ONLY resets when user unlocks or selects time extension
# - All fixes from v0.9.5-8 included
#
# ROOT CAUSE:
# The markActivity() function (line 3904-3906) was resetting lockoutActivityTime:
#   markActivity(){
#     ...
#     if(enablePasswordProtection && lockoutTimeout > 0){
#       lockoutActivityTime = now;  // ← THIS WAS THE PROBLEM
#     }
#   }
#
# markActivity() is called on EVERY:
# - Mouse move
# - Mouse click
# - Keyboard press
# - Page load
# - Focus change
#
# This meant lockoutActivityTime was CONSTANTLY being reset, so the lockout
# timer could NEVER reach the configured timeout (e.g., 17 minutes).
#
# FIX:
# Removed the lockoutActivityTime reset from markActivity() entirely.
# Now lockoutActivityTime only resets when:
# 1. User unlocks the screen (in unlockScreen() function)
# 2. User selects a time extension (in showPauseDialog/showInactivityPrompt)
#
# This is simple and correct: lockout should trigger after X minutes of
# inactivity, regardless of whether user is actively using the site or not.
# Time extensions explicitly extend the lockout timer when user confirms presence.
#
# RELEASE v0.9.5-6 - Boot Password Sequence Fix
#
# What was in v0.9.5-6:
# - Boot password now required BEFORE showing any websites
# - Limited power menu when locked (no Reload option)
#
# TROUBLESHOOTING: If navigation (Ctrl+Tab, swipe) doesn't work:
# - Check your config.json for sites with duration: -1 (hidden sites)
# - Hidden sites don't appear in rotation and don't count toward navigation
# - Ensure you have at least 2 visible sites (duration >= 0) for navigation to work
# - Run the install script menu option 1 to view current configuration
#
# RELEASE v0.9.5-4 - CRITICAL Security and Compatibility Fixes
#
# What was in v0.9.5-4:
# - CRITICAL SECURITY FIX: Restricted polkit permissions to prevent Ctrl+Alt+Del bypass
#   * Changed org.freedesktop.login1.* (ALL actions) to specific power operations only
#   * Prevents session switching and VT access that could bypass kiosk security
# - CRITICAL SECURITY FIX: Added X server ServerFlags to block VT switching
#   * Disabled Ctrl+Alt+F1-F12 VT switching with DontVTSwitch option
#   * Disabled Ctrl+Alt+Backspace X server kill with DontZap option
#   * Added AllowClosedownGrabs protection
# - SECURITY: Enhanced LightDM greeter security settings
#   * Hide user list, disable manual login, disable guest account
# - FIXED: Autostart script compatibility errors ([[: not found)
#   * Converted bash-specific [[ ]] syntax to POSIX-compliant [ ] syntax
#   * Fixed all conditional tests in display schedule and quiet hours logic
# - FIXED: xbindkeys errors (missing .xbindkeysrc)
#   * Now creates empty .xbindkeysrc file to prevent xbindkeys startup errors
#
# RELEASE v0.9.5-3 - Extension and Manual Navigation Fixes
#
# What was in v0.9.5-3:
# - CRITICAL FIX: Time extensions now work correctly (15 min actually = 15 min)
#   * Removed inactivityExtensionUntil=0 from markActivity() function
#   * Extensions no longer cleared by clicking extension buttons
#   * Pause button extensions now work for full selected duration
#   * Manual site timeout extensions now work for full selected duration
# - FIXED: Manual tab switching now clears extensions appropriately
#   * Ctrl+Tab, Ctrl+Shift+Tab, swipe gestures now clear active extensions
#   * Prevents confusion when user manually navigates during extension
#
# RELEASE v0.9.5-2 - Settings Persistence & Timing Fixes
#
# What was in v0.9.5-2:
# - CRITICAL FIX: Sites no longer wiped when editing password/pause/OSK settings
#   * Added load_existing_config() to preserve all settings before save
#   * Fixed empty URLS/DURS arrays from overwriting sites in config.json
# - CRITICAL FIX: Password protection now properly saved/persists on reboot
# - CRITICAL FIX: Sites now properly saved/persist on reboot
# - FIXED: Time extension now works on correct site (not next rotation site)
#   * Pause dialog blocks rotation while user is selecting time
#   * Inactivity prompt blocks rotation while user is responding
# - FIXED: Pause button now properly blocks rotation for selected duration
# - FIXED: Manual site timeout popup no longer appears 1 min after extension expires
#   * Extension expiration now properly resets lastUserInteraction timer
# - NEW: Cancel/exit option in password and optional features menus
#   * Menus now ask "Save these changes?" before applying
#   * Answer "no" to discard changes without affecting config
# - ENHANCED: Comprehensive settings display on main menu
#   * Shows all sites with [HOME] marker
#   * Shows home URL and inactivity timeout
#   * Shows pause/keyboard button status
#   * Shows complete password protection configuration
#
# RELEASE v0.9.5-1 - Lockout Stay Locked Fix
#
# What was in v0.9.5-1:
# - CRITICAL FIX: Lockout screen now stays locked until password entered
# - Fixed rotation timer continuing to run during lockout
# - Added isLockedOut checks to all navigation functions
# - Fixed undefined 'now' variable bugs in callback functions
# - Lockout window is now truly modal and cannot be bypassed
#
# RELEASE v0.9.5 Features:
# - NEW: Time-based session lockout (lock at specific time daily)
# - NEW: Active hours for lockout (only enforce during configured hours)
# - NEW: Password on boot/power-on (require password when system starts)
# - NEW: Inactivity-based lockout with password protection
# - FIXED: Keyboard button disable now works correctly (OSK won't appear)
# - FIXED: Password entry screen (no longer requires multiple Enter presses)
# - ENHANCED: Extensive debug logging for lockout timers
# - All existing features from v0.9.4 included
#
# RELEASE v0.9.4 Features:
# - Optional pause button (can be disabled during install/rerun)
# - Optional keyboard button (can be disabled during install/rerun)
# - Password protection with customizable session lockout
# - Password required after display schedule wake-up
#
# RELEASE v0.9.2-6 - Enhanced Electron Update Tool
#
# What was in v0.9.2-6:
# - ENHANCED: Comprehensive Electron update tool with safety checks
# - Detects kiosk installation across multiple locations automatically
# - Verifies Electron is running before attempting updates
# - Displays current version and fetches latest stable version from npm
# - Warns about breaking changes with documentation links
# - Creates automatic backups before updating (package.json, package-lock.json)
# - Provides clear restore instructions if something goes wrong
# - Automatic rollback if update fails
# - Fixes chrome-sandbox permissions automatically after installation
# - Multiple confirmation prompts to prevent accidental updates
# - Handles edge cases: network failures, missing installations, permission issues
#
# RELEASE v0.9.2 - Pause Button for Rotation Sites
#
# What's NEW in v0.9.2:
# - NEW: Pause button for timed rotation sites (appears on user interaction)
# - Pause button appears in bottom-left corner when you interact with a timed site
# - Auto-hides after 5 seconds of inactivity
# - Click pause button to select pause duration (15 min, 30 min, 1 hr, 2 hr)
# - Home return popup now only appears on manual sites (duration = 0)
# - Timed sites (duration > 0) use pause button instead of home return popup
#
# RELEASE v0.9.1-1 - Home Return Fix for Timed Sites (DEPRECATED)
#
# What was in v0.9.1-1:
# - Attempted fix for home return popup on timed sites
# - Replaced by v0.9.2 pause button approach
#
# RELEASE v0.9.0 - Bug Fixes & Input Validation
#
# What's NEW in v0.9.0:
# - FIXED: Octal time parsing bug (08:00-09:59 would crash)
# - Added comprehensive input validation functions
# - Added URL reorder functionality
# - Improved URL delete with automatic HOME_TAB_INDEX adjustment
# - Added ask_time(), ask_integer(), ask_url(), ask_menu_choice() validators
# - Updated site configuration menu to use dynamic validation
# - README.md with full documentation and licensing
# - TODO.md tracking remaining features
#
# What's in v0.9.9.1.4:
# - Fixed site rotation during time extensions (now properly pauses rotation)
# - Fixed "I'm still here" button (now resets rotation timer and stays on current page)
# - Time extensions now properly block both rotation AND return-to-home
# - siteStartTime properly reset when user confirms presence or extends time
#
# What's in v0.9.9.1.3:
# - Fixed display schedule watchdog conflict (display stays off during scheduled times)
# - Fixed quiet hours watchdog conflict (audio stays muted during quiet hours)
# - Watchdogs now schedule-aware and respect display off/on and quiet hours timers
# - Properly handles overnight time ranges (e.g., 22:00-06:00)
#
# What's in v0.9.9.1:
# - Added HTML on-screen keyboard (non-interfering)
# - Keyboard auto-shows on text field focus (optional)
#   * Screen blanking disabled
#   * Jitsi audio keep-alive
#   * PTT spacebar hardcoded
#   * Squeezelite name displays correctly
#   * Schedule times display correctly
#   * LMS installs reliably
#   * WiFi config works
#   * CUPS detection fixed
#   * VPN setup keys work
#   * Keyboard never auto-pops up
#   * Blue keyboard icon (⌨️) appears bottom-right when you tap a text field
#   * Fixed media playback detection
#   * Fixed schedule time display
#   * Added emergency hotspot
#   * Fixed chromebook consol shortcuts

#
# Built with Claude Sonnet 4/.5 AI assistance
# License: GPL v3 - Keep derivatives open sour
# Repository: https://github.com/[YOUR-USERNAME]/ubuntu-based-kiosk
#
# TARGET SYSTEMS:
# - Ubuntu 24.04+ Server (minimal install recommended)
# - Raspberry Pi 4+ (with or without touchscreen)
# - Laptops, desktops, all-in-ones, 2-in-1s
# - Touch support optional (works with keyboard/mouse)
#
# SECURITY NOTICE:
# This is NOT suitable for secure locations or public kiosks.
# Do NOT use as a replacement for hardened kiosk solutions.
# Use entirely at your own risk.
#
# PURPOSE:
# Home/office kiosk for reusing old hardware, displaying:
# - Self-hosted services (Immich, MagicMirror2, Home Assistant)
# - Web dashboards, digital signage
# - Photo slideshows, family calendars
# - Any web-based content
#
################################################################################

set -euo pipefail

################################################################################
### SECTION 1: CONSTANTS & GLOBALS
################################################################################

SCRIPT_VERSION="0.9.5-9"
KIOSK_USER="kiosk"
BUILD_USER="${SUDO_USER:-$(whoami)}"
KIOSK_HOME="/home/${KIOSK_USER}"
KIOSK_DIR="${KIOSK_HOME}/kiosk-app"
CONFIG_PATH="${KIOSK_DIR}/config.json"

# DEFAULT VALUES
AUTOSWITCH="true"
SWIPE_MODE="dual"
ALLOW_NAVIGATION="same-origin"
declare -a URLS=()
declare -a DURS=()
declare -a USERS=()
declare -a PASSES=()
HOME_TAB_INDEX=-1
INACTIVITY_TIMEOUT=60
ENABLE_PAUSE_BUTTON="true"
ENABLE_KEYBOARD_BUTTON="true"
ENABLE_PASSWORD_PROTECTION="false"
LOCKOUT_PASSWORD=""
LOCKOUT_TIMEOUT=0
LOCKOUT_AT_TIME=""
LOCKOUT_ACTIVE_START=""
LOCKOUT_ACTIVE_END=""
REQUIRE_PASSWORD_ON_BOOT="false"

################################################################################
### SECTION 2: HELPER/UTILITY FUNCTIONS  
################################################################################

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "✓ $*"
}

log_warning() {
    echo "⚠ $*"
}

# INPUT VALIDATION HELPER
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    
    while true; do
        read -r -p "$prompt (y/n) [$default]: " answer
        answer="${answer:-$default}"
        
        # Convert to lowercase and check
        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "❌ Invalid input. Please enter 'y' or 'n' (yes/no)"
                echo
                ;;
        esac
    done
}
# Enhanced validation that accepts more formats
validate_yes_no() {
    local answer="$1"
    case "${answer,,}" in
        y|yes|yeah|yep|yup|sure|ok|okay) return 0 ;;
        n|no|nope|nah) return 1 ;;
        *) return 2 ;;  # Invalid
    esac
}

# Ask yes/no with better error messages
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    
    while true; do
        read -r -p "$prompt (y/n) [$default]: " answer
        answer="${answer:-$default}"
        
        validate_yes_no "$answer"
        local result=$?
        
        if [[ $result -eq 0 ]]; then
            return 0
        elif [[ $result -eq 1 ]]; then
            return 1
        else
            echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
            echo
        fi
    done
}


pause() {
    read -r -p "Press Enter to continue..."
}

################################################################################
### COMPREHENSIVE INPUT VALIDATION FUNCTIONS
################################################################################

# Validate time in HH:MM format
validate_time() {
    local time="$1"
    if [[ $time =~ ^([0-1][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        return 0
    else
        return 1
    fi
}

# Ask for time with validation
ask_time() {
    local prompt="$1"
    local default="$2"
    local time=""

    while true; do
        read -r -p "$prompt [$default]: " time
        time="${time:-$default}"

        if validate_time "$time"; then
            echo "$time"
            return 0
        else
            echo "❌ Invalid time format. Please use HH:MM (00:00 to 23:59)"
            echo
        fi
    done
}

# Validate integer
validate_integer() {
    local value="$1"
    local min="${2:--2147483648}"  # Default to INT_MIN
    local max="${3:-2147483647}"   # Default to INT_MAX

    if [[ $value =~ ^-?[0-9]+$ ]]; then
        if [[ $value -ge $min && $value -le $max ]]; then
            return 0
        fi
    fi
    return 1
}

# Ask for integer with validation
ask_integer() {
    local prompt="$1"
    local default="$2"
    local min="${3:--2147483648}"
    local max="${4:-2147483647}"
    local value=""

    while true; do
        read -r -p "$prompt [$default]: " value
        value="${value:-$default}"

        if validate_integer "$value" "$min" "$max"; then
            echo "$value"
            return 0
        else
            echo "❌ Invalid number. Please enter an integer between $min and $max"
            echo
        fi
    done
}

# Validate URL format
validate_url() {
    local url="$1"
    # Basic URL validation - check for http(s):// or file:// or data:
    if [[ $url =~ ^(https?|file|data)://.*$ ]] || [[ $url =~ ^about: ]]; then
        return 0
    else
        return 1
    fi
}

# Ask for URL with validation
ask_url() {
    local prompt="$1"
    local default="$2"
    local url=""

    while true; do
        read -r -p "$prompt [$default]: " url
        url="${url:-$default}"

        if validate_url "$url"; then
            echo "$url"
            return 0
        else
            echo "❌ Invalid URL. Must start with http://, https://, file://, data:, or about:"
            echo
        fi
    done
}

# Validate menu choice
validate_menu_choice() {
    local choice="$1"
    local max="$2"

    if validate_integer "$choice" 0 "$max"; then
        return 0
    else
        return 1
    fi
}

# Ask for menu choice with validation
ask_menu_choice() {
    local max="$1"
    local choice=""

    while true; do
        read -r -p "Choose [0-$max]: " choice

        if validate_menu_choice "$choice" "$max"; then
            echo "$choice"
            return 0
        else
            echo "❌ Invalid choice. Please enter a number between 0 and $max"
            echo
        fi
    done
}

is_service_active() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

is_service_enabled() {
    local service="$1"
    # Check if service file exists first
    if systemctl list-unit-files 2>/dev/null | grep -q "^${service}\s"; then
        systemctl is-enabled --quiet "$service" 2>/dev/null
    else
        return 1
    fi
}

get_ip_address() {
    hostname -I | awk '{print $1}' || echo "No IP"
}

get_vpn_ips() {
    local vpn_info=""
    
    if command -v wg &>/dev/null && sudo wg show 2>/dev/null | grep -q interface; then
        local wg_ip=$(sudo wg show all | grep "allowed ips" | head -1 | awk '{print $3}' | cut -d'/' -f1)
        [[ -n "$wg_ip" ]] && vpn_info="${vpn_info}WireGuard: $wg_ip | "
    fi
    
    if command -v tailscale &>/dev/null; then
        local ts_ip=$(tailscale ip -4 2>/dev/null)
        [[ -n "$ts_ip" ]] && vpn_info="${vpn_info}Tailscale: $ts_ip | "
    fi
    
    if command -v netbird &>/dev/null; then
        local nb_ip=$(netbird status 2>/dev/null | grep "NetBird IP:" | awk '{print $3}')
        [[ -n "$nb_ip" ]] && vpn_info="${vpn_info}Netbird: $nb_ip | "
    fi
    
    vpn_info="${vpn_info% | }"
    [[ -n "$vpn_info" ]] && echo "$vpn_info" || echo "None"
}

kiosk_user_exists() {
    id "$KIOSK_USER" &>/dev/null 2>&1
}

is_kiosk_installed() {
    kiosk_user_exists && sudo -u "$KIOSK_USER" test -f "$KIOSK_DIR/main.js" 2>/dev/null
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$file" "$backup"
        log_success "Backup: $backup"
        echo "$backup"
    fi
}

get_battery_status() {
    if [[ -d /sys/class/power_supply/BAT0 ]] || [[ -d /sys/class/power_supply/BAT1 ]]; then
        local bat_path=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
        if [[ -n "$bat_path" ]]; then
            local capacity=$(cat "$bat_path/capacity" 2>/dev/null || echo "N/A")
            local status=$(cat "$bat_path/status" 2>/dev/null || echo "Unknown")
            echo "${capacity}% (${status})"
            return 0
        fi
    fi
    echo "No battery"
    return 1
}

get_cpu_temp() {
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        local temp_c=$((temp / 1000))
        local temp_f=$((temp_c * 9 / 5 + 32))
        echo "${temp_c}°C / ${temp_f}°F"
    elif command -v sensors &>/dev/null; then
        sensors 2>/dev/null | grep -i "core 0" | awk '{print $3}' | head -1 || echo "N/A"
    else
        echo "N/A"
    fi
}

get_cpu_info() {
    local cpu_model=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    if [[ -z "$cpu_model" ]]; then
        cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
    fi
    
    local cores=$(nproc)
    local threads=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    
    echo "${cpu_model} (${cores} cores, ${threads} threads)"
}

################################################################################
### SECTION 2.5: STATUS DISPLAY FUNCTIONS
################################################################################

show_system_status() {
    echo " ══ SYSTEM STATUS ══"
    echo
    
    if is_kiosk_installed; then
        echo "Core System: ✓ Installed (v${SCRIPT_VERSION})"
        is_service_active lightdm && echo "  LightDM: ✓ Running" || echo "  LightDM: ✗ Stopped"
    else
        echo "Core System: ✗ Not installed"
    fi
    echo
    
    echo " ══ SYSTEM RESOURCES ══"
    
    local ip=$(get_ip_address)
    echo "IP Address:  $ip"
    
    local vpn_ips=$(get_vpn_ips)
    if [[ "$vpn_ips" != "None" ]]; then
        echo "VPN IPs:     $vpn_ips"
    fi
    
    local disk_info=$(df -h / | tail -1)
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_avail=$(echo "$disk_info" | awk '{print $4}')
    local disk_pct=$(echo "$disk_info" | awk '{print $5}')
    echo "Disk:        $disk_used used / $disk_total total ($disk_avail free) [$disk_pct]"
    
    local mem_info=$(free -h | grep "Mem:")
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_avail=$(echo "$mem_info" | awk '{print $7}')
    local mem_pct=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
    echo "RAM:         $mem_used used / $mem_total total ($mem_avail free) [${mem_pct}%]"
    
    local cpu=$(get_cpu_info)
    echo "CPU:         $cpu"
    
    local temp=$(get_cpu_temp)
    echo "Temperature: $temp"
    
    local battery=$(get_battery_status)
    echo "Battery:     $battery"
    
    local uptime=$(uptime -p | sed 's/up //')
    echo "Uptime:      $uptime"
    
    echo
}

show_addon_status() {
    echo " ╔══ INSTALLED ADDONS ══╗"
    echo
    
    local any_addon=false
    
    # LMS/Squeezelite - FAST CHECK (just check if files exist)
    local lms_active=false
    local sq_active=false
    
    if [[ -f /lib/systemd/system/logitechmediaserver.service ]] || \
       [[ -f /lib/systemd/system/lyrionmusicserver.service ]]; then
        lms_active=true
        any_addon=true
    fi
    
    if [[ -f /etc/systemd/system/squeezelite.service ]]; then
        sq_active=true
        any_addon=true
    fi
    
    # Check if services are actually running
    if is_service_active logitechmediaserver || is_service_enabled logitechmediaserver || \
       is_service_active lyrionmusicserver || is_service_enabled lyrionmusicserver; then
        lms_active=true
        any_addon=true
    fi
    if is_service_active squeezelite || is_service_enabled squeezelite; then
        sq_active=true
        any_addon=true
    fi
    
    if $lms_active || $sq_active; then
        local status_text="LMS/Squeezelite: "
        if $lms_active && $sq_active; then
            status_text="${status_text}✓ Server+Player"
        elif $lms_active; then
            status_text="${status_text}✓ Server only"
        else
            status_text="${status_text}✓ Player only"
        fi
        
        if $lms_active; then
            local lms_ip=$(get_ip_address)
            status_text="${status_text} (Server: http://${lms_ip}:9000)"
        fi
        
        echo "$status_text"
        
        # Squeezelite player name
        if is_service_active squeezelite || is_service_enabled squeezelite; then
            local player_name="Unknown"
            if [[ -f /usr/local/bin/squeezelite-start.sh ]]; then
                player_name=$(grep '^PLAYER_NAME=' /usr/local/bin/squeezelite-start.sh 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "Unknown")
            fi
            if [[ "$player_name" != "Unknown" ]]; then
                echo "  Player: $player_name"
            fi
        fi
    fi

    # Jitsi Intercom - FAST CHECK
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        if sudo -u "$KIOSK_USER" grep -q "meet.jit.si" "$CONFIG_PATH" 2>/dev/null; then
            any_addon=true
            echo "Jitsi Intercom: ✓ Configured"
            
            if [[ -f /etc/systemd/system/jitsi-ptt.service ]]; then
                echo "  PTT: ✓ Installed (Spacebar)"
            fi
        fi
    fi
  
    # talkkonnect/Murmur Intercom - FAST CHECK
    local murmur_installed=false
    local talkkonnect_installed=false
    
    [[ -f /lib/systemd/system/mumble-server.service ]] && murmur_installed=true
    [[ -f "$HOME/go/bin/talkkonnect" ]] && talkkonnect_installed=true
    
    if $murmur_installed || $talkkonnect_installed; then
        any_addon=true
        local tk_status="talkkonnect: "
        if $murmur_installed && $talkkonnect_installed; then
            tk_status="${tk_status}✓ Server+Client"
        elif $murmur_installed; then
            tk_status="${tk_status}✓ Server only"
        else
            tk_status="${tk_status}✓ Client only"
        fi
        
        if systemctl is-active --quiet mumble-server 2>/dev/null; then
            local tk_ip=$(get_ip_address)
            tk_status="${tk_status} (${tk_ip}:64738)"
        fi
        
        echo "$tk_status"
    fi

    # CUPS - FAST CHECK
    if dpkg -l 2>/dev/null | grep -q "^ii\s\+cups\s"; then
        any_addon=true
        local cups_ip=$(get_ip_address)
        echo "CUPS Printing: ✓ Installed (http://${cups_ip}:631)"
    fi
    
    # VNC - FAST CHECK
    if [[ -f /etc/systemd/system/x11vnc.service ]]; then
        any_addon=true
        local vnc_ip=$(get_ip_address)
        echo "VNC: ✓ Installed (${vnc_ip}:5900)"
    fi
    
    # VPNs - FAST CHECK
    [[ -x /usr/bin/wg ]] && { any_addon=true; echo "WireGuard: ✓ Installed"; }
    [[ -x /usr/bin/tailscale ]] && { any_addon=true; echo "Tailscale: ✓ Installed"; }
    [[ -x /usr/bin/netbird ]] && { any_addon=true; echo "Netbird: ✓ Installed"; }
    
    if ! $any_addon; then
        echo "No addons installed"
    fi
    
    echo
}
show_schedule_status() {
    echo " ══ SCHEDULED TASKS ══"
    echo
    
    local any_schedule=false
    
    # FAST CHECK - just look for timer files, read them directly
    if [[ -f /etc/systemd/system/kiosk-shutdown.timer ]]; then
        any_schedule=true
        local ptime=$(grep "^OnCalendar=" /etc/systemd/system/kiosk-shutdown.timer 2>/dev/null | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        [[ -n "$ptime" ]] && echo "Power: Shutdown daily at $ptime" || echo "Power: Shutdown enabled"
    fi
    
    if [[ -f /etc/systemd/system/kiosk-display-off.timer ]]; then
        any_schedule=true
        local doff_time=$(grep "^OnCalendar=" /etc/systemd/system/kiosk-display-off.timer 2>/dev/null | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        local don_time=$(grep "^OnCalendar=" /etc/systemd/system/kiosk-display-on.timer 2>/dev/null | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        [[ -n "$doff_time" && -n "$don_time" ]] && echo "Display: Off at $doff_time, On at $don_time" || echo "Display: Enabled"
    fi
    
    if [[ -f /etc/systemd/system/kiosk-quiet-start.timer ]]; then
        any_schedule=true
        local qstart_time=$(grep "^OnCalendar=" /etc/systemd/system/kiosk-quiet-start.timer 2>/dev/null | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        local qend_time=$(grep "^OnCalendar=" /etc/systemd/system/kiosk-quiet-end.timer 2>/dev/null | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        [[ -n "$qstart_time" && -n "$qend_time" ]] && echo "Quiet: $qstart_time to $qend_time" || echo "Quiet: Enabled"
    fi
    
    if [[ -f /etc/systemd/system/kiosk-electron-reload.timer ]]; then
        any_schedule=true
        echo "Electron Reload: Enabled"
    fi
    
    if ! $any_schedule; then
        echo "No schedules configured"
    fi
    echo
}


################################################################################
### SECTION 3: CORE CONFIGURATION FUNCTIONS
################################################################################

show_current_config() {
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        echo " ═══ CURRENT CONFIGURATION ═══"
        echo

        local autoswitch=$(sudo -u "$KIOSK_USER" jq -r '.autoswitch' "$CONFIG_PATH" 2>/dev/null)
        local swipe_mode=$(sudo -u "$KIOSK_USER" jq -r '.swipeMode' "$CONFIG_PATH" 2>/dev/null)
        local allow_nav=$(sudo -u "$KIOSK_USER" jq -r '.allowNavigation' "$CONFIG_PATH" 2>/dev/null)
        local tab_count=$(sudo -u "$KIOSK_USER" jq -r '.tabs | length' "$CONFIG_PATH" 2>/dev/null || echo "0")
        local home_tab=$(sudo -u "$KIOSK_USER" jq -r '.homeTabIndex // -1' "$CONFIG_PATH" 2>/dev/null)
        local inactivity_timeout=$(sudo -u "$KIOSK_USER" jq -r '.inactivityTimeout // 120' "$CONFIG_PATH" 2>/dev/null)

        echo "Auto-rotation: $autoswitch"
        echo "Touch control: $swipe_mode"
        echo "Navigation: $allow_nav"
        echo "Sites configured: $tab_count"

        if [[ "$home_tab" != "-1" ]]; then
            local timeout_min=$((inactivity_timeout / 60))
            echo "Home URL: Site $((home_tab + 1)) (timeout: ${timeout_min} min)"
        else
            echo "Home URL: Not configured"
        fi

        if [[ "$tab_count" -gt 0 ]]; then
            echo
            echo "Sites:"
            local has_rotation=false
            for ((i=0; i<tab_count; i++)); do
                local url=$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].url" "$CONFIG_PATH")
                local dur=$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].duration" "$CONFIG_PATH")
                local dur_display="${dur}s"
                local home_marker=""

                if [[ "$dur" == "0" ]]; then
                    dur_display="manual"
                elif [[ "$dur" == "-1" ]]; then
                    dur_display="hidden"
                else
                    has_rotation=true
                fi

                [[ "$home_tab" == "$i" ]] && home_marker=" [HOME]"

                echo "  $((i+1)). $url ($dur_display)$home_marker"
            done

            if $has_rotation; then
                echo
                echo "  ℹ Auto-rotation active for sites with duration > 0"
            fi
        fi

        echo
        echo "Optional Features:"
        local pause_btn=$(sudo -u "$KIOSK_USER" jq -r '.enablePauseButton // true' "$CONFIG_PATH" 2>/dev/null)
        local keyboard_btn=$(sudo -u "$KIOSK_USER" jq -r '.enableKeyboardButton // true' "$CONFIG_PATH" 2>/dev/null)
        echo "  Pause button: $pause_btn"
        echo "  Keyboard button: $keyboard_btn"

        echo
        echo "Password Protection:"
        local password_enabled=$(sudo -u "$KIOSK_USER" jq -r '.enablePasswordProtection // false' "$CONFIG_PATH" 2>/dev/null)
        if [[ "$password_enabled" == "true" ]]; then
            local lockout_timeout=$(sudo -u "$KIOSK_USER" jq -r '.lockoutTimeout // 0' "$CONFIG_PATH" 2>/dev/null)
            local lockout_at_time=$(sudo -u "$KIOSK_USER" jq -r '.lockoutAtTime // ""' "$CONFIG_PATH" 2>/dev/null)
            local lockout_active_start=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveStart // ""' "$CONFIG_PATH" 2>/dev/null)
            local lockout_active_end=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveEnd // ""' "$CONFIG_PATH" 2>/dev/null)
            local boot_password=$(sudo -u "$KIOSK_USER" jq -r '.requirePasswordOnBoot // false' "$CONFIG_PATH" 2>/dev/null)

            echo "  Status: Enabled"
            if [[ "$lockout_timeout" -gt 0 ]]; then
                echo "  Lockout after: ${lockout_timeout} min inactivity"
            else
                echo "  Lockout after: Only on display wake/boot"
            fi
            [[ -n "$lockout_at_time" ]] && echo "  Lock at: $lockout_at_time daily"
            if [[ -n "$lockout_active_start" && -n "$lockout_active_end" ]]; then
                echo "  Active hours: $lockout_active_start - $lockout_active_end"
            fi
            echo "  Password on boot: $boot_password"
        else
            echo "  Status: Disabled"
        fi
        echo
    else
        log_warning "No configuration found"
        echo
    fi
}

configure_timezone() {
    echo " ═══ TIMEZONE CONFIGURATION ═══"
    echo
    local current_tz=$(timedatectl show -p Timezone --value)
    echo "Current timezone: $current_tz"
    echo
    
    echo "Select timezone:"
    echo
    echo "Common Timezones:"
    echo "  1. America/New_York (US Eastern)"
    echo "  2. America/Chicago (US Central)"
    echo "  3. America/Denver (US Mountain)"
    echo "  4. America/Los_Angeles (US Pacific)"
    echo "  5. America/Phoenix (US Arizona)"
    echo "  6. America/Anchorage (US Alaska)"
    echo "  7. Pacific/Honolulu (US Hawaii)"
    echo "  8. Europe/London (UK)"
    echo "  9. Europe/Paris (Central Europe)"
    echo " 10. Europe/Berlin (Germany)"
    echo " 11. Europe/Rome (Italy)"
    echo " 12. Asia/Tokyo (Japan)"
    echo " 13. Asia/Shanghai (China)"
    echo " 14. Asia/Dubai (UAE)"
    echo " 15. Australia/Sydney (Australia East)"
    echo " 16. Pacific/Auckland (New Zealand)"
    echo " 17. Search for timezone"
    echo " 18. Enter timezone manually"
    echo "  0. Keep current ($current_tz)"
    echo
    read -r -p "Choose [0-18]: " tz_choice
    
    local new_tz=""
    case "$tz_choice" in
        1) new_tz="America/New_York" ;;
        2) new_tz="America/Chicago" ;;
        3) new_tz="America/Denver" ;;
        4) new_tz="America/Los_Angeles" ;;
        5) new_tz="America/Phoenix" ;;
        6) new_tz="America/Anchorage" ;;
        7) new_tz="Pacific/Honolulu" ;;
        8) new_tz="Europe/London" ;;
        9) new_tz="Europe/Paris" ;;
        10) new_tz="Europe/Berlin" ;;
        11) new_tz="Europe/Rome" ;;
        12) new_tz="Asia/Tokyo" ;;
        13) new_tz="Asia/Shanghai" ;;
        14) new_tz="Asia/Dubai" ;;
        15) new_tz="Australia/Sydney" ;;
        16) new_tz="Pacific/Auckland" ;;
        17)
            echo
            echo "Available regions:"
            local regions=($(timedatectl list-timezones | cut -d'/' -f1 | sort -u))
            for i in "${!regions[@]}"; do
                printf "  %2d) %s\n" $((i+1)) "${regions[$i]}"
            done
            echo
            read -r -p "Select region number [1-${#regions[@]}]: " region_num
            
            if [[ "$region_num" =~ ^[0-9]+$ ]] && [[ "$region_num" -ge 1 ]] && [[ "$region_num" -le "${#regions[@]}" ]]; then
                local selected_region="${regions[$((region_num-1))]}"
                echo
                echo "Timezones in $selected_region:"
                local timezones=($(timedatectl list-timezones | grep "^${selected_region}/"))
                for i in "${!timezones[@]}"; do
                    printf "  %3d) %s\n" $((i+1)) "${timezones[$i]}"
                done
                echo
                read -r -p "Select timezone number [1-${#timezones[@]}]: " tz_num
                
                if [[ "$tz_num" =~ ^[0-9]+$ ]] && [[ "$tz_num" -ge 1 ]] && [[ "$tz_num" -le "${#timezones[@]}" ]]; then
                    new_tz="${timezones[$((tz_num-1))]}"
                else
                    log_error "Invalid timezone selection"
                    return
                fi
            else
                log_error "Invalid region selection"
                return
            fi
            ;;
        18)
            echo
            read -r -p "Enter timezone (e.g., America/New_York): " new_tz
            ;;
        0|"")
            echo "Keeping current timezone"
            return
            ;;
        *)
            log_error "Invalid choice"
            return
            ;;
    esac
    
    case "$new_tz" in
        "US/Eastern") new_tz="America/New_York" ;;
        "US/Central") new_tz="America/Chicago" ;;
        "US/Mountain") new_tz="America/Denver" ;;
        "US/Pacific") new_tz="America/Los_Angeles" ;;
        "US/Alaska") new_tz="America/Anchorage" ;;
        "US/Hawaii") new_tz="Pacific/Honolulu" ;;
        "US/Arizona") new_tz="America/Phoenix" ;;
    esac
    
    if [[ -n "$new_tz" ]]; then
        if timedatectl list-timezones | grep -q "^${new_tz}$"; then
            sudo timedatectl set-timezone "$new_tz" && log_success "Timezone updated to $new_tz"
        else
            log_error "Invalid timezone: $new_tz"
        fi
    fi
}

configure_touch_controls() {
    echo " ═══ TOUCH CONTROLS CONFIGURATION ═══"
    echo
    echo "Touch control modes:"
    echo
    echo "  DUAL-DIRECTION (recommended for touchscreens):"
    echo "    • Two-finger swipe left/right = Switch between sites"
    echo "    • One-finger swipe left/right = Navigate within page (arrow keys)"
    echo "    Allows both site switching AND page navigation"
    echo
    echo "  STANDARD (simpler):"
    echo "    • Two-finger swipe left/right = Switch between sites only"
    echo "    • One-finger swipes do nothing"
    echo
    echo "NOTE: Touch controls are optional. Keyboard/mouse work without touch."
    echo
    
    load_config || true
    
    local current_mode="dual"
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        current_mode=$(sudo -u "$KIOSK_USER" jq -r '.swipeMode' "$CONFIG_PATH" 2>/dev/null)
    fi
    
    echo "Current: $current_mode"
    read -r -p "Use dual-direction mode? (y/n): " use_dual
    
    if [[ "$use_dual" =~ ^[Nn]$ ]]; then
        SWIPE_MODE="standard"
    else
        SWIPE_MODE="dual"
    fi
    
    log_success "Touch mode: $SWIPE_MODE"
}

configure_navigation_security() {
    echo " ═══ NAVIGATION SECURITY ═══"
    echo
    echo "Controls what users can access by clicking links:"
    echo
    echo "  RESTRICTED:"
    echo "    • Only the exact URL loaded (no link clicking)"
    echo "    • Use for locked-down kiosks"
    echo
    echo "  SAME-ORIGIN (recommended):"
    echo "    • Can click links within the same domain"
    echo "    • Example: example.com can link to example.com/page2"
    echo "    • Cannot go to different domains"
    echo
    echo "  OPEN:"
    echo "    • Can click any link, browse anywhere"
    echo "    • Use only for trusted environments"
    echo
    
    load_config || true
    
    local current_nav="same-origin"
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        current_nav=$(sudo -u "$KIOSK_USER" jq -r '.allowNavigation' "$CONFIG_PATH" 2>/dev/null)
    fi
    
    echo "Current: $current_nav"
    echo
    read -r -p "(r)estricted / (s)ame-origin / (o)pen [s]: " nav_choice
    
    case "${nav_choice:-s}" in
        [Rr]) ALLOW_NAVIGATION="restricted" ;;
        [Oo]) ALLOW_NAVIGATION="open" ;;
        *) ALLOW_NAVIGATION="same-origin" ;;
    esac
    
    log_success "Navigation: $ALLOW_NAVIGATION"
}

configure_optional_features() {
    echo " ═══ OPTIONAL FEATURES ═══"
    echo
    echo "Configure which optional features to enable:"
    echo

    # Load existing config if available
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        local current_pause=$(sudo -u "$KIOSK_USER" jq -r '.enablePauseButton // true' "$CONFIG_PATH" 2>/dev/null)
        local current_keyboard=$(sudo -u "$KIOSK_USER" jq -r '.enableKeyboardButton // true' "$CONFIG_PATH" 2>/dev/null)
        echo "Current settings: Pause=${current_pause}, Keyboard=${current_keyboard}"
    fi

    echo
    echo "PAUSE BUTTON:"
    echo "  Allows users to pause timed site rotation"
    if ask_yes_no "Enable pause button?" "y"; then
        ENABLE_PAUSE_BUTTON="true"
        log_success "Pause button enabled"
    else
        ENABLE_PAUSE_BUTTON="false"
        log_warning "Pause button disabled (functionality removed)"
    fi

    echo
    echo "KEYBOARD BUTTON:"
    echo "  Shows on-screen keyboard for text input"
    if ask_yes_no "Enable keyboard button?" "y"; then
        ENABLE_KEYBOARD_BUTTON="true"
        log_success "Keyboard button enabled"
    else
        ENABLE_KEYBOARD_BUTTON="false"
        log_warning "Keyboard button disabled (functionality removed)"
    fi

    echo
    if ask_yes_no "Save these changes?" "y"; then
        return 0
    else
        log_info "Changes discarded"
        return 1
    fi
}

configure_password_protection() {
    echo " ═══ PASSWORD PROTECTION & SESSION LOCKOUT ═══"
    echo
    echo "Add password protection with automatic lockout:"
    echo "  • Blank screen after inactivity period"
    echo "  • Password required to unlock"
    echo "  • Password required after display schedule wake-up"
    echo "  • Optional: Lock at specific time"
    echo "  • Optional: Only active during certain hours"
    echo "  • Optional: Require password on system boot"
    echo

    # Load existing config if available
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        local current_enabled=$(sudo -u "$KIOSK_USER" jq -r '.enablePasswordProtection // false' "$CONFIG_PATH" 2>/dev/null)
        local current_timeout=$(sudo -u "$KIOSK_USER" jq -r '.lockoutTimeout // 0' "$CONFIG_PATH" 2>/dev/null)
        if [[ "$current_enabled" == "true" ]]; then
            echo "Current: Enabled, lockout after ${current_timeout} minutes"
        else
            echo "Current: Disabled"
        fi
    fi

    echo
    if ask_yes_no "Enable password protection?" "n"; then
        ENABLE_PASSWORD_PROTECTION="true"

        # Ask for password
        echo
        echo "Set lockout password:"
        while true; do
            read -r -s -p "Enter password: " pass1
            echo
            read -r -s -p "Confirm password: " pass2
            echo

            if [[ -z "$pass1" ]]; then
                echo "❌ Password cannot be empty"
                continue
            fi

            if [[ "$pass1" == "$pass2" ]]; then
                # Hash the password using SHA-256
                LOCKOUT_PASSWORD=$(echo -n "$pass1" | sha256sum | cut -d' ' -f1)
                break
            else
                echo "❌ Passwords don't match, try again"
            fi
        done

        # Ask for lockout timeout
        echo
        echo "Session lockout time (minutes of inactivity):"
        echo "  Enter 0 to only require password after display schedule wake-up or boot"
        LOCKOUT_TIMEOUT=$(ask_integer "Lockout timeout in minutes" "30" 0 1440)

        # Ask for time-based lockout
        echo
        if ask_yes_no "Lock automatically at a specific time each day?" "n"; then
            read -r -p "Enter time to lock (HH:MM, 24-hour format, e.g., 17:00): " LOCKOUT_AT_TIME
            # Validate time format
            if [[ "$LOCKOUT_AT_TIME" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                log_success "Will lock at ${LOCKOUT_AT_TIME} daily"
            else
                echo "⚠ Invalid time format, time-based lockout disabled"
                LOCKOUT_AT_TIME=""
            fi
        else
            LOCKOUT_AT_TIME=""
        fi

        # No time-based lockout restrictions - password protection always active when enabled
        LOCKOUT_ACTIVE_START=""
        LOCKOUT_ACTIVE_END=""

        # Ask for boot password requirement
        echo
        if ask_yes_no "Require password on system boot/power on?" "y"; then
            REQUIRE_PASSWORD_ON_BOOT="true"
            log_success "Password will be required on boot"
        else
            REQUIRE_PASSWORD_ON_BOOT="false"
            log_info "Password only required after inactivity or display wake"
        fi

        log_success "Password protection enabled (lockout: ${LOCKOUT_TIMEOUT} min)"
    else
        ENABLE_PASSWORD_PROTECTION="false"
        LOCKOUT_PASSWORD=""
        LOCKOUT_TIMEOUT=0
        LOCKOUT_AT_TIME=""
        LOCKOUT_ACTIVE_START=""
        LOCKOUT_ACTIVE_END=""
        REQUIRE_PASSWORD_ON_BOOT="false"
        log_info "Password protection disabled"
    fi

    echo
    if ask_yes_no "Save these changes?" "y"; then
        return 0
    else
        log_info "Changes discarded"
        return 1
    fi
}

configure_sites() {
    while true; do
        echo " ═══ SITES CONFIGURATION ═══"
        echo
        
        URLS=()
        DURS=()
        USERS=()
        PASSES=()
        
        if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
            HOME_TAB_INDEX=$(sudo -u "$KIOSK_USER" jq -r '.homeTabIndex // -1' "$CONFIG_PATH" 2>/dev/null)
            INACTIVITY_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.inactivityTimeout // 120' "$CONFIG_PATH" 2>/dev/null)
            
            local tab_count=$(sudo -u "$KIOSK_USER" jq -r '.tabs | length' "$CONFIG_PATH" 2>/dev/null || echo "0")
            if [[ "$tab_count" -gt 0 ]]; then
                echo "Current sites:"
                local has_rotation=false
                for ((i=0; i<tab_count; i++)); do
                    local url=$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].url" "$CONFIG_PATH")
                    local dur=$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].duration" "$CONFIG_PATH")
                    local user=$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].username // empty" "$CONFIG_PATH")
                    
                    local dur_display="${dur}s"
                    local mode_display=""
                    
                    if [[ "$dur" == "-1" ]]; then
                        dur_display="hidden"
                        mode_display=" [HIDDEN]"
                    elif [[ "$dur" == "0" ]]; then
                        dur_display="manual"
                        mode_display=" [MANUAL-ONLY]"
                    else
                        mode_display=" [AUTO-ROTATE]"
                        has_rotation=true
                    fi
                    
                    local auth_display=""
                    [[ -n "$user" ]] && auth_display=" [auth]"
                    
                    local home_display=""
                    [[ "$HOME_TAB_INDEX" == "$i" ]] && home_display=" [HOME]"
                    
                    echo "  $((i+1)). $url ($dur_display)$auth_display$home_display$mode_display"
                    
                    URLS+=("$url")
                    DURS+=("$dur")
                    USERS+=("$user")
                    PASSES+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].password // empty" "$CONFIG_PATH")")
                done
                echo
                
                if $has_rotation; then
                    echo "Auto-rotation: ✓ Active (sites with duration > 0)"
                else
                    echo "Auto-rotation: ✗ No sites configured for rotation"
                fi
                echo
                
                if [[ "$HOME_TAB_INDEX" != "-1" ]]; then
                    local timeout_min=$((INACTIVITY_TIMEOUT / 60))
                    echo "Home URL: ✓ Enabled (${timeout_min} min timeout)"
                else
                    echo "Home URL: ✗ Disabled"
                fi
                echo
                
                echo "Options:"
                echo "  1. Keep all sites as-is"
                echo "  2. Update durations"
                echo "  3. Add more sites"
                echo "  4. Reorder sites"
                echo "  5. Delete a site"
                echo "  6. Configure Home URL"
                echo "  7. Clear all, start over"
                echo "  0. Return to menu"
                echo
                local site_choice=$(ask_menu_choice 7)

                case "$site_choice" in
                    1)
                        log_success "Keeping existing sites"
                        return
                        ;;
                    2)
                        update_site_durations
                        save_config
                        continue
                        ;;
                    3)
                        echo
                        echo "Adding new sites:"
                        add_new_sites_simple
                        save_config
                        continue
                        ;;
                    4)
                        reorder_sites
                        save_config
                        continue
                        ;;
                    5)
                        delete_site
                        save_config
                        continue
                        ;;
                    6)
                        configure_home_url
                        save_config
                        continue
                        ;;
                    7)
                        URLS=()
                        DURS=()
                        USERS=()
                        PASSES=()
                        HOME_TAB_INDEX=-1
                        INACTIVITY_TIMEOUT=120
                        add_new_sites
                        save_config
                        continue
                        ;;
                    0)
                        return
                        ;;
                esac
            fi
        fi
        
        add_new_sites
        save_config
        return
    done
}

update_site_durations() {
    echo
    echo "Update site durations:"
    echo
    echo "ℹ Duration Guide:"
    echo "  • 0 seconds = Manual only (won't auto-rotate)"
    echo "  • 1-999 seconds = Auto-rotates every X seconds"
    echo "  • -1 = Hidden tab (F10 to access)"
    echo
    
    local new_durs=()
    
    for idx in "${!URLS[@]}"; do
        echo "Site $((idx+1)): ${URLS[$idx]}"
        read -r -p "  Duration in seconds (0=manual, >0=rotate) [${DURS[$idx]}]: " new_dur
        new_dur="${new_dur:-${DURS[$idx]}}"
        new_durs+=("$new_dur")
        echo
    done
    
    DURS=("${new_durs[@]}")
    
    log_success "Site durations updated"
}

delete_site() {
    echo
    echo "Delete which site?"
    for idx in "${!URLS[@]}"; do
        echo "  $((idx+1)). ${URLS[$idx]}"
    done
    echo
    local max_sites="${#URLS[@]}"
    local del_num=$(ask_integer "Enter number to delete (0=cancel)" "0" 0 "$max_sites")

    if [[ "$del_num" -ge 1 ]] && [[ "$del_num" -le "$max_sites" ]]; then
        local del_idx=$((del_num-1))
        echo "Deleting: ${URLS[$del_idx]}"
        unset 'URLS[$del_idx]'
        unset 'DURS[$del_idx]'
        unset 'USERS[$del_idx]'
        unset 'PASSES[$del_idx]'
        URLS=("${URLS[@]}")
        DURS=("${DURS[@]}")
        USERS=("${USERS[@]}")
        PASSES=("${PASSES[@]}")

        # Adjust HOME_TAB_INDEX if necessary
        if [[ "$HOME_TAB_INDEX" == "$del_idx" ]]; then
            HOME_TAB_INDEX=-1
            log_warning "Home URL was deleted - home feature disabled"
        elif [[ "$HOME_TAB_INDEX" -gt "$del_idx" ]]; then
            HOME_TAB_INDEX=$((HOME_TAB_INDEX - 1))
        fi

        log_success "Site deleted"
        log_warning "Site numbers have changed! Review rotation settings."
    else
        echo "Cancelled"
    fi
}

reorder_sites() {
    if [[ "${#URLS[@]}" -lt 2 ]]; then
        log_warning "Need at least 2 sites to reorder"
        pause
        return
    fi

    echo
    echo " ═══ REORDER SITES ═══"
    echo
    echo "Current order:"
    for idx in "${!URLS[@]}"; do
        echo "  $((idx+1)). ${URLS[$idx]}"
    done
    echo

    local max_sites="${#URLS[@]}"
    local from_num=$(ask_integer "Move which site? (0=cancel)" "0" 0 "$max_sites")

    if [[ "$from_num" == "0" ]]; then
        echo "Cancelled"
        return
    fi

    local to_num=$(ask_integer "Move to position? (1-$max_sites)" "1" 1 "$max_sites")

    local from_idx=$((from_num - 1))
    local to_idx=$((to_num - 1))

    if [[ "$from_idx" == "$to_idx" ]]; then
        echo "Same position - no change"
        return
    fi

    # Save the item to move
    local move_url="${URLS[$from_idx]}"
    local move_dur="${DURS[$from_idx]}"
    local move_user="${USERS[$from_idx]}"
    local move_pass="${PASSES[$from_idx]}"

    # Remove from old position
    unset 'URLS[$from_idx]'
    unset 'DURS[$from_idx]'
    unset 'USERS[$from_idx]'
    unset 'PASSES[$from_idx]'
    URLS=("${URLS[@]}")
    DURS=("${DURS[@]}")
    USERS=("${USERS[@]}")
    PASSES=("${PASSES[@]}")

    # Adjust to_idx if needed (if we removed an item before the target)
    if [[ "$from_idx" -lt "$to_idx" ]]; then
        to_idx=$((to_idx - 1))
    fi

    # Insert at new position
    URLS=("${URLS[@]:0:$to_idx}" "$move_url" "${URLS[@]:$to_idx}")
    DURS=("${DURS[@]:0:$to_idx}" "$move_dur" "${DURS[@]:$to_idx}")
    USERS=("${USERS[@]:0:$to_idx}" "$move_user" "${USERS[@]:$to_idx}")
    PASSES=("${PASSES[@]:0:$to_idx}" "$move_pass" "${PASSES[@]:$to_idx}")

    # Update HOME_TAB_INDEX if it was affected
    if [[ "$HOME_TAB_INDEX" == "$from_idx" ]]; then
        HOME_TAB_INDEX=$to_idx
    elif [[ "$from_idx" -lt "$HOME_TAB_INDEX" ]] && [[ "$HOME_TAB_INDEX" -le "$to_idx" ]]; then
        HOME_TAB_INDEX=$((HOME_TAB_INDEX - 1))
    elif [[ "$from_idx" -gt "$HOME_TAB_INDEX" ]] && [[ "$HOME_TAB_INDEX" -ge "$to_idx" ]]; then
        HOME_TAB_INDEX=$((HOME_TAB_INDEX + 1))
    fi

    echo
    echo "New order:"
    for idx in "${!URLS[@]}"; do
        echo "  $((idx+1)). ${URLS[$idx]}"
    done

    log_success "Sites reordered"
}

configure_home_url() {
    echo
    echo " ═══ HOME URL CONFIGURATION ═══"
    echo
    echo "A HOME URL is where the kiosk returns after inactivity on other tabs."
    echo
    echo "How it works:"
    echo "  • Choose one site to be the HOME tab"
    echo "  • After X minutes on other tabs, user is prompted:"
    echo "    \"Are you still here?\""
    echo "  • If no response in 10 seconds, returns to HOME tab"
    echo "  • Good for: Main dashboard, photo slideshow, default screen"
    echo
    
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        HOME_TAB_INDEX=$(sudo -u "$KIOSK_USER" jq -r '.homeTabIndex // -1' "$CONFIG_PATH" 2>/dev/null)
        INACTIVITY_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.inactivityTimeout // 120' "$CONFIG_PATH" 2>/dev/null)
    fi
    
    if [[ "$HOME_TAB_INDEX" != "-1" ]]; then
        local timeout_min=$((INACTIVITY_TIMEOUT / 60))
        echo "Current: Site #$((HOME_TAB_INDEX + 1)) is HOME (${timeout_min} min timeout)"
    else
        echo "Current: Disabled"
    fi
    echo
    
    echo "Options:"
    echo "  1. Enable/Change Home URL"
    echo "  2. Disable Home URL"
    echo "  0. Cancel"
    echo
    read -r -p "Choose [0-2]: " home_choice
    
    case "$home_choice" in
        1)
            echo
            echo "Select which site should be HOME:"
            for idx in "${!URLS[@]}"; do
                echo "  $((idx+1)). ${URLS[$idx]}"
            done
            echo
            read -r -p "Site number [1]: " site_num
            site_num="${site_num:-1}"
            
            if [[ "$site_num" =~ ^[0-9]+$ ]] && [[ "$site_num" -ge 1 ]] && [[ "$site_num" -le "${#URLS[@]}" ]]; then
                HOME_TAB_INDEX=$((site_num - 1))
                
                echo
                read -r -p "Inactivity timeout in minutes [2]: " timeout_min
                timeout_min="${timeout_min:-2}"
                INACTIVITY_TIMEOUT=$((timeout_min * 60))
                
                log_success "Home URL: Site #${site_num} (${timeout_min} min timeout)"
            else
                log_error "Invalid site number"
            fi
            ;;
        2)
            HOME_TAB_INDEX=-1
            INACTIVITY_TIMEOUT=120
            log_success "Home URL disabled"
            ;;
        0)
            echo "Cancelled"
            ;;
    esac
}

add_new_sites() {
    echo " ═══ SITE ROTATION SETUP ═══"
    echo
    echo "HOW AUTO-ROTATION WORKS:"
    echo "────────────────────────────"
    echo "Each site has a DURATION:"
    echo
    echo "  • Duration > 0   = Auto-rotates after X seconds"
    echo "  • Duration = 0   = Manual only (swipe to access)"
    echo "  • Duration = -1  = Hidden (F10 or 3-finger up + PIN)"
    echo
    echo "💡 Want NO auto-rotation? Set ALL sites to 0 seconds"
    echo "   (You can still swipe between sites manually)"
    echo
    echo
    echo "EXAMPLES:"
    echo "  Site A: 180s → Auto-rotates every 3 minutes"
    echo "  Site B: 60s  → Auto-rotates every 1 minute"
    echo "  Site C: 0s   → Manual access only"
    echo "  Site D: -1s  → Hidden behind PIN"
    echo
    pause
    
    local use_home_url=false
    local inactivity_minutes=2
    local home_duration=180
    
    echo " ═══ HOME URL FEATURE ═══"
    echo
    echo "A HOME URL returns the kiosk to a default screen after inactivity."
    echo
    echo "How it works:"
    echo "  • First site = HOME"
    echo "  • After X minutes of inactivity on OTHER sites:"
    echo "    → Prompt: \"Are you still here?\""
    echo "    → No response = returns to HOME"
    echo
    echo "Good for: Photo slideshows, dashboards, screensavers"
    echo
    if ask_yes_no "Enable HOME URL feature?" "n"; then
        use_home_url=true
        read -r -p "Inactivity timeout in minutes [2]: " inactivity_minutes
        inactivity_minutes="${inactivity_minutes:-2}"
        read -r -p "Home display duration in seconds [180]: " home_duration
        home_duration="${home_duration:-180}"
        echo "✓ HOME: Returns after ${inactivity_minutes}min, displays ${home_duration}s"
    else
        echo "✓ HOME disabled"
    fi
    echo
    
    echo " ═══ ENTER SITES ═══"
    echo
    echo "Supported formats:"
    echo "  • example.com → https://example.com"
    echo "  • https://example.com"
    echo "  • 192.168.1.3:8080 → http://192.168.1.3:8080"
    echo
    if $use_home_url; then
        echo "FIRST SITE = HOME (will display ${home_duration}s before rotating)"
    fi
    echo
    echo "Enter sites (blank when done):"
    echo
    
    local is_first=true
    while true; do
        echo "────────────────────────────"
        read -r -p "URL (blank=done): " raw_url
        [[ -z "$raw_url" ]] && break
        
        # Parse URL
        local url=""
        if [[ "$raw_url" =~ ^https?:// ]]; then
            url="$raw_url"
        elif [[ "$raw_url" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            url="http://${raw_url}"
        else
            url="https://${raw_url}"
        fi
        
        # Duration
        local dur=""
        local is_home=false
        
        if $is_first && $use_home_url; then
            is_home=true
            dur=$home_duration
            echo "  → HOME site (${dur}s rotation)"
        else
            echo "  Duration options:"
            echo "    >0 = Auto-rotate (e.g., 180 = 3 minutes)"
            echo "     0 = Manual only"
            echo "    -1 = Hidden (PIN protected)"
            read -r -p "  Duration [180]: " dur
            dur="${dur:-180}"
        fi
        
        # Auth
        echo ""
        echo "❓ Does this website require login credentials?"
        echo ""
        echo "   ONLY say yes if:"
        echo "   • The website uses HTTP Basic Authentication"
        echo "   • You get a browser popup asking for username/password"
        echo "   • The website documentation says 'Basic Auth'"
        echo ""
        echo "   Say NO if:"
        echo "   • The website has a login page with forms"
        echo "   • You don't know what Basic Auth is"
        echo "   • The website is public (Google, YouTube, etc.)"
        echo ""
        read -r -p "  Does this site use Basic Auth? (y/n): " needs_auth
        
        if [[ "$needs_auth" =~ ^[Yy]$ ]]; then
            echo ""
            echo "  Enter credentials (saved in config.json)"
            read -r -p "    Username: " auth_user
            read -r -s -p "    Password: " auth_pass
            echo
            USERS+=("$auth_user")
            PASSES+=("$auth_pass")
        else
            USERS+=("")
            PASSES+=("")
        fi
        
        URLS+=("$url")
        DURS+=("$dur")
        
        if $is_home; then
            HOME_TAB_INDEX=$((${#URLS[@]} - 1))
            INACTIVITY_TIMEOUT=$((inactivity_minutes * 60))
            echo "  ✓ HOME configured"
        fi
        
        local dur_display="${dur}s"
        [[ "$dur" == "0" ]] && dur_display="manual"
        [[ "$dur" == "-1" ]] && dur_display="hidden"
        echo "  ✓ Added: $url ($dur_display)"
        
        is_first=false
    done
    
    if [[ ${#URLS[@]} -eq 0 ]]; then
        URLS=("https://www.ubuntu.com")
        DURS=(180)
        USERS=("")
        PASSES=("")
        log_success "Using default: ubuntu.com (180s)"
    fi
    
    echo
    log_success "${#URLS[@]} sites configured"
    
    # Auto-switch if any site has duration > 0
    AUTOSWITCH="false"
    for dur in "${DURS[@]}"; do
        if [[ "$dur" != "0" && "$dur" != "-1" ]]; then
            AUTOSWITCH="true"
            break
        fi
    done
    
    echo
    if [[ "$AUTOSWITCH" == "true" ]]; then
        echo "✓ Auto-rotation ENABLED"
        echo "  Sites with duration>0 will rotate"
        echo "  Sites with duration=0 are manual-only"
        [[ "$use_home_url" == "true" ]] && echo "  Home included in rotation (${home_duration}s)"
    else
        echo "✓ Auto-rotation DISABLED (all sites manual)"
    fi
}

add_new_sites_simple() {
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        local current_autoswitch=$(sudo -u "$KIOSK_USER" jq -r '.autoswitch' "$CONFIG_PATH" 2>/dev/null)
        AUTOSWITCH="$current_autoswitch"
    fi
    
    local has_existing_timings=false
    local existing_timing=""
    for dur in "${DURS[@]}"; do
        if [[ "$dur" != "0" && "$dur" != "-1" ]]; then
            has_existing_timings=true
            existing_timing="$dur"
            break
        fi
    done
    
    echo "Enter new sites (blank URL when done):"
    echo
    echo "ℹ Duration: 0=manual only, >0=auto-rotate every X seconds"
    echo
    
    while true; do
        read -r -p "URL (blank=done): " raw_url
        [[ -z "$raw_url" ]] && break
        
        local url=""
        if [[ "$raw_url" =~ ^https?:// ]]; then
            url="$raw_url"
        elif [[ "$raw_url" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            url="http://${raw_url}"
        else
            url="https://${raw_url}"
        fi
        
        local dur=""
        if [[ "$AUTOSWITCH" == "true" ]]; then
            if $has_existing_timings; then
                read -r -p "  Duration in seconds [$existing_timing]: " dur
                dur="${dur:-$existing_timing}"
            else
                read -r -p "  Duration in seconds [180]: " dur
                dur="${dur:-180}"
            fi
        else
            dur=0
            echo "  Duration: manual (auto-rotation is disabled)"
        fi
        
        read -r -p "  Basic auth? (y/n): " needs_auth
        if [[ "$needs_auth" =~ ^[Yy]$ ]]; then
            read -r -p "    Username: " auth_user
            read -r -s -p "    Password: " auth_pass
            echo
            USERS+=("$auth_user")
            PASSES+=("$auth_pass")
        else
            USERS+=("")
            PASSES+=("")
        fi
        
        URLS+=("$url")
        DURS+=("$dur")
    done
    
    log_success "${#URLS[@]} total sites configured"
}

################################################################################
### SECTION 4: WIFI CONFIGURATION (3-method scan + better errors)
################################################################################

configure_wifi() {
    echo " ══ WIFI CONFIGURATION ══"
    echo
    
    # Verify we have necessary tools
    local has_tools=false
    if command -v nmcli &>/dev/null || command -v iw &>/dev/null || command -v wpa_cli &>/dev/null; then
        has_tools=true
    fi
    
    if ! $has_tools; then
        log_error "No WiFi tools found (nmcli, iw, or wpa_cli)"
        echo "Install: sudo apt install network-manager wireless-tools wpasupplicant"
        pause
        return 1
    fi
    
    local wifi_iface=$(ls /sys/class/net 2>/dev/null | grep -E "^wl" | head -1)
    
    if [[ -z "$wifi_iface" ]]; then
        log_warning "No WiFi hardware detected"
        echo "If you have USB WiFi adapter, ensure it's plugged in"
        pause
        return 1
    fi
    
    echo "Interface: $wifi_iface"
    echo "Current IP: $(get_ip_address)"
    echo
    
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        log_warning "SSH detected - changes auto-revert after 60s if connection fails"
        echo
    fi
    
    read -r -p "Configure WiFi? (y/n): " do_wifi
    [[ ! "$do_wifi" =~ ^[Yy]$ ]] && return 0
    
    echo "Bringing up interface..."
    if ! sudo ip link set "$wifi_iface" up 2>/dev/null; then
        log_error "Failed to bring up interface"
        pause
        return 1
    fi
    sleep 3
    
    echo "Scanning for networks (this takes 5-10 seconds)..."
    local scan_results=""
    
    # Try nmcli first
    if command -v nmcli &>/dev/null; then
        if sudo nmcli device wifi rescan 2>/dev/null; then
            sleep 5
            scan_results=$(nmcli -t -f SSID,SIGNAL device wifi list 2>/dev/null | sort -t: -k2 -rn | cut -d: -f1 | grep -v "^$" | uniq)
        fi
    fi
    
    # Fallback to iw if nmcli failed
    if [[ -z "$scan_results" ]] && command -v iw &>/dev/null; then
        if sudo iw dev "$wifi_iface" scan 2>/dev/null | grep -E "^BSS|SSID:" > /tmp/wifi_scan.txt; then
            scan_results=$(grep "SSID:" /tmp/wifi_scan.txt | sed 's/.*SSID: //' | grep -v "^$" | sort -u)
            rm -f /tmp/wifi_scan.txt
        fi
    fi
    
    # Fallback to wpa_cli
    if [[ -z "$scan_results" ]]; then
        sudo wpa_cli -i "$wifi_iface" scan >/dev/null 2>&1 || true
        sleep 5
        scan_results=$(sudo wpa_cli -i "$wifi_iface" scan_results 2>/dev/null | awk -F'\t' 'NR>1 && $5!="" {print $5}' | sort -u)
    fi
    
    local ssid=""
    if [[ -z "$scan_results" ]]; then
        log_warning "No networks found in scan"
        echo "This could mean:"
        echo "  • WiFi is disabled in BIOS/UEFI"
        echo "  • Hardware WiFi switch is off"
        echo "  • Driver not loaded"
        echo "  • Networks out of range"
        echo
        read -r -p "Enter SSID manually anyway? (y/n): " manual
        if [[ "$manual" =~ ^[Yy]$ ]]; then
            read -r -p "SSID: " ssid
        else
            return 1
        fi
    else
        echo
        echo "Available networks (strongest first):"
        echo "$scan_results" | nl -w2 -s'. '
        echo "  0. Manual entry"
        echo
        read -r -p "Select network number or enter SSID: " choice
        if [[ "$choice" == "0" ]]; then
            read -r -p "SSID: " ssid
        elif [[ "$choice" =~ ^[0-9]+$ ]]; then
            ssid=$(echo "$scan_results" | sed -n "${choice}p")
        else
            ssid="$choice"
        fi
    fi
    
    [[ -z "$ssid" ]] && { log_error "No SSID provided"; return 1; }
    
    read -r -s -p "Password for '$ssid': " password
    echo
    [[ -z "$password" ]] && { log_error "No password provided"; return 1; }
    
    local netplan_file=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
    if [[ -z "$netplan_file" ]]; then
        netplan_file="/etc/netplan/50-cloud-init.yaml"
    fi
    
    if [[ -f "$netplan_file" ]]; then
        local backup="${netplan_file}.backup-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$netplan_file" "$backup"
        log_success "Backup: $backup"
    fi
    
    local temp_plan="/tmp/netplan-$$.yaml"
    cat > "$temp_plan" <<EOF
network:
  version: 2
  renderer: networkd
  wifis:
    $wifi_iface:
      dhcp4: true
      dhcp6: false
      optional: true
      access-points:
        "$ssid":
          password: "$password"
EOF
    
    if [[ -n "${SSH_CONNECTION:-}" ]] && [[ -f "$backup" ]]; then
        local watchdog="/tmp/wifi-watchdog-$$.sh"
        cat > "$watchdog" <<'WATCHEOF'
#!/bin/bash
sleep 60
if [[ -f "$1" && -f "$2" ]]; then
    ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$ip" ]] || ! ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        cp "$1" "$2"
        netplan apply 2>/dev/null
        echo "WiFi config reverted - connection failed" | wall
    fi
fi
rm -f "$0"
WATCHEOF
        chmod +x "$watchdog"
        nohup sudo bash "$watchdog" "$backup" "$netplan_file" >/dev/null 2>&1 &
        echo "Watchdog started - will revert in 60s if connection fails"
    fi
    
    sudo cp "$temp_plan" "$netplan_file"
    sudo chmod 0600 "$netplan_file"
    
    echo "Applying configuration..."
    if sudo netplan apply 2>&1 | tee /tmp/netplan-error.log; then
        sleep 10
        local new_ip=$(get_ip_address)
        if [[ -n "$new_ip" && "$new_ip" != "No IP" ]]; then
            log_success "Connected: $ssid ($new_ip)"
            if [[ -n "${SSH_CONNECTION:-}" ]]; then
                echo "Connection successful - watchdog will not revert"
            fi
        else
            log_warning "Config applied but no IP yet"
            echo "Check: sudo journalctl -u systemd-networkd -f"
        fi
    else
        log_error "netplan apply failed"
        echo "Error log:"
        cat /tmp/netplan-error.log
        if [[ -f "$backup" ]]; then
            echo
            read -r -p "Restore backup? (y/n): " restore
            if [[ "$restore" =~ ^[Yy]$ ]]; then
                sudo cp "$backup" "$netplan_file"
                sudo netplan apply
            fi
        fi
    fi
    
    rm -f "$temp_plan" /tmp/netplan-error.log
    pause
}
################################################################################
### FIX 4.5: EMERGENCY HOTSPOT WITH ON-SCREEN NOTIFICATION
################################################################################

# ADD THIS NEW FUNCTION after configure_wifi() function (around line 2100)

configure_emergency_hotspot() {
    echo
    echo "══ EMERGENCY HOTSPOT ══"
    echo
    echo "Creates a WiFi hotspot if no internet connection after boot."
    echo "Allows you to connect and reconfigure the kiosk remotely."
    echo
    
    local hotspot_enabled=false
    if [[ -f /usr/local/bin/kiosk-emergency-hotspot ]]; then
        hotspot_enabled=true
        echo "Status: ✓ Configured"
        local hotspot_ssid=$(grep '^HOTSPOT_SSID=' /usr/local/bin/kiosk-emergency-hotspot 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        echo "  SSID: $hotspot_ssid"
        echo
        echo "Options:"
        echo "  1. Keep as-is"
        echo "  2. Reconfigure"
        echo "  3. Disable"
        echo "  0. Return"
    else
        echo "Status: Not configured"
        echo
        echo "Options:"
        echo "  1. Enable emergency hotspot"
        echo "  0. Return"
    fi
    echo
    read -r -p "Choose: " choice
    
    case "$choice" in
        1)
            if $hotspot_enabled; then
                echo "Keeping current configuration"
                pause
                return
            else
                install_emergency_hotspot
            fi
            ;;
        2)
            if $hotspot_enabled; then
                install_emergency_hotspot
            fi
            ;;
        3)
            if $hotspot_enabled; then
                disable_emergency_hotspot
            fi
            ;;
        0) return ;;
    esac
}

install_emergency_hotspot() {
    echo
    echo "Installing emergency hotspot system..."
    
    # Install required packages
    sudo apt install -y hostapd dnsmasq iptables
    
    # Stop services for now
    sudo systemctl stop hostapd dnsmasq 2>/dev/null || true
    sudo systemctl disable hostapd dnsmasq 2>/dev/null || true
    
    # Get WiFi interface
    local wifi_iface=$(ls /sys/class/net 2>/dev/null | grep -E "^wl" | head -1)
    if [[ -z "$wifi_iface" ]]; then
        log_error "No WiFi interface found"
        pause
        return 1
    fi
    
    echo "WiFi interface: $wifi_iface"
    echo
    
    # Get configuration
    read -r -p "Hotspot SSID [Kiosk-Emergency]: " hotspot_ssid
    hotspot_ssid="${hotspot_ssid:-Kiosk-Emergency}"
    
    read -r -s -p "Hotspot password (8+ chars): " hotspot_pass
    echo
    while [[ ${#hotspot_pass} -lt 8 ]]; do
        echo "Password must be at least 8 characters"
        read -r -s -p "Hotspot password: " hotspot_pass
        echo
    done
    
    local hotspot_ip="192.168.50.1"
    
    # Create emergency hotspot script
    sudo tee /usr/local/bin/kiosk-emergency-hotspot > /dev/null <<EOF
#!/bin/bash
################################################################################
### KIOSK EMERGENCY HOTSPOT
### Auto-starts if no internet connection 60 seconds after boot
################################################################################

WIFI_IFACE="$wifi_iface"
HOTSPOT_SSID="$hotspot_ssid"
HOTSPOT_PASS="$hotspot_pass"
HOTSPOT_IP="$hotspot_ip"
KIOSK_USER="$KIOSK_USER"

# Wait 60 seconds after boot
sleep 60

# Check for internet connectivity
if ping -c 3 -W 5 8.8.8.8 >/dev/null 2>&1; then
    logger "KIOSK: Internet connected - emergency hotspot not needed"
    exit 0
fi

logger "KIOSK: No internet detected - starting emergency hotspot"

# Stop any conflicting services
systemctl stop wpa_supplicant 2>/dev/null || true
ip link set \$WIFI_IFACE down 2>/dev/null || true
sleep 2

# Configure static IP for hotspot
ip addr flush dev \$WIFI_IFACE
ip addr add \${HOTSPOT_IP}/24 dev \$WIFI_IFACE
ip link set \$WIFI_IFACE up

# Configure dnsmasq
cat > /tmp/dnsmasq-hotspot.conf <<DNSMASQ
interface=\$WIFI_IFACE
dhcp-range=192.168.50.10,192.168.50.50,12h
dhcp-option=3,\$HOTSPOT_IP
dhcp-option=6,\$HOTSPOT_IP
server=8.8.8.8
log-queries
log-dhcp
DNSMASQ

# Start dnsmasq
dnsmasq -C /tmp/dnsmasq-hotspot.conf

# Configure hostapd
cat > /tmp/hostapd-hotspot.conf <<HOSTAPD
interface=\$WIFI_IFACE
driver=nl80211
ssid=\$HOTSPOT_SSID
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=\$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
HOSTAPD

# Start hostapd
hostapd -B /tmp/hostapd-hotspot.conf

# Enable IP forwarding (optional - for internet sharing if wired connection exists)
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# Show notification on kiosk display
sudo -u \$KIOSK_USER DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u \$KIOSK_USER)/bus \\
    notify-send -u critical -t 0 "Emergency Hotspot Active" \\
    "SSID: \$HOTSPOT_SSID\\nPassword: \$HOTSPOT_PASS\\nConnect to: http://\$HOTSPOT_IP" 2>/dev/null || true

logger "KIOSK: Emergency hotspot started - SSID: \$HOTSPOT_SSID, IP: \$HOTSPOT_IP"

# Create on-screen notification HTML
sudo -u \$KIOSK_USER tee /tmp/hotspot-notification.html > /dev/null <<'NOTIFY'
<!DOCTYPE html>
<html>
<head>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: rgba(0,0,0,0.95);
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
}
.container {
  text-align: center;
  padding: 40px;
  background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
  border-radius: 20px;
  box-shadow: 0 10px 40px rgba(0,0,0,0.5);
  max-width: 600px;
}
h1 { font-size: 48px; margin-bottom: 20px; }
.icon { font-size: 72px; margin-bottom: 20px; }
.info { font-size: 24px; margin: 20px 0; line-height: 1.6; }
.credential { 
  background: rgba(0,0,0,0.3);
  padding: 15px;
  border-radius: 10px;
  margin: 10px 0;
  font-family: monospace;
  font-size: 20px;
}
.dismiss {
  margin-top: 30px;
  padding: 15px 40px;
  font-size: 18px;
  background: white;
  color: #e74c3c;
  border: none;
  border-radius: 10px;
  cursor: pointer;
  font-weight: bold;
}
.dismiss:hover { background: #ecf0f1; }
</style>
</head>
<body>
<div class="container">
  <div class="icon">📡</div>
  <h1>Emergency Hotspot Active</h1>
  <div class="info">No internet connection detected<br>Hotspot created for remote access</div>
  <div class="credential">SSID: <strong>\$HOTSPOT_SSID</strong></div>
  <div class="credential">Password: <strong>\$HOTSPOT_PASS</strong></div>
  <div class="credential">Connect to: <strong>http://\$HOTSPOT_IP</strong></div>
  <button class="dismiss" onclick="window.close()">Dismiss</button>
</div>
<script>
// Auto-dismiss after 5 minutes
setTimeout(() => window.close(), 300000);
</script>
</body>
</html>
NOTIFY

# Show notification window if Electron is running
if pgrep -f "electron.*main.js" >/dev/null 2>&1; then
    sudo -u \$KIOSK_USER DISPLAY=:0 \\
        /home/\$KIOSK_USER/kiosk-app/node_modules/electron/dist/electron \\
        /tmp/hotspot-notification.html &
fi

exit 0
EOF
    
    sudo chmod +x /usr/local/bin/kiosk-emergency-hotspot
    
    # Create systemd service
    sudo tee /etc/systemd/system/kiosk-emergency-hotspot.service > /dev/null <<'HOTSPOTSVC'
[Unit]
Description=Kiosk Emergency Hotspot
After=network.target lightdm.service
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiosk-emergency-hotspot
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
HOTSPOTSVC
    
    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable kiosk-emergency-hotspot.service
    
    echo
    log_success "Emergency hotspot configured"
    echo "  SSID: $hotspot_ssid"
    echo "  Password: $hotspot_pass"
    echo "  IP: $hotspot_ip"
    echo
    echo "Hotspot will auto-start if no internet after 60 seconds of boot"
    echo "On-screen notification will show connection details"
    
    pause
}

disable_emergency_hotspot() {
    echo
    read -r -p "Disable emergency hotspot? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo systemctl stop kiosk-emergency-hotspot.service 2>/dev/null || true
        sudo systemctl disable kiosk-emergency-hotspot.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/kiosk-emergency-hotspot.service
        sudo rm -f /usr/local/bin/kiosk-emergency-hotspot
        sudo systemctl daemon-reload
        log_success "Emergency hotspot disabled"
    fi
    pause
}



################################################################################
### SECTION 5: POWER/DISPLAY/QUIET SCHEDULES
################################################################################

configure_power_display_quiet() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════"
        echo "   POWER / DISPLAY / QUIET HOURS                             "
        echo "════════════════════════════════════════════════════════════"
        echo
        
        show_schedule_status
        
        local rtc_available=false
        local rtc_status="Not available"
        if [[ -w /sys/class/rtc/rtc0/wakealarm ]] || sudo test -w /sys/class/rtc/rtc0/wakealarm 2>/dev/null; then
            rtc_available=true
            rtc_status="✓ Available and enabled"
        elif [[ -e /sys/class/rtc/rtc0/wakealarm ]]; then
            rtc_status="⚠ Available but not writable"
        fi
        
        echo " ═══ RTC Wake Capability ═══"
        echo "Status: $rtc_status"
        echo
        if $rtc_available; then
            echo "Can schedule: Power on/off + Display on/off"
        else
            echo "Can schedule: Display on/off only"
            if grep -qi "raspberry" /proc/cpuinfo 2>/dev/null; then
                echo "  Raspberry Pi: Requires DS3231/DS1307 RTC module"
            fi
        fi
        echo
        
        echo "Options:"
        echo "  1. Configure power schedule"
        $rtc_available || echo "     (Not available)"
        echo "  2. Configure display schedule"
        echo "  3. Configure quiet hours"
        echo "  4. Configure Electron reload"
        echo "  5. Remove all schedules"
        echo "  6. Test schedules & system"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-6]: " choice
        
        case "$choice" in
            1)
                if $rtc_available; then
                    configure_power_schedule
                else
                    log_warning "RTC not available"
                    pause
                fi
                ;;
            2) configure_display_schedule ;;
            3) configure_quiet_hours ;;
            4) configure_electron_reload ;;
            5) remove_all_schedules ;;
            6) show_testing_menu ;;
            0) return ;;
        esac
    done
}

#!/bin/bash
################################################################################
### COMPLETE SCHEDULE FUNCTIONS - DROP-IN REPLACEMENT
### Insert these functions around line 3300 in install_kiosk_v 09.9.1.sh
################################################################################

# CONTEXT: These functions are called from configure_power_display_quiet()
# They replace the existing schedule configuration functions

################################################################################
### POWER SCHEDULE FUNCTION (COMPLETE)
################################################################################

configure_power_schedule() {
    echo
    echo " ══ POWER SCHEDULING ══"
    echo
    
    # Check if RTC is available
    local rtc_available=false
    if [[ -w /sys/class/rtc/rtc0/wakealarm ]] || sudo test -w /sys/class/rtc/rtc0/wakealarm 2>/dev/null; then
        rtc_available=true
        echo "✓ RTC wake capability detected"
    else
        echo "⚠ RTC wake not available (shutdown only, no auto-wake)"
    fi
    echo
    
    read -r -p "Shutdown time (HH:MM) [22:00]: " shutdown_time
    shutdown_time="${shutdown_time:-22:00}"
    
    if $rtc_available; then
        read -r -p "Wake time (HH:MM) [06:00]: " wake_time
        wake_time="${wake_time:-06:00}"
    else
        wake_time=""
    fi
    
    # Remove any existing power schedule files
    sudo systemctl stop kiosk-shutdown.timer 2>/dev/null || true
    sudo systemctl disable kiosk-shutdown.timer 2>/dev/null || true
    sudo rm -f /etc/systemd/system/kiosk-shutdown.{service,timer}
    sudo rm -f /usr/local/bin/kiosk-power-off.sh
    sudo rm -f /usr/local/bin/rtc-wake.sh
    sudo rm -f /etc/cron.d/kiosk-rtc-wake
    
    # Create shutdown script
    sudo tee /usr/local/bin/kiosk-power-off.sh > /dev/null <<'EOF'
#!/bin/bash
logger "KIOSK: Scheduled shutdown initiated"
systemctl poweroff
EOF
    sudo chmod +x /usr/local/bin/kiosk-power-off.sh
    
    # Create shutdown service
    sudo tee /etc/systemd/system/kiosk-shutdown.service > /dev/null <<'EOF'
[Unit]
Description=Kiosk Scheduled Shutdown

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiosk-power-off.sh
EOF
    
    # Create shutdown timer
    sudo tee /etc/systemd/system/kiosk-shutdown.timer > /dev/null <<EOF
[Unit]
Description=Kiosk Shutdown Timer

[Timer]
OnCalendar=*-*-* ${shutdown_time}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Create RTC wake script if available
    if $rtc_available && [[ -n "$wake_time" ]]; then
        sudo tee /usr/local/bin/rtc-wake.sh > /dev/null <<'RTCSCRIPT'
#!/bin/bash
WAKE_TIME="$1"
CURRENT=$(date +%s)
WAKE=$(date -d "$WAKE_TIME" +%s)

# If wake time is earlier than current time, schedule for tomorrow
[[ $WAKE -le $CURRENT ]] && WAKE=$(date -d "tomorrow $WAKE_TIME" +%s)

# Clear existing alarm
echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true

# Set new alarm
if echo $WAKE > /sys/class/rtc/rtc0/wakealarm 2>/dev/null; then
    logger "KIOSK: RTC wake set for $(date -d @$WAKE '+%Y-%m-%d %H:%M:%S')"
    echo "RTC wake set for $(date -d @$WAKE '+%Y-%m-%d %H:%M:%S')"
else
    logger "KIOSK: ERROR - Failed to set RTC wake"
    echo "ERROR: Failed to set RTC wake"
    exit 1
fi
RTCSCRIPT
        sudo chmod +x /usr/local/bin/rtc-wake.sh
        
        # Create cron job to set RTC wake 5 minutes before shutdown
        local shutdown_hour="${shutdown_time%%:*}"
        local shutdown_min="${shutdown_time##*:}"
        local wake_min=$((10#$shutdown_min - 5))
        local wake_hour=$((10#$shutdown_hour))
        
        # Handle negative minutes
        if [[ $wake_min -lt 0 ]]; then
            wake_min=$((wake_min + 60))
            wake_hour=$((wake_hour - 1))
        fi
        
        # Handle negative hour (before midnight)
        if [[ $wake_hour -lt 0 ]]; then
            wake_hour=$((wake_hour + 24))
        fi
        
        sudo tee /etc/cron.d/kiosk-rtc-wake > /dev/null <<EOF
# Set RTC wake alarm 5 minutes before shutdown
$wake_min $wake_hour * * * root /usr/local/bin/rtc-wake.sh "$wake_time" >> /var/log/kiosk-rtc.log 2>&1
EOF
        
        log_info "RTC wake cron job created"
    fi
    
    # Reload systemd and enable timer
    sudo systemctl daemon-reload
    sudo systemctl enable kiosk-shutdown.timer
    sudo systemctl start kiosk-shutdown.timer
    
    echo
    log_success "Power schedule configured"
    echo "  Shutdown: $shutdown_time daily"
    if $rtc_available && [[ -n "$wake_time" ]]; then
        echo "  Wake: $wake_time daily"
    fi
    
    # Show next activation
    echo
    echo "Next scheduled shutdown:"
    systemctl list-timers kiosk-shutdown.timer --no-pager | grep kiosk-shutdown || echo "  (checking...)"
    
    # Test RTC wake if configured
    if $rtc_available && [[ -n "$wake_time" ]]; then
        echo
        read -r -p "Test RTC wake setup now? (y/n): " test_rtc
        if [[ "$test_rtc" =~ ^[Yy]$ ]]; then
            echo "Testing RTC wake for $wake_time..."
            sudo /usr/local/bin/rtc-wake.sh "$wake_time"
            echo "Check: cat /sys/class/rtc/rtc0/wakealarm"
            cat /sys/class/rtc/rtc0/wakealarm 2>/dev/null && echo "✓ RTC wake is set" || echo "✗ RTC wake failed"
        fi
    fi
    
    pause
}

################################################################################
### DISPLAY SCHEDULE FUNCTION (COMPLETE)
################################################################################

configure_display_schedule() {
    echo
    echo " ══ DISPLAY SCHEDULING ══"
    echo
    
    # Check if power schedule exists
    if systemctl is-enabled kiosk-shutdown.timer &>/dev/null 2>&1; then
        local ptime=$(systemctl cat kiosk-shutdown.timer 2>/dev/null | grep "^OnCalendar=" | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        echo "⚠ Power shutdown configured at $ptime"
        echo "  Display will already be off when system shuts down"
        echo
    fi
    
    read -r -p "Display OFF time (HH:MM) [22:00]: " doff
    doff="${doff:-22:00}"
    read -r -p "Display ON time (HH:MM) [06:00]: " don
    don="${don:-06:00}"
    
    # Get kiosk user ID for DBUS
    local kiosk_uid=$(id -u "$KIOSK_USER")
    
    # Remove any existing display schedule files
    sudo systemctl stop kiosk-display-{on,off}.timer 2>/dev/null || true
    sudo systemctl disable kiosk-display-{on,off}.timer 2>/dev/null || true
    sudo rm -f /etc/systemd/system/kiosk-display-{on,off}.{service,timer}
    sudo rm -f /usr/local/bin/kiosk-display-{on,off}.sh
    
    # Create display-off script with multiple methods
    sudo tee /usr/local/bin/kiosk-display-off.sh > /dev/null <<EOF
#!/bin/bash
# Turn off display using multiple methods for reliability

# Method 1: xset via kiosk user
sudo -u $KIOSK_USER DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$kiosk_uid/bus xset dpms force off 2>/dev/null && echo "✓ xset dpms off" || echo "✗ xset failed"

# Method 2: vbetool (if available)
if command -v vbetool &>/dev/null; then
    vbetool dpms off 2>/dev/null && echo "✓ vbetool off" || echo "✗ vbetool failed"
fi

# Method 3: Backlight control (laptops)
if [[ -d /sys/class/backlight ]]; then
    for bl in /sys/class/backlight/*/brightness; do
        if [[ -w "\$bl" ]]; then
            echo 0 > "\$bl" 2>/dev/null && echo "✓ backlight off: \$bl" || echo "✗ backlight failed"
        fi
    done
fi

logger "KIOSK: Display turned OFF (scheduled)"
EOF
    sudo chmod +x /usr/local/bin/kiosk-display-off.sh
    
    # Create display-on script with multiple methods
    sudo tee /usr/local/bin/kiosk-display-on.sh > /dev/null <<EOF
#!/bin/bash
# Turn on display using multiple methods for reliability

# Method 1: xset via kiosk user
sudo -u $KIOSK_USER DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$kiosk_uid/bus xset dpms force on 2>/dev/null && echo "✓ xset dpms on" || echo "✗ xset failed"

# Method 2: vbetool (if available)
if command -v vbetool &>/dev/null; then
    vbetool dpms on 2>/dev/null && echo "✓ vbetool on" || echo "✗ vbetool failed"
fi

# Method 3: Backlight control (laptops)
if [[ -d /sys/class/backlight ]]; then
    for bl in /sys/class/backlight/*/brightness; do
        if [[ -w "\$bl" ]]; then
            cat "\${bl%/*}/max_brightness" > "\$bl" 2>/dev/null && echo "✓ backlight on: \$bl" || echo "✗ backlight failed"
        fi
    done
fi

# Method 4: Wake up input (move mouse)
sudo -u $KIOSK_USER DISPLAY=:0 xdotool mousemove 1 1 2>/dev/null && echo "✓ mouse wiggle" || echo "✗ mouse wiggle failed"

# Method 5: Signal Electron app to require password if enabled
sudo -u $KIOSK_USER touch /home/$KIOSK_USER/kiosk-app/.display-wake 2>/dev/null && echo "✓ password flag set" || echo "✗ password flag failed"

logger "KIOSK: Display turned ON (scheduled)"
EOF
    sudo chmod +x /usr/local/bin/kiosk-display-on.sh
    
    # Create systemd services
    sudo tee /etc/systemd/system/kiosk-display-off.service > /dev/null <<'EOF'
[Unit]
Description=Kiosk Display Off

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiosk-display-off.sh
StandardOutput=journal
StandardError=journal
EOF
    
    sudo tee /etc/systemd/system/kiosk-display-on.service > /dev/null <<'EOF'
[Unit]
Description=Kiosk Display On

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiosk-display-on.sh
StandardOutput=journal
StandardError=journal
EOF
    
    # Create timers
    sudo tee /etc/systemd/system/kiosk-display-off.timer > /dev/null <<EOF
[Unit]
Description=Kiosk Display Off Timer

[Timer]
OnCalendar=*-*-* ${doff}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    sudo tee /etc/systemd/system/kiosk-display-on.timer > /dev/null <<EOF
[Unit]
Description=Kiosk Display On Timer

[Timer]
OnCalendar=*-*-* ${don}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload systemd and enable timers
    sudo systemctl daemon-reload
    sudo systemctl enable kiosk-display-off.timer kiosk-display-on.timer
    sudo systemctl start kiosk-display-off.timer kiosk-display-on.timer
    
    echo
    log_success "Display schedule configured"
    echo "  OFF: $doff daily"
    echo "  ON: $don daily"
    
    # Show next activations
    echo
    echo "Next scheduled display changes:"
    systemctl list-timers kiosk-display-* --no-pager | grep kiosk-display || echo "  (checking...)"
    
    # Offer to test now
    echo
    read -r -p "Test display control now? (y/n): " test_display
    if [[ "$test_display" =~ ^[Yy]$ ]]; then
        echo
        echo "Testing display OFF in 3 seconds..."
        sleep 3
        sudo /usr/local/bin/kiosk-display-off.sh
        echo
        echo "Waiting 5 seconds..."
        sleep 5
        echo "Testing display ON..."
        sudo /usr/local/bin/kiosk-display-on.sh
        echo
        echo "✓ Display test complete"
    fi
    
    pause
}

################################################################################
### QUIET HOURS FUNCTION (COMPLETE)
################################################################################

configure_quiet_hours() {
    echo
    echo " ══ QUIET HOURS ══"
    echo
    
    # Show existing schedules for context
    if systemctl is-enabled kiosk-shutdown.timer &>/dev/null 2>&1; then
        local ptime=$(systemctl cat kiosk-shutdown.timer 2>/dev/null | grep "^OnCalendar=" | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        echo "ℹ Power shutdown: $ptime"
    fi
    if systemctl is-enabled kiosk-display-off.timer &>/dev/null 2>&1; then
        local doff=$(systemctl cat kiosk-display-off.timer 2>/dev/null | grep "^OnCalendar=" | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        local don=$(systemctl cat kiosk-display-on.timer 2>/dev/null | grep "^OnCalendar=" | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//')
        echo "ℹ Display: OFF at $doff, ON at $don"
    fi
    echo
    
    read -r -p "Quiet hours start (HH:MM) [22:00]: " qstart
    qstart="${qstart:-22:00}"
    read -r -p "Quiet hours end (HH:MM) [07:00]: " qend
    qend="${qend:-07:00}"
    
    echo
    echo "What should be muted during quiet hours?"
    echo "  1. All audio (mute system)"
    echo "  2. Squeezelite only (stop music player)"
    echo "  3. Jitsi PTT only (stop intercom)"
    read -r -p "Choice [1]: " qmode
    qmode="${qmode:-1}"
    
    # Remove any existing quiet hours files
    sudo systemctl stop kiosk-quiet-{start,end}.timer 2>/dev/null || true
    sudo systemctl disable kiosk-quiet-{start,end}.timer 2>/dev/null || true
    sudo rm -f /etc/systemd/system/kiosk-quiet-{start,end}.{service,timer}
    sudo rm -f /usr/local/bin/kiosk-quiet-{start,end}.sh
    
    # Create quiet start/end scripts based on mode
    case "$qmode" in
        1)
            # Mute all audio
            sudo tee /usr/local/bin/kiosk-quiet-start.sh > /dev/null <<'EOF'
#!/bin/bash
# Save current volume before muting
pactl get-sink-volume @DEFAULT_SINK@ | grep -oE '[0-9]+%' | head -1 | tr -d '%' > /tmp/kiosk-vol-backup 2>/dev/null || echo "100" > /tmp/kiosk-vol-backup
pactl set-sink-mute @DEFAULT_SINK@ 1 2>/dev/null
logger "KIOSK: Quiet hours started - all audio muted"
echo "✓ Quiet hours: All audio muted"
EOF
            sudo tee /usr/local/bin/kiosk-quiet-end.sh > /dev/null <<'EOF'
#!/bin/bash
# Restore previous volume
VOL=$(cat /tmp/kiosk-vol-backup 2>/dev/null || echo "100")
pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null
pactl set-sink-volume @DEFAULT_SINK@ ${VOL}% 2>/dev/null
logger "KIOSK: Quiet hours ended - audio restored to ${VOL}%"
echo "✓ Quiet hours ended: Audio restored to ${VOL}%"
EOF
            ;;
        2)
            # Stop Squeezelite only
            sudo tee /usr/local/bin/kiosk-quiet-start.sh > /dev/null <<'EOF'
#!/bin/bash
systemctl stop squeezelite 2>/dev/null
logger "KIOSK: Quiet hours started - Squeezelite stopped"
echo "✓ Quiet hours: Squeezelite stopped"
EOF
            sudo tee /usr/local/bin/kiosk-quiet-end.sh > /dev/null <<'EOF'
#!/bin/bash
systemctl start squeezelite 2>/dev/null
logger "KIOSK: Quiet hours ended - Squeezelite started"
echo "✓ Quiet hours ended: Squeezelite started"
EOF
            ;;
        3)
            # Stop Jitsi PTT only
            sudo tee /usr/local/bin/kiosk-quiet-start.sh > /dev/null <<'EOF'
#!/bin/bash
systemctl stop jitsi-ptt 2>/dev/null
logger "KIOSK: Quiet hours started - Jitsi PTT stopped"
echo "✓ Quiet hours: Jitsi PTT stopped"
EOF
            sudo tee /usr/local/bin/kiosk-quiet-end.sh > /dev/null <<'EOF'
#!/bin/bash
systemctl start jitsi-ptt 2>/dev/null
logger "KIOSK: Quiet hours ended - Jitsi PTT started"
echo "✓ Quiet hours ended: Jitsi PTT started"
EOF
            ;;
    esac
    
    sudo chmod +x /usr/local/bin/kiosk-quiet-{start,end}.sh
    
    # Create systemd services
    sudo tee /etc/systemd/system/kiosk-quiet-start.service > /dev/null <<'EOF'
[Unit]
Description=Kiosk Quiet Hours Start

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiosk-quiet-start.sh
StandardOutput=journal
StandardError=journal
EOF
    
    sudo tee /etc/systemd/system/kiosk-quiet-end.service > /dev/null <<'EOF'
[Unit]
Description=Kiosk Quiet Hours End

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiosk-quiet-end.sh
StandardOutput=journal
StandardError=journal
EOF
    
    # Create timers
    sudo tee /etc/systemd/system/kiosk-quiet-start.timer > /dev/null <<EOF
[Unit]
Description=Kiosk Quiet Hours Start Timer

[Timer]
OnCalendar=*-*-* ${qstart}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    sudo tee /etc/systemd/system/kiosk-quiet-end.timer > /dev/null <<EOF
[Unit]
Description=Kiosk Quiet Hours End Timer

[Timer]
OnCalendar=*-*-* ${qend}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload systemd and enable timers
    sudo systemctl daemon-reload
    sudo systemctl enable kiosk-quiet-start.timer kiosk-quiet-end.timer
    sudo systemctl start kiosk-quiet-start.timer kiosk-quiet-end.timer
    
    echo
    log_success "Quiet hours configured"
    echo "  Start: $qstart daily"
    echo "  End: $qend daily"
    echo "  Mode: $(case $qmode in 1) echo 'All audio muted';; 2) echo 'Squeezelite stopped';; 3) echo 'Jitsi PTT stopped';; esac)"
    
    # Show next activations
    echo
    echo "Next scheduled quiet hours:"
    systemctl list-timers kiosk-quiet-* --no-pager | grep kiosk-quiet || echo "  (checking...)"
    
    # Offer to test now
    echo
    read -r -p "Test quiet hours now? (y/n): " test_quiet
    if [[ "$test_quiet" =~ ^[Yy]$ ]]; then
        echo
        echo "Testing quiet START..."
        sudo /usr/local/bin/kiosk-quiet-start.sh
        echo
        echo "Waiting 5 seconds..."
        sleep 5
        echo "Testing quiet END..."
        sudo /usr/local/bin/kiosk-quiet-end.sh
        echo
        echo "✓ Quiet hours test complete"
    fi
    
    pause
}

################################################################################
### ELECTRON RELOAD FUNCTION (COMPLETE)
################################################################################

configure_electron_reload() {
    echo
    echo " ══ ELECTRON RELOAD SCHEDULE ══"
    echo
    echo "Automatically reload Electron to prevent memory leaks."
    echo "Squeezelite music continues playing during reload."
    echo
    
    # Check if already configured
    if systemctl is-enabled kiosk-electron-reload.timer &>/dev/null 2>&1; then
        local reload_cal=$(systemctl cat kiosk-electron-reload.timer 2>/dev/null | grep "^OnCalendar=" | cut -d'=' -f2)
        local reload_time=$(echo "$reload_cal" | sed 's/\*-\*-\* //' | sed 's/:00$//')
        echo "Status: ✓ Enabled"
        echo "Schedule: $reload_cal"
        echo
        echo "Options:"
        echo "  1. Keep current schedule"
        echo "  2. Change schedule"
        echo "  3. Disable automatic reload"
        echo "  0. Return"
    else
        echo "Status: ✗ Not configured"
        echo
        echo "Options:"
        echo "  1. Daily at 3am"
        echo "  2. Every 3 days at 3am"
        echo "  3. Custom schedule"
        echo "  0. Return"
    fi
    echo
    read -r -p "Choose [0-3]: " choice
    
    case "$choice" in
        0) return ;;
        1)
            if systemctl is-enabled kiosk-electron-reload.timer &>/dev/null 2>&1; then
                echo "Keeping current schedule"
                pause
                return
            else
                setup_electron_reload_timer "*-*-* 03:00:00" "Daily at 3am"
            fi
            ;;
        2)
            if systemctl is-enabled kiosk-electron-reload.timer &>/dev/null 2>&1; then
                custom_electron_reload_schedule
            else
                setup_electron_reload_timer "*-*-1,4,7,10,13,16,19,22,25,28,31 03:00:00" "Every 3 days at 3am"
            fi
            ;;
        3)
            if systemctl is-enabled kiosk-electron-reload.timer &>/dev/null 2>&1; then
                disable_electron_reload_timer
            else
                custom_electron_reload_schedule
            fi
            ;;
    esac
    pause
}

setup_electron_reload_timer() {
    local schedule="$1"
    local description="$2"
    
    # Remove existing files
    sudo systemctl stop kiosk-electron-reload.timer 2>/dev/null || true
    sudo systemctl disable kiosk-electron-reload.timer 2>/dev/null || true
    sudo rm -f /etc/systemd/system/kiosk-electron-reload.{service,timer}
    sudo rm -f /usr/local/bin/kiosk-reload-electron
    
    # Create reload script
    sudo tee /usr/local/bin/kiosk-reload-electron > /dev/null <<'RELOADSCRIPT'
#!/bin/bash
logger "KIOSK: Scheduled Electron reload"
systemctl restart lightdm
RELOADSCRIPT
    sudo chmod +x /usr/local/bin/kiosk-reload-electron
    
    # Create service
    sudo tee /etc/systemd/system/kiosk-electron-reload.service > /dev/null <<'RELOADSVC'
[Unit]
Description=Reload Electron App

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kiosk-reload-electron
RELOADSVC
    
    # Create timer
    sudo tee /etc/systemd/system/kiosk-electron-reload.timer > /dev/null <<EOF
[Unit]
Description=Electron Reload Timer

[Timer]
OnCalendar=$schedule
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start
    sudo systemctl daemon-reload
    sudo systemctl enable kiosk-electron-reload.timer
    sudo systemctl start kiosk-electron-reload.timer
    
    echo
    log_success "Electron reload configured: $description"
    echo "  Schedule: $schedule"
    echo
    echo "Next scheduled reload:"
    systemctl list-timers kiosk-electron-reload.timer --no-pager | grep kiosk-electron || echo "  (checking...)"
}

custom_electron_reload_schedule() {
    echo
    echo "Custom Schedule Options:"
    echo "  1. Every X days at specific time"
    echo "  2. Daily at custom time"
    echo "  3. Specific weekday"
    echo "  0. Cancel"
    echo
    read -r -p "Choose [0-3]: " custom_choice
    
    local schedule=""
    local description=""
    
    case "$custom_choice" in
        1)
            read -r -p "Reload every X days [3]: " days
            days="${days:-3}"
            read -r -p "Time (HH:MM) [03:00]: " time
            time="${time:-03:00}"
            
            # Generate day list
            local day_list=""
            for ((d=1; d<=31; d+=days)); do
                day_list="${day_list}${d},"
            done
            day_list="${day_list%,}"
            
            schedule="*-*-${day_list} ${time}:00"
            description="Every $days days at $time"
            ;;
        2)
            read -r -p "Time (HH:MM) [03:00]: " time
            time="${time:-03:00}"
            schedule="*-*-* ${time}:00"
            description="Daily at $time"
            ;;
        3)
            echo "Days: Mon Tue Wed Thu Fri Sat Sun"
            read -r -p "Enter day: " day
            read -r -p "Time (HH:MM) [03:00]: " time
            time="${time:-03:00}"
            schedule="${day} *-*-* ${time}:00"
            description="Every $day at $time"
            ;;
        0) return ;;
        *) 
            log_error "Invalid choice"
            return
            ;;
    esac
    
    if [[ -n "$schedule" ]]; then
        setup_electron_reload_timer "$schedule" "$description"
    fi
}

disable_electron_reload_timer() {
    echo
    read -r -p "Disable automatic Electron reload? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo systemctl stop kiosk-electron-reload.timer 2>/dev/null || true
        sudo systemctl disable kiosk-electron-reload.timer 2>/dev/null || true
        sudo rm -f /etc/systemd/system/kiosk-electron-reload.{service,timer}
        sudo rm -f /usr/local/bin/kiosk-reload-electron
        sudo systemctl daemon-reload
        log_success "Automatic Electron reload disabled"
    fi
}

################################################################################
### END OF SCHEDULE FUNCTIONS
################################################################################

# CONTEXT: These functions are called from the menu system
# They should be inserted BEFORE the configure_power_display_quiet() function
# and AFTER the show_schedule_status() function

test_display_control() {
    echo
    echo " ═══ TEST DISPLAY CONTROL ═══"
    echo
    echo "This will test turning the display off and on."
    echo
    read -r -p "Test now? (y/n): " do_test
    [[ ! "$do_test" =~ ^[Yy]$ ]] && return
    
    echo
    echo "Testing display OFF in 3 seconds..."
    sleep 3
    
    if [[ -f /usr/local/bin/kiosk-display-off.sh ]]; then
        sudo /usr/local/bin/kiosk-display-off.sh
        echo "Display should be OFF"
    else
        # Fallback if script doesn't exist yet
        local kiosk_uid=$(id -u "$KIOSK_USER")
        sudo -u "$KIOSK_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$kiosk_uid/bus xset dpms force off
        echo "Display turned OFF (xset method)"
    fi
    
    echo
    echo "Waiting 5 seconds..."
    sleep 5
    
    echo "Testing display ON..."
    if [[ -f /usr/local/bin/kiosk-display-on.sh ]]; then
        sudo /usr/local/bin/kiosk-display-on.sh
        echo "Display should be ON"
    else
        # Fallback
        local kiosk_uid=$(id -u "$KIOSK_USER")
        sudo -u "$KIOSK_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$kiosk_uid/bus xset dpms force on
        echo "Display turned ON (xset method)"
    fi
    
    echo
    if systemctl is-enabled kiosk-display-off.timer &>/dev/null 2>&1; then
        echo "✓ Display timers are configured"
        echo
        echo "Schedule status:"
        systemctl list-timers kiosk-display-* --all --no-pager 2>/dev/null
    else
        echo "⚠ Display timers not configured yet"
        echo "  Use option 2 to configure them"
    fi
    
    pause
}

remove_all_schedules() {
    echo
    echo "Removing all schedules..."
    
    # Stop timers
    sudo systemctl stop kiosk-shutdown.timer 2>/dev/null || true
    sudo systemctl stop kiosk-display-off.timer 2>/dev/null || true
    sudo systemctl stop kiosk-display-on.timer 2>/dev/null || true
    sudo systemctl stop kiosk-quiet-start.timer 2>/dev/null || true
    sudo systemctl stop kiosk-quiet-end.timer 2>/dev/null || true
    sudo systemctl stop kiosk-electron-reload.timer 2>/dev/null || true
    
    # Disable timers
    sudo systemctl disable kiosk-shutdown.timer 2>/dev/null || true
    sudo systemctl disable kiosk-display-off.timer 2>/dev/null || true
    sudo systemctl disable kiosk-display-on.timer 2>/dev/null || true
    sudo systemctl disable kiosk-quiet-start.timer 2>/dev/null || true
    sudo systemctl disable kiosk-quiet-end.timer 2>/dev/null || true
    sudo systemctl disable kiosk-electron-reload.timer 2>/dev/null || true
    
    # Remove files
    sudo rm -f /etc/systemd/system/kiosk-shutdown.{service,timer}
    sudo rm -f /etc/systemd/system/kiosk-display-*.{service,timer}
    sudo rm -f /etc/systemd/system/kiosk-quiet-*.{service,timer}
    sudo rm -f /etc/systemd/system/kiosk-electron-reload.{service,timer}
    sudo rm -f /usr/local/bin/kiosk-power-off.sh
    sudo rm -f /usr/local/bin/kiosk-display-off.sh
    sudo rm -f /usr/local/bin/kiosk-display-on.sh
    sudo rm -f /usr/local/bin/kiosk-quiet-*.sh
    sudo rm -f /usr/local/bin/rtc-wake.sh
    sudo rm -f /usr/local/bin/kiosk-reload-electron
    sudo rm -f /etc/cron.d/kiosk-rtc-wake
    
    sudo systemctl daemon-reload
    
    log_success "All schedules removed"
    pause
}
###############################################################################
### testing submenu
###############################################################################
show_testing_menu() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════"
        echo "   SCHEDULE & SYSTEM TESTING                                 "
        echo "════════════════════════════════════════════════════════════"
        echo
        
        echo "Available Tests:"
        echo "  1. Display Control (on/off test)"
        echo "  2. Quiet Hours (mute/unmute test)"
        echo "  3. Power Schedule (show next shutdown time)"
        echo "  4. Audio System Test"
        echo "  5. Network Test"
        echo "  6. Keyboard Test"
        echo "  7. Run All Tests"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-7]: " choice
        
        case "$choice" in
            1) test_display_control ;;
            2) test_quiet_hours ;;
            3) test_power_schedule ;;
            4) audio_test ;;
            5) network_test ;;
            6) test_keyboard ;;
            7) run_all_tests ;;
            0) return ;;
        esac
    done
}

test_quiet_hours() {
    echo
    echo " ═══ QUIET HOURS TEST ═══"
    echo
    
    if ! systemctl is-enabled kiosk-quiet-start.timer &>/dev/null; then
        echo "❌ Quiet hours not configured"
        pause
        return
    fi
    
    echo "Testing quiet hours mute/unmute..."
    echo
    
    echo "1. Getting current volume..."
    local current_vol=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oE '[0-9]+%' | head -1 | tr -d '%')
    echo "   Current: ${current_vol}%"
    
    echo
    echo "2. Testing MUTE (quiet start)..."
    sudo /usr/local/bin/kiosk-quiet-start.sh
    sleep 2
    local muted=$(pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes" && echo "✓ MUTED" || echo "✗ NOT MUTED")
    echo "   Result: $muted"
    
    echo
    echo "3. Testing UNMUTE (quiet end)..."
    sudo /usr/local/bin/kiosk-quiet-end.sh
    sleep 2
    local unmuted=$(pactl get-sink-mute @DEFAULT_SINK@ | grep -q "no" && echo "✓ UNMUTED" || echo "✗ STILL MUTED")
    echo "   Result: $unmuted"
    
    echo
    echo "✓ Quiet hours test complete"
    echo
    systemctl list-timers kiosk-quiet-* --all --no-pager
    
    pause
}

test_power_schedule() {
    echo
    echo " ═══ POWER SCHEDULE TEST ═══"
    echo
    
    if ! systemctl is-enabled kiosk-shutdown.timer &>/dev/null; then
        echo "❌ Power schedule not configured"
        pause
        return
    fi
    
    echo "Power schedule status:"
    echo
    systemctl list-timers kiosk-shutdown.timer --all --no-pager
    
    echo
    echo "⚠️  Note: Cannot test actual shutdown without shutting down!"
    echo "    To manually test: sudo systemctl start kiosk-shutdown.service"
    echo
    
    if [[ -f /usr/local/bin/rtc-wake.sh ]]; then
        echo "RTC wake script exists ✓"
        local wake_config=$(grep -h "rtc-wake" /etc/cron.d/kiosk-rtc-wake 2>/dev/null)
        if [[ -n "$wake_config" ]]; then
            echo "Wake schedule: $wake_config"
        fi
    else
        echo "No RTC wake configured"
    fi
    
    pause
}

test_keyboard() {
    echo
    echo " ═══ KEYBOARD TEST ═══"
    echo
    echo "Testing keyboard visibility and function..."
    echo
    echo "Please perform these tests on the kiosk display:"
    echo
    echo "  1. 2-finger swipe DOWN → keyboard should appear"
    echo "  2. Type some characters"
    echo "  3. 2-finger swipe DOWN again → keyboard should close"
    echo "  4. Tap a text field → keyboard should auto-appear"
    echo "  5. Click keyboard X button → keyboard should close"
    echo
    echo "Check electron log for keyboard events:"
    echo "  sudo tail -f /home/kiosk/electron.log | grep -i keyboard"
    echo
    
    pause
}

run_all_tests() {
    echo
    echo " ═══ RUNNING ALL TESTS ═══"
    echo
    
    echo "Test 1/5: Display Control"
    test_display_control
    
    echo
    echo "Test 2/5: Quiet Hours"
    test_quiet_hours
    
    echo
    echo "Test 3/5: Power Schedule"
    test_power_schedule
    
    echo
    echo "Test 4/5: Audio"
    audio_test
    
    echo
    echo "Test 5/5: Network"
    network_test
    
    echo
    echo "✓ All tests complete!"
    pause
}

################################################################################
### SECTION 6: CONFIG SAVE/LOAD
################################################################################

load_config() {
    if ! sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        return 1
    fi
    
    local loaded_autoswitch=$(sudo -u "$KIOSK_USER" jq -r '.autoswitch' "$CONFIG_PATH" 2>/dev/null)
    AUTOSWITCH="$loaded_autoswitch"
    
    local loaded_swipe=$(sudo -u "$KIOSK_USER" jq -r '.swipeMode' "$CONFIG_PATH" 2>/dev/null)
    SWIPE_MODE="$loaded_swipe"
    
    local loaded_nav=$(sudo -u "$KIOSK_USER" jq -r '.allowNavigation' "$CONFIG_PATH" 2>/dev/null)
    ALLOW_NAVIGATION="$loaded_nav"
    
    HOME_TAB_INDEX=$(sudo -u "$KIOSK_USER" jq -r '.homeTabIndex // -1' "$CONFIG_PATH" 2>/dev/null)
    INACTIVITY_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.inactivityTimeout // 120' "$CONFIG_PATH" 2>/dev/null)

    # Load new optional features
    local loaded_pause=$(sudo -u "$KIOSK_USER" jq -r '.enablePauseButton // true' "$CONFIG_PATH" 2>/dev/null)
    [[ "$loaded_pause" == "true" ]] && ENABLE_PAUSE_BUTTON="true" || ENABLE_PAUSE_BUTTON="false"

    local loaded_keyboard=$(sudo -u "$KIOSK_USER" jq -r '.enableKeyboardButton // true' "$CONFIG_PATH" 2>/dev/null)
    [[ "$loaded_keyboard" == "true" ]] && ENABLE_KEYBOARD_BUTTON="true" || ENABLE_KEYBOARD_BUTTON="false"

    local loaded_password=$(sudo -u "$KIOSK_USER" jq -r '.enablePasswordProtection // false' "$CONFIG_PATH" 2>/dev/null)
    [[ "$loaded_password" == "true" ]] && ENABLE_PASSWORD_PROTECTION="true" || ENABLE_PASSWORD_PROTECTION="false"

    LOCKOUT_PASSWORD=$(sudo -u "$KIOSK_USER" jq -r '.lockoutPassword // ""' "$CONFIG_PATH" 2>/dev/null)
    LOCKOUT_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.lockoutTimeout // 0' "$CONFIG_PATH" 2>/dev/null)
    LOCKOUT_AT_TIME=$(sudo -u "$KIOSK_USER" jq -r '.lockoutAtTime // ""' "$CONFIG_PATH" 2>/dev/null)
    LOCKOUT_ACTIVE_START=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveStart // ""' "$CONFIG_PATH" 2>/dev/null)
    LOCKOUT_ACTIVE_END=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveEnd // ""' "$CONFIG_PATH" 2>/dev/null)

    local loaded_boot_password=$(sudo -u "$KIOSK_USER" jq -r '.requirePasswordOnBoot // false' "$CONFIG_PATH" 2>/dev/null)
    [[ "$loaded_boot_password" == "true" ]] && REQUIRE_PASSWORD_ON_BOOT="true" || REQUIRE_PASSWORD_ON_BOOT="false"

    local tab_count=$(sudo -u "$KIOSK_USER" jq -r '.tabs | length' "$CONFIG_PATH" 2>/dev/null || echo "0")
    URLS=()
    DURS=()
    USERS=()
    PASSES=()
    
    for ((i=0; i<tab_count; i++)); do
        URLS+=($(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].url" "$CONFIG_PATH"))
        DURS+=($(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].duration" "$CONFIG_PATH"))
        USERS+=($(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].username // empty" "$CONFIG_PATH"))
        PASSES+=($(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].password // empty" "$CONFIG_PATH"))
    done
    
    return 0
}

save_config() {
    if ! kiosk_user_exists; then
        log_error "Kiosk user doesn't exist - run full install first"
        return 1
    fi
    
    sudo mkdir -p "$KIOSK_DIR"
    sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"
    
    local tmp=$(mktemp)
    
    # Auto-rotation is now automatic based on site durations
    # Always enable if any site has duration > 0
    local auto_json="true"
    
    local dual_json="false"
    [[ "$SWIPE_MODE" == "dual" ]] && dual_json="true"

    local pause_btn_json="true"
    [[ "$ENABLE_PAUSE_BUTTON" == "false" ]] && pause_btn_json="false"

    local keyboard_btn_json="true"
    [[ "$ENABLE_KEYBOARD_BUTTON" == "false" ]] && keyboard_btn_json="false"

    local password_json="false"
    [[ "$ENABLE_PASSWORD_PROTECTION" == "true" ]] && password_json="true"

    local boot_password_json="false"
    [[ "$REQUIRE_PASSWORD_ON_BOOT" == "true" ]] && boot_password_json="true"

    jq -n \
      --arg unit "s" \
      --argjson autoswitch "$auto_json" \
      --argjson enableTouch true \
      --argjson dualSwipe "$dual_json" \
      --arg swipeMode "$SWIPE_MODE" \
      --arg allowNavigation "$ALLOW_NAVIGATION" \
      --argjson homeTabIndex "${HOME_TAB_INDEX:--1}" \
      --argjson inactivityTimeout "${INACTIVITY_TIMEOUT:-120}" \
      --argjson enablePauseButton "$pause_btn_json" \
      --argjson enableKeyboardButton "$keyboard_btn_json" \
      --argjson enablePasswordProtection "$password_json" \
      --arg lockoutPassword "${LOCKOUT_PASSWORD:-}" \
      --argjson lockoutTimeout "${LOCKOUT_TIMEOUT:-0}" \
      --arg lockoutAtTime "${LOCKOUT_AT_TIME:-}" \
      --arg lockoutActiveStart "${LOCKOUT_ACTIVE_START:-}" \
      --arg lockoutActiveEnd "${LOCKOUT_ACTIVE_END:-}" \
      --argjson requirePasswordOnBoot "$boot_password_json" \
      '{unit:$unit,autoswitch:$autoswitch,enableTouch:$enableTouch,dualSwipe:$dualSwipe,swipeMode:$swipeMode,allowNavigation:$allowNavigation,homeTabIndex:$homeTabIndex,inactivityTimeout:$inactivityTimeout,enablePauseButton:$enablePauseButton,enableKeyboardButton:$enableKeyboardButton,enablePasswordProtection:$enablePasswordProtection,lockoutPassword:$lockoutPassword,lockoutTimeout:$lockoutTimeout,lockoutAtTime:$lockoutAtTime,lockoutActiveStart:$lockoutActiveStart,lockoutActiveEnd:$lockoutActiveEnd,requirePasswordOnBoot:$requirePasswordOnBoot,tabs:[]}' > "$tmp"
    
    if [[ ${#URLS[@]} -gt 0 ]]; then
        for idx in "${!URLS[@]}"; do
            local url="${URLS[$idx]:-}"
            local dur="${DURS[$idx]:-0}"
            local user="${USERS[$idx]:-}"
            local pass="${PASSES[$idx]:-}"
            
            # NOTE: No autoRotate field - duration controls rotation
            jq --arg u "$url" \
               --argjson d "$dur" \
               --arg user "$user" \
               --arg pass "$pass" \
               '.tabs += [{"url":$u,"duration":$d,"username":$user,"password":$pass}]' \
               "$tmp" > "${tmp}.new"
            mv -f "${tmp}.new" "$tmp"
        done
    fi
    
    sudo -u "$KIOSK_USER" bash -c "cat > '$CONFIG_PATH'" < "$tmp"
    sudo -u "$KIOSK_USER" chmod 644 "$CONFIG_PATH"
    
    rm -f "$tmp"
    
    log_success "Configuration saved"
    
    if is_service_active lightdm; then
        echo
        echo "Configuration saved. Changes take effect after reload."
        read -r -p "Reload kiosk now? (y/n): " do_reload
        if [[ ! "$do_reload" =~ ^[Nn]$ ]]; then
            echo "Reloading kiosk..."
            sudo systemctl restart lightdm
            sleep 2
            log_success "Kiosk reloaded"
        else
            log_warning "Remember to reload: sudo systemctl restart lightdm"
        fi
    fi
}

load_existing_config() {
    # Load all existing configuration from config.json into bash variables
    # This MUST be called before any menu that calls save_config
    # Otherwise settings will be lost!

    if ! sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        # No existing config, use defaults
        return 0
    fi

    # Load sites/tabs
    URLS=()
    DURS=()
    USERS=()
    PASSES=()

    local tab_count=$(sudo -u "$KIOSK_USER" jq -r '.tabs | length' "$CONFIG_PATH" 2>/dev/null || echo "0")
    if [[ "$tab_count" -gt 0 ]]; then
        for ((i=0; i<tab_count; i++)); do
            URLS+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].url" "$CONFIG_PATH")")
            DURS+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].duration" "$CONFIG_PATH")")
            USERS+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].username // empty" "$CONFIG_PATH")")
            PASSES+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].password // empty" "$CONFIG_PATH")")
        done
    fi

    # Load general settings
    HOME_TAB_INDEX=$(sudo -u "$KIOSK_USER" jq -r '.homeTabIndex // -1' "$CONFIG_PATH" 2>/dev/null || echo "-1")
    INACTIVITY_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.inactivityTimeout // 120' "$CONFIG_PATH" 2>/dev/null || echo "120")
    ALLOW_NAVIGATION=$(sudo -u "$KIOSK_USER" jq -r '.allowNavigation // "same-origin"' "$CONFIG_PATH" 2>/dev/null || echo "same-origin")
    SWIPE_MODE=$(sudo -u "$KIOSK_USER" jq -r '.swipeMode // "horizontal"' "$CONFIG_PATH" 2>/dev/null || echo "horizontal")

    # Load optional features
    local pause_btn=$(sudo -u "$KIOSK_USER" jq -r '.enablePauseButton // true' "$CONFIG_PATH" 2>/dev/null)
    [[ "$pause_btn" == "true" ]] && ENABLE_PAUSE_BUTTON="true" || ENABLE_PAUSE_BUTTON="false"

    local keyboard_btn=$(sudo -u "$KIOSK_USER" jq -r '.enableKeyboardButton // true' "$CONFIG_PATH" 2>/dev/null)
    [[ "$keyboard_btn" == "true" ]] && ENABLE_KEYBOARD_BUTTON="true" || ENABLE_KEYBOARD_BUTTON="false"

    # Load password protection settings
    local password_enabled=$(sudo -u "$KIOSK_USER" jq -r '.enablePasswordProtection // false' "$CONFIG_PATH" 2>/dev/null)
    [[ "$password_enabled" == "true" ]] && ENABLE_PASSWORD_PROTECTION="true" || ENABLE_PASSWORD_PROTECTION="false"

    LOCKOUT_PASSWORD=$(sudo -u "$KIOSK_USER" jq -r '.lockoutPassword // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
    LOCKOUT_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.lockoutTimeout // 0' "$CONFIG_PATH" 2>/dev/null || echo "0")
    LOCKOUT_AT_TIME=$(sudo -u "$KIOSK_USER" jq -r '.lockoutAtTime // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
    LOCKOUT_ACTIVE_START=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveStart // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
    LOCKOUT_ACTIVE_END=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveEnd // ""' "$CONFIG_PATH" 2>/dev/null || echo "")

    local boot_password=$(sudo -u "$KIOSK_USER" jq -r '.requirePasswordOnBoot // false' "$CONFIG_PATH" 2>/dev/null)
    [[ "$boot_password" == "true" ]] && REQUIRE_PASSWORD_ON_BOOT="true" || REQUIRE_PASSWORD_ON_BOOT="false"
}
################################################################################
### SECTION 7: INSTALL/UNINSTALL SYSTEM FUNCTIONS
################################################################################

full_reinstall() {
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  FULL REINSTALL - NUCLEAR OPTION"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    echo "⚠️  This will COMPLETELY WIPE:"
    echo "  • All kiosk configuration and sites"
    echo "  • All Electron/Node.js installations"
    echo "  • All browser caches and data"
    echo "  • CUPS printer system"
    echo ""
    echo "Then reinstall everything from scratch."
    echo ""
    read -p "Are you ABSOLUTELY SURE? (type YES): " CONFIRM
    
    if [ "$CONFIRM" != "YES" ]; then
        echo "Cancelled."
        return
    fi
    
    # ONLY ask about VPN/VNC
    echo ""
    echo "Keep VPN/VNC settings?"
    read -p "(y/n): " KEEP_VPN
    
    echo ""
    echo "Beginning nuclear reinstall..."
    
    # Stop everything
    echo "[1/8] Stopping all services..."
    sudo systemctl stop lightdm 2>/dev/null || true
    
    # Backup ONLY VPN/VNC if requested
    VPN_BACKUP=""
    if [[ "$KEEP_VPN" =~ ^[Yy]$ ]]; then
        echo "[2/8] Backing up VPN/VNC..."
        VPN_BACKUP="/tmp/kiosk-vpn-backup-$(date +%s)"
        mkdir -p "$VPN_BACKUP"
        
        [ -d "/etc/openvpn" ] && sudo cp -r /etc/openvpn "$VPN_BACKUP/" 2>/dev/null || true
        
        if [ -f "/home/$KIOSK_USER/.vnc/passwd" ]; then
            sudo -u "$KIOSK_USER" mkdir -p "$VPN_BACKUP/vnc"
            sudo -u "$KIOSK_USER" cp /home/$KIOSK_USER/.vnc/passwd "$VPN_BACKUP/vnc/" 2>/dev/null || true
        fi
        
        echo "✓ VPN/VNC backed up"
    else
        echo "[2/8] Nuking VPN/VNC too"
    fi
    
    # NUCLEAR WIPE
    echo "[3/8] Wiping kiosk files..."
    sudo rm -rf "$KIOSK_DIR"
    sudo rm -f /home/$KIOSK_USER/.xsession
    sudo rm -f /home/$KIOSK_USER/electron.log
    sudo rm -rf /home/$KIOSK_USER/.cache
    sudo rm -rf /home/$KIOSK_USER/.config/Electron
    sudo rm -rf /home/$KIOSK_USER/.config/chromium
    
    echo "[4/8] Removing CUPS..."
    sudo systemctl stop cups 2>/dev/null || true
    sudo systemctl disable cups 2>/dev/null || true
    sudo apt-get purge -y cups cups-client cups-common 2>/dev/null || true
    
    echo "[5/8] Removing Node.js..."
    sudo apt-get purge -y nodejs npm 2>/dev/null || true
    sudo rm -rf /usr/local/lib/node_modules
    sudo rm -rf /usr/local/bin/node
    sudo rm -rf /usr/local/bin/npm
    
    if [[ ! "$KEEP_VPN" =~ ^[Yy]$ ]]; then
        echo "[6/8] Removing VPN/VNC..."
        sudo systemctl stop x11vnc openvpn* 2>/dev/null || true
        sudo systemctl disable x11vnc openvpn* 2>/dev/null || true
        sudo apt-get purge -y x11vnc openvpn 2>/dev/null || true
        sudo rm -rf /home/$KIOSK_USER/.vnc
        sudo rm -rf /etc/openvpn
        sudo rm -f /etc/systemd/system/x11vnc.service
    else
        echo "[6/8] Preserving VPN/VNC"
    fi
    
    echo "[7/8] System cleanup..."
    sudo systemctl daemon-reload
    sudo apt-get autoremove -y 2>/dev/null || true
    sudo apt-get autoclean 2>/dev/null || true
    
    echo ""
    echo "✓✓✓ EVERYTHING WIPED ✓✓✓"
    echo ""
    
    # Fresh install
    echo "[8/8] Fresh installation starting..."
    first_time_install
    
    # Restore ONLY VPN/VNC if backed up
    if [ -n "$VPN_BACKUP" ] && [ -d "$VPN_BACKUP" ]; then
        echo ""
        echo "Restoring VPN/VNC..."
        [ -d "$VPN_BACKUP/openvpn" ] && sudo cp -r "$VPN_BACKUP/openvpn" /etc/ 2>/dev/null || true
        
        if [ -f "$VPN_BACKUP/vnc/passwd" ]; then
            sudo -u "$KIOSK_USER" mkdir -p /home/$KIOSK_USER/.vnc
            sudo -u "$KIOSK_USER" cp "$VPN_BACKUP/vnc/passwd" /home/$KIOSK_USER/.vnc/ 2>/dev/null || true
        fi
        
        rm -rf "$VPN_BACKUP"
        echo "✓ VPN/VNC restored"
    fi
    
    echo ""
    log_success "Nuclear reinstall complete! System is FRESH."
    echo ""
    pause
}
################################################################################
### SECTION 8: FIRST TIME INSTALLATION
################################################################################

first_time_install() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   Ubuntu Based Kiosk (UBK) v${SCRIPT_VERSION} - Installation          "
    echo "════════════════════════════════════════════════════════════"
    echo
    echo "This will install a HEADLESS KIOSK (no desktop environment):"
    echo
    echo "CORE:"
    echo "  • Kiosk user with auto-login"
    echo "  • LightDM + Openbox (minimal window manager)"
    echo "  • Electron browser (v33.4.11)"
    echo "  • Multi-site rotation with touch controls"
    echo "  • Hardware video acceleration"
    echo "  • Audio support (PipeWire)"
    echo "  • Time synchronization (NTP)"
    echo
    echo "OPTIONAL (configure after install):"
    echo "  • Lyrion Music Server (LMS) / Squeezelite"
    echo "  • CUPS printing"
    echo "  • Jitsi intercom"
    echo "  • Remote desktop (VNC)"
    echo "  • VPN (WireGuard, Tailscale, Netbird)"
    echo "  • Onboard touchscreen keyboard"
    echo
    read -r -p "Proceed with installation? (y/n): " proceed
    [[ "$proceed" != "y" ]] && exit 0
    
    echo
    echo "[1/27] Installing packages..."
    sudo apt update
    sudo apt install -y \
      xorg openbox lightdm unclutter screen curl git build-essential \
      ca-certificates gnupg lsb-release jq ufw x11-xserver-utils xinput \
      vainfo mesa-utils libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers \
      libva2 libva-drm2 libva-x11-2 mesa-va-drivers \
      libegl-mesa0 libegl1-mesa-dev libgles2-mesa-dev \
      pipewire pipewire-pulse pipewire-alsa wireplumber pipewire-audio-client-libraries alsa-utils libnotify-bin \
      systemd-timesyncd acpid xbindkeys xdotool python3-evdev
    
    if lspci | grep -i "VGA.*Intel" >/dev/null 2>&1; then
        sudo apt install -y intel-gpu-tools xserver-xorg-video-intel \
          i965-va-driver intel-media-va-driver
    fi
    
    echo "[2/27] Configuring time synchronization..."
    sudo systemctl enable systemd-timesyncd
    sudo systemctl start systemd-timesyncd
    log_success "NTP time sync enabled"
    
    echo "[3/27] Creating kiosk user..."
    if ! id "$KIOSK_USER" &>/dev/null; then
        sudo useradd -m -s /bin/bash -G audio,video,input,plugdev,netdev "$KIOSK_USER"
        echo "$KIOSK_USER:kiosk" | sudo chpasswd
        log_success "Kiosk user created"
    else
        log_success "Kiosk user already exists"
    fi
    
    echo "[4/27] Configuring timezone..."
    configure_timezone
    
    echo "[5/27] Setting up kiosk directories..."
    sudo mkdir -p "$KIOSK_DIR"
    sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME"
    
    echo "[6/27] Installing Node.js..."
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
    fi
    echo "Node.js: $(node -v)"
    
    echo "[7-10/27] Core configuration..."
    configure_touch_controls
    configure_navigation_security
    configure_optional_features
    configure_password_protection
    configure_sites

    echo "[12/27] Initial scheduling (optional)..."
    echo
    read -r -p "Configure power/display/quiet schedules now? (y/n): " do_schedules
    if [[ "$do_schedules" =~ ^[Yy]$ ]]; then
        configure_power_display_quiet
    else
        log_info "Schedules can be configured later from Core Settings menu"
    fi
    
    save_config
   
##################################################################
####################start-main.js#################################
###################################################################
echo "[13/27] Installing Electron..."
sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/main.js" > /dev/null <<'MAINJS'
const {app,BrowserWindow,BrowserView,globalShortcut,ipcMain,dialog}=require('electron');
const {exec}=require('child_process');
const fs=require('fs');
const path=require('path');
const os=require('os');

const CONFIG_FILE=path.join(__dirname,'config.json');
const VERSION='0.9.5-10';

let mainWindow,views=[],hiddenViews=[],tabs=[],currentIndex=0,showingHidden=false;
let pinWindow=null,promptWindow=null,pauseWindow=null,htmlKeyboardWindow=null;
let tabIndexToViewIndex=[];
let currentHiddenIndex=0;

let masterTimer=null;
let siteStartTime=Date.now();
let lastUserInteraction=Date.now();
let lastMediaCheck=Date.now();
let keyboardOpenTime=0;
let keyboardLastUsed=0;
let inactivityExtensionUntil=0;

let manualNavigationMode=false;
let programmaticNavigation=false;

let mediaIsPlaying=false;
let userRecentlyActive=false;
let keyboardIsOpen=false;
let keyboardClosePending=false;

const USER_ACTIVITY_PAUSE=60000;
const KEYBOARD_AUTO_CLOSE=30000;
const MEDIA_CHECK_INTERVAL=3000;
const MEDIA_GRACE_PERIOD=30000;
const SAFETY_MAX_EXTENSION=14400000;
const INACTIVITY_PROMPT_TIMEOUT=15000;

let lastMediaStateChange=Date.now();

let homeTabIndex=-1;
let inactivityTimeout=120000;
let allowNavigation='same-origin';
let enablePauseButton=true;
let enableKeyboardButton=true;
let enablePasswordProtection=false;
let lockoutPassword="";
let lockoutTimeout=0;
let lockoutAtTime="";
let lockoutActiveStart="";
let lockoutActiveEnd="";
let requirePasswordOnBoot=false;

// Password lockout state
let isLockedOut=false;
let lockoutWindow=null;
let lockoutTimer=null;
let lockoutActivityTime=Date.now();
let requirePasswordAfterDisplay=false;
let lastScheduledLockCheck=0;

function loadConfig(){
  try{
    if(!fs.existsSync(CONFIG_FILE)){
      console.log('[CONFIG] No config file found');
      return [];
    }
    
    const data=fs.readFileSync(CONFIG_FILE,'utf8');
    const config=JSON.parse(data);
    
    homeTabIndex=(config.homeTabIndex!=null)?config.homeTabIndex:-1;
    inactivityTimeout=(config.inactivityTimeout||120)*1000;
    allowNavigation=config.allowNavigation||'same-origin';
    enablePauseButton=(config.enablePauseButton!==false);
    enableKeyboardButton=(config.enableKeyboardButton!==false);
    enablePasswordProtection=(config.enablePasswordProtection===true);
    lockoutPassword=config.lockoutPassword||"";
    lockoutTimeout=(config.lockoutTimeout||0)*60000; // Convert minutes to ms
    lockoutAtTime=config.lockoutAtTime||"";
    lockoutActiveStart=config.lockoutActiveStart||"";
    lockoutActiveEnd=config.lockoutActiveEnd||"";
    requirePasswordOnBoot=(config.requirePasswordOnBoot===true);

    console.log('[CONFIG] ═══════════════════════════');
    console.log('[CONFIG] Home tab index:',homeTabIndex);
    console.log('[CONFIG] Inactivity timeout:',inactivityTimeout/1000,'seconds');
    console.log('[CONFIG] Navigation:',allowNavigation);
console.log('[CONFIG] Pause button:',enablePauseButton);    console.log('[CONFIG] Keyboard button:',enableKeyboardButton);    console.log('[CONFIG] Password protection:',enablePasswordProtection);    console.log('[CONFIG] Lockout timeout:',lockoutTimeout/60000,'minutes');
    if(lockoutAtTime)console.log('[CONFIG] Lock at time:',lockoutAtTime);
    if(lockoutActiveStart&&lockoutActiveEnd)console.log('[CONFIG] Active hours:',lockoutActiveStart,'-',lockoutActiveEnd);
    console.log('[CONFIG] Require password on boot:',requirePasswordOnBoot);
    console.log('[CONFIG] Sites:',config.tabs?.length||0);
    console.log('[CONFIG] ═══════════════════════════');
    
    return config.tabs||[];
  }catch(e){
    console.error('[CONFIG] Load error:',e.message);
    return [];
  }
}

function markActivity(){
  const now=Date.now();
  const timeSinceLastActivity=now-lastUserInteraction;

  if(timeSinceLastActivity>5000){
    console.log('[ACTIVITY] User interaction detected');
  }

  lastUserInteraction=now;
  userRecentlyActive=true;

  if(promptWindow&&!promptWindow.isDestroyed()){
    console.log('[ACTIVITY] Closing inactivity prompt');
    promptWindow.close();
    promptWindow=null;
  }

  // CRITICAL FIX: Don't clear extensions on activity
  // Extensions should only expire naturally or be explicitly cancelled
  // If user is active, they're using the current site - extension should remain
  // inactivityExtensionUntil=0;  // REMOVED - was breaking extensions

  // CRITICAL: Do NOT reset lockout timer on activity
  // Lockout timer should only reset when:
  // 1. User unlocks the screen (in unlockScreen function)
  // 2. User selects a time extension (in showPauseDialog/showInactivityPrompt)
  // If we reset it here, ANY activity (mouse move, click, etc.) prevents lockout
  // REMOVED: lockoutActivityTime reset - was preventing inactivity lockout from ever triggering
}

function markKeyboardActivity(){
  const now=Date.now();
  keyboardLastUsed=now;
  keyboardOpenTime=now;
  keyboardClosePending=false;
}

// Password lockout functions
function showLockoutScreen(){
  if(isLockedOut||!enablePasswordProtection||!lockoutPassword)return;

  isLockedOut=true;
  console.log('[LOCKOUT] Showing lockout screen');

  // Detach all browser views to prevent content from being visible
  console.log('[LOCKOUT] Detaching all browser views for security');
  views.forEach(view=>{
    if(mainWindow&&!mainWindow.isDestroyed()){
      try{
        mainWindow.removeBrowserView(view);
      }catch(e){
        console.log('[LOCKOUT] View already detached or error:',e.message);
      }
    }
  });
  hiddenViews.forEach(view=>{
    if(mainWindow&&!mainWindow.isDestroyed()){
      try{
        mainWindow.removeBrowserView(view);
      }catch(e){
        console.log('[LOCKOUT] Hidden view already detached or error:',e.message);
      }
    }
  });

  // Create lockout window
  lockoutWindow=new BrowserWindow({
    fullscreen:true,
    frame:false,
    backgroundColor:'#000000',
    webPreferences:{
      nodeIntegration:true,
      contextIsolation:false
    }
  });

  lockoutWindow.loadURL('data:text/html;charset=utf-8,'+encodeURIComponent(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        *{margin:0;padding:0;box-sizing:border-box;}
        body{
          background:#000;
          color:#fff;
          font-family:Arial,sans-serif;
          display:flex;
          justify-content:center;
          align-items:center;
          height:100vh;
          overflow:hidden;
        }
        .lockout-container{
          text-align:center;
          max-width:400px;
        }
        h1{font-size:32px;margin-bottom:30px;}
        input{
          width:100%;
          padding:15px;
          font-size:18px;
          border:2px solid #fff;
          background:#000;
          color:#fff;
          border-radius:5px;
          margin-bottom:20px;
        }
        button{
          padding:15px 30px;
          font-size:18px;
          background:#fff;
          color:#000;
          border:none;
          border-radius:5px;
          cursor:pointer;
        }
        button:hover{background:#ccc;}
        .error{color:#f44;margin-top:15px;display:none;}
      </style>
    </head>
    <body>
      <div class="lockout-container">
        <h1>Session Locked</h1>
        <input type="password" id="password" placeholder="Enter password to unlock" autofocus>
        <button onclick="checkPassword()">Unlock</button>
        <div class="error" id="error">Incorrect password</div>
      </div>
      <script>
        const crypto=require('crypto');
        const{ipcRenderer}=require('electron');

        function checkPassword(){
          const pass=document.getElementById('password').value;
          const hash=crypto.createHash('sha256').update(pass).digest('hex');
          ipcRenderer.send('check-lockout-password',hash);
        }

        document.getElementById('password').addEventListener('keydown',(e)=>{
          if(e.key==='Enter')checkPassword();
        });

        ipcRenderer.on('password-incorrect',()=>{
          document.getElementById('error').style.display='block';
          document.getElementById('password').value='';
          document.getElementById('password').focus();
        });
      </script>
    </body>
    </html>
  `));

  lockoutWindow.on('closed',()=>{
    lockoutWindow=null;
  });
}

function unlockScreen(){
  if(!isLockedOut)return;

  console.log('[LOCKOUT] Unlocking screen');
  isLockedOut=false;
  requirePasswordAfterDisplay=false;

  if(lockoutWindow&&!lockoutWindow.isDestroyed()){
    lockoutWindow.close();
    lockoutWindow=null;
  }

  // Restore current view using proper method
  if(showingHidden&&hiddenViews[currentHiddenIndex]){
    const[w,h]=mainWindow.getContentSize();
    mainWindow.setTopBrowserView(hiddenViews[currentHiddenIndex]);
    hiddenViews[currentHiddenIndex].setBounds({x:0,y:0,width:w,height:h});
  }else if(views[currentIndex]){
    attachView(currentIndex);
  }

  // Start master timer if not already running (handles boot password case)
  if(!masterTimer){
    startMasterTimer();
  }

  // Reset activity time
  lockoutActivityTime=Date.now();
}

// Helper: Check if current time is within active hours
function isWithinActiveHours(){
  if(!lockoutActiveStart||!lockoutActiveEnd)return true; // No restriction

  const now=new Date();
  const currentTime=now.getHours()*60+now.getMinutes(); // Current time in minutes

  const[startH,startM]=lockoutActiveStart.split(':').map(Number);
  const[endH,endM]=lockoutActiveEnd.split(':').map(Number);
  const startMinutes=startH*60+startM;
  const endMinutes=endH*60+endM;

  // Handle overnight ranges (e.g., 22:00-06:00)
  if(startMinutes>endMinutes){
    return currentTime>=startMinutes||currentTime<endMinutes;
  }

  return currentTime>=startMinutes&&currentTime<endMinutes;
}

// Helper: Check if it's time to auto-lock
function checkScheduledLockTime(){
  if(!lockoutAtTime){
    return;
  }
  if(isLockedOut)return;

  const now=new Date();
  const currentHour=now.getHours();
  const currentMin=now.getMinutes();
  const[targetH,targetM]=lockoutAtTime.split(':').map(Number);

  // Check once per minute to avoid multiple locks
  const currentMinute=currentHour*60+currentMin;
  const targetMinute=targetH*60+targetM;

  // Debug log every 60 seconds
  if(Math.floor(Date.now()/60000)!==Math.floor((Date.now()-1000)/60000)){
    const timeStr=String(currentHour).padStart(2,'0')+':'+String(currentMin).padStart(2,'0');
    console.log('[LOCKOUT-SCHED] Current: '+timeStr+' ('+currentMinute+' min) | Target: '+lockoutAtTime+' ('+targetMinute+' min) | Match: '+(currentMinute===targetMinute));
  }

  if(currentMinute===targetMinute&&lastScheduledLockCheck!==currentMinute){
    lastScheduledLockCheck=currentMinute;
    console.log('[LOCKOUT] *** SCHEDULED LOCK TIME REACHED: '+lockoutAtTime+' ***');
    showLockoutScreen();
  }
}

function checkLockoutTimer(){
  if(!enablePasswordProtection){
    return;
  }
  if(isLockedOut)return;

  const now=Date.now();

  // Check for scheduled lock time
  checkScheduledLockTime();

  // Check inactivity-based lockout
  if(lockoutTimeout>0){
    // Check if within active hours (if configured)
    if(!isWithinActiveHours()){
      // Log every 60 seconds when outside active hours
      if(Math.floor(now/60000)!==Math.floor((now-1000)/60000)){
        console.log('[LOCKOUT] Outside active hours, lockout disabled');
      }
      return; // Outside active hours, don't enforce lockout
    }

    // CRITICAL: Respect time extensions from pause button and manual site timeout
    if(inactivityExtensionUntil>0&&now<inactivityExtensionUntil){
      // Still within extension period - don't lock
      const remaining=Math.floor((inactivityExtensionUntil-now)/1000);
      const remMin=Math.floor(remaining/60);
      const remSec=remaining%60;

      // Log every 30 seconds during extension
      if(Math.floor(now/30000)!==Math.floor((now-1000)/30000)){
        console.log('[LOCKOUT-INACT] ⏸ Extension active: '+remMin+'m '+remSec+'s remaining - lockout paused');
      }
      return;  // Skip lockout check during extension
    }else if(inactivityExtensionUntil>0&&now>=inactivityExtensionUntil){
      // Extension expired - reset lockout activity timer
      console.log('[LOCKOUT-INACT] ⏰ Extension expired - resetting lockout timer');
      inactivityExtensionUntil=0;
      lockoutActivityTime=now;  // CRITICAL: Reset so lockout doesn't trigger immediately
    }

    const timeSinceActivity=now-lockoutActivityTime;
    const minutesSinceActivity=Math.floor(timeSinceActivity/60000);
    const lockoutMinutes=Math.floor(lockoutTimeout/60000);

    // Log every 30 seconds
    if(Math.floor(timeSinceActivity/30000)!==Math.floor((timeSinceActivity-1000)/30000)){
      console.log('[LOCKOUT-INACT] Idle: '+minutesSinceActivity+'m / '+lockoutMinutes+'m');
    }

    if(timeSinceActivity>=lockoutTimeout){
      console.log('[LOCKOUT] Inactivity timeout reached, locking screen');
      showLockoutScreen();
    }
  }
}

function checkMediaPlayback(){
  let view=null;
  if(showingHidden&&hiddenViews[currentHiddenIndex]){
    view=hiddenViews[currentHiddenIndex];
  }else if(views[currentIndex]){
    view=views[currentIndex];
  }
  
  if(!view||!view.webContents){
    if(mediaIsPlaying){
      mediaIsPlaying=false;
      lastMediaStateChange=Date.now();
    }
    return;
  }
  
  if(view.webContents.isLoadingMainFrame()||!view.webContents.getURL()){
    return;
  }
  
  view.webContents.executeJavaScript(`
    (function(){
      try{
        let playing=false;
        let method='';
        let details='';
        
        const videos=document.querySelectorAll("video");
        for(let v of videos){
          if(!v.paused&&!v.ended&&v.readyState>=2&&v.currentTime>0){
            playing=true;
            method='video';
            details='HTML5 video';
            break;
          }
        }
        
        if(!playing){
          const audios=document.querySelectorAll("audio");
          for(let a of audios){
            if(!a.paused&&!a.ended&&a.readyState>=2&&a.currentTime>0){
              playing=true;
              method='audio';
              details='HTML5 audio';
              break;
            }
          }
        }
        
        if(!playing){
          const iframes=document.querySelectorAll(
            'iframe[src*="youtube"],iframe[src*="vimeo"],'+
            'iframe[src*="dailymotion"],iframe[src*="twitch"],'+
            'iframe[src*="plex"],iframe[src*="emby"],iframe[src*="jellyfin"]'
          );
          for(let iframe of iframes){
            const rect=iframe.getBoundingClientRect();
            if(rect.width>200&&rect.height>100&&rect.top<window.innerHeight&&rect.bottom>0){
              playing=true;
              method='iframe';
              const src=iframe.src||'';
              if(src.includes('youtube'))details='YouTube';
              else if(src.includes('plex'))details='Plex';
              else if(src.includes('emby'))details='Emby';
              else if(src.includes('jellyfin'))details='Jellyfin';
              else if(src.includes('vimeo'))details='Vimeo';
              else details='Embedded player';
              break;
            }
          }
        }
        
        if(!playing){
          if(document.querySelector('.Player-progressBar')||
             document.querySelector('[class*="PlayerControls"]')){
            const plexVideo=document.querySelector('video');
            if(plexVideo&&!plexVideo.paused){
              playing=true;
              method='plex-app';
              details='Plex Web';
            }
          }
          
          if(document.querySelector('.videoPlayerContainer')||
             document.querySelector('.nowPlayingBar')){
            const jellyfinVideo=document.querySelector('video');
            if(jellyfinVideo&&!jellyfinVideo.paused){
              playing=true;
              method='jellyfin-app';
              details='Jellyfin Web';
            }
          }
          
          if(document.querySelector('.videoPlayerContainer')||
             document.querySelector('.nowPlayingBar')){
            const embyVideo=document.querySelector('video');
            if(embyVideo&&!embyVideo.paused){
              playing=true;
              method='emby-app';
              details='Emby Web';
            }
          }
        }
        
        return {playing:playing,method:method,details:details};
      }catch(e){
        return {playing:false,error:e.message};
      }
    })();
  `,true).then(result=>{
    const wasPlaying=mediaIsPlaying;
    const now=Date.now();
    
    if(result&&result.playing){
      if(!wasPlaying){
        console.log('[MEDIA] ▶ Started:',result.details||result.method);
      }
      mediaIsPlaying=true;
      lastMediaStateChange=now;
    }else{
      if(wasPlaying){
        console.log('[MEDIA] ⏸ Stopped');
      }
      mediaIsPlaying=false;
      if(wasPlaying){
        lastMediaStateChange=now;
      }
    }
  }).catch(err=>{});
}

function startMasterTimer(){
  if(masterTimer){
    clearInterval(masterTimer);
  }

  console.log('[TIMER] ╔═══ MASTER TIMER STARTED ════╗');
  console.log('[TIMER] Home tab index:',homeTabIndex);
  console.log('[TIMER] Inactivity timeout:',inactivityTimeout/1000,'seconds');
  console.log('[TIMER] Password protection:',enablePasswordProtection);
  if(enablePasswordProtection){
    console.log('[TIMER] Lockout timeout:',lockoutTimeout/60000,'minutes');
    if(lockoutAtTime)console.log('[TIMER] Scheduled lock time:',lockoutAtTime);
    if(lockoutActiveStart&&lockoutActiveEnd)console.log('[TIMER] Active hours:',lockoutActiveStart,'-',lockoutActiveEnd);
  }
  console.log('[TIMER] ╚═══════════════════════════════════╝');

  siteStartTime=Date.now();
  lastUserInteraction=Date.now();
  
  masterTimer=setInterval(()=>{
    const now=Date.now();
    
    // 1. KEYBOARD AUTO-CLOSE
    if(keyboardIsOpen&&!keyboardClosePending){
      const idleTime=now-keyboardLastUsed;
      if(idleTime>KEYBOARD_AUTO_CLOSE){
        keyboardClosePending=true;
        closeHTMLKeyboard();
      }
    }

    // 1.5. LOCKOUT TIMER CHECK
    checkLockoutTimer();

    // 1.6. CHECK FOR DISPLAY WAKE FLAG
    const displayWakeFlag=path.join(__dirname,'.display-wake');
    if(enablePasswordProtection&&lockoutPassword&&fs.existsSync(displayWakeFlag)){
      console.log('[LOCKOUT] Display wake detected, requiring password');
      fs.unlinkSync(displayWakeFlag);
      if(!isLockedOut){
        showLockoutScreen();
      }
    }

    // CRITICAL: If locked out, skip all navigation/rotation logic
    if(isLockedOut){
      return;
    }

    // 2. MEDIA CHECK
    if(now-lastMediaCheck>MEDIA_CHECK_INTERVAL){
      checkMediaPlayback();
      lastMediaCheck=now;
    }
    
    // 3. MEDIA BLOCKING
    if(mediaIsPlaying){
      return;
    }
    
    // 4. GRACE PERIOD
    const timeSinceMediaStopped=now-lastMediaStateChange;
    if(timeSinceMediaStopped<MEDIA_GRACE_PERIOD){
      return;
    }
    
    // 5. USER ACTIVITY CHECK
    const timeSinceInteraction=now-lastUserInteraction;
    userRecentlyActive=timeSinceInteraction<USER_ACTIVITY_PAUSE;
    
    if(userRecentlyActive){
      return;
    }
    
    // 6. SITE ROTATION
    if(!showingHidden&&views.length>1){
      // CRITICAL: Don't rotate while pause dialog is open (user is selecting time)
      if(pauseWindow&&!pauseWindow.isDestroyed()){
        return;
      }

      // CRITICAL: Don't rotate while inactivity prompt is open (user is responding)
      if(promptWindow&&!promptWindow.isDestroyed()){
        return;
      }

      // Skip rotation if user is in an extension period (they confirmed they're still there)
      if(inactivityExtensionUntil>0&&now<inactivityExtensionUntil){
        // Log every 30 seconds during extension
        if(Math.floor(now/30000)!==Math.floor((now-1000)/30000)){
          const remaining=Math.floor((inactivityExtensionUntil-now)/1000);
          const remMin=Math.floor(remaining/60);
          const remSec=remaining%60;
          console.log('[ROTATION] ⏸ Paused - Extension active: '+remMin+'m '+remSec+'s remaining');
        }
        // Don't rotate during extension period
        return;
      }

      const currentTabIdx=viewIndexToTabIndex(currentIndex);

      if(currentTabIdx>=0&&tabs[currentTabIdx]){
        const siteDuration=parseInt(tabs[currentTabIdx].duration)||0;

        if(siteDuration>0){
          const timeOnSite=now-siteStartTime;

          if(timeOnSite>=siteDuration*1000){
            rotateToNextSite();
            return; // CRITICAL: Don't run HOME RETURN CHECK after rotating - site was timed
          }
        }
      }
    }
    
// 7. HOME RETURN CHECK (manual sites only)
    if(homeTabIndex>=0&&!showingHidden){
      const homeViewIdx=getHomeViewIndex();
      const currentTabIdx=viewIndexToTabIndex(currentIndex);

      // Only show home return prompt for manual sites (duration = 0)
      // Timed sites use the pause button instead
      if(homeViewIdx>=0&&currentIndex!==homeViewIdx&&currentTabIdx>=0&&tabs[currentTabIdx]){
        const siteDuration=parseInt(tabs[currentTabIdx].duration)||0;

        // Skip home return check for timed rotation sites
        if(siteDuration>0){
          // This is a timed site - pause button is used instead
          return;
        }

        // CRITICAL: Don't show prompt while pause dialog is open
        if(pauseWindow&&!pauseWindow.isDestroyed()){
          return;
        }

        // CRITICAL: Don't show prompt while inactivity prompt is already open
        if(promptWindow&&!promptWindow.isDestroyed()){
          return;
        }

        const idleTime=now-lastUserInteraction;

        // CRITICAL FIX: Use absolute time check for extensions
        let effectiveTimeout=inactivityTimeout;
        if(inactivityExtensionUntil>0&&now<inactivityExtensionUntil){
          // Still within extension period - don't timeout
          if(Math.floor(idleTime/15000)!==Math.floor((idleTime-1000)/15000)){
            const remaining=Math.floor((inactivityExtensionUntil-now)/1000);
            const remMin=Math.floor(remaining/60);
            const remSec=remaining%60;
            console.log('[HOME] ⏰ Extended mode: '+remMin+'m '+remSec+'s remaining');
          }
          return;  // Skip timeout check during extension
        }else if(inactivityExtensionUntil>0&&now>=inactivityExtensionUntil){
          // Extension expired - clear it and reset inactivity timer
          console.log('[HOME] ⏰ Extension expired - resetting inactivity timer');
          inactivityExtensionUntil=0;
          lastUserInteraction=now;  // CRITICAL: Reset interaction time so prompt doesn't show immediately
          siteStartTime=now;  // Also reset rotation timer
        }

        // Log every 15 seconds
        if(Math.floor(idleTime/15000)!==Math.floor((idleTime-1000)/15000)){
          const idleMinutes=Math.floor(idleTime/60000);
          const idleSeconds=Math.floor((idleTime%60000)/1000);
          const timeoutMinutes=Math.floor(effectiveTimeout/60000);
          const timeoutSeconds=Math.floor((effectiveTimeout%60000)/1000);
          console.log('[HOME] 🏠 IDLE: '+idleMinutes+'m '+idleSeconds+'s / '+timeoutMinutes+'m '+timeoutSeconds+'s');
        }

        if(idleTime>=effectiveTimeout){
          console.log('[HOME] 🔔 *** SHOWING PROMPT NOW ***');
          showInactivityPrompt();
        }
      }
    }
  },1000);
}

function stopMasterTimer(){
  if(masterTimer){
    clearInterval(masterTimer);
    masterTimer=null;
  }
}

function rotateToNextSite(){
  if(isLockedOut)return;
  if(!views.length||showingHidden)return;
  
  let nextIdx=(currentIndex+1)%views.length;
  const startIdx=nextIdx;
  let found=false;
  let attempts=0;
  
  do{
    const tabIdx=viewIndexToTabIndex(nextIdx);
    if(tabIdx>=0&&tabs[tabIdx]){
      const dur=parseInt(tabs[tabIdx].duration)||0;
      if(dur>0){
        found=true;
        break;
      }
    }
    nextIdx=(nextIdx+1)%views.length;
    attempts++;
  }while(nextIdx!==startIdx&&attempts<views.length);
  
  if(found&&nextIdx!==currentIndex){
    currentIndex=nextIdx;
    attachView(currentIndex);
  }
}

function attachView(i){
  closeHTMLKeyboard();

  // Don't change views while locked out
  if(isLockedOut){
    console.log('[MAIN] Blocked attachView - screen is locked');
    return;
  }

  if(!mainWindow||!views[i]||showingHidden)return;

  currentIndex=i;
  mainWindow.setTopBrowserView(views[i]);
  const[w,h]=mainWindow.getContentSize();
  views[i].setBounds({x:0,y:0,width:w,height:h});
  
  const tabIdx=viewIndexToTabIndex(i);
  if(tabIdx>=0&&tabs[tabIdx]){
    const configuredUrl=tabs[tabIdx].url;
    const currentUrl=views[i].webContents.getURL();

    if(currentUrl&&!currentUrl.startsWith(configuredUrl)){
      programmaticNavigation=true;
      views[i].webContents.loadURL(configuredUrl);
    }

    // Control pause button visibility based on site duration
    // Show on rotation sites (duration > 0), hide on manual sites (duration = 0)
    const siteDuration=parseInt(tabs[tabIdx].duration)||0;
    const shouldShow=enablePauseButton&&siteDuration>0;
    console.log('[MAIN] Sending pause-button-visibility to tab '+tabIdx+' ('+tabs[tabIdx].url+') - duration='+siteDuration+'s, shouldShow='+shouldShow);
    views[i].webContents.send('pause-button-visibility',shouldShow);
  }

  views[i].webContents.focus();
  siteStartTime=Date.now();
}

function nextTab(){
  if(isLockedOut)return;
  if(!views.length||showingHidden)return;
  console.log('[MANUAL] User switched tab forward → manualNavigationMode=TRUE');
  manualNavigationMode=true;
  currentIndex=(currentIndex+1)%views.length;
  attachView(currentIndex);
  markActivity();
  inactivityExtensionUntil=0;  // Clear extension on manual navigation
  console.log('[MANUAL] Extension cleared due to manual tab switch');
}

function prevTab(){
  if(isLockedOut)return;
  if(!views.length||showingHidden)return;
  console.log('[MANUAL] User switched tab backward → manualNavigationMode=TRUE');
  manualNavigationMode=true;
  currentIndex=(currentIndex-1+views.length)%views.length;
  attachView(currentIndex);
  markActivity();
  inactivityExtensionUntil=0;  // Clear extension on manual navigation
  console.log('[MANUAL] Extension cleared due to manual tab switch');
}

function getHomeViewIndex(){
  if(homeTabIndex<0)return -1;
  if(homeTabIndex>=tabIndexToViewIndex.length)return -1;
  return tabIndexToViewIndex[homeTabIndex];
}

function returnToHome(){
  if(isLockedOut)return;

  const homeViewIdx=getHomeViewIndex();
  if(homeViewIdx<0)return;

  console.log('[HOME] 🏠 RETURNING TO HOME → manualNavigationMode=FALSE');

  if(showingHidden){
    showingHidden=false;
    currentHiddenIndex=0;
  }

  if(promptWindow&&!promptWindow.isDestroyed()){
    promptWindow.close();
    promptWindow=null;
  }

  manualNavigationMode=false;
  currentIndex=homeViewIdx;
  attachView(currentIndex);

  inactivityExtensionUntil=0;

  // Reset lockout timer on activity
  if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
    lockoutActivityTime=Date.now();
  }
  markActivity();
}

function showInactivityPrompt(){
  if(promptWindow&&!promptWindow.isDestroyed())return;
  
  promptWindow=new BrowserWindow({
    width:800,
    height:600,
    frame:false,
    alwaysOnTop:true,
    parent:mainWindow,
    modal:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });
  
  promptWindow.loadFile(path.join(__dirname,'inactivity-prompt-extended.html'));
  
  promptWindow.on('closed',()=>{
    promptWindow=null;
  });
  
  setTimeout(()=>{
    if(promptWindow&&!promptWindow.isDestroyed()){
      console.log('[PROMPT] No response - returning home');
      promptWindow.close();
      promptWindow=null;
      returnToHome();
    }
  },INACTIVITY_PROMPT_TIMEOUT);
  
  ipcMain.once('user-still-here',(event,minutes)=>{
    if(promptWindow&&!promptWindow.isDestroyed()){
      promptWindow.close();
    }
    promptWindow=null;

    if(minutes===-1){
      // User clicked "No, go home"
      inactivityExtensionUntil=0;

      // Reset lockout timer on activity
      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=Date.now();
      }
      returnToHome();
    }else if(minutes===0){
      // User clicked "Yes, I'm still here" - reset everything
      inactivityExtensionUntil=0;

      // Reset lockout timer on activity
      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=Date.now();
      }
      markActivity();
      // CRITICAL: Reset site rotation timer so they stay on current page
      siteStartTime=Date.now();
      console.log('[PROMPT] User confirmed presence - rotation timer reset');
    }else{
      // User selected a time extension
      const now=Date.now();
      inactivityExtensionUntil=now+(minutes*60*1000);
      lastUserInteraction=now;
      // CRITICAL: Reset site rotation timer during extension
      siteStartTime=now;

      // CRITICAL: Reset lockout timer during extension
      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=now;
        console.log('[PROMPT] Lockout timer also reset during extension');
      }

      console.log('[PROMPT] Extended for '+minutes+' min until: '+new Date(inactivityExtensionUntil).toLocaleTimeString());
      console.log('[PROMPT] Rotation timer reset - staying on current page');
    }
  });
}

function showPauseDialog(){
  if(pauseWindow&&!pauseWindow.isDestroyed())return;

  pauseWindow=new BrowserWindow({
    width:800,
    height:600,
    frame:false,
    alwaysOnTop:true,
    parent:mainWindow,
    modal:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });

  pauseWindow.loadFile(path.join(__dirname,'pause-dialog.html'));

  pauseWindow.on('closed',()=>{
    pauseWindow=null;
  });

  ipcMain.once('pause-time-selected',(event,minutes)=>{
    if(pauseWindow&&!pauseWindow.isDestroyed()){
      pauseWindow.close();
    }
    pauseWindow=null;

    if(minutes===0){
      // Cancel - do nothing
      console.log('[PAUSE] Cancelled');
    }else{
      // Set extension time
      const now=Date.now();
      inactivityExtensionUntil=now+(minutes*60*1000);
      lastUserInteraction=now;
      siteStartTime=now;

      // CRITICAL: Reset lockout timer during extension
      if(enablePasswordProtection&&lockoutTimeout>0&&!isLockedOut){
        lockoutActivityTime=now;
        console.log('[PAUSE] Lockout timer also reset during extension');
      }

      console.log('[PAUSE] Extended for '+minutes+' min until: '+new Date(inactivityExtensionUntil).toLocaleTimeString());
      console.log('[PAUSE] Rotation and inactivity timers paused');
    }
  });
}

function showHTMLKeyboard(){
  if(keyboardIsOpen){
    keyboardLastUsed=Date.now();
    keyboardOpenTime=Date.now();
    keyboardClosePending=false;
    return;
  }
  
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.focus();
    keyboardLastUsed=Date.now();
    keyboardOpenTime=Date.now();
    keyboardIsOpen=true;
    keyboardClosePending=false;
    return;
  }
  
  const{width,height}=mainWindow.getBounds();
  const kbHeight=Math.floor(height*0.4);
  const kbY=height-kbHeight;
  
  htmlKeyboardWindow=new BrowserWindow({
    width:width,
    height:kbHeight,
    x:0,
    y:kbY,
    frame:false,
    alwaysOnTop:true,
    skipTaskbar:true,
    focusable:false,
    webPreferences:{
      nodeIntegration:true,
      contextIsolation:false,
      backgroundThrottling:false
    }
  });
  
  htmlKeyboardWindow.loadFile(path.join(__dirname,'keyboard.html'));
  
  htmlKeyboardWindow.webContents.on('did-finish-load',()=>{
    keyboardIsOpen=true;
    keyboardOpenTime=Date.now();
    keyboardLastUsed=Date.now();
    keyboardClosePending=false;
    notifyKeyboardState(true);
    
    if(mainWindow&&!mainWindow.isDestroyed()){
      mainWindow.focus();
      if(views[currentIndex]&&views[currentIndex].webContents){
        views[currentIndex].webContents.focus();
      }
    }
  });
  
  htmlKeyboardWindow.on('closed',()=>{
    keyboardIsOpen=false;
    keyboardClosePending=false;
    htmlKeyboardWindow=null;
    notifyKeyboardState(false);
  });
}

function closeHTMLKeyboard(){
  if(!keyboardIsOpen)return;
  
  const wasAutoClosed=keyboardClosePending;
  
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.close();
  }
  htmlKeyboardWindow=null;
  keyboardIsOpen=false;
  keyboardClosePending=false;
  notifyKeyboardState(false);
  
  if(wasAutoClosed){
    const allViews=[...views,...hiddenViews];
    allViews.forEach(view=>{
      if(view&&view.webContents){
        view.webContents.send('keyboard-auto-closed');
      }
    });
  }
  
  if(mainWindow&&!mainWindow.isDestroyed()){
    mainWindow.focus();
  }
}

function notifyKeyboardState(visible){
  const allViews=[...views,...hiddenViews];
  allViews.forEach(view=>{
    if(view&&view.webContents){
      view.webContents.send('keyboard-state-changed',visible);
    }
  });
}

function viewIndexToTabIndex(viewIdx){
  for(let i=0;i<tabIndexToViewIndex.length;i++){
    if(tabIndexToViewIndex[i]===viewIdx)return i;
  }
  return -1;
}

function toggleHidden(){
  if(pinWindow&&!pinWindow.isDestroyed()){
    pinWindow.close();
    pinWindow=null;
    return;
  }
  
  if(!hiddenViews.length)return;
  
  if(showingHidden){
    currentHiddenIndex++;
    if(currentHiddenIndex>=hiddenViews.length){
      currentHiddenIndex=0;
      returnToTabs();
    }else{
      showHiddenTab(currentHiddenIndex);
    }
  }else{
    currentHiddenIndex=0;
    showPinEntry();
  }
}

function returnToTabs(){
  if(!views.length)return;
  
  const[w,h]=mainWindow.getContentSize();
  mainWindow.setTopBrowserView(views[currentIndex]);
  views[currentIndex].setBounds({x:0,y:0,width:w,height:h});
  showingHidden=false;
  currentHiddenIndex=0;
  
  markActivity();
}

function showPinEntry(){
  if(pinWindow&&!pinWindow.isDestroyed()){
    pinWindow.focus();
    return;
  }
  
  pinWindow=new BrowserWindow({
    width:500,
    height:650,
    frame:false,
    alwaysOnTop:true,
    parent:mainWindow,
    modal:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });
  
  pinWindow.loadFile(path.join(__dirname,'pin-entry.html'));
  pinWindow.on('closed',()=>{pinWindow=null;});
  
  ipcMain.once('pin-correct',()=>{
    if(pinWindow&&!pinWindow.isDestroyed()){
      pinWindow.close();
    }
    pinWindow=null;
    showHiddenTab(currentHiddenIndex);
  });
  
  ipcMain.once('pin-cancelled',()=>{
    if(pinWindow&&!pinWindow.isDestroyed()){
      pinWindow.close();
    }
    pinWindow=null;
  });
}

function showHiddenTab(index){
  if(!hiddenViews[index])return;
  
  const[w,h]=mainWindow.getContentSize();
  mainWindow.setTopBrowserView(hiddenViews[index]);
  hiddenViews[index].setBounds({x:0,y:0,width:w,height:h});
  showingHidden=true;
}

function forceReturnToTabs(){
  if(pinWindow&&!pinWindow.isDestroyed()){
    pinWindow.close();
    pinWindow=null;
  }
  returnToTabs();
}

function showPowerMenu(){
  const ipAddress=os.networkInterfaces();
  let ip='No IP';
  for(const name of Object.keys(ipAddress)){
    for(const net of ipAddress[name]){
      if(net.family==='IPv4'&&!net.internal){
        ip=net.address;
        break;
      }
    }
  }

  // Show limited menu when locked out (no Reload option to prevent bypass)
  if(isLockedOut){
    console.log('[SECURITY] Showing limited power menu - system is locked out');
    // Show power menu on lockoutWindow (solid screen) instead of mainWindow
    const targetWindow=(lockoutWindow&&!lockoutWindow.isDestroyed())?lockoutWindow:mainWindow;
    const r=dialog.showMessageBoxSync(targetWindow,{
      type:'question',
      buttons:['Shutdown','Restart','Cancel'],
      defaultId:2,
      title:'Power Options',
      message:'System is locked. Limited options available.\n\nVersion: '+VERSION+'\nIP Address: '+ip,
      noLink:true
    });

    if(r===0)exec('systemctl poweroff');
    else if(r===1)exec('systemctl reboot');
    return;
  }

  // Full menu when unlocked
  const r=dialog.showMessageBoxSync(mainWindow,{
    type:'question',
    buttons:['Shutdown','Restart','Reload','Cancel'],
    defaultId:3,
    title:'Power Options',
    message:'What would you like to do?\n\nVersion: '+VERSION+'\nIP Address: '+ip,
    noLink:true
  });

  if(r===0)exec('systemctl poweroff');
  else if(r===1)exec('systemctl reboot');
  else if(r===2){app.relaunch();app.quit();}
}

function createWindow(){
  tabs=loadConfig();
  
  mainWindow=new BrowserWindow({
    fullscreen:true,
    kiosk:true,
    frame:false,
    show:false,
    webPreferences:{
      nodeIntegration:false,
      contextIsolation:true,
      sandbox:false,
      preload:path.join(__dirname,'preload.js')
    }
  });
  
  mainWindow.setMenu(null);
  mainWindow.show();
  
  mainWindow.on('focus',()=>markActivity());
  mainWindow.webContents.on('before-input-event',()=>markActivity());
  
  if(!tabs.length){
    mainWindow.loadURL('data:text/html,<body>No Sites Configured</body>');
    return;
  }
  
  let viewIndex=0;
  tabs.forEach((t,tabIdx)=>{
    const view=new BrowserView({
      webPreferences:{
        contextIsolation:true,
        sandbox:false,
        preload:path.join(__dirname,'preload.js'),
        backgroundThrottling:false
      }
    });
    
    mainWindow.addBrowserView(view);
    
    let url=t.url;
    if(t.username&&t.password){
      try{
        const u=new URL(t.url);
        u.username=t.username;
        u.password=t.password;
        url=u.toString();
      }catch(e){}
    }
    
    const initialOrigin=new URL(t.url).origin;
    
    if(allowNavigation==='restricted'){
      view.webContents.on('will-navigate',(e,u)=>{
        if(u!==url&&u!==t.url)e.preventDefault();
      });
      view.webContents.setWindowOpenHandler(()=>({action:'deny'}));
    }else if(allowNavigation==='same-origin'){
      view.webContents.on('will-navigate',(e,u)=>{
        try{
          if(new URL(u).origin!==initialOrigin)e.preventDefault();
        }catch(x){
          e.preventDefault();
        }
      });
    }
    
    view.webContents.on('before-input-event',()=>markActivity());
    view.webContents.on('did-start-loading',()=>{
      if(!programmaticNavigation){
        markActivity();
      }
    });
    view.webContents.on('did-navigate',()=>{
      if(programmaticNavigation){
        programmaticNavigation=false;
      }else{
        markActivity();
      }
    });
    
    view.webContents.setAudioMuted(false);
    view.webContents.loadURL(url);
    
    view.webContents.on('did-finish-load',()=>{
      view.webContents.executeJavaScript(`
        ["mousedown","keydown","touchstart","scroll","click"].forEach(e=>{
          document.addEventListener(e,()=>{
            if(window.electronAPI?.notifyActivity){
              window.electronAPI.notifyActivity();
            }
          },true);
        });
      `).catch(()=>{});

      // Send pause button visibility on every page load to handle reloads
      const siteDuration=parseInt(t.duration)||0;
      const shouldShow=enablePauseButton&&siteDuration>0;
      view.webContents.send('pause-button-visibility',shouldShow);

      // Send keyboard button enabled status
      view.webContents.send('keyboard-button-enabled',enableKeyboardButton);
      console.log('[MAIN] Page loaded - sending keyboard-button-enabled: '+enableKeyboardButton);
      console.log('[MAIN] Page loaded - resending pause-button-visibility: '+shouldShow+' for '+t.url);
    });
    
    const isHidden=parseInt(t.duration)===-1;
    if(isHidden){
      hiddenViews.push(view);
      tabIndexToViewIndex[tabIdx]=-1;
    }else{
      views.push(view);
      tabIndexToViewIndex[tabIdx]=viewIndex;
      viewIndex++;
    }
  });
  
  const homeViewIdx=getHomeViewIndex();
  const startIndex=homeViewIdx>=0?homeViewIdx:0;
  
  if(views.length){
    setTimeout(()=>{
      // Check for boot flag FIRST - require password on boot if configured
      const bootFlag=path.join(__dirname,'.boot-flag');
      if(enablePasswordProtection&&lockoutPassword&&requirePasswordOnBoot&&fs.existsSync(bootFlag)){
        console.log('[LOCKOUT] Boot detected, requiring password BEFORE showing sites');
        fs.unlinkSync(bootFlag);
        showLockoutScreen();
        // Don't attach view or start timer - wait for password unlock
      }else{
        // Normal startup - show sites
        attachView(startIndex);
        startMasterTimer();
      }
    },1000);
  }
  
  ipcMain.on('swipe-left',()=>{nextTab();});
  ipcMain.on('swipe-right',()=>{prevTab();});
  ipcMain.on('show-power-menu',showPowerMenu);
  ipcMain.on('toggle-hidden',toggleHidden);
  ipcMain.on('user-activity',markActivity);
  ipcMain.on('show-keyboard',()=>{showHTMLKeyboard();});
  ipcMain.on('close-keyboard',()=>{closeHTMLKeyboard();});
  ipcMain.on('keyboard-activity',()=>{markKeyboardActivity();});
  ipcMain.on('show-pause-dialog',()=>{showPauseDialog();});
ipcMain.on('check-lockout-password',(event,hash)=>{    if(hash===lockoutPassword){      unlockScreen();    }else{      if(lockoutWindow&&!lockoutWindow.isDestroyed()){        lockoutWindow.webContents.send('password-incorrect');      }    }  });
  
  ipcMain.on('keyboard-type',(event,key)=>{
    markKeyboardActivity();
    
    let view=null;
    if(showingHidden&&hiddenViews[currentHiddenIndex]){
      view=hiddenViews[currentHiddenIndex];
    }else if(views[currentIndex]){
      view=views[currentIndex];
    }
    
    if(!view||!view.webContents)return;
    
    const safeKey=JSON.stringify(key).slice(1,-1);
    
    if(key==='Backspace'){
      view.webContents.executeJavaScript(`
        (function(){
          const el=document.activeElement;
          if(el&&(el.tagName==="INPUT"||el.tagName==="TEXTAREA")){
            const s=el.selectionStart||0;
            if(s>0){
              el.value=el.value.substring(0,s-1)+el.value.substring(el.selectionEnd||s);
              el.selectionStart=el.selectionEnd=s-1;
              el.dispatchEvent(new Event("input",{bubbles:true}));
            }
          }
        })();
      `).catch(()=>{});
    }else if(key==='Enter'){
      view.webContents.executeJavaScript(`
        (function(){
          const el=document.activeElement;
          if(el){
            if(el.tagName==="TEXTAREA"){
              const s=el.selectionStart||0;
              el.value=el.value.substring(0,s)+"\\n"+el.value.substring(el.selectionEnd||s);
              el.selectionStart=el.selectionEnd=s+1;
              el.dispatchEvent(new Event("input",{bubbles:true}));
            }else if(el.tagName==="INPUT"){
              const form=el.closest("form");
              if(form){
                form.dispatchEvent(new Event("submit",{bubbles:true,cancelable:true}));
              }
            }
          }
        })();
      `).catch(()=>{});
    }else if(key===' '){
      view.webContents.executeJavaScript(`
        (function(){
          const el=document.activeElement;
          if(el&&(el.tagName==="INPUT"||el.tagName==="TEXTAREA")){
            const s=el.selectionStart||0;
            el.value=el.value.substring(0,s)+" "+el.value.substring(el.selectionEnd||s);
            el.selectionStart=el.selectionEnd=s+1;
            el.dispatchEvent(new Event("input",{bubbles:true}));
          }
        })();
      `).catch(()=>{});
    }else{
      view.webContents.executeJavaScript(`
        (function(){
          const text="${safeKey}";
          const el=document.activeElement;
          if(el&&(el.tagName==="INPUT"||el.tagName==="TEXTAREA")){
            const s=el.selectionStart||0;
            const e=el.selectionEnd||s;
            el.value=el.value.substring(0,s)+text+el.value.substring(e);
            el.selectionStart=el.selectionEnd=s+text.length;
            el.dispatchEvent(new Event("input",{bubbles:true}));
            el.dispatchEvent(new Event("change",{bubbles:true}));
          }
        })();
      `).catch(()=>{});
    }
  });
  
  if(views.length>1){
    globalShortcut.register('Control+Tab',()=>{nextTab();});
    globalShortcut.register('Control+Shift+Tab',()=>{prevTab();});
    globalShortcut.register('Control+]',()=>{nextTab();});
    globalShortcut.register('Control+[',()=>{prevTab();});
    globalShortcut.register('Alt+Right',()=>{nextTab();});
    globalShortcut.register('Alt+Left',()=>{prevTab();});
  }
  
  globalShortcut.register('F10',toggleHidden);
  globalShortcut.register('Control+H',toggleHidden);
  globalShortcut.register('Escape',forceReturnToTabs);
  globalShortcut.register('Control+Alt+Delete',showPowerMenu);
  globalShortcut.register('Control+Alt+P',showPowerMenu);
  globalShortcut.register('Control+Alt+Escape',showPowerMenu);
  globalShortcut.register('Control+K',()=>{
    if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
      closeHTMLKeyboard();
    }else{
      showHTMLKeyboard();
    }
  });
  
  mainWindow.on('resize',()=>{
    const[w,h]=mainWindow.getContentSize();
    if(showingHidden&&hiddenViews[currentHiddenIndex]){
      hiddenViews[currentHiddenIndex].setBounds({x:0,y:0,width:w,height:h});
    }else if(views[currentIndex]){
      views[currentIndex].setBounds({x:0,y:0,width:w,height:h});
    }
  });
}

if(!app.requestSingleInstanceLock())app.quit();

app.on('certificate-error',(e,w,u,er,c,cb)=>{
  e.preventDefault();
  cb(true);
});

app.on('ready',createWindow);

app.on('will-quit',()=>{
  globalShortcut.unregisterAll();
  stopMasterTimer();
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.close();
  }
});

app.on('window-all-closed',()=>{
  if(process.platform!=='darwin')app.quit();
});

app.on('activate',()=>{
  if(BrowserWindow.getAllWindows().length===0)createWindow();
});
MAINJS
#############################################################################
###############################end of main.js################################
##############################################################################
echo "[14/27] Creating keyboard.html with shift display + 30s timeout..."
sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/keyboard.html" > /dev/null <<'KBHTML' 
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: rgba(0, 0, 0, 0.95);
      color: #ecf0f1;
      display: flex;
      flex-direction: column;
      justify-content: center;
      padding: 10px;
      overflow: hidden;
    }
    .keyboard { width: 100%; max-width: 1200px; margin: 0 auto; }
    .row { display: flex; justify-content: center; margin-bottom: 8px; gap: 6px; }
    .key {
      min-width: 60px; height: 60px;
      background: linear-gradient(135deg, #34495e 0%, #2c3e50 100%);
      border: 2px solid #4a5f7f; border-radius: 8px; color: white;
      font-size: 24px; font-weight: 600; cursor: pointer;
      display: flex; align-items: center; justify-content: center;
      transition: all 0.1s; user-select: none; box-shadow: 0 4px 8px rgba(0,0,0,0.3);
    }
    .key:active {
      transform: scale(0.95);
      background: linear-gradient(135deg, #3498db 0%, #2980b9 100%);
      border-color: #5dade2;
    }
    .key.space { flex: 3; }
    .key.wide { min-width: 90px; }
    .key.extra-wide { min-width: 120px; }
    .key.special {
      background: linear-gradient(135deg, #2c3e50 0%, #1a252f 100%);
      font-size: 16px;
    }
    .key.enter {
      background: linear-gradient(135deg, #27ae60 0%, #229954 100%);
      border-color: #52be80;
    }
    .key.backspace {
      background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
      border-color: #ec7063;
    }
    .key.shift, .key.caps {
      background: linear-gradient(135deg, #f39c12 0%, #d68910 100%);
      border-color: #f8c471;
    }
    .key.shift.active, .key.caps.active {
      background: linear-gradient(135deg, #16a085 0%, #138d75 100%);
      border-color: #48c9b0;
    }
    .header {
      text-align: center;
      margin-bottom: 10px;
      font-size: 16px;
      color: #bdc3c7;
    }
    .close-btn {
      position: absolute;
      top: 10px;
      right: 10px;
      width: 40px;
      height: 40px;
      background: rgba(231, 76, 60, 0.9);
      border: 2px solid #e74c3c;
      border-radius: 50%;
      color: white;
      font-size: 24px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.2s;
      z-index: 9999;
    }
    .close-btn:active {
      transform: scale(0.9);
      background: rgba(192, 57, 43, 0.9);
    }
  </style>
</head>
<body>
  <div class="close-btn" onclick="closeKeyboard()">×</div>
  
  <div class="keyboard">
    <div class="header">⌨️ Keyboard - Click icon or swipe to reopen</div>
    
    <!-- Number Row -->
    <div class="row">
      <div class="key" data-key="1" data-shift="!" onclick="typeKey(this)">1</div>
      <div class="key" data-key="2" data-shift="@" onclick="typeKey(this)">2</div>
      <div class="key" data-key="3" data-shift="#" onclick="typeKey(this)">3</div>
      <div class="key" data-key="4" data-shift="$" onclick="typeKey(this)">4</div>
      <div class="key" data-key="5" data-shift="%" onclick="typeKey(this)">5</div>
      <div class="key" data-key="6" data-shift="^" onclick="typeKey(this)">6</div>
      <div class="key" data-key="7" data-shift="&" onclick="typeKey(this)">7</div>
      <div class="key" data-key="8" data-shift="*" onclick="typeKey(this)">8</div>
      <div class="key" data-key="9" data-shift="(" onclick="typeKey(this)">9</div>
      <div class="key" data-key="0" data-shift=")" onclick="typeKey(this)">0</div>
      <div class="key" data-key="-" data-shift="_" onclick="typeKey(this)">-</div>
      <div class="key" data-key="=" data-shift="+" onclick="typeKey(this)">=</div>
      <div class="key backspace wide" onclick="typeKey(this)" data-special="Backspace">⌫</div>
    </div>
    
    <!-- Top Row -->
    <div class="row">
      <div class="key special wide" onclick="typeKey(this)" data-special="Tab">Tab</div>
      <div class="key" data-key="q" onclick="typeKey(this)">q</div>
      <div class="key" data-key="w" onclick="typeKey(this)">w</div>
      <div class="key" data-key="e" onclick="typeKey(this)">e</div>
      <div class="key" data-key="r" onclick="typeKey(this)">r</div>
      <div class="key" data-key="t" onclick="typeKey(this)">t</div>
      <div class="key" data-key="y" onclick="typeKey(this)">y</div>
      <div class="key" data-key="u" onclick="typeKey(this)">u</div>
      <div class="key" data-key="i" onclick="typeKey(this)">i</div>
      <div class="key" data-key="o" onclick="typeKey(this)">o</div>
      <div class="key" data-key="p" onclick="typeKey(this)">p</div>
      <div class="key" data-key="[" data-shift="{" onclick="typeKey(this)">[</div>
      <div class="key" data-key="]" data-shift="}" onclick="typeKey(this)">]</div>
      <div class="key" data-key="\\" data-shift="|" onclick="typeKey(this)">\</div>
    </div>
    
    <!-- Home Row -->
    <div class="row">
      <div class="key caps special extra-wide" onclick="toggleCaps()" id="caps-key">Caps</div>
      <div class="key" data-key="a" onclick="typeKey(this)">a</div>
      <div class="key" data-key="s" onclick="typeKey(this)">s</div>
      <div class="key" data-key="d" onclick="typeKey(this)">d</div>
      <div class="key" data-key="f" onclick="typeKey(this)">f</div>
      <div class="key" data-key="g" onclick="typeKey(this)">g</div>
      <div class="key" data-key="h" onclick="typeKey(this)">h</div>
      <div class="key" data-key="j" onclick="typeKey(this)">j</div>
      <div class="key" data-key="k" onclick="typeKey(this)">k</div>
      <div class="key" data-key="l" onclick="typeKey(this)">l</div>
      <div class="key" data-key=";" data-shift=":" onclick="typeKey(this)">;</div>
      <div class="key" data-key="'" data-shift='"' onclick="typeKey(this)">'</div>
      <div class="key enter extra-wide" onclick="typeKey(this)" data-special="Enter">↵</div>
    </div>
    
    <!-- Bottom Row -->
    <div class="row">
      <div class="key shift extra-wide" onclick="toggleShift()" id="shift-left">⇧</div>
      <div class="key" data-key="z" onclick="typeKey(this)">z</div>
      <div class="key" data-key="x" onclick="typeKey(this)">x</div>
      <div class="key" data-key="c" onclick="typeKey(this)">c</div>
      <div class="key" data-key="v" onclick="typeKey(this)">v</div>
      <div class="key" data-key="b" onclick="typeKey(this)">b</div>
      <div class="key" data-key="n" onclick="typeKey(this)">n</div>
      <div class="key" data-key="m" onclick="typeKey(this)">m</div>
      <div class="key" data-key="," data-shift="<" onclick="typeKey(this)">,</div>
      <div class="key" data-key="." data-shift=">" onclick="typeKey(this)">.</div>
      <div class="key" data-key="/" data-shift="?" onclick="typeKey(this)">/</div>
      <div class="key shift extra-wide" onclick="toggleShift()" id="shift-right">⇧</div>
    </div>
    
    <!-- Space Row -->
    <div class="row">
      <div class="key special" onclick="typeKey(this)" data-special="Control">Ctrl</div>
      <div class="key special" onclick="typeKey(this)" data-special="Alt">Alt</div>
      <div class="key space" onclick="typeKey(this)" data-special=" ">Space</div>
      <div class="key special" onclick="typeKey(this)" data-special="Alt">Alt</div>
      <div class="key special" onclick="typeKey(this)" data-special="Control">Ctrl</div>
    </div>
  </div>
  
  <script>
    const { ipcRenderer } = require('electron');
    let shiftPressed = false;
    let capsLock = false;
    
    // CRITICAL: Do NOT preventDefault on keyboard events
    // This allows physical keyboard to work alongside OSK
    window.addEventListener('keydown', (e) => {
      // Don't interfere with physical keyboard
      // Just update our visual state if needed
      if (e.key === 'CapsLock') {
        capsLock = !capsLock;
        updateCapsDisplay();
      }
    }, {passive: true});
    
    function updateKeyDisplay() {
      const keys = document.querySelectorAll('.key[data-key]');
      keys.forEach(key => {
        const baseKey = key.getAttribute('data-key');
        const shiftKey = key.getAttribute('data-shift');
        if (/^[a-z]$/.test(baseKey)) {
          const shouldBeUpper = (shiftPressed && !capsLock) || (!shiftPressed && capsLock);
          key.textContent = shouldBeUpper ? baseKey.toUpperCase() : baseKey.toLowerCase();
        } else if (shiftKey) {
          key.textContent = shiftPressed ? shiftKey : baseKey;
        }
      });
    }
    
    function typeKey(element) {
      const special = element.getAttribute('data-special');
      if (special) {
        ipcRenderer.send('keyboard-type', special);
        return;
      }
      
      const baseKey = element.getAttribute('data-key');
      const shiftKey = element.getAttribute('data-shift');
      let finalKey = baseKey;
      
      if (/^[a-z]$/.test(baseKey)) {
        const shouldBeUpper = (shiftPressed && !capsLock) || (!shiftPressed && capsLock);
        finalKey = shouldBeUpper ? baseKey.toUpperCase() : baseKey.toLowerCase();
      } else if (shiftPressed && shiftKey) {
        finalKey = shiftKey;
      }
      
      ipcRenderer.send('keyboard-type', finalKey);
      
      if (shiftPressed) {
        shiftPressed = false;
        updateShiftDisplay();
        updateKeyDisplay();
      }
    }
    
    function toggleShift() {
      shiftPressed = !shiftPressed;
      updateShiftDisplay();
      updateKeyDisplay();
    }
    
    function toggleCaps() {
      capsLock = !capsLock;
      updateCapsDisplay();
      updateKeyDisplay();
    }
    
    function updateShiftDisplay() {
      document.querySelectorAll('.shift').forEach(key => {
        if (shiftPressed) key.classList.add('active');
        else key.classList.remove('active');
      });
    }
    
    function updateCapsDisplay() {
      const capsKey = document.getElementById('caps-key');
      if (capsLock) capsKey.classList.add('active');
      else capsKey.classList.remove('active');
    }
    
    function closeKeyboard() {
      ipcRenderer.send('close-keyboard');
    }
    
    updateKeyDisplay();
    
    // Tell main process we're ready
    ipcRenderer.send('keyboard-ready');
  </script>
</body>
</html>
KBHTML

echo "[14.5/27] Creating pause-dialog.html..."
sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/pause-dialog.html" > /dev/null <<'PAUSEHTML'
<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: rgba(0,0,0,0.9);
      color: #ecf0f1;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      height: 100vh;
      padding: 40px;
    }
    .container { text-align: center; max-width: 600px; }
    h2 { font-size: 32px; margin-bottom: 20px; }
    .message { font-size: 20px; margin-bottom: 30px; line-height: 1.5; }
    .options {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 15px;
      margin: 30px 0;
    }
    .btn {
      padding: 20px 40px;
      font-size: 18px;
      cursor: pointer;
      border: none;
      border-radius: 12px;
      font-weight: bold;
      transition: all 0.2s;
      color: white;
    }
    .btn-extend { background: #e67e22; }
    .btn-extend:hover { background: #d35400; }
    .btn-extend:active { background: #ba4a00; }

    .btn-cancel {
      background: #95a5a6;
      grid-column: 1 / -1;
      font-size: 16px;
      padding: 15px;
    }
    .btn-cancel:hover { background: #7f8c8d; }

    .info {
      font-size: 14px;
      color: #95a5a6;
      margin-top: 20px;
      line-height: 1.6;
    }
  </style>
</head>
<body>
  <div class="container">
    <h2>⏸️ Pause Timers</h2>
    <div class="message">
      Select how long to pause rotation and inactivity timers:
    </div>

    <div class="options">
      <button class="btn btn-extend" onclick="selectTime(15)">
        🍿 15 minutes
      </button>

      <button class="btn btn-extend" onclick="selectTime(30)">
        ⏱️ 30 minutes
      </button>

      <button class="btn btn-extend" onclick="selectTime(60)">
        🎬 1 hour
      </button>

      <button class="btn btn-extend" onclick="selectTime(120)">
        📺 2 hours
      </button>

      <button class="btn btn-cancel" onclick="selectTime(0)">
        ✗ Cancel
      </button>
    </div>

    <div class="info">
      After the time expires, normal rotation and return-to-home logic will resume.
    </div>
  </div>

  <script>
    const {ipcRenderer} = require('electron');

    function selectTime(minutes) {
      ipcRenderer.send('pause-time-selected', minutes);
    }
  </script>
</body>
</html>
PAUSEHTML

echo "[15/27] Creating PIN entry dialog..."
    sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/pin-entry.html" > /dev/null <<'PINHTML'
<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #2c3e50;
      color: #ecf0f1;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      height: 100vh;
      padding: 20px;
    }
    .container { width: 100%; max-width: 400px; }
    h2 { text-align: center; margin-bottom: 30px; font-size: 24px; }
    #pin-display {
      width: 100%;
      padding: 20px;
      font-size: 48px;
      text-align: center;
      margin: 20px 0;
      border: 3px solid #34495e;
      border-radius: 12px;
      background: #34495e;
      color: #ecf0f1;
      letter-spacing: 20px;
      min-height: 90px;
      line-height: 50px;
      font-family: monospace;
    }
    #error { color: #e74c3c; text-align: center; display: none; margin: 10px 0; font-weight: bold; font-size: 18px; }
    .numpad { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 20px 0; }
    .numpad button {
      padding: 30px;
      font-size: 32px;
      border: none;
      border-radius: 12px;
      background: #34495e;
      color: #ecf0f1;
      cursor: pointer;
      font-weight: bold;
      transition: background 0.2s;
    }
    .numpad button:active { background: #3498db; }
    .numpad button:hover { background: #475d6d; }
    .actions { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 20px; }
    .btn { padding: 20px; font-size: 20px; cursor: pointer; border: none; border-radius: 12px; font-weight: bold; }
    #clear { background: #f39c12; color: white; }
    #backspace { background: #e67e22; color: white; }
    #submit { background: #27ae60; color: white; }
    #cancel { background: #e74c3c; color: white; }
    .info { text-align: center; font-size: 14px; color: #95a5a6; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <h2>🔒 Enter PIN</h2>
    <div id="pin-display">••••</div>
    <div id="error">❌ Incorrect PIN</div>
    <div class="numpad">
      <button onclick="addDigit('1')">1</button>
      <button onclick="addDigit('2')">2</button>
      <button onclick="addDigit('3')">3</button>
      <button onclick="addDigit('4')">4</button>
      <button onclick="addDigit('5')">5</button>
      <button onclick="addDigit('6')">6</button>
      <button onclick="addDigit('7')">7</button>
      <button onclick="addDigit('8')">8</button>
      <button onclick="addDigit('9')">9</button>
      <button id="clear" onclick="clearPin()">Clear</button>
      <button onclick="addDigit('0')">0</button>
      <button id="backspace" onclick="backspace()">⌫</button>
    </div>
    <div class="actions">
      <button class="btn" id="submit" onclick="submitPin()">✓ Submit</button>
      <button class="btn" id="cancel" onclick="cancel()">✗ Cancel</button>
    </div>
    <div class="info">Default PIN: 1234 (4-8 digits)</div>
  </div>
  <script>
    const {ipcRenderer} = require('electron');
    const fs = require('fs');
    const path = require('path');
    const pinFile = path.join(__dirname, '.jitsi-pin');
    let correctPin = '1234';
    let enteredPin = '';
    try {
      const stored = fs.readFileSync(pinFile, 'utf8').trim();
      if (stored !== 'NOPIN') correctPin = stored;
      else correctPin = null;
    } catch(e) {}
    function updateDisplay() {
      const display = document.getElementById('pin-display');
      if (enteredPin.length === 0) {
        display.textContent = '••••';
        display.style.color = '#7f8c8d';
      } else {
        display.textContent = '•'.repeat(enteredPin.length);
        display.style.color = '#ecf0f1';
      }
    }
    function addDigit(digit) {
      if (enteredPin.length < 8) {
        enteredPin += digit;
        updateDisplay();
        document.getElementById('error').style.display = 'none';
      }
    }
    function backspace() { enteredPin = enteredPin.slice(0, -1); updateDisplay(); }
    function clearPin() { enteredPin = ''; updateDisplay(); document.getElementById('error').style.display = 'none'; }
    function submitPin() {
      if (enteredPin.length < 4) {
        document.getElementById('error').textContent = '❌ PIN must be 4-8 digits';
        document.getElementById('error').style.display = 'block';
        return;
      }
      if (correctPin === null || enteredPin === correctPin) {
        ipcRenderer.send('pin-correct');
      } else {
        document.getElementById('error').textContent = '❌ Incorrect PIN';
        document.getElementById('error').style.display = 'block';
        enteredPin = '';
        updateDisplay();
      }
    }
    function cancel() { ipcRenderer.send('pin-cancelled'); }
    document.addEventListener('keydown', (e) => {
      if (e.key >= '0' && e.key <= '9') addDigit(e.key);
      else if (e.key === 'Backspace') backspace();
      else if (e.key === 'Enter') submitPin();
      else if (e.key === 'Escape') cancel();
    });
    updateDisplay();
  </script>
</body>
</html>
PINHTML
    
echo "[15/27] Creating inactivity prompt..."
    sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/inactivity-prompt-extended.html" > /dev/null <<'INACTHTML'
<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: rgba(0,0,0,0.9);
      color: #ecf0f1;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      height: 100vh;
      padding: 40px;
    }
    .container { text-align: center; max-width: 600px; }
    h2 { font-size: 32px; margin-bottom: 20px; }
    .message { font-size: 20px; margin-bottom: 20px; line-height: 1.5; }
    .countdown { font-size: 72px; font-weight: bold; color: #e74c3c; margin: 20px 0; }
    .options { 
      display: grid; 
      grid-template-columns: 1fr 1fr; 
      gap: 15px; 
      margin: 30px 0;
    }
    .btn {
      padding: 20px 40px;
      font-size: 18px;
      cursor: pointer;
      border: none;
      border-radius: 12px;
      font-weight: bold;
      transition: all 0.2s;
      color: white;
    }
    .btn-primary {
      background: #27ae60;
      grid-column: 1 / -1;
    }
    .btn-primary:hover { background: #229954; }
    .btn-primary:active { background: #1e8449; }
    
    .btn-extend { background: #3498db; }
    .btn-extend:hover { background: #2980b9; }
    .btn-extend:active { background: #21618c; }
    
    .btn-home {
      background: #95a5a6;
      grid-column: 1 / -1;
      font-size: 14px;
      padding: 12px;
    }
    .btn-home:hover { background: #7f8c8d; }
    
    .info {
      font-size: 14px;
      color: #95a5a6;
      margin-top: 20px;
      line-height: 1.6;
    }
  </style>
</head>
<body>
  <div class="container">
    <h2>👋 Are you still here?</h2>
    <div class="message">
      No activity detected. Choose an option:
    </div>
    <div class="countdown" id="countdown">15</div>
    
    <div class="options">
      <button class="btn btn-primary" onclick="imHere(0)">
        ✓ Yes, I'm here!
      </button>
      
      <button class="btn btn-extend" onclick="imHere(15)">
        🍿 15 more minutes
      </button>
      
      <button class="btn btn-extend" onclick="imHere(30)">
        ⏱️ 30 more minutes
      </button>
      
      <button class="btn btn-extend" onclick="imHere(60)">
        🎬 1 hour
      </button>
      
      <button class="btn btn-extend" onclick="imHere(120)">
        📺 2 hours
      </button>
      
      <button class="btn btn-home" onclick="goHome()">
        🏠 Return to home now
      </button>
    </div>
    
    <div class="info">
      ℹ️ Extensions pause the inactivity timer<br>
      Media playback (video/audio) automatically pauses the timer<br>
      Maximum extension: 4 hours (safety timeout)
    </div>
  </div>
  <script>
    const {ipcRenderer} = require('electron');
    let count = 15;
    const interval = setInterval(() => {
      count--;
      document.getElementById('countdown').textContent = count;
      if (count <= 0) {
        clearInterval(interval);
      }
    }, 1000);
    
    function imHere(minutes) {
      clearInterval(interval);
      console.log('[PROMPT] User selected: '+(minutes===0?'Continue':minutes+' minutes'));
      ipcRenderer.send('user-still-here', minutes);
    }

   function goHome() {
      clearInterval(interval);
      console.log('[PROMPT] User requested immediate home return');
      ipcRenderer.send('user-still-here', -1);
    }
    
    document.addEventListener('keydown', (e) => {
      if (e.key === ' ' || e.key === 'Enter') {
        e.preventDefault();
        imHere(0);
      } else if (e.key === 'Escape') {
        goHome();
      }
    });
  </script>
</body>
</html>
INACTHTML
    
    echo "1234" | sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/.jitsi-pin" >/dev/null
    sudo -u "$KIOSK_USER" chmod 600 "$KIOSK_DIR/.jitsi-pin"
    log_success "Default PIN: 1234"
###########################################################################
############################start-preload##################################
###########################################################################
sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/preload.js" > /dev/null <<'PRELOAD'
const {contextBridge,ipcRenderer}=require('electron');

contextBridge.exposeInMainWorld('electronAPI',{
  notifyActivity:()=>ipcRenderer.send('user-activity'),
  showKeyboard:()=>ipcRenderer.send('show-keyboard'),
  closeKeyboard:()=>ipcRenderer.send('close-keyboard'),
  keyboardActivity:()=>ipcRenderer.send('keyboard-activity'),
  showPauseDialog:()=>ipcRenderer.send('show-pause-dialog')
});

// Pause button state (MUST be outside DOMContentLoaded to persist across page loads)
let pauseButton=null;
let pauseButtonShouldShow=false;
let pauseButtonShown=false;
let pauseButtonHideTimer=null;
const PAUSE_BUTTON_HIDE_DELAY=5000; // Hide after 5 seconds of inactivity

// Pause button functions (must be outside DOMContentLoaded for IPC listener)
function createPauseButton(){
  if(pauseButton)return;

  pauseButton=document.createElement('div');
  pauseButton.id='electron-pause-button';
  pauseButton.innerHTML='<div style="display:flex;gap:4px;"><div style="width:6px;height:24px;background:white;border-radius:2px;"></div><div style="width:6px;height:24px;background:white;border-radius:2px;"></div></div>';
  pauseButton.title='Pause rotation';
  pauseButton.style.cssText=`
    position:fixed;bottom:20px;left:20px;width:60px;height:60px;
    background:rgba(230,126,34,0.95);border:3px solid rgba(255,255,255,0.9);
    border-radius:50%;display:none;align-items:center;justify-content:center;
    font-size:32px;cursor:pointer;z-index:999999;
    box-shadow:0 4px 12px rgba(0,0,0,0.4);user-select:none;
  `;

  pauseButton.addEventListener('click',(e)=>{
    e.preventDefault();
    e.stopPropagation();
    ipcRenderer.send('show-pause-dialog');
  });

  document.body.appendChild(pauseButton);
}

function showPauseButton(){
  if(!pauseButton)createPauseButton();
  pauseButton.style.display='flex';
  pauseButtonShown=true;

  // Clear existing hide timer
  if(pauseButtonHideTimer){
    clearTimeout(pauseButtonHideTimer);
    pauseButtonHideTimer=null;
  }

  // Set new hide timer - button will auto-hide after inactivity
  pauseButtonHideTimer=setTimeout(()=>{
    console.log('[PAUSE-BTN] Auto-hiding after '+PAUSE_BUTTON_HIDE_DELAY+'ms inactivity');
    hidePauseButton();
  },PAUSE_BUTTON_HIDE_DELAY);
}

function hidePauseButton(){
  if(pauseButtonHideTimer){
    clearTimeout(pauseButtonHideTimer);
    pauseButtonHideTimer=null;
  }
  if(pauseButton){
    pauseButton.style.display='none';
    pauseButtonShown=false;
  }
}

// Declare variables at top level so IPC handlers and DOMContentLoaded can share them
let keyboardButtonEnabled=true;
let keyboardVisible=false;
let keyboardIcon=null;

// Listen for pause button visibility control from main process
// CRITICAL: This must be outside DOMContentLoaded so it doesn't reset on page load
ipcRenderer.on('pause-button-visibility',(event,shouldShow)=>{
  console.log('[PAUSE-BTN] Visibility update: shouldShow='+shouldShow);
  pauseButtonShouldShow=shouldShow;
  if(!shouldShow){
    // If button should not show on this site, hide it immediately
    console.log('[PAUSE-BTN] Hiding button (manual site)');
    hidePauseButton();
  }else{
    console.log('[PAUSE-BTN] Button enabled - will show on user interaction');
  }
  // If shouldShow is true, button will appear on user interaction
});

ipcRenderer.on('keyboard-button-enabled',(event,enabled)=>{
  keyboardButtonEnabled=enabled;
  console.log('[KEYBOARD-BTN] Keyboard button enabled: '+enabled);
  // Note: keyboardIcon may not exist yet if page hasn't loaded
  if(keyboardIcon&&!enabled){
    keyboardIcon.style.display='none';
  }
});

window.addEventListener('DOMContentLoaded',()=>{
  document.addEventListener('contextmenu',e=>e.preventDefault());

  const SWIPE_THRESHOLD=120;
  const SWIPE_MAX_TIME=500;
  const SWIPE_TOLERANCE=50;

  let touchStartX=0;
  let touchStartY=0;
  let touchStartTime=0;
  let fingerCount=0;
  let lastKeyboardRequest=0;
  let keyboardAutoClosedThisSession=false;
  const KEYBOARD_REQUEST_THROTTLE=1000;
  
  const activityEvents=[
    'mousedown','mouseup','mousemove','click','dblclick',
    'wheel','scroll',
    'keydown','keyup','keypress',
    'touchstart','touchmove','touchend',
    'pointerdown','pointerup','pointermove',
    'input','change'
  ];
  
  let lastActivityNotification=0;
  const ACTIVITY_THROTTLE=1000;
  
  function notifyActivity(){
    const now=Date.now();
    if(now-lastActivityNotification>ACTIVITY_THROTTLE){
      if(window.electronAPI?.notifyActivity){
        window.electronAPI.notifyActivity();
        lastActivityNotification=now;
      }
    }
  }
  
  activityEvents.forEach(eventType=>{
    document.addEventListener(eventType,notifyActivity,{
      passive:true,
      capture:true
    });
  });
  
  ipcRenderer.on('keyboard-state-changed',(event,visible)=>{
    keyboardVisible=visible;
    if(visible){
      showKeyboardIcon();
      keyboardAutoClosedThisSession=false;
    }else{
      hideKeyboardIcon();
    }
  });
  
  ipcRenderer.on('keyboard-auto-closed',()=>{
    keyboardAutoClosedThisSession=true;
  });
  
  function createKeyboardIcon(){
    if(keyboardIcon||!keyboardButtonEnabled)return;
    
    
    keyboardIcon=document.createElement('div');
    keyboardIcon.id='electron-keyboard-icon';
    keyboardIcon.innerHTML='⌨️';
    keyboardIcon.style.cssText=`
      position:fixed;bottom:20px;right:20px;width:60px;height:60px;
      background:rgba(52,152,219,0.95);border:3px solid rgba(255,255,255,0.9);
      border-radius:50%;display:none;align-items:center;justify-content:center;
      font-size:32px;cursor:pointer;z-index:999999;
      box-shadow:0 4px 12px rgba(0,0,0,0.4);user-select:none;
    `;
    
    keyboardIcon.addEventListener('click',(e)=>{
      e.preventDefault();
      e.stopPropagation();
      keyboardAutoClosedThisSession=false;
      if(keyboardVisible){
        ipcRenderer.send('close-keyboard');
      }else{
        ipcRenderer.send('show-keyboard');
      }
    });
    
    document.body.appendChild(keyboardIcon);
  }
  
  function showKeyboardIcon(){
    if(!keyboardButtonEnabled)return;
    if(!keyboardIcon)createKeyboardIcon();
    if(keyboardIcon)keyboardIcon.style.display='flex';
  }
  
  function hideKeyboardIcon(){
    if(keyboardIcon)keyboardIcon.style.display='none';
  }
  
  function isTextInput(el){
    if(!el)return false;
    const tag=(el.tagName||'').toLowerCase();
    const type=(el.type||'').toLowerCase();
    const editable=el.isContentEditable||el.contentEditable==='true';
    return(tag==='input'&&['text','email','password','search','tel','url','number'].includes(type))||tag==='textarea'||editable;
  }
  
  document.addEventListener('focusin',(e)=>{
    if(keyboardButtonEnabled&&isTextInput(e.target)){
      showKeyboardIcon();
    }
  },true);
  
  document.addEventListener('focusout',(e)=>{
    if(keyboardButtonEnabled&&isTextInput(e.target)){
      setTimeout(()=>{
        if(!isTextInput(document.activeElement)){
          hideKeyboardIcon();
        }
      },100);
    }
  },true);
  
  document.addEventListener('mousedown',(e)=>{
    if(keyboardButtonEnabled&&isTextInput(e.target)){
      if(keyboardVisible){
        if(window.electronAPI?.keyboardActivity){
          window.electronAPI.keyboardActivity();
        }
      }else{
        keyboardAutoClosedThisSession=false;
        const now=Date.now();
        if(now-lastKeyboardRequest>KEYBOARD_REQUEST_THROTTLE){
          lastKeyboardRequest=now;
          setTimeout(()=>ipcRenderer.send('show-keyboard'),50);
        }
      }
    }
  },true);
  
  document.addEventListener('touchstart',e=>{
    if(e.touches.length>=1){
      touchStartX=e.touches[0].clientX;
      touchStartY=e.touches[0].clientY;
      touchStartTime=Date.now();
      fingerCount=e.touches.length;
    }
  },{passive:true});
  
  document.addEventListener('touchend',e=>{
    if(e.changedTouches.length>=1){
      const touchEndX=e.changedTouches[0].clientX;
      const touchEndY=e.changedTouches[0].clientY;
      const deltaX=touchEndX-touchStartX;
      const deltaY=touchEndY-touchStartY;
      const deltaTime=Date.now()-touchStartTime;
      
      if(deltaTime>SWIPE_MAX_TIME)return;
      
      const absX=Math.abs(deltaX);
      const absY=Math.abs(deltaY);
      
      if(fingerCount===3&&absY>SWIPE_THRESHOLD&&absX<SWIPE_TOLERANCE&&deltaY<0){
        ipcRenderer.send('toggle-hidden');
      }
      else if(fingerCount===2&&absY>SWIPE_THRESHOLD&&absX<SWIPE_TOLERANCE&&deltaY>0){
        if(keyboardButtonEnabled){
          keyboardAutoClosedThisSession=false;
          if(keyboardVisible){
            ipcRenderer.send('close-keyboard');
          }else{
            ipcRenderer.send('show-keyboard');
          }
        }
      }
      else if(fingerCount===2&&absX>SWIPE_THRESHOLD&&absY<SWIPE_TOLERANCE){
        ipcRenderer.send(deltaX>0?'swipe-right':'swipe-left');
      }
      else if(fingerCount===1&&absX<30&&absY<30){
        const target=document.elementFromPoint(touchEndX,touchEndY);
        if(keyboardButtonEnabled&&target&&isTextInput(target)&&!keyboardVisible){
          keyboardAutoClosedThisSession=false;
          const now=Date.now();
          if(now-lastKeyboardRequest>KEYBOARD_REQUEST_THROTTLE){
            lastKeyboardRequest=now;
            setTimeout(()=>ipcRenderer.send('show-keyboard'),50);
          }
        }
      }
    }
  },{passive:true});

  // Show pause button on user interaction (for rotation sites only)
  let lastUserInteraction=0;
  const USER_INTERACTION_THROTTLE=500;

  function handleUserInteraction(eventType){
    const now=Date.now();
    if(now-lastUserInteraction<USER_INTERACTION_THROTTLE)return;
    lastUserInteraction=now;

    console.log('[PAUSE-BTN] User interaction ('+eventType+') - shouldShow='+pauseButtonShouldShow+', shown='+pauseButtonShown);
    // Show/refresh pause button if allowed on this site
    if(pauseButtonShouldShow){
      if(!pauseButtonShown){
        console.log('[PAUSE-BTN] Showing pause button now');
      }else{
        console.log('[PAUSE-BTN] Resetting auto-hide timer');
      }
      showPauseButton(); // This will reset the hide timer
    }
  }

  // Show pause button on any user interaction
  const pauseButtonTriggers=['mousedown','touchstart','keydown'];
  pauseButtonTriggers.forEach(eventType=>{
    document.addEventListener(eventType,()=>handleUserInteraction(eventType),{passive:true,capture:true});
  });
});
PRELOAD
############################################################################
################################end-preload.js##############################
############################################################################
    echo "[16/27] Creating package.json..."
    sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/package.json" > /dev/null <<'PKGJSON'
{
  "name": "kiosk-app",
  "version": "1.0.0",
  "main": "main.js",
  "dependencies": {
    "electron": "^33.4.11"
  }
}
PKGJSON

    echo "[17/27] Installing Electron packages..."
    echo "Note: npm may show deprecation warnings (safe to ignore)"
    sudo -u "$KIOSK_USER" bash -lc "cd '$KIOSK_DIR' && npm install --unsafe-perm"
    
    local sandbox="$KIOSK_DIR/node_modules/electron/dist/chrome-sandbox"
    if [[ -f "$sandbox" ]]; then
        sudo chown root:root "$sandbox"
        sudo chmod 4755 "$sandbox"
    fi
    
sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/start.sh" > /dev/null <<'LAUNCHER'
#!/bin/bash
cd /home/kiosk/kiosk-app

# Wait for network
for i in {1..30}; do
  ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && break
  sleep 2
done

export DISPLAY=:0
export ELECTRON_ENABLE_LOGGING=1

# Ensure PipeWire is running
systemctl --user is-active --quiet pipewire || systemctl --user start pipewire
systemctl --user is-active --quiet pipewire-pulse || systemctl --user start pipewire-pulse
systemctl --user is-active --quiet wireplumber || systemctl --user start wireplumber

# Wait for PipeWire
for i in {1..10}; do
    pactl info >/dev/null 2>&1 && break
    sleep 1
done

exec node_modules/electron/dist/electron . \
  --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage \
  --enable-features=UseOzonePlatform --ozone-platform=x11 \
  --enable-audio-service-sandbox=false --autoplay-policy=no-user-gesture-required \
  2>&1 | tee -a /home/kiosk/electron.log
LAUNCHER
    sudo chmod +x "$KIOSK_DIR/start.sh"
    
    echo "[18/27] Configuring Openbox with AGGRESSIVE screen keep-alive..."
    sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.config/openbox" "$KIOSK_HOME/.config/pulse"

    # Create empty xbindkeysrc to prevent errors
    sudo -u "$KIOSK_USER" touch "$KIOSK_HOME/.xbindkeysrc"

sudo -u "$KIOSK_USER" tee "$KIOSK_HOME/.config/openbox/autostart" > /dev/null <<'AUTOSTART'
#!/bin/bash

# AGGRESSIVE DPMS disable - multiple methods
xset s off
xset s noblank
xset -dpms
xset s 0 0
xset dpms 0 0 0
xset dpms force on

# Keep screen on forever - watchdog (schedule-aware)
(
  while true; do
    sleep 300  # Every 5 minutes

    # Check if display schedule is active
    schedule_active=false
    if systemctl is-active --quiet kiosk-display-off.timer && systemctl is-active --quiet kiosk-display-on.timer; then
      # Get display off and on times from systemd timers
      doff=$(systemctl cat kiosk-display-off.timer 2>/dev/null | grep "^OnCalendar=" | sed 's/.*\*-\*-\* //' | sed 's/:00$//')
      don=$(systemctl cat kiosk-display-on.timer 2>/dev/null | grep "^OnCalendar=" | sed 's/.*\*-\*-\* //' | sed 's/:00$//')

      if [ -n "$doff" ] && [ -n "$don" ]; then
        # Get current time in HH:MM format
        current_time=$(date +%H:%M)

        # Convert times to minutes since midnight for comparison
        # Using 10# prefix to force decimal interpretation (fixes octal bug for 08:xx and 09:xx times)
        current_mins=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
        off_mins=$(( 10#$(echo "$doff" | cut -d: -f1) * 60 + 10#$(echo "$doff" | cut -d: -f2) ))
        on_mins=$(( 10#$(echo "$don" | cut -d: -f1) * 60 + 10#$(echo "$don" | cut -d: -f2) ))

        # Check if we're in the "display off" window
        if [ "$off_mins" -lt "$on_mins" ]; then
          # Normal case: off time is before on time (e.g., 22:00 to 06:00 next day)
          if [ "$current_mins" -ge "$off_mins" ] && [ "$current_mins" -lt "$on_mins" ]; then
            schedule_active=true
          fi
        else
          # Overnight case: off time is after on time (e.g., 06:00 to 22:00)
          if [ "$current_mins" -ge "$off_mins" ] || [ "$current_mins" -lt "$on_mins" ]; then
            schedule_active=true
          fi
        fi
      fi
    fi

    # Only force display on if NOT in scheduled off period
    if [ "$schedule_active" = "false" ]; then
      xset s reset 2>/dev/null
      xset dpms force on 2>/dev/null
    fi
  done
) &

# Start PipeWire user services
systemctl --user start pipewire pipewire-pulse wireplumber
sleep 3

# Wait for PipeWire to be ready
for i in {1..15}; do
    pactl info >/dev/null 2>&1 && break
    sleep 1
done

# Wait for ALSA devices
for i in {1..10}; do
    pactl list sinks short | grep -q alsa && break
    sleep 1
done

# Set audio levels (speakers 100%, mic 100%, mic unmuted)
pactl set-sink-volume @DEFAULT_SINK@ 100%
pactl set-source-volume @DEFAULT_SOURCE@ 100%
pactl set-source-mute @DEFAULT_SOURCE@ 0

# Audio watchdog - checks every 30 seconds (quiet hours aware)
(
  while true; do
    sleep 30

    # Check if quiet hours is active
    quiet_active=false
    if systemctl is-active --quiet kiosk-quiet-start.timer && systemctl is-active --quiet kiosk-quiet-end.timer; then
      # Get quiet hours start and end times from systemd timers
      qstart=$(systemctl cat kiosk-quiet-start.timer 2>/dev/null | grep "^OnCalendar=" | sed 's/.*\*-\*-\* //' | sed 's/:00$//')
      qend=$(systemctl cat kiosk-quiet-end.timer 2>/dev/null | grep "^OnCalendar=" | sed 's/.*\*-\*-\* //' | sed 's/:00$//')

      if [ -n "$qstart" ] && [ -n "$qend" ]; then
        # Convert times to minutes since midnight for comparison
        # Using 10# prefix to force decimal interpretation (fixes octal bug for 08:xx and 09:xx times)
        current_mins=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
        start_mins=$(( 10#$(echo "$qstart" | cut -d: -f1) * 60 + 10#$(echo "$qstart" | cut -d: -f2) ))
        end_mins=$(( 10#$(echo "$qend" | cut -d: -f1) * 60 + 10#$(echo "$qend" | cut -d: -f2) ))

        # Check if we're in quiet hours window
        if [ "$start_mins" -lt "$end_mins" ]; then
          # Normal case: start time is before end time (e.g., 08:00 to 17:00)
          if [ "$current_mins" -ge "$start_mins" ] && [ "$current_mins" -lt "$end_mins" ]; then
            quiet_active=true
          fi
        else
          # Overnight case: start time is after end time (e.g., 22:00 to 07:00)
          if [ "$current_mins" -ge "$start_mins" ] || [ "$current_mins" -lt "$end_mins" ]; then
            quiet_active=true
          fi
        fi
      fi
    fi

    # Check if PipeWire is running
    if ! pactl info >/dev/null 2>&1; then
      logger "KIOSK: Audio dead, restarting PipeWire"
      systemctl --user restart pipewire pipewire-pulse wireplumber
      sleep 5
      # Only restore audio levels if NOT in quiet hours
      if [ "$quiet_active" = "false" ]; then
        pactl set-sink-volume @DEFAULT_SINK@ 100%
        pactl set-source-volume @DEFAULT_SOURCE@ 100%
        pactl set-source-mute @DEFAULT_SOURCE@ 0
      fi
    fi

    # Check if PTT service is running (only if not in quiet hours)
    if [ "$quiet_active" = "false" ]; then
      if ! systemctl is-active --quiet jitsi-ptt; then
        logger "KIOSK: PTT service dead, restarting"
        systemctl restart jitsi-ptt
      fi

      # Unmute mic (in case Jitsi muted it)
      pactl set-source-mute @DEFAULT_SOURCE@ 0 2>/dev/null
    fi
  done
) &

# Other services
unclutter -idle 0.1 -root &
XDG_RUNTIME_DIR=/run/user/$(id -u) xbindkeys &

# Create boot flag for password requirement on boot
touch /home/kiosk/kiosk-app/.boot-flag

# Start kiosk app AFTER audio is ready
sleep 2
/home/kiosk/kiosk-app/start.sh &
AUTOSTART
    sudo chmod 750 "$KIOSK_HOME/.config/openbox/autostart"
    
    if lspci | grep -i "VGA.*Intel" >/dev/null 2>&1; then
        sudo mkdir -p /etc/X11/xorg.conf.d/
        sudo tee /etc/X11/xorg.conf.d/20-intel.conf > /dev/null <<'EOF'
Section "Device"
    Identifier "Intel Graphics"
    Driver "intel"
    Option "AccelMethod" "sna"
    Option "TearFree" "true"
    Option "DRI" "3"
EndSection
EOF
    fi

    # SECURITY: Disable VT switching and dangerous X server key combinations
    sudo mkdir -p /etc/X11/xorg.conf.d/
    sudo tee /etc/X11/xorg.conf.d/10-serverflags.conf > /dev/null <<'EOF'
Section "ServerFlags"
    # Disable Ctrl+Alt+Backspace (X server kill)
    Option "DontZap" "true"

    # Disable VT switching (Ctrl+Alt+F1-F12)
    Option "DontVTSwitch" "true"

    # Don't allow clients to disconnect on exit
    Option "AllowClosedownGrabs" "false"
EndSection
EOF

    echo "[19/27] Configuring autologin..."
    sudo mkdir -p /etc/lightdm/lightdm.conf.d
    sudo tee /etc/lightdm/lightdm.conf.d/10-kiosk.conf > /dev/null <<EOF
[SeatDefaults]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=openbox
autologin-session=openbox

# SECURITY: Greeter security settings
greeter-hide-users=true
greeter-show-manual-login=false
allow-guest=false
EOF
    
    echo "[20/27] Configuring firewall..."
    sudo ufw --force enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    
    echo "[21/27] Configuring power management..."
    sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
    sudo tee /etc/polkit-1/localauthority/50-local.d/kiosk-power.pkla > /dev/null <<'EOF'
[Allow kiosk power operations]
Identity=unix-user:kiosk
Action=org.freedesktop.login1.power-off;org.freedesktop.login1.power-off-multiple-sessions;org.freedesktop.login1.reboot;org.freedesktop.login1.reboot-multiple-sessions;org.freedesktop.login1.suspend;org.freedesktop.login1.suspend-multiple-sessions
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
    
    echo "[22/27] Configuring volume controls..."
    sudo tee /usr/local/bin/kiosk-volume-up > /dev/null <<'EOF'
#!/bin/bash
CURRENT=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oE '[0-9]+%' | head -1 | tr -d '%')
NEW=$((CURRENT + 5))
[[ $NEW -gt 100 ]] && NEW=100
pactl set-sink-volume @DEFAULT_SINK@ ${NEW}%
EOF
    sudo chmod +x /usr/local/bin/kiosk-volume-up
    
    sudo tee /usr/local/bin/kiosk-volume-down > /dev/null <<'EOF'
#!/bin/bash
CURRENT=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oE '[0-9]+%' | head -1 | tr -d '%')
NEW=$((CURRENT - 5))
[[ $NEW -lt 0 ]] && NEW=0
pactl set-sink-volume @DEFAULT_SINK@ ${NEW}%
EOF
    sudo chmod +x /usr/local/bin/kiosk-volume-down
    
    echo "[23/27] Installing PTT service (spacebar hardcoded)..."
    
    sudo tee /usr/local/bin/jitsi-ptt-service.py > /dev/null <<'SMARTPTT'
#!/usr/bin/env python3
"""
Jitsi PTT Service - Push-to-Talk with SPACEBAR
DOES NOT GRAB KEYBOARD - other keys work normally
"""
import evdev
import subprocess
import sys

SPACEBAR_SCANCODE = 57

def find_keyboard():
    """Find a keyboard device with spacebar"""
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    
    for dev in devices:
        caps = dev.capabilities()
        if evdev.ecodes.EV_KEY in caps:
            if SPACEBAR_SCANCODE in caps[evdev.ecodes.EV_KEY]:
                print(f"PTT: Using {dev.name}")
                return dev
    
    print(f"ERROR: No keyboard found with spacebar")
    return None

def mute_output():
    """Mute speakers (user is talking)"""
    subprocess.run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "1"], 
                   capture_output=True)

def unmute_output():
    """Unmute speakers (user is listening)"""
    subprocess.run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "0"], 
                   capture_output=True)

def main():
    keyboard = find_keyboard()
    if not keyboard:
        sys.exit(1)
    
    print(f"PTT Key: SPACEBAR (scancode {SPACEBAR_SCANCODE})")
    print(f"Smart PTT: HOLD = talk, RELEASE = listen")
    print("NOTE: Does NOT grab keyboard - all other keys work")
    
    # CRITICAL: Do NOT call keyboard.grab()
    # This allows other keys to work normally
    try:
        for event in keyboard.read_loop():
            if event.type == evdev.ecodes.EV_KEY and event.code == SPACEBAR_SCANCODE:
                if event.value == 1:  # Pressed
                    mute_output()
                elif event.value == 0:  # Released
                    unmute_output()
            # All other events pass through
    except KeyboardInterrupt:
        print("\nPTT service stopped")
        unmute_output()
        sys.exit(0)

if __name__ == "__main__":
    main()
SMARTPTT
    
    sudo chmod +x /usr/local/bin/jitsi-ptt-service.py
    
    sudo tee /etc/systemd/system/jitsi-ptt.service > /dev/null <<'PTTSVC'
[Unit]
Description=Jitsi PTT Service
After=lightdm.service sound.target pipewire.service
Wants=pipewire.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/jitsi-ptt-service.py
Restart=always
RestartSec=5
StartLimitInterval=300
StartLimitBurst=20
WatchdogSec=60
TimeoutStopSec=10
RuntimeMaxSec=infinity

[Install]
WantedBy=multi-user.target
PTTSVC
    
    sudo systemctl daemon-reload
    sudo systemctl enable jitsi-ptt.service
    
    log_success "PTT service installed (Spacebar)"
    

echo "[24/27] Configuring hardware buttons with enhanced detection..."

# Install evtest for debugging
sudo apt install -y evtest 2>/dev/null || true

# Get kiosk UID
local kiosk_uid=$(id -u "$KIOSK_USER")

# Create enhanced trigger script with multiple methods
sudo -u "$KIOSK_USER" tee "$KIOSK_HOME/trigger-power-menu.sh" > /dev/null <<PWREOF
#!/bin/bash
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$kiosk_uid/bus

logger "KIOSK: Power button pressed - triggering menu via multiple methods"

# Give display time to be ready
sleep 0.3

# Method 1: Find Electron window by class and send keys
ELECTRON_WINDOW=\$(xdotool search --class "electron" 2>/dev/null | head -1)
if [ -n "\$ELECTRON_WINDOW" ]; then
  logger "KIOSK: Found Electron window \$ELECTRON_WINDOW"
  xdotool windowactivate --sync \$ELECTRON_WINDOW 2>/dev/null
  sleep 0.2
  xdotool key --window \$ELECTRON_WINDOW --clearmodifiers ctrl+alt+Delete 2>/dev/null
  if [ \$? -eq 0 ]; then
    logger "KIOSK: Power menu triggered via Method 1 (xdotool window)"
    exit 0
  fi
fi

# Method 2: Find window by PID
NODE_PID=\$(pgrep -f "node.*electron" | head -1)
if [ -n "\$NODE_PID" ]; then
  WINDOW_BY_PID=\$(xdotool search --pid \$NODE_PID 2>/dev/null | head -1)
  if [ -n "\$WINDOW_BY_PID" ]; then
    logger "KIOSK: Found window by PID: \$WINDOW_BY_PID"
    xdotool windowactivate --sync \$WINDOW_BY_PID 2>/dev/null
    sleep 0.2
    xdotool key --window \$WINDOW_BY_PID --clearmodifiers ctrl+alt+Delete 2>/dev/null
    if [ \$? -eq 0 ]; then
      logger "KIOSK: Power menu triggered via Method 2 (PID)"
      exit 0
    fi
  fi
fi

# Method 3: Direct key injection (no specific window)
logger "KIOSK: Trying direct key injection"
xdotool key --clearmodifiers ctrl+alt+Delete 2>/dev/null
if [ \$? -eq 0 ]; then
  logger "KIOSK: Power menu triggered via Method 3 (direct injection)"
  exit 0
fi

# Method 4: Send SIGUSR1 to Node process
if [ -n "\$NODE_PID" ]; then
  logger "KIOSK: Sending SIGUSR1 to Node PID \$NODE_PID"
  kill -USR1 \$NODE_PID 2>/dev/null
  exit 0
fi

logger "KIOSK: All power button trigger methods failed"
PWREOF

sudo chmod +x "$KIOSK_HOME/trigger-power-menu.sh"

# Create test script for debugging
sudo tee /usr/local/bin/test-power-button > /dev/null <<'TESTEOF'
#!/bin/bash
echo "Testing power button configuration..."
echo

echo "1. Checking acpid service..."
if systemctl is-active --quiet acpid; then
  echo "  ✓ acpid is running"
else
  echo "  ✗ acpid is NOT running"
  echo "  Fix: sudo systemctl start acpid"
fi
echo

echo "2. Checking acpi events..."
if [ -d /etc/acpi/events ]; then
  echo "  Event files found:"
  ls -la /etc/acpi/events/kiosk-* 2>/dev/null || echo "  ✗ No kiosk event files"
else
  echo "  ✗ /etc/acpi/events not found"
fi
echo

echo "3. Testing Electron window detection..."
ELECTRON_WINDOW=$(DISPLAY=:0 xdotool search --class "electron" 2>/dev/null | head -1)
if [ -n "$ELECTRON_WINDOW" ]; then
  echo "  ✓ Found Electron window: $ELECTRON_WINDOW"
else
  echo "  ✗ Electron window not found"
  echo "  Is the kiosk running?"
fi
echo

echo "4. Manual trigger test (run as kiosk user)..."
echo "  sudo -u kiosk /home/kiosk/trigger-power-menu.sh"
echo

echo "5. Watch acpi events (press Ctrl+C to stop)..."
echo "  sudo acpi_listen"
echo

echo "6. Test hardware button (install evtest first: sudo apt install evtest)..."
echo "  sudo evtest"
echo "  Then press power button and look for button/power events"
TESTEOF

sudo chmod +x /usr/local/bin/test-power-button

# Remove old configs
sudo rm -f /etc/acpi/events/powerbtn* /etc/acpi/events/power* 2>/dev/null

# Create MULTIPLE event handlers for different power button formats
# Format 1: Standard power button
sudo tee /etc/acpi/events/kiosk-power-button > /dev/null <<EOF
event=button/power.*
action=sudo -u $KIOSK_USER $KIOSK_HOME/trigger-power-menu.sh
EOF

# Format 2: PBTN variant
sudo tee /etc/acpi/events/kiosk-power-pbtn > /dev/null <<EOF
event=button/power PBTN
action=sudo -u $KIOSK_USER $KIOSK_HOME/trigger-power-menu.sh
EOF

# Format 3: PWR variant
sudo tee /etc/acpi/events/kiosk-power-pwr > /dev/null <<EOF
event=button/power PWR
action=sudo -u $KIOSK_USER $KIOSK_HOME/trigger-power-menu.sh
EOF

# Format 4: Catch-all
sudo tee /etc/acpi/events/kiosk-power-any > /dev/null <<EOF
event=button/power
action=sudo -u $KIOSK_USER $KIOSK_HOME/trigger-power-menu.sh
EOF

# Configure systemd to ignore power button (let acpid handle it)
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/power-button.conf > /dev/null <<'EOF'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
EOF

# Reload everything
sudo systemctl daemon-reload
sudo systemctl restart systemd-logind
sudo systemctl enable acpid
sudo systemctl restart acpid

# Give it time to start
sleep 2

# Verify setup
if systemctl is-active --quiet acpid; then
    log_success "Power button configured with enhanced detection"
    echo
    echo "  Test command: sudo -u $KIOSK_USER $KIOSK_HOME/trigger-power-menu.sh"
    echo "  Debug tool: test-power-button"
    echo "  Watch events: sudo acpi_listen"
else
    log_warning "acpid may not be running properly"
    echo "  Check status: sudo systemctl status acpid"
    echo "  View events: sudo journalctl -u acpid -n 50"
fi
    echo "[25/27] WiFi configuration..."
    configure_wifi
    
    echo
    echo "[26/27] Finalizing installation..."
    log_success "Core installation complete!"
    echo
    echo "Next steps:"
    echo "  • Rerun this script to configure addons"
    echo "  • Reboot to start the kiosk"
    echo
    read -r -p "Reboot now? (y/n): " do_reboot
    if [[ ! "$do_reboot" =~ ^[Nn]$ ]]; then
        echo "Rebooting..."
        sleep 3
        sudo reboot
    fi
}

################################################################################
### SECTION 9: ADDON FUNCTIONS - LMS/SQUEEZELITE
################################################################################

addon_lms_squeezelite() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════"
        echo "   LMS SERVER / SQUEEZELITE PLAYER                           "
        echo "════════════════════════════════════════════════════════════"
        echo
        
        local lms_installed=false
        local sq_installed=false
        
        if is_service_active logitechmediaserver || is_service_enabled logitechmediaserver || \
           is_service_active lyrionmusicserver || is_service_enabled lyrionmusicserver; then
            lms_installed=true
            local lms_ip=$(get_ip_address)
            echo "LMS Server: ✓ Installed"
            if is_service_active logitechmediaserver || is_service_active lyrionmusicserver; then
                echo "  Status: Running"
            else
                echo "  Status: Stopped"
            fi
            echo "  Web: http://${lms_ip}:9000"
            echo
        fi
        
        if is_service_active squeezelite || is_service_enabled squeezelite; then
            sq_installed=true
            local player_name="Unknown"
            if [[ -f /usr/local/bin/squeezelite-start.sh ]]; then
                player_name=$(grep '^PLAYER_NAME=' /usr/local/bin/squeezelite-start.sh 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "Unknown")
            fi
            echo "Squeezelite Player: ✓ Installed"
            is_service_active squeezelite && echo "  Status: Running" || echo "  Status: Stopped"
            echo "  Name: $player_name"
            echo
        fi
        
        echo "ℹ A server is needed to stream music. The kiosk can run the"
        echo "  server (if sufficient resources) or connect to another server."
        echo
        
        echo "Options:"
        local menu_num=1
        local -A menu_actions
        
        echo "  ${menu_num}. Install/Configure LMS Server"
        menu_actions[$menu_num]="install_lms"
        ((menu_num++))
        
        echo "  ${menu_num}. Install/Configure Squeezelite Player"
        menu_actions[$menu_num]="install_squeezelite"
        ((menu_num++))
        
        if $lms_installed; then
            echo "  ${menu_num}. Uninstall LMS Server"
            menu_actions[$menu_num]="uninstall_lms"
            ((menu_num++))
        fi
        
        if $sq_installed; then
            echo "  ${menu_num}. Uninstall Squeezelite Player"
            menu_actions[$menu_num]="uninstall_squeezelite"
            ((menu_num++))
        fi
        
        echo "  0. Return"
        echo
        local max_option=$((menu_num-1))
        read -r -p "Choose [0-$max_option]: " choice
        
        if [[ "$choice" == "0" ]]; then
            return
        elif [[ -n "${menu_actions[$choice]:-}" ]]; then
            ${menu_actions[$choice]}
        else
            log_error "Invalid choice"
            sleep 1
        fi
    done
}

install_lms() {
    echo
    if is_service_active logitechmediaserver || is_service_active lyrionmusicserver; then
        echo "LMS is already installed."
        read -r -p "Reconfigure port? (y/n): " reconfig
        if [[ "$reconfig" =~ ^[Yy]$ ]]; then
            read -r -p "New HTTP port [9000]: " new_port
            new_port="${new_port:-9000}"
            sudo sed -i "s/httpport:.*/httpport: $new_port/" /etc/squeezeboxserver/prefs/server.prefs 2>/dev/null || true
            sudo systemctl restart lyrionmusicserver 2>/dev/null || sudo systemctl restart logitechmediaserver 2>/dev/null
            log_success "LMS reconfigured on port $new_port"
        fi
        pause
        return
    fi
    
    echo "Installing Lyrion Music Server..."
    
    # Try repository method first
    if wget -qO - https://debian.slimdevices.com/debian/squeezebox-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/lms-keyring.gpg 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/lms-keyring.gpg] http://debian.slimdevices.com/debian stable main" | sudo tee /etc/apt/sources.list.d/lms.list
        sudo apt update
        if sudo apt install -y logitechmediaserver 2>/dev/null; then
            log_success "LMS installed via repository"
        else
            log_warning "Repository install failed, trying direct download..."
        fi
    fi
    
    # Fallback to direct download if repository failed
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
    
    # Detect which service name to use
# Detect which service name actually exists
    local service_name=""
    if systemctl list-unit-files | grep -q "lyrionmusicserver.service"; then
        service_name="lyrionmusicserver"
    elif systemctl list-unit-files | grep -q "logitechmediaserver.service"; then
        service_name="logitechmediaserver"
    else
        # Check what was actually installed
        log_warning "Service file not found, checking installed files..."
        service_name=$(dpkg -L lyrionmusicserver logitechmediaserver 2>/dev/null | grep -m1 '\.service$' | xargs basename | sed 's/.service$//' || echo "")
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
    sudo systemctl enable "$service_name" 2>&1 | tee /tmp/lms-enable.log
    sudo systemctl start "$service_name" 2>&1 | tee /tmp/lms-start.log
    
    sudo ufw allow 9000/tcp comment 'LMS-HTTP' 2>/dev/null || true
    sudo ufw allow 3483/tcp comment 'LMS-SlimProto' 2>/dev/null || true
    sudo ufw allow 3483/udp comment 'LMS-Discovery' 2>/dev/null || true
    
    local lms_ip=$(get_ip_address)
    log_success "LMS installed"
    echo "  Web interface: http://${lms_ip}:9000"
    pause
}


uninstall_lms() {
    echo
    read -r -p "Remove LMS Server? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    # Detect which service name is in use
    local service_name=""
    if systemctl list-unit-files | grep -q "lyrionmusicserver.service"; then
        service_name="lyrionmusicserver"
    elif systemctl list-unit-files | grep -q "logitechmediaserver.service"; then
        service_name="logitechmediaserver"
    fi
    
    if [[ -n "$service_name" ]]; then
        echo "Stopping $service_name..."
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
    fi
    
    # Try to remove both possible package names
    sudo apt remove -y lyrionmusicserver 2>/dev/null || true
    sudo apt remove -y logitechmediaserver 2>/dev/null || true
    
    # Clean up repository
    sudo rm -f /etc/apt/sources.list.d/lms.list
    sudo rm -f /usr/share/keyrings/lms-keyring.gpg
    
    # Remove config/data (optional - ask user)
    read -r -p "Remove LMS data and configuration? (y/n): " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        sudo rm -rf /var/lib/squeezeboxserver
        sudo rm -rf /etc/squeezeboxserver
        log_success "LMS and data removed"
    else
        log_success "LMS removed (data preserved)"
    fi
    
    pause
}

install_squeezelite() {
    echo
    if is_service_active squeezelite; then
        echo "Squeezelite is already installed."
        read -r -p "Reconfigure? (y/n): " reconfig
        [[ ! "$reconfig" =~ ^[Yy]$ ]] && { pause; return; }
    fi
    
    if ! command -v squeezelite &>/dev/null; then
        sudo apt install -y squeezelite
    fi
    
    read -r -p "Player name [Kiosk]: " player_name
    player_name="${player_name:-Kiosk}"
    
    echo
    echo "LMS Server Configuration:"
    echo "  Enter IP:PORT of your LMS server"
    echo "  Leave blank for auto-discovery on LAN"
    echo
    read -r -p "LMS Server (e.g., 192.168.1.100:3483): " lms_server
    
    sudo tee /usr/local/bin/squeezelite-start.sh > /dev/null <<SQSTART
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
    
    sudo chmod +x /usr/local/bin/squeezelite-start.sh
    
    local kiosk_uid=$(id -u "$KIOSK_USER")
    
    sudo tee /etc/systemd/system/squeezelite.service > /dev/null <<EOF
[Unit]
Description=Squeezelite
After=sound.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$KIOSK_USER
Environment="XDG_RUNTIME_DIR=/run/user/$kiosk_uid"
ExecStartPre=/bin/sleep 10
ExecStart=/usr/local/bin/squeezelite-start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
sudo systemctl daemon-reload
    sudo systemctl enable squeezelite
    
    log_success "Squeezelite installed: $player_name"
    [[ -n "$lms_server" ]] && echo "  Server: $lms_server" || echo "  Server: Auto-discovery"
    echo ""
    echo "⚠️  IMPORTANT: Squeezelite requires a reboot to work properly"
    echo ""
    read -r -p "Reboot now? (y/n): " do_reboot
    if [[ "$do_reboot" =~ ^[Yy]$ ]]; then
        echo "Rebooting in 5 seconds..."
        sleep 5
        sudo reboot
    else
        echo "⚠️  Remember to reboot before using Squeezelite"
        echo "  Command: sudo reboot"
    fi
    pause
}

uninstall_squeezelite() {
    echo
    read -r -p "Remove Squeezelite Player? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    sudo systemctl stop squeezelite
    sudo systemctl disable squeezelite
    sudo rm -f /etc/systemd/system/squeezelite.service
    sudo rm -f /usr/local/bin/squeezelite-start.sh
    sudo apt remove -y squeezelite
    log_success "Squeezelite removed"
    pause
}

################################################################################
### SECTION 10: ADDON - CUPS (with fixed detection)
################################################################################

addon_cups() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   CUPS PRINTING SUPPORT                                        "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    local cups_installed=false
    if dpkg -l 2>/dev/null | grep -q "^ii.*cups\s"; then
        cups_installed=true
    fi
    
    if $cups_installed && systemctl is-active --quiet cups; then
        local cups_ip=$(get_ip_address)
        echo "Status: ✓ Installed and running"
        echo "  Admin interface: http://${cups_ip}:631"
        echo
        echo "Options:"
        echo "  1. Keep as-is"
        echo "  2. Reconfigure for network access"
        echo "  3. Complete uninstall (purge)"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-3]: " action
        
        case "$action" in
            2) reconfigure_cups ;;
            3) complete_cups_uninstall ;;
            0) return ;;
            *) log_success "Keeping CUPS"; pause ;;
        esac
    elif $cups_installed; then
        echo "Status: ⚠ Installed but not running"
        echo
        echo "Options:"
        echo "  1. Start CUPS"
        echo "  2. Complete uninstall (purge)"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-2]: " action
        
        case "$action" in
            1)
                sudo systemctl enable cups
                sudo systemctl start cups
                log_success "CUPS started"
                pause
                ;;
            2) complete_cups_uninstall ;;
            0) return ;;
        esac
    else
        echo "Status: Not installed"
        echo
        read -r -p "Install CUPS printing? (y/N): " install
        
        if [[ "$install" =~ ^[Yy]$ ]]; then
            install_cups_fresh
        fi
        pause
    fi
}

complete_cups_uninstall() {
    echo
    echo "Performing complete CUPS uninstall..."
    
    sudo systemctl stop cups cups-browsed 2>/dev/null || true
    sudo systemctl disable cups cups-browsed 2>/dev/null || true
    
    sudo apt remove --purge -y cups cups-daemon cups-client cups-filters \
      cups-common cups-core-drivers cups-server-common cups-browsed \
      cups-ppdc cups-bsd libcups2 libcupsimage2 2>/dev/null || true
    
    sudo apt remove --purge -y printer-driver-all printer-driver-cups-pdf \
      hplip printer-driver-gutenprint foomatic-db-compressed-ppds \
      openprinting-ppds 2>/dev/null || true
    
    sudo rm -rf /etc/cups /var/cache/cups /var/spool/cups /var/log/cups /usr/share/cups
    sudo rm -f /etc/polkit-1/localauthority/50-local.d/kiosk-printing.pkla
    
    sudo apt autoremove -y
    sudo apt clean
    
    log_success "CUPS completely removed"
    pause
}

install_cups_fresh() {
    echo
    echo "Installing CUPS from scratch..."
    
    sudo apt update
    sudo apt install -y cups cups-client cups-filters printer-driver-all \
      printer-driver-cups-pdf hplip printer-driver-gutenprint \
      foomatic-db-compressed-ppds openprinting-ppds
    
    sudo systemctl enable cups
    sudo systemctl start cups
    
    echo "Waiting for CUPS to start..."
    for i in {1..30}; do
        if systemctl is-active --quiet cups && lpstat -r &>/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    sudo usermod -aG lpadmin "$BUILD_USER"
    [[ -n "${SUDO_USER:-}" ]] && sudo usermod -aG lpadmin "$SUDO_USER" 2>/dev/null || true
    
    reconfigure_cups
    
    local cups_ip=$(get_ip_address)
    log_success "CUPS installed"
    echo "  Web interface: http://${cups_ip}:631"
}

reconfigure_cups() {
    [[ -f /etc/cups/cupsd.conf ]] && sudo cp /etc/cups/cupsd.conf /etc/cups/cupsd.conf.backup-$(date +%Y%m%d-%H%M%S)
    
    if command -v cupsctl &>/dev/null; then
        sudo cupsctl --remote-admin --remote-any --share-printers 2>/dev/null || true
    fi
    
    sudo sed -i 's/^Listen localhost:631/Port 631/' /etc/cups/cupsd.conf 2>/dev/null
    sudo sed -i 's/^Listen 127.0.0.1:631/Port 631/' /etc/cups/cupsd.conf 2>/dev/null
    
    sudo tee /etc/polkit-1/localauthority/50-local.d/kiosk-printing.pkla > /dev/null <<'EOF'
[Allow kiosk printing]
Identity=unix-user:kiosk
Action=org.opensuse.cupspkhelper.mechanism.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
    
    sudo ufw allow 631/tcp comment 'CUPS' 2>/dev/null || true
    sudo systemctl restart cups
    
    log_success "CUPS configured for network access"
    pause
}

################################################################################
### SECTION 11: ADDON - JITSI (with keep-alive)
################################################################################

addon_jitsi_intercom() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   JITSI INTERCOM (TWO-WAY AUDIO)                            "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    local jitsi_configured=false
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        if sudo -u "$KIOSK_USER" jq -e '.tabs[] | select(.url | contains("jit"))' "$CONFIG_PATH" >/dev/null 2>&1; then
            jitsi_configured=true
            local room_url=$(sudo -u "$KIOSK_USER" jq -r '.tabs[] | select(.url | contains("jit")) | .url' "$CONFIG_PATH")
            echo "Status: ✓ Configured"
            echo "  Room: $room_url"
            echo
        fi
    fi
    
    if systemctl is-active --quiet jitsi-ptt 2>/dev/null; then
        echo "PTT Service: ✓ Running"
        echo "  PTT Key: Spacebar (hold to talk)"
        echo
    fi
    
    if $jitsi_configured; then
        echo "Options:"
        echo "  1. Keep as-is"
        echo "  2. Change room/server"
        echo "  3. Change PIN"
        echo "  4. Remove Jitsi"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-5]: " action
        
        case "$action" in
            2)
                if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
                    sudo -u "$KIOSK_USER" jq 'del(.tabs[] | select(.url | contains("jit")))' "$CONFIG_PATH" > /tmp/config.tmp
                    sudo -u "$KIOSK_USER" cp /tmp/config.tmp "$CONFIG_PATH"
                fi
                install_jitsi_intercom
                ;;
            3)
                echo
                echo "PIN Configuration:"
                read -r -s -p "New PIN (blank=no PIN): " new_pin
                echo
                if [[ -z "$new_pin" ]]; then
                    echo "NOPIN" | sudo -u kiosk tee /home/kiosk/kiosk-app/.jitsi-pin >/dev/null
                    log_success "PIN disabled"
                elif [[ "$new_pin" =~ ^[0-9]{4,8}$ ]]; then
                    echo "$new_pin" | sudo -u kiosk tee /home/kiosk/kiosk-app/.jitsi-pin >/dev/null
                    sudo chmod 600 /home/kiosk/kiosk-app/.jitsi-pin
                    log_success "PIN updated"
                else
                    log_error "PIN must be 4-8 digits"
                fi
                pause
                ;;
            4) remove_jitsi_intercom ;;
            0) return ;;
            *) log_success "Keeping Jitsi"; pause ;;
        esac
    else
        echo "Status: Not configured"
        echo
        echo "Jitsi provides:"
        echo "  • Two-way audio (Kiosk ↔ Phone)"
        echo "  • Hidden tab (F10 or 3-finger swipe)"
        echo "  • Audio-only mode (Spacebar PTT)"
        echo "  • Works with mobile Jitsi app"
        echo
        read -r -p "Configure Jitsi intercom? (y/n): " install
        
        if [[ "$install" =~ ^[Yy]$ ]]; then
            install_jitsi_intercom
        fi
    fi
}

install_jitsi_intercom() {
    echo
    echo " ══ JITSI SETUP ══"
    echo
    echo "Choose Jitsi server type:"
    echo "  1. Public Jitsi (meet.jit.si) - Free, no setup"
    echo "  2. Self-hosted Jitsi - Your own server"
    echo
    read -r -p "Choose [1-3]: " server_choice
    
    local url=""
    local room="kiosk-$(openssl rand -hex 12)"
    
    case "$server_choice" in
        1)
            url="https://meet.jit.si/${room}#config.startWithAudioMuted=true&config.startWithVideoMuted=true&config.prejoinPageEnabled=false&config.disableThirdPartyRequests=true"
            log_success "Using public Jitsi server"
            ;;
        2)
            read -r -p "Enter your Jitsi server URL (e.g., jitsi.example.com): " jitsi_server
            if [[ -z "$jitsi_server" ]]; then
                log_error "No server provided"
                pause
                return
            fi
            url="https://${jitsi_server}/${room}#config.startWithAudioMuted=true&config.startWithVideoMuted=true&config.prejoinPageEnabled=false"
            log_success "Using self-hosted: $jitsi_server"
            ;;
         *)
            log_error "Invalid choice"
            pause
            return
            ;;
    esac

    
    read -r -p "PIN (4-8 digits) [1234]: " pin
    pin="${pin:-1234}"
    [[ ! "$pin" =~ ^[0-9]{4,8}$ ]] && pin="1234"
    
    echo "$pin" | sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/.jitsi-pin" >/dev/null
    sudo -u "$KIOSK_USER" chmod 600 "$KIOSK_DIR/.jitsi-pin"
    
    load_config || true
    URLS+=("$url")
    DURS+=(-1)
    USERS+=("")
    PASSES+=("")
    save_config
    
    log_success "Jitsi configured: $room (PIN: $pin)"
    echo "Room URL: $url"
    
    if ! systemctl is-active --quiet jitsi-ptt; then
        sudo systemctl start jitsi-ptt
    fi
    
    pause
}
remove_jitsi_intercom() {
    echo
    read -r -p "Remove Jitsi intercom? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        sudo -u "$KIOSK_USER" jq 'del(.tabs[] | select(.url | contains("jit")))' "$CONFIG_PATH" > /tmp/config.tmp
        sudo -u "$KIOSK_USER" cp /tmp/config.tmp "$CONFIG_PATH"
    fi
    
    sudo systemctl stop jitsi-ptt 2>/dev/null || true
    
    log_success "Jitsi intercom removed"
    pause
}


################################################################################
### SECTION 11.5: ADDON - TALKKONNECT/MURMUR INTERCOM (FIXED)
################################################################################

addon_talkkonnect_intercom() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   TALKKONNECT/MURMUR INTERCOM                                   "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    local murmur_installed=false
    local talkkonnect_installed=false
    local murmur_running=false
    local talkkonnect_running=false
    
    # Check Murmur server
    if systemctl list-unit-files | grep -q "mumble-server.service"; then
        murmur_installed=true
        if systemctl is-active --quiet mumble-server; then
            murmur_running=true
        fi
    fi
    
    # Check talkkonnect client
    if command -v talkkonnect &>/dev/null || [[ -f "$HOME/go/bin/talkkonnect" ]]; then
        talkkonnect_installed=true
        if systemctl is-active --quiet talkkonnect; then
            talkkonnect_running=true
        fi
    fi
    
    # Display status
    if $murmur_installed; then
        echo "Murmur Server: ✓ Installed"
        if $murmur_running; then
            echo "  Status: Running"
            local server_ip=$(get_ip_address)
            echo "  Address: $server_ip:64738"
        else
            echo "  Status: Stopped"
        fi
        echo
    fi
    
    if $talkkonnect_installed; then
        echo "talkkonnect Client: ✓ Installed"
        if $talkkonnect_running; then
            echo "  Status: Running"
            if [[ -f /home/$KIOSK_USER/talkkonnect.xml ]]; then
                local server=$(grep "serveraddress" /home/$KIOSK_USER/talkkonnect.xml 2>/dev/null | sed 's/.*<serveraddress>\(.*\)<\/serveraddress>/\1/' || echo "Unknown")
                echo "  Server: $server"
            fi
        else
            echo "  Status: Stopped"
        fi
        echo
    fi
    
    # Menu options
    echo "Options:"
    local menu_num=1
    
    if ! $murmur_installed && ! $talkkonnect_installed; then
        echo "  1. Install Murmur server + talkkonnect (all-in-one)"
        echo "  2. Install talkkonnect only (connect to existing server)"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-2]: " choice
        
        case "$choice" in
            1) install_murmur_and_talkkonnect ;;
            2) install_talkkonnect_only ;;
            0) return ;;
        esac
    else
        if $murmur_installed; then
            echo "  $menu_num. $([ $murmur_running = true ] && echo 'Stop' || echo 'Start') Murmur server"
            local murmur_toggle=$menu_num
            ((menu_num++))
            echo "  $menu_num. Reconfigure Murmur server"
            local murmur_reconfig=$menu_num
            ((menu_num++))
            echo "  $menu_num. Uninstall Murmur server"
            local murmur_uninstall=$menu_num
            ((menu_num++))
        else
            echo "  $menu_num. Install Murmur server"
            local murmur_install=$menu_num
            ((menu_num++))
        fi
        
        if $talkkonnect_installed; then
            echo "  $menu_num. $([ $talkkonnect_running = true ] && echo 'Stop' || echo 'Start') talkkonnect client"
            local tk_toggle=$menu_num
            ((menu_num++))
            echo "  $menu_num. Reconfigure talkkonnect client"
            local tk_reconfig=$menu_num
            ((menu_num++))
            echo "  $menu_num. View talkkonnect logs"
            local tk_logs=$menu_num
            ((menu_num++))
            echo "  $menu_num. Uninstall talkkonnect client"
            local tk_uninstall=$menu_num
            ((menu_num++))
        else
            echo "  $menu_num. Install talkkonnect client"
            local tk_install=$menu_num
            ((menu_num++))
        fi
        
        echo "  0. Return"
        echo
        read -r -p "Choose [0-$((menu_num-1))]: " choice
        
        # Handle selection
        if [[ -n "${murmur_toggle:-}" ]] && [[ "$choice" == "$murmur_toggle" ]]; then
            toggle_murmur_service
        elif [[ -n "${murmur_reconfig:-}" ]] && [[ "$choice" == "$murmur_reconfig" ]]; then
            reconfigure_murmur
        elif [[ -n "${murmur_uninstall:-}" ]] && [[ "$choice" == "$murmur_uninstall" ]]; then
            uninstall_murmur
        elif [[ -n "${murmur_install:-}" ]] && [[ "$choice" == "$murmur_install" ]]; then
            install_murmur_server
        elif [[ -n "${tk_toggle:-}" ]] && [[ "$choice" == "$tk_toggle" ]]; then
            toggle_talkkonnect_service
        elif [[ -n "${tk_reconfig:-}" ]] && [[ "$choice" == "$tk_reconfig" ]]; then
            reconfigure_talkkonnect
        elif [[ -n "${tk_logs:-}" ]] && [[ "$choice" == "$tk_logs" ]]; then
            view_talkkonnect_logs
        elif [[ -n "${tk_uninstall:-}" ]] && [[ "$choice" == "$tk_uninstall" ]]; then
            uninstall_talkkonnect
        elif [[ -n "${tk_install:-}" ]] && [[ "$choice" == "$tk_install" ]]; then
            install_talkkonnect_only
        elif [[ "$choice" == "0" ]]; then
            return
        fi
    fi
}

install_murmur_server() {
    echo
    echo " ═══ INSTALLING MURMUR SERVER ═══"
    echo
    
    echo "[1/5] Installing mumble-server package..."
    sudo apt update
    sudo apt install -y mumble-server
    
    echo "[2/5] Getting configuration details..."
    read -r -s -p "SuperUser password: " superuser_pass
    echo
    read -r -s -p "Server password (clients need this): " server_pass
    echo
    read -r -p "Welcome text [Welcome to Kiosk Intercom]: " welcome_text
    welcome_text="${welcome_text:-Welcome to Kiosk Intercom}"
    
    echo "[3/5] Creating configuration..."
    local config_file="/etc/mumble-server.ini"
    
    # Create config if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        sudo tee "$config_file" > /dev/null <<'MURMURCONF'
# Murmur configuration file

# Database location
database=/var/lib/mumble-server/mumble-server.sqlite

# Network settings
port=64738
host=0.0.0.0

# Logging
logfile=/var/log/mumble-server/mumble-server.log

# Limits
users=10
bandwidth=72000

# Welcome message
welcometext=Welcome

# Server password
serverpassword=

# Allow pings
allowping=true

# Enable HTML
allowhtml=true
MURMURCONF
        log_success "Config file created"
    fi
    
    # Update configuration
    sudo sed -i "s|^welcometext=.*|welcometext=$welcome_text|" "$config_file"
    sudo sed -i "s|^port=.*|port=64738|" "$config_file"
    sudo sed -i "s|^users=.*|users=10|" "$config_file"
    sudo sed -i "s|^bandwidth=.*|bandwidth=72000|" "$config_file"
    
    if [[ -n "$server_pass" ]]; then
        sudo sed -i "s|^serverpassword=.*|serverpassword=$server_pass|" "$config_file"
    fi
    
    echo "[4/5] Setting SuperUser password..."
    # Stop service before setting password
    sudo systemctl stop mumble-server 2>/dev/null || true
    sleep 2
    
    # Set SuperUser password
    echo "$superuser_pass" | sudo murmurd -ini "$config_file" -supw - 2>/dev/null || {
        log_warning "Could not set SuperUser password via murmurd command"
        echo "You can set it later with: sudo murmurd -ini $config_file -supw YOUR_PASSWORD"
    }
    
    echo "[5/5] Starting service..."
    sudo systemctl enable mumble-server
    sudo systemctl start mumble-server
    
    # Configure firewall
    sudo ufw allow 64738/tcp comment 'Mumble/Murmur' 2>/dev/null || true
    sudo ufw allow 64738/udp comment 'Mumble/Murmur' 2>/dev/null || true
    
    sleep 3
    
    local server_ip=$(get_ip_address)
    log_success "Murmur server installed"
    echo
    echo "  Server: $server_ip:64738"
    echo "  SuperUser: SuperUser / $superuser_pass"
    [[ -n "$server_pass" ]] && echo "  Password: $server_pass"
    echo
    echo "Connect with Mumble app:"
    echo "  Server: $server_ip"
    echo "  Port: 64738"
    [[ -n "$server_pass" ]] && echo "  Password: $server_pass"
    
    pause
}

install_murmur_and_talkkonnect() {
    echo
    echo "Installing Murmur server..."
    install_murmur_server
    
    echo
    echo "Now installing talkkonnect client..."
    echo "Configuring to connect to local server..."
    
    # Auto-configure for local server
    AUTO_SERVER="127.0.0.1"
    AUTO_PORT="64738"
    read -r -p "Username for talkkonnect [kiosk]: " tk_user
    tk_user="${tk_user:-kiosk}"
    read -r -s -p "Server password: " tk_pass
    echo
    
    install_talkkonnect_with_config "$AUTO_SERVER" "$AUTO_PORT" "$tk_user" "$tk_pass" "Root"
}

install_talkkonnect_only() {
    echo
    echo " ═══ INSTALLING TALKKONNECT (STANDALONE) ═══"
    echo
    
    echo "Enter Murmur/Mumble server details:"
    read -r -p "Server address (IP or domain): " server_addr
    read -r -p "Port [64738]: " server_port
    server_port="${server_port:-64738}"
    read -r -p "Username: " tk_user
    read -r -s -p "Password: " tk_pass
    echo
    read -r -p "Channel [Root]: " tk_channel
    tk_channel="${tk_channel:-Root}"
    
    install_talkkonnect_with_config "$server_addr" "$server_port" "$tk_user" "$tk_pass" "$tk_channel"
}

install_talkkonnect_with_config() {
    local server_addr="$1"
    local server_port="$2"
    local tk_user="$3"
    local tk_pass="$4"
    local tk_channel="$5"
    
    echo
    echo "[1/4] Installing Go..."
    if ! command -v go &>/dev/null; then
        wget -q https://golang.org/dl/go1.23.4.linux-amd64.tar.gz
        sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
        rm go1.23.4.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh
    fi
    
    echo "[2/4] Installing audio dependencies..."
    sudo apt install -y libopenal-dev libopus-dev alsa-utils portaudio19-dev git
    
    echo "[3/4] Cloning and building talkkonnect..."
    local tk_src="/tmp/talkkonnect-src"
    rm -rf "$tk_src"
    git clone https://github.com/talkkonnect/talkkonnect.git "$tk_src"
    
    echo "Building (this takes 5-10 minutes)..."
    
    # Build as kiosk user with proper environment
    sudo -u "$KIOSK_USER" bash -c "
        export PATH=/usr/local/go/bin:\$PATH
        export HOME=/home/$KIOSK_USER
        export GOPATH=/home/$KIOSK_USER/go
        export CGO_ENABLED=1
        
        mkdir -p /home/$KIOSK_USER/go/bin
        
        cd '$tk_src' || exit 1
        
        echo 'Compiling...'
        go build -v -o /home/$KIOSK_USER/go/bin/talkkonnect . 2>&1 | tail -20
        
        if [[ -f /home/$KIOSK_USER/go/bin/talkkonnect ]]; then
            chmod +x /home/$KIOSK_USER/go/bin/talkkonnect
            echo 'Build successful'
            exit 0
        else
            echo 'Build failed - binary not created'
            exit 1
        fi
    "
    
    local build_result=$?
    rm -rf "$tk_src"
    
    if [[ $build_result -ne 0 ]]; then
        log_error "Build failed"
        echo
        echo "Troubleshooting:"
        echo "  1. Check Go version: go version"
        echo "  2. Ensure build tools: sudo apt install build-essential"
        echo "  3. Check logs above for specific errors"
        pause
        return 1
    fi
    
    # Verify binary
    if [[ ! -x "/home/$KIOSK_USER/go/bin/talkkonnect" ]]; then
        log_error "Binary not executable after build"
        pause
        return 1
    fi
    
    log_success "talkkonnect built successfully"
    
    echo "[4/4] Creating configuration..."
    
    sudo -u "$KIOSK_USER" tee /home/$KIOSK_USER/talkkonnect.xml > /dev/null <<TKXML
<?xml version="1.0" encoding="UTF-8"?>
<document type="talkkonnect.org/talkkonnect">
  <accounts>
    <account>
      <default>true</default>
      <name>Primary</name>
      <server>$server_addr</server>
      <username>$tk_user</username>
      <password>$tk_pass</password>
      <insecure>true</insecure>
      <port>$server_port</port>
      <channel>$tk_channel</channel>
    </account>
  </accounts>
  
  <software>
    <settings>
      <outputdevice>default</outputdevice>
      <loglevel>3</loglevel>
      <cancellingnoisegate>false</cancellingnoisegate>
      <simplex>true</simplex>
    </settings>
  </software>
  
  <hardware>
    <ledstrip><enabled>false</enabled></ledstrip>
    <targetboard>rpi</targetboard>
    <buttons>
      <button>
        <enabled>true</enabled>
        <name>Transmit</name>
        <pin>spacebar</pin>
        <action>transmit</action>
      </button>
    </buttons>
  </hardware>
  
  <audio>
    <input>
      <enabled>true</enabled>
      <device>default</device>
      <samplerate>48000</samplerate>
      <channels>1</channels>
    </input>
    <output>
      <enabled>true</enabled>
      <device>default</device>
      <samplerate>48000</samplerate>
      <channels>2</channels>
      <volume>100</volume>
    </output>
  </audio>
</document>
TKXML
    
    # Create systemd service
    sudo tee /etc/systemd/system/talkkonnect.service > /dev/null <<EOF
[Unit]
Description=talkkonnect Mumble Client
After=network.target sound.target pipewire.service
Wants=pipewire.service

[Service]
Type=simple
User=$KIOSK_USER
Environment="PATH=/usr/local/go/bin:/usr/bin:/bin"
Environment="HOME=/home/$KIOSK_USER"
Environment="GOPATH=/home/$KIOSK_USER/go"
WorkingDirectory=/home/$KIOSK_USER
ExecStartPre=/bin/sleep 10
ExecStart=/home/$KIOSK_USER/go/bin/talkkonnect -config /home/$KIOSK_USER/talkkonnect.xml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable talkkonnect
    sudo systemctl start talkkonnect
    
    sleep 3
    
    log_success "talkkonnect installed"
    echo "  Server: $server_addr:$server_port"
    echo "  PTT Key: Spacebar"
    
    # Show status
    echo
    if systemctl is-active --quiet talkkonnect; then
        echo "✓ Service started successfully"
    else
        echo "⚠ Service may have issues - check logs:"
        echo "  sudo journalctl -u talkkonnect -n 50"
    fi
    
    pause
}

toggle_murmur_service() {
    echo
    if systemctl is-active --quiet mumble-server; then
        echo "Stopping Murmur server..."
        sudo systemctl stop mumble-server
        log_success "Murmur stopped"
    else
        echo "Starting Murmur server..."
        sudo systemctl start mumble-server
        sleep 2
        if systemctl is-active --quiet mumble-server; then
            log_success "Murmur started"
        else
            log_error "Failed to start - check logs: sudo journalctl -u mumble-server"
        fi
    fi
    pause
}

toggle_talkkonnect_service() {
    echo
    if systemctl is-active --quiet talkkonnect; then
        echo "Stopping talkkonnect..."
        sudo systemctl stop talkkonnect
        log_success "talkkonnect stopped"
    else
        echo "Starting talkkonnect..."
        sudo systemctl start talkkonnect
        sleep 2
        if systemctl is-active --quiet talkkonnect; then
            log_success "talkkonnect started"
        else
            log_error "Failed to start - check logs: sudo journalctl -u talkkonnect"
        fi
    fi
    pause
}

reconfigure_murmur() {
    echo
    echo "Reconfigure Murmur Server:"
    echo "  1. Change welcome text"
    echo "  2. Change server password"
    echo "  3. Change SuperUser password"
    echo "  4. Change port"
    echo "  0. Cancel"
    read -r -p "Choose: " reconfig_choice
    
    local config_file="/etc/mumble-server.ini"
    
    case "$reconfig_choice" in
        1)
            read -r -p "New welcome text: " new_welcome
            sudo sed -i "s|^welcometext=.*|welcometext=$new_welcome|" "$config_file"
            sudo systemctl restart mumble-server
            log_success "Welcome text updated"
            ;;
        2)
            read -r -s -p "New server password (blank=none): " new_pass
            echo
            sudo sed -i "s|^serverpassword=.*|serverpassword=$new_pass|" "$config_file"
            sudo systemctl restart mumble-server
            log_success "Server password updated"
            ;;
        3)
            read -r -s -p "New SuperUser password: " su_pass
            echo
            sudo systemctl stop mumble-server
            echo "$su_pass" | sudo murmurd -ini "$config_file" -supw - 2>/dev/null
            sudo systemctl start mumble-server
            log_success "SuperUser password updated"
            ;;
        4)
            read -r -p "New port [64738]: " new_port
            new_port="${new_port:-64738}"
            sudo sed -i "s|^port=.*|port=$new_port|" "$config_file"
            sudo systemctl restart mumble-server
            log_success "Port updated to $new_port"
            ;;
    esac
    pause
}

reconfigure_talkkonnect() {
    echo
    echo "Reconfigure talkkonnect:"
    echo "  1. Change server"
    echo "  2. Change credentials"
    echo "  3. Change channel"
    echo "  0. Cancel"
    read -r -p "Choose: " reconfig_choice
    
    case "$reconfig_choice" in
        1)
            read -r -p "Server address: " new_server
            read -r -p "Port [64738]: " new_port
            new_port="${new_port:-64738}"
            sudo -u "$KIOSK_USER" sed -i "s|<server>.*</server>|<server>$new_server</server>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo -u "$KIOSK_USER" sed -i "s|<port>.*</port>|<port>$new_port</port>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo systemctl restart talkkonnect
            log_success "Server updated"
            ;;
        2)
            read -r -p "Username: " new_user
            read -r -s -p "Password: " new_pass
            echo
            sudo -u "$KIOSK_USER" sed -i "s|<username>.*</username>|<username>$new_user</username>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo -u "$KIOSK_USER" sed -i "s|<password>.*</password>|<password>$new_pass</password>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo systemctl restart talkkonnect
            log_success "Credentials updated"
            ;;
        3)
            read -r -p "Channel: " new_channel
            sudo -u "$KIOSK_USER" sed -i "s|<channel>.*</channel>|<channel>$new_channel</channel>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo systemctl restart talkkonnect
            log_success "Channel updated"
            ;;
    esac
    pause
}

view_talkkonnect_logs() {
    echo
    echo "Recent talkkonnect logs:"
    echo "═══════════════════════════════════════════════════════════════"
    sudo journalctl -u talkkonnect -n 50 --no-pager
    echo
    pause
}

uninstall_murmur() {
    echo
    read -r -p "Uninstall Murmur server? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && return
    
    echo "Uninstalling..."
    sudo systemctl stop mumble-server 2>/dev/null || true
    sudo systemctl disable mumble-server 2>/dev/null || true
    sudo apt remove -y mumble-server 2>/dev/null || true
    
    read -r -p "Remove configuration and database? (y/n): " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        sudo rm -rf /var/lib/mumble-server
        sudo rm -f /etc/mumble-server.ini
        log_success "Murmur and data removed"
    else
        log_success "Murmur removed (data preserved)"
    fi
    
    pause
}

uninstall_talkkonnect() {
    echo
    read -r -p "Uninstall talkkonnect? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && return
    
    echo "Uninstalling..."
    sudo systemctl stop talkkonnect 2>/dev/null || true
    sudo systemctl disable talkkonnect 2>/dev/null || true
    sudo rm -f /etc/systemd/system/talkkonnect.service
    sudo rm -f /home/$KIOSK_USER/talkkonnect.xml
    sudo rm -f /home/$KIOSK_USER/go/bin/talkkonnect
    
    sudo systemctl daemon-reload
    
    log_success "talkkonnect uninstalled"
    pause
}
################################################################################
### SECTION 12: ADDON - VNC
################################################################################

addon_vnc() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   VNC REMOTE DESKTOP                                        "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    if is_service_active x11vnc; then
        echo "Status: ✓ Running"
        local vnc_ip=$(get_ip_address)
        echo "  Connect: ${vnc_ip}:5900"
        echo
        echo "Options:"
        echo "  1. Keep as-is"
        echo "  2. Reconfigure password"
        echo "  3. Uninstall"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-3]: " action
        
        case "$action" in
            2)
                echo
                read -r -s -p "New VNC password: " vnc_pass
                echo
                sudo -u "$KIOSK_USER" x11vnc -storepasswd "$vnc_pass" "$KIOSK_HOME/.vnc/passwd"
                sudo systemctl restart x11vnc
                log_success "VNC password updated"
                pause
                ;;
            3)
                echo
                read -r -p "Remove VNC? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo systemctl stop x11vnc
                    sudo systemctl disable x11vnc
                    sudo rm -f /etc/systemd/system/x11vnc.service
                    sudo apt remove -y x11vnc
                    log_success "VNC removed"
                fi
                pause
                ;;
            0) return ;;
            *) log_success "Keeping VNC"; pause ;;
        esac
    else
        echo "Status: Not installed"
        read -r -p "Install x11vnc? (y/n): " install
        
        if [[ "$install" =~ ^[Yy]$ ]]; then
            sudo apt install -y x11vnc
            
            read -r -s -p "VNC password: " vnc_pass
            echo
            
            sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_HOME/.vnc"
            sudo -u "$KIOSK_USER" x11vnc -storepasswd "$vnc_pass" "$KIOSK_HOME/.vnc/passwd"
            
            sudo tee /etc/systemd/system/x11vnc.service > /dev/null <<EOF
[Unit]
Description=x11vnc Remote Desktop
After=lightdm.service

[Service]
Type=simple
User=$KIOSK_USER
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -rfbauth $KIOSK_HOME/.vnc/passwd -forever -loop -noxdamage -repeat -shared
Restart=always

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl enable x11vnc
            sudo systemctl start x11vnc
            
            sudo ufw allow 5900/tcp comment 'VNC' 2>/dev/null || true
            
            local vnc_ip=$(get_ip_address)
            log_success "VNC installed"
            echo "  Connect: ${vnc_ip}:5900"
        fi
        pause
    fi
}

################################################################################
### SECTION 13: ADDON - VPNs (with setup key support)
################################################################################

addon_wireguard() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   WIREGUARD VPN                                             "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    if command -v wg &>/dev/null && sudo wg show 2>/dev/null | grep -q interface; then
        echo "Status: ✓ Connected"
        echo
        sudo wg show | grep -E "interface:|endpoint:|allowed ips:" | sed 's/^/  /'
        echo
        echo "Options:"
        echo "  1. Keep as-is"
        echo "  2. Show full config"
        echo "  3. Paste new config"
        echo "  4. Uninstall"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-5]: " action
        
        case "$action" in
            2) sudo wg show all; pause ;;
            3) configure_wireguard_paste ;;
            4)
                read -r -p "Remove WireGuard? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo systemctl stop wg-quick@* 2>/dev/null || true
                    sudo systemctl disable wg-quick@* 2>/dev/null || true
                    sudo apt remove -y wireguard wireguard-tools
                    log_success "WireGuard removed"
                fi
                pause
                ;;
            0) return ;;
            *) pause ;;
        esac
    else
        echo "Status: Not installed"
        echo
        read -r -p "Install WireGuard? (y/n): " install
        
        if [[ "$install" =~ ^[Yy]$ ]]; then
            sudo apt install -y wireguard wireguard-tools
            log_success "WireGuard installed"
            echo
            echo "Options:"
            echo "  1. Paste config now"
            echo "  2. Configure later"
            read -r -p "Choose [1-2]: " config_choice
            
            [[ "$config_choice" == "1" ]] && configure_wireguard_paste
        fi
        pause
    fi
}

configure_wireguard_paste() {
    echo
    echo "Paste your WireGuard config (Ctrl+D when done):"
    local config=$(cat)
    
    if [[ -z "$config" ]]; then
        log_error "No config provided"
        return
    fi
    
    read -r -p "Config name [wg0]: " wg_name
    wg_name="${wg_name:-wg0}"
    
    echo "$config" | sudo tee "/etc/wireguard/${wg_name}.conf" > /dev/null
    sudo chmod 600 "/etc/wireguard/${wg_name}.conf"
    
    sudo systemctl enable "wg-quick@${wg_name}"
    sudo systemctl start "wg-quick@${wg_name}"
    
    log_success "WireGuard configured: $wg_name"
    pause
}

addon_tailscale() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   TAILSCALE VPN                                             "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    if command -v tailscale &>/dev/null; then
        local ts_status=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null || echo "unknown")
        
        if [[ "$ts_status" == "Running" ]]; then
            echo "Status: ✓ Connected"
            local ts_ip=$(tailscale ip -4 2>/dev/null)
            local ts_name=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName' 2>/dev/null)
            echo "  Hostname: $ts_name"
            echo "  IP: $ts_ip"
            echo
        else
            echo "Status: ✓ Installed, not connected"
            echo
        fi
        
        echo "Options:"
        echo "  1. Keep as-is"
        echo "  2. Connect (interactive)"
        echo "  3. Connect with auth key"
        echo "  4. Show status"
        echo "  5. Uninstall"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-5]: " action
        
        case "$action" in
            2)
                echo
                sudo tailscale up
                log_success "Tailscale connected"
                pause
                ;;
            3)
                echo
                echo "Get auth key from: https://login.tailscale.com/admin/settings/keys"
                read -r -p "Enter auth key: " authkey
                if [[ -n "$authkey" ]]; then
                    sudo tailscale up --authkey="$authkey"
                    log_success "Tailscale connected"
                fi
                pause
                ;;
            4) tailscale status; pause ;;
            5)
                read -r -p "Remove Tailscale? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo tailscale down
                    sudo apt remove -y tailscale
                    log_success "Tailscale removed"
                fi
                pause
                ;;
            0) return ;;
            *) pause ;;
        esac
    else
        echo "Status: Not installed"
        echo
        read -r -p "Install Tailscale? (y/n): " install
        
        if [[ "$install" =~ ^[Yy]$ ]]; then
            curl -fsSL https://tailscale.com/install.sh | sh
            log_success "Tailscale installed"
            echo
            echo "Options:"
            echo "  1. Connect now (interactive)"
            echo "  2. Connect with auth key"
            echo "  3. Connect later"
            read -r -p "Choose [1-3]: " connect_choice
            
            case "$connect_choice" in
                1) sudo tailscale up ;;
                2)
                    echo "Get auth key from: https://login.tailscale.com/admin/settings/keys"
                    read -r -p "Enter auth key: " authkey
                    [[ -n "$authkey" ]] && sudo tailscale up --authkey="$authkey"
                    ;;
            esac
        fi
        pause
    fi
}

addon_netbird() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   NETBIRD VPN                                               "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    if command -v netbird &>/dev/null; then
        local nb_status=$(netbird status 2>/dev/null | grep "Status:" | awk '{print $2}')
        
        if [[ "$nb_status" == "Connected" ]]; then
            echo "Status: ✓ Connected"
            netbird status | grep -E "NetBird IP:|Public key:" | sed 's/^/  /'
            echo
        else
            echo "Status: ✓ Installed, not connected"
            echo
        fi
        
        echo "Options:"
        echo "  1. Keep as-is"
        echo "  2. Connect with setup key"
        echo "  3. Show status"
        echo "  4. Uninstall"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-5]: " action
        
        case "$action" in
            2)
                echo
                echo "Get setup key from Netbird dashboard"
                read -r -p "Enter setup key: " setup_key
                if [[ -n "$setup_key" ]]; then
                    sudo netbird up --setup-key "$setup_key"
                    log_success "Netbird connected"
                fi
                pause
                ;;
            3) netbird status; pause ;;
            4)
                read -r -p "Remove Netbird? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo netbird down
                    sudo apt remove -y netbird
                    log_success "Netbird removed"
                fi
                pause
                ;;
            0) return ;;
            *) pause ;;
        esac
    else
        echo "Status: Not installed"
        echo
        read -r -p "Install Netbird? (y/n): " install
        
        if [[ "$install" =~ ^[Yy]$ ]]; then
            curl -fsSL https://pkgs.netbird.io/install.sh | sh
            log_success "Netbird installed"
            echo
            read -r -p "Connect with setup key now? (y/n): " do_connect
            if [[ "$do_connect" =~ ^[Yy]$ ]]; then
                echo "Get setup key from Netbird dashboard"
                read -r -p "Enter setup key: " setup_key
                [[ -n "$setup_key" ]] && sudo netbird up --setup-key "$setup_key"
            fi
        fi
        pause
    fi
}

################################################################################
### SECTION 14: ADDON - HTML ON-SCREEN KEYBOARD
################################################################################

addon_onscreen_keyboard() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   HTML ON-SCREEN KEYBOARD                                   "
    echo "════════════════════════════════════════════════════════════"
    echo
    
    local keyboard_installed=false
    local auto_show_enabled=false
    
    if [[ -f "$KIOSK_DIR/keyboard.html" ]]; then
        keyboard_installed=true
        echo "Status: ✓ Installed"
        
        # Check if auto-show is enabled
        if sudo grep -q "Auto-shows on text fields" "$KIOSK_DIR/preload.js" 2>/dev/null; then
            auto_show_enabled=true
            echo "  Mode: Auto-show on text fields"
        else
            echo "  Mode: Manual (3-finger tap or icon)"
        fi
    else
        echo "Status: Not installed"
    fi
    
    echo
    echo "Options:"
    if ! $keyboard_installed; then
        echo "  1. Install HTML Keyboard"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-1]: " choice
        
        case "$choice" in
            1) install_html_keyboard ;;
            0) return ;;
        esac
    else
        echo "  1. Toggle auto-show (currently: $([ $auto_show_enabled = true ] && echo 'enabled' || echo 'disabled'))"
        echo "  2. Test keyboard"
        echo "  3. View keyboard logs"
        echo "  4. SSH Credentials Helper"
        echo "  5. Uninstall"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-5]: " choice
        
        case "$choice" in
            1) toggle_keyboard_autoshow ;;
            2) test_html_keyboard ;;
            3) view_keyboard_logs ;;
            4) ssh_credentials_helper ;;
            5) uninstall_html_keyboard ;;
            0) return ;;
        esac
    fi
}

install_html_keyboard() {
    echo
    echo "Installing HTML On-Screen Keyboard..."
    echo
    
    # Create keyboard.html
    sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/keyboard.html" > /dev/null <<'KBHTML'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: rgba(0, 0, 0, 0.95);
      color: #ecf0f1;
      display: flex;
      flex-direction: column;
      justify-content: center;
      padding: 10px;
      overflow: hidden;
    }
    .keyboard { width: 100%; max-width: 1200px; margin: 0 auto; }
    .row { display: flex; justify-content: center; margin-bottom: 8px; gap: 6px; }
    .key {
      min-width: 60px; height: 60px;
      background: linear-gradient(135deg, #34495e 0%, #2c3e50 100%);
      border: 2px solid #4a5f7f; border-radius: 8px; color: white;
      font-size: 24px; font-weight: 600; cursor: pointer;
      display: flex; align-items: center; justify-content: center;
      transition: all 0.1s; user-select: none; box-shadow: 0 4px 8px rgba(0,0,0,0.3);
    }
    .key:active {
      transform: scale(0.95);
      background: linear-gradient(135deg, #3498db 0%, #2980b9 100%);
      border-color: #5dade2;
    }
    .key.space { flex: 3; }
    .key.wide { min-width: 90px; }
    .key.extra-wide { min-width: 120px; }
    .key.special {
      background: linear-gradient(135deg, #2c3e50 0%, #1a252f 100%);
      font-size: 16px;
    }
    .key.enter {
      background: linear-gradient(135deg, #27ae60 0%, #229954 100%);
      border-color: #52be80;
    }
    .key.backspace {
      background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
      border-color: #ec7063;
    }
    .key.shift, .key.caps {
      background: linear-gradient(135deg, #f39c12 0%, #d68910 100%);
      border-color: #f8c471;
    }
    .key.shift.active, .key.caps.active {
      background: linear-gradient(135deg, #16a085 0%, #138d75 100%);
      border-color: #48c9b0;
    }
    .header {
      text-align: center;
      margin-bottom: 10px;
      font-size: 16px;
      color: #bdc3c7;
    }
    .close-btn {
      position: absolute;
      top: 10px;
      right: 10px;
      width: 40px;
      height: 40px;
      background: rgba(231, 76, 60, 0.9);
      border: 2px solid #e74c3c;
      border-radius: 50%;
      color: white;
      font-size: 24px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.2s;
      z-index: 9999;
    }
    .close-btn:active {
      transform: scale(0.9);
      background: rgba(192, 57, 43, 0.9);
    }
  </style>
</head>
<body>
  <div class="close-btn" onclick="closeKeyboard()">×</div>
  
  <div class="keyboard">
    <div class="header">⌨️ Keyboard - 2-finger swipe down to reopen</div>
    
    <!-- Number Row -->
    <div class="row">
      <div class="key" data-key="1" data-shift="!" onclick="typeKey(this)">1</div>
      <div class="key" data-key="2" data-shift="@" onclick="typeKey(this)">2</div>
      <div class="key" data-key="3" data-shift="#" onclick="typeKey(this)">3</div>
      <div class="key" data-key="4" data-shift="$" onclick="typeKey(this)">4</div>
      <div class="key" data-key="5" data-shift="%" onclick="typeKey(this)">5</div>
      <div class="key" data-key="6" data-shift="^" onclick="typeKey(this)">6</div>
      <div class="key" data-key="7" data-shift="&" onclick="typeKey(this)">7</div>
      <div class="key" data-key="8" data-shift="*" onclick="typeKey(this)">8</div>
      <div class="key" data-key="9" data-shift="(" onclick="typeKey(this)">9</div>
      <div class="key" data-key="0" data-shift=")" onclick="typeKey(this)">0</div>
      <div class="key" data-key="-" data-shift="_" onclick="typeKey(this)">-</div>
      <div class="key" data-key="=" data-shift="+" onclick="typeKey(this)">=</div>
      <div class="key backspace wide" onclick="typeKey(this)" data-special="Backspace">⌫</div>
    </div>
    
    <!-- Top Row -->
    <div class="row">
      <div class="key special wide" onclick="typeKey(this)" data-special="Tab">Tab</div>
      <div class="key" data-key="q" onclick="typeKey(this)">q</div>
      <div class="key" data-key="w" onclick="typeKey(this)">w</div>
      <div class="key" data-key="e" onclick="typeKey(this)">e</div>
      <div class="key" data-key="r" onclick="typeKey(this)">r</div>
      <div class="key" data-key="t" onclick="typeKey(this)">t</div>
      <div class="key" data-key="y" onclick="typeKey(this)">y</div>
      <div class="key" data-key="u" onclick="typeKey(this)">u</div>
      <div class="key" data-key="i" onclick="typeKey(this)">i</div>
      <div class="key" data-key="o" onclick="typeKey(this)">o</div>
      <div class="key" data-key="p" onclick="typeKey(this)">p</div>
      <div class="key" data-key="[" data-shift="{" onclick="typeKey(this)">[</div>
      <div class="key" data-key="]" data-shift="}" onclick="typeKey(this)">]</div>
      <div class="key" data-key="\\" data-shift="|" onclick="typeKey(this)">\</div>
    </div>
    
    <!-- Home Row -->
    <div class="row">
      <div class="key caps special extra-wide" onclick="toggleCaps()" id="caps-key">Caps</div>
      <div class="key" data-key="a" onclick="typeKey(this)">a</div>
      <div class="key" data-key="s" onclick="typeKey(this)">s</div>
      <div class="key" data-key="d" onclick="typeKey(this)">d</div>
      <div class="key" data-key="f" onclick="typeKey(this)">f</div>
      <div class="key" data-key="g" onclick="typeKey(this)">g</div>
      <div class="key" data-key="h" onclick="typeKey(this)">h</div>
      <div class="key" data-key="j" onclick="typeKey(this)">j</div>
      <div class="key" data-key="k" onclick="typeKey(this)">k</div>
      <div class="key" data-key="l" onclick="typeKey(this)">l</div>
      <div class="key" data-key=";" data-shift=":" onclick="typeKey(this)">;</div>
      <div class="key" data-key="'" data-shift='"' onclick="typeKey(this)">'</div>
      <div class="key enter extra-wide" onclick="typeKey(this)" data-special="Enter">↵</div>
    </div>
    
    <!-- Bottom Row -->
    <div class="row">
      <div class="key shift extra-wide" onclick="toggleShift()" id="shift-left">⇧</div>
      <div class="key" data-key="z" onclick="typeKey(this)">z</div>
      <div class="key" data-key="x" onclick="typeKey(this)">x</div>
      <div class="key" data-key="c" onclick="typeKey(this)">c</div>
      <div class="key" data-key="v" onclick="typeKey(this)">v</div>
      <div class="key" data-key="b" onclick="typeKey(this)">b</div>
      <div class="key" data-key="n" onclick="typeKey(this)">n</div>
      <div class="key" data-key="m" onclick="typeKey(this)">m</div>
      <div class="key" data-key="," data-shift="<" onclick="typeKey(this)">,</div>
      <div class="key" data-key="." data-shift=">" onclick="typeKey(this)">.</div>
      <div class="key" data-key="/" data-shift="?" onclick="typeKey(this)">/</div>
      <div class="key shift extra-wide" onclick="toggleShift()" id="shift-right">⇧</div>
    </div>
    
    <!-- Space Row -->
    <div class="row">
      <div class="key special" onclick="typeKey(this)" data-special="Control">Ctrl</div>
      <div class="key special" onclick="typeKey(this)" data-special="Alt">Alt</div>
      <div class="key space" onclick="typeKey(this)" data-special=" ">Space</div>
      <div class="key special" onclick="typeKey(this)" data-special="Alt">Alt</div>
      <div class="key special" onclick="typeKey(this)" data-special="Control">Ctrl</div>
    </div>
  </div>
  
  <script>
    const { ipcRenderer } = require('electron');
    let shiftPressed = false;
    let capsLock = false;
    
    const shiftMap = {
      '1':'!', '2':'@', '3':'#', '4':'$', '5':'%',
      '6':'^', '7':'&', '8':'*', '9':'(', '0':')',
      '-':'_', '=':'+', '[':'{', ']':'}', '\\':'|',
      ';':':', '\'':'"', ',':'<', '.':'>', '/':'?'
    };
    
    function typeKey(element) {
      const special = element.getAttribute('data-special');
      if (special) {
        ipcRenderer.send('keyboard-type', special);
        return;
      }
      
      const baseKey = element.getAttribute('data-key');
      const shiftKey = element.getAttribute('data-shift');
      let finalKey = baseKey;
      
      if (/^[a-z]$/.test(baseKey)) {
        const shouldBeUpper = (shiftPressed && !capsLock) || (!shiftPressed && capsLock);
        finalKey = shouldBeUpper ? baseKey.toUpperCase() : baseKey.toLowerCase();
      } else if (shiftPressed && shiftKey) {
        finalKey = shiftKey;
      }
      
      ipcRenderer.send('keyboard-type', finalKey);
      
      if (shiftPressed) {
        shiftPressed = false;
        updateShiftDisplay();
        updateKeyDisplay();
      }
    }
    
    function toggleShift() {
      shiftPressed = !shiftPressed;
      updateShiftDisplay();
      updateKeyDisplay();
    }
    
    function toggleCaps() {
      capsLock = !capsLock;
      const capsKey = document.getElementById('caps-key');
      if (capsLock) {
        capsKey.classList.add('active');
      } else {
        capsKey.classList.remove('active');
      }
      updateKeyDisplay();
    }
    
    function updateShiftDisplay() {
      const shiftKeys = document.querySelectorAll('.shift');
      shiftKeys.forEach(key => {
        if (shiftPressed) {
          key.classList.add('active');
        } else {
          key.classList.remove('active');
        }
      });
    }
    
    function updateKeyDisplay() {
      const keys = document.querySelectorAll('.key[data-key]');
      keys.forEach(key => {
        const baseKey = key.getAttribute('data-key');
        const shiftKey = key.getAttribute('data-shift');
        if (/^[a-z]$/.test(baseKey)) {
          const shouldBeUpper = (shiftPressed && !capsLock) || (!shiftPressed && capsLock);
          key.textContent = shouldBeUpper ? baseKey.toUpperCase() : baseKey.toLowerCase();
        } else if (shiftKey) {
          key.textContent = shiftPressed ? shiftKey : baseKey;
        }
      });
    }
    
    function closeKeyboard() {
      ipcRenderer.send('close-keyboard');
    }
    
    updateKeyDisplay();
  </script>
</body>
</html>
KBHTML
    
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/keyboard.html"
    log_success "keyboard.html created"
    
    # Update keyboard button to show only when keyboard visible
    sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/keyboard-button.html" > /dev/null <<'BTNHTML'
<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { margin: 0; overflow: hidden; background: transparent; }
    #keyboard-btn {
      position: fixed;
      top: 20px;
      right: 20px;
      width: 60px;
      height: 60px;
      border-radius: 50%;
      background: rgba(46, 204, 113, 0.9);
      border: 3px solid rgba(255, 255, 255, 0.8);
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 32px;
      color: white;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
      transition: all 0.2s;
      z-index: 999999;
      user-select: none;
    }
    #keyboard-btn:active {
      transform: scale(0.95);
      background: rgba(39, 174, 96, 0.9);
    }
    #keyboard-btn.hidden {
      opacity: 0;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <div id="keyboard-btn" class="hidden" title="Close Keyboard">⌨️</div>
  <script>
    const { ipcRenderer } = require('electron');
    const btn = document.getElementById('keyboard-btn');
    
    ipcRenderer.on('keyboard-state', (event, state) => {
      if (state) {
        btn.classList.remove('hidden');
      } else {
        btn.classList.add('hidden');
      }
    });
    
    btn.addEventListener('click', () => {
      ipcRenderer.send('toggle-keyboard');
    });
  </script>
</body>
</html>
BTNHTML
    
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/keyboard-button.html"
    log_success "keyboard-button.html created"
    
    # Ask about auto-show
    echo
    echo "Keyboard Mode:"
    echo "  1. Auto-show on text fields (recommended)"
    echo "  2. Manual only (3-finger tap)"
    echo
    read -r -p "Choose mode [1]: " kb_mode
    kb_mode="${kb_mode:-1}"
    
    if [[ "$kb_mode" == "1" ]]; then
        enable_keyboard_autoshow
    else
        disable_keyboard_autoshow
    fi
    
    # Update main.js
    update_mainjs_keyboard
    
    log_success "HTML Keyboard installed"
    echo
    echo "Restart kiosk to activate: Main Menu → Option 4"
    pause
}

update_mainjs_keyboard() {
    local mainjs="$KIOSK_DIR/main.js"
    
    # Backup
    sudo cp "$mainjs" "${mainjs}.backup-htmlkb-$(date +%Y%m%d-%H%M%S)"
    
    # Add keyboard variables if not exists
    if ! sudo grep -q "let htmlKeyboardWindow" "$mainjs"; then
        sudo sed -i '/let keyboardWindow=null;/a let htmlKeyboardWindow=null;let keyboardButtonCheckInterval=null;' "$mainjs"
    fi
    
    # Add keyboard functions
    local tmpfunc=$(mktemp)
    cat > "$tmpfunc" <<'KBFUNC'

function showHTMLKeyboard(){
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.focus();
    return;
  }
  
  const{width,height}=mainWindow.getBounds();
  const kbHeight=Math.floor(height*0.4);
  const kbY=height-kbHeight;
  
  htmlKeyboardWindow=new BrowserWindow({
    width:width,
    height:kbHeight,
    x:0,
    y:kbY,
    frame:false,
    alwaysOnTop:true,
    skipTaskbar:true,
    webPreferences:{nodeIntegration:true,contextIsolation:false}
  });
  
  htmlKeyboardWindow.loadFile(path.join(__dirname,'keyboard.html'));
  
  htmlKeyboardWindow.on('closed',()=>{
    htmlKeyboardWindow=null;
  });
  
  // Focus first input field after keyboard shows
  setTimeout(()=>{
    let view=null;
    if(showingHidden&&hiddenViews[currentHiddenIndex]){
      view=hiddenViews[currentHiddenIndex];
    }else if(views[currentIndex]){
      view=views[currentIndex];
    }
    if(view&&view.webContents){
      view.webContents.executeJavaScript(`
        (function(){
          const inputs=document.querySelectorAll('input[type="text"],input[type="email"],input[type="password"],input[type="search"],input[type="tel"],input[type="url"],input[type="number"],textarea');
          if(inputs.length>0){
            inputs[0].focus();
            inputs[0].scrollIntoView({behavior:'smooth',block:'center'});
            console.log('[KB] Focused first input field');
            return true;
          }
          return false;
        })();
      `).catch(e=>console.error('[KB] Focus error:',e));
    }
  },300);
  
  console.log('[KEYBOARD] HTML keyboard shown');
}

function closeHTMLKeyboard(){
  if(!keyboardIsOpen){
    return;
  }
  
  const wasAutoClosed=keyboardClosePending;
  
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    htmlKeyboardWindow.close();
  }
  htmlKeyboardWindow=null;
  keyboardIsOpen=false;
  keyboardClosePending=false;
  notifyKeyboardState(false);
  
  // Notify all views if this was an auto-close
  if(wasAutoClosed){
    console.log('[KB] Auto-closed - notifying views');
    const allViews=[...views,...hiddenViews];
    allViews.forEach(view=>{
      if(view&&view.webContents){
        view.webContents.send('keyboard-auto-closed');
      }
    });
  }
  
  if(mainWindow&&!mainWindow.isDestroyed()){
    mainWindow.focus();
  }
  
  console.log('[KB] Closed'+(wasAutoClosed?' (auto)':' (manual)'));
}

function toggleHTMLKeyboard(){
  if(htmlKeyboardWindow&&!htmlKeyboardWindow.isDestroyed()){
    closeHTMLKeyboard();
  }else{
    showHTMLKeyboard();
  }
}

function toggleKeyboard(){
  toggleHTMLKeyboard();
}

KBFUNC
    
    sudo sed -i '/^function createWindow(){/e cat '"$tmpfunc" "$mainjs"
    rm "$tmpfunc"
    
    # Add keyboard button persistence
    if ! sudo grep -q "keyboardButtonCheckInterval=setInterval" "$mainjs"; then
        sudo sed -i '/createKeyboardButton();/a\  keyboardButtonCheckInterval=setInterval(()=>{if(!keyboardWindow||keyboardWindow.isDestroyed()){createKeyboardButton();}},3000);' "$mainjs"
    fi
    
    # Add IPC handlers
    if ! sudo grep -q "ipcMain.on('keyboard-type'" "$mainjs"; then
        sudo sed -i "/ipcMain.on('toggle-keyboard',toggleKeyboard);/a\
  ipcMain.on('keyboard-type',(event,key)=>
    if(!mainWindow||mainWindow.isDestroyed())return;\
    const view=mainWindow.getTopBrowserView();\
    if(view){\
      view.webContents.sendInputEvent({type:'keyDown',keyCode:key});\
      view.webContents.sendInputEvent({type:'char',keyCode:key});\
      view.webContents.sendInputEvent({type:'keyUp',keyCode:key});\
      markActivity();\
    }\
  });\
  ipcMain.on('close-keyboard',()=>{closeHTMLKeyboard();});\
  ipcMain.on('show-keyboard',()=>{if(!htmlKeyboardWindow||htmlKeyboardWindow.isDestroyed()){showHTMLKeyboard();}});\
  ipcMain.on('hide-keyboard',()=>{closeHTMLKeyboard();});" "$mainjs"
    fi
    
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$mainjs"
    log_success "main.js updated"
}

enable_keyboard_autoshow() {
    sudo cp "$KIOSK_DIR/preload.js" "$KIOSK_DIR/preload.js.backup-autoshow-$(date +%Y%m%d-%H%M%S)"
   
disable_keyboard_autoshow() {
    sudo cp "$KIOSK_DIR/preload.js" "$KIOSK_DIR/preload.js.backup-manual-$(date +%Y%m%d-%H%M%S)"
    
    # Set autoShowEnabled to false in the preload.js
    sudo sed -i 's/let autoShowEnabled = true/let autoShowEnabled = false/' "$KIOSK_DIR/preload.js"
    
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/preload.js"
    log_success "Auto-show disabled"
}
    sudo -u "$KIOSK_USER" tee "$KIOSK_DIR/preload.js" > /dev/null <<'PRELOAD'
const {contextBridge,ipcRenderer}=require('electron');

console.log('════════════════════════════════════════════════════════════');
console.log('  Jitsi PTT: SPACEBAR (hold to talk, release to listen)');
console.log('  Hidden Tab: 3-finger UP swipe (PIN protected)');
console.log('  Keyboard: 2-finger DOWN swipe (always available)');
console.log('════════════════════════════════════════════════════════════');

contextBridge.exposeInMainWorld('electronAPI', {
  notifyActivity: () => ipcRenderer.send('user-activity'),
  showKeyboard: () => ipcRenderer.send('show-keyboard')
});

window.addEventListener('DOMContentLoaded',()=>{
  document.addEventListener('contextmenu',e=>e.preventDefault());
  
  const SWIPE_THRESHOLD=120;
  const SWIPE_MAX_TIME=500;
  const SWIPE_TOLERANCE=50;
  
  let touchStartX=0;
  let touchStartY=0;
  let touchStartTime=0;
  let fingerCount=0;
  
  // Track keyboard state globally
  let keyboardVisible = false;
  let lastKeyboardRequest = 0;
  
  // Listen for keyboard state changes from main process
  ipcRenderer.on('keyboard-visible', (event, visible) => {
    keyboardVisible = visible;
    console.log(`[KEYBOARD] State: ${visible ? 'visible' : 'hidden'}`);
  });
  
  document.addEventListener('touchstart',e=>{
    if(e.touches.length>=1){
      touchStartX=e.touches[0].clientX;
      touchStartY=e.touches[0].clientY;
      touchStartTime=Date.now();
      fingerCount=e.touches.length;
    }
  },{passive:true});
  
  document.addEventListener('touchend',e=>{
    if(e.changedTouches.length>=1){
      const touchEndX=e.changedTouches[0].clientX;
      const touchEndY=e.changedTouches[0].clientY;
      const deltaX=touchEndX-touchStartX;
      const deltaY=touchEndY-touchStartY;
      const deltaTime=Date.now()-touchStartTime;
      
      if(deltaTime>SWIPE_MAX_TIME)return;
      
      const absX=Math.abs(deltaX);
      const absY=Math.abs(deltaY);
      
      // 3-finger UP = hidden tabs
      if(fingerCount===3 && absY>SWIPE_THRESHOLD && absX<SWIPE_TOLERANCE){
        if(deltaY<0){
          console.log('[TOUCH] 3-finger UP - show hidden tab');
          ipcRenderer.send('toggle-hidden');
        }
      }
      // 2-finger vertical DOWN = keyboard (ALWAYS works, no throttling)
      else if(fingerCount===2 && absY>SWIPE_THRESHOLD && absX<SWIPE_TOLERANCE && deltaY>0){
        const now = Date.now();
        console.log('[TOUCH] 2-finger DOWN - toggle keyboard');
        ipcRenderer.send('show-keyboard');
        lastKeyboardRequest = now;
      }
      // 2-finger HORIZONTAL = change tabs
      else if(fingerCount===2 && absX>SWIPE_THRESHOLD && absY<SWIPE_TOLERANCE){
        console.log('[TOUCH] 2-finger HORIZONTAL - change tab');
        ipcRenderer.send(deltaX>0?'swipe-right':'swipe-left');
      }
      // 1-finger HORIZONTAL = arrow keys
      else if(fingerCount===1 && absX>SWIPE_THRESHOLD && absY<SWIPE_TOLERANCE){
        const key=deltaX>0?'ArrowRight':'ArrowLeft';
        const keyCode=deltaX>0?39:37;
        ['keydown','keyup'].forEach(eventType=>{
          document.dispatchEvent(new KeyboardEvent(eventType,{
            key:key,code:key,keyCode:keyCode,which:keyCode,bubbles:true,cancelable:true
          }));
        });
      }
    }
  },{passive:true});
  
  // Optional: Auto-show on text field focus (can be disabled)
  let autoShowEnabled = true; // Set to false to disable auto-show
  
  if (autoShowEnabled) {
    function isTextInput(el){
      if(!el)return false;
      const tag=(el.tagName||'').toLowerCase();
      const type=(el.type||'').toLowerCase();
      const editable=el.isContentEditable===true||el.contentEditable==='true';
      const isInput=tag==='input'&&['text','email','password','search','tel','url','number'].includes(type);
      const isTextArea=tag==='textarea';
      return isInput||isTextArea||editable;
    }
    
    document.addEventListener('focusin',(e)=>{
      if(isTextInput(e.target) && !keyboardVisible){
        const now = Date.now();
        if (now - lastKeyboardRequest > 1000) {
          console.log('[AUTO-KB] Text field focused - showing keyboard');
          ipcRenderer.send('show-keyboard');
          lastKeyboardRequest = now;
        }
      }
    },true);
  }
});
PRELOAD
    
    sudo chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/preload.js"
    log_success "Manual mode enabled"
}

toggle_keyboard_autoshow() {
    if sudo grep -q "Auto-shows on text fields" "$KIOSK_DIR/preload.js" 2>/dev/null; then
        echo
        echo "Disabling auto-show..."
        disable_keyboard_autoshow
        echo "Keyboard will now only show via 3-finger tap"
    else
        echo
        echo "Enabling auto-show..."
        enable_keyboard_autoshow
        echo "Keyboard will auto-show on text fields"
    fi
    echo
    echo "Restart kiosk for changes: Main Menu → Option 4"
    pause
}

test_html_keyboard() {
    echo
    echo "Testing keyboard..."
    echo "The keyboard should appear when you restart the kiosk"
    echo "and tap on any text field (if auto-show enabled)"
    echo
    echo "Or use 3-finger tap to test manually"
    pause
}

view_keyboard_logs() {
    echo
    echo "Recent keyboard activity:"
    echo "─────────────────────────────────────────────"
    sudo tail -50 /home/kiosk/electron.log 2>/dev/null | grep -i "keyboard\|AUTO-SHOW\|3-finger TAP" || echo "No keyboard logs found"
    pause
}

ssh_credentials_helper() {
    clear
    echo "════════════════════════════════════════════════════════════"
    echo "   SSH CREDENTIALS HELPER                                    "
    echo "════════════════════════════════════════════════════════════"
    echo
    echo "This helps you paste complex passwords from SSH"
    echo
    
    local ip=$(get_ip_address)
    echo "Current IP: $ip"
    echo
    
    if systemctl is-active --quiet ssh; then
        echo "SSH: ✓ Running"
        echo
        echo "To use:"
        echo "  1. SSH into kiosk: ssh $(whoami)@$ip"
        echo "  2. Copy your password: echo 'your-complex-password'"
        echo "  3. Paste into website manually"
        echo
        echo "Or for auto-type (advanced):"
        echo "  ssh $(whoami)@$ip 'export DISPLAY=:0; xdotool type \"password\"'"
    else
        echo "SSH: ✗ Not running"
        echo
        read -r -p "Enable SSH? (y/n): " enable_ssh
        
        if [[ "$enable_ssh" =~ ^[Yy]$ ]]; then
            sudo systemctl enable ssh
            sudo systemctl start ssh
            sudo ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
            echo "✓ SSH enabled"
            echo
            echo "Connect: ssh $(whoami)@$ip"
        fi
    fi
    
    pause
}

uninstall_html_keyboard() {
    echo
    read -r -p "Remove HTML Keyboard? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    sudo rm -f "$KIOSK_DIR/keyboard.html"
    sudo rm -f "$KIOSK_DIR/keyboard-button.html"
    
    # Keyboard code remains in main.js (harmless)
    echo
    echo "Note: Keyboard code remains in main.js (inactive)"
    echo "Run Core Settings → Full Reinstall for complete cleanup"
    
    log_success "HTML Keyboard removed"
    pause
}
################################################################################
### SECTION 15: ADVANCED MENU FUNCTIONS
################################################################################

manual_electron_update() {
    clear
    echo "══════════════════════════════════════════════════════════"
    echo "   MANUAL ELECTRON UPDATE                                 "
    echo "══════════════════════════════════════════════════════════"
    echo ""

    # Check if kiosk directory exists (use sudo in case of restricted permissions)
    if ! sudo test -d "$KIOSK_DIR" 2>/dev/null; then
        log_error "Kiosk directory not found: $KIOSK_DIR"
        pause
        return 1
    fi

    # Function to get current electron version
    get_current_electron_version_local() {
        local package_json="$KIOSK_DIR/package.json"

        if ! sudo test -f "$package_json" 2>/dev/null; then
            echo "unknown"
            return 1
        fi

        # Try to get version from package.json (use sudo to read)
        local version=$(sudo grep -oP '"electron"\s*:\s*"\^?\K[0-9.]+' "$package_json" 2>/dev/null || echo "")

        if [ -z "$version" ]; then
            # Try to get from installed node_modules
            local electron_pkg="$KIOSK_DIR/node_modules/electron/package.json"
            if sudo test -f "$electron_pkg" 2>/dev/null; then
                version=$(sudo grep -oP '"version"\s*:\s*"\K[0-9.]+' "$electron_pkg" 2>/dev/null || echo "unknown")
            else
                version="not installed"
            fi
        fi

        echo "$version"
    }

    # Function to check if electron is running
    check_electron_running_local() {
        if pgrep -f "electron.*main.js" >/dev/null 2>&1; then
            return 0
        elif pgrep -f "node.*electron" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    }

    # Function to get latest electron version
    get_latest_electron_version_local() {
        log_info "Fetching latest stable Electron version from npm..." >&2

        local version=""

        # Method 1: Use npm view
        version=$(npm view electron version 2>/dev/null || echo "")

        # Method 2: Use curl to npm registry if npm view fails
        if [ -z "$version" ]; then
            version=$(curl -s https://registry.npmjs.org/electron/latest 2>/dev/null | grep -oP '"version"\s*:\s*"\K[0-9.]+' || echo "")
        fi

        # Method 3: Check GitHub releases as fallback
        if [ -z "$version" ]; then
            version=$(curl -s https://api.github.com/repos/electron/electron/releases/latest 2>/dev/null | grep -oP '"tag_name"\s*:\s*"v\K[0-9.]+' || echo "")
        fi

        if [ -z "$version" ]; then
            echo "unknown"
            return 1
        fi

        echo "$version"
    }

    # Get current version
    log_info "Checking current Electron version..."
    CURRENT_VERSION=$(get_current_electron_version_local)

    if [ "$CURRENT_VERSION" = "not installed" ]; then
        log_error "Electron is not installed in $KIOSK_DIR/node_modules/"
        log_error "Please run the kiosk installation first"
        pause
        return 1
    elif [ "$CURRENT_VERSION" = "unknown" ]; then
        log_warning "Could not determine current Electron version"
    else
        log_success "Current Electron version: $CURRENT_VERSION"
    fi
    echo ""

    # Check if electron is running
    if check_electron_running_local; then
        log_success "Electron app is running"
    else
        log_warning "Electron app does not appear to be running"
    fi
    echo ""

    # Ask if user wants to check for updates
    read -r -p "Check for latest Electron version? (y/n): " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update check cancelled"
        pause
        return 0
    fi

    # Get latest version
    LATEST_VERSION=$(get_latest_electron_version_local)

    if [ "$LATEST_VERSION" = "unknown" ]; then
        log_error "Could not fetch latest Electron version"
        log_error "Please check your internet connection"
        pause
        return 1
    fi

    log_success "Latest stable Electron version: $LATEST_VERSION"
    echo ""

    # Compare versions
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        log_success "You are already running the latest version!"
        echo ""
        read -r -p "Do you want to reinstall Electron $LATEST_VERSION? (y/n): " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Update cancelled"
            pause
            return 0
        fi
    fi

    # Show update summary
    echo "──────────────────────────────────────────────────────────"
    echo "UPDATE SUMMARY"
    echo "──────────────────────────────────────────────────────────"
    echo "Current version: $CURRENT_VERSION"
    echo "Target version:  $LATEST_VERSION"
    echo "Installation:    $KIOSK_DIR"
    echo ""

    # Extract major versions for breaking changes check
    CURRENT_MAJOR=$(echo "$CURRENT_VERSION" | cut -d'.' -f1)
    LATEST_MAJOR=$(echo "$LATEST_VERSION" | cut -d'.' -f1)

    # Show breaking changes warning
    log_warning "IMPORTANT: Check for breaking changes!"
    echo ""
    echo "Before updating, review the Electron release notes:"
    echo "  https://www.electronjs.org/docs/latest/breaking-changes"
    echo ""

    if [ "$LATEST_MAJOR" != "$CURRENT_MAJOR" ]; then
        log_warning "MAJOR VERSION CHANGE DETECTED! (v$CURRENT_MAJOR → v$LATEST_MAJOR)"
        echo ""
        echo "Major version changes may include:"
    else
        echo "Changes may include:"
    fi
    echo "  • API changes that require code updates"
    echo "  • Node.js version updates"
    echo "  • Chromium version updates"
    echo "  • Deprecated feature removals"
    echo ""

    # Confirm after reviewing breaking changes
    read -r -p "Have you reviewed the breaking changes and want to proceed? (y/n): " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled"
        pause
        return 0
    fi

    # Create backup
    echo ""
    log_info "Creating backup..."
    local kiosk_owner=$(sudo stat -c '%U' "$KIOSK_DIR")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${KIOSK_DIR}/backups/electron_backup_${timestamp}"

    sudo -u "$kiosk_owner" mkdir -p "$backup_dir"

    # Backup package.json and package-lock.json
    if sudo test -f "$KIOSK_DIR/package.json" 2>/dev/null; then
        sudo -u "$kiosk_owner" cp "$KIOSK_DIR/package.json" "$backup_dir/"
        log_success "Backed up package.json"
    fi

    if sudo test -f "$KIOSK_DIR/package-lock.json" 2>/dev/null; then
        sudo -u "$kiosk_owner" cp "$KIOSK_DIR/package-lock.json" "$backup_dir/"
        log_success "Backed up package-lock.json"
    fi

    # Save current Electron version
    echo "$CURRENT_VERSION" | sudo -u "$kiosk_owner" tee "$backup_dir/electron_version.txt" > /dev/null
    log_success "Backup created at: $backup_dir"
    echo ""

    # Show restore instructions
    echo "──────────────────────────────────────────────────────────"
    echo "RESTORE INSTRUCTIONS (if needed)"
    echo "──────────────────────────────────────────────────────────"
    echo "If you need to restore from backup:"
    echo "  1. sudo systemctl stop kiosk"
    echo "  2. sudo cp $backup_dir/package.json $KIOSK_DIR/"
    echo "  3. cd $KIOSK_DIR && sudo -u $KIOSK_USER npm install"
    echo "  4. sudo systemctl start kiosk"
    echo ""
    echo "Backup location: $backup_dir"
    echo ""

    # Final confirmation
    read -r -p "Proceed with Electron update to version $LATEST_VERSION? (y/n): " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled"
        log_info "Backup preserved at: $backup_dir"
        pause
        return 0
    fi

    # Perform update
    echo ""
    echo "──────────────────────────────────────────────────────────"
    echo "UPDATING ELECTRON"
    echo "──────────────────────────────────────────────────────────"

    log_info "Stopping kiosk display..."
    sudo systemctl stop lightdm || true
    sleep 2

    log_info "Updating Electron to version $LATEST_VERSION..."

    # Update package.json with new version
    sudo -u "$KIOSK_USER" sed -i "s/\"electron\": \".*\"/\"electron\": \"^$LATEST_VERSION\"/" "$KIOSK_DIR/package.json"

    # Remove old electron installation
    if sudo test -d "$KIOSK_DIR/node_modules/electron" 2>/dev/null; then
        log_info "Removing old Electron installation..."
        sudo -u "$KIOSK_USER" rm -rf "$KIOSK_DIR/node_modules/electron"
    fi

    # Install new version
    log_info "Installing Electron $LATEST_VERSION (this may take a few minutes)..."

    if sudo -u "$KIOSK_USER" bash -c "cd '$KIOSK_DIR' && npm install electron@'$LATEST_VERSION'" 2>&1 | tee /tmp/electron_install.log; then
        echo ""
        log_success "Electron updated successfully to version $LATEST_VERSION"

        # Fix chrome-sandbox permissions
        local sandbox="$KIOSK_DIR/node_modules/electron/dist/chrome-sandbox"
        if sudo test -f "$sandbox" 2>/dev/null; then
            sudo chown root:root "$sandbox"
            sudo chmod 4755 "$sandbox"
            log_success "Fixed chrome-sandbox permissions"
        fi

        # Verify new version
        NEW_VERSION=$(get_current_electron_version_local)
        echo ""
        log_success "Electron updated from $CURRENT_VERSION to $NEW_VERSION"
        echo ""

        # Restart kiosk display
        read -r -p "Restart kiosk display now? (y/n): " -n 1
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restarting kiosk display..."
            sudo systemctl start lightdm
            sleep 3

            if systemctl is-active --quiet lightdm; then
                log_success "Kiosk display started successfully"
            else
                log_error "Kiosk display failed to start"
                log_error "Check logs with: sudo journalctl -u lightdm -n 50"
                echo ""
                log_warning "You may need to restore from backup"
            fi
        else
            log_info "Kiosk display not started"
            log_info "Start manually with: sudo systemctl start lightdm"
        fi

        echo ""
        log_success "Backup preserved at: $backup_dir"
        log_info "You can delete the backup after confirming everything works"

    else
        echo ""
        log_error "Failed to install Electron $LATEST_VERSION"
        log_error "Check /tmp/electron_install.log for details"
        echo ""
        log_warning "Attempting to restore from backup..."

        # Restore package.json
        if sudo test -f "$backup_dir/package.json" 2>/dev/null; then
            sudo -u "$KIOSK_USER" cp "$backup_dir/package.json" "$KIOSK_DIR/"
            log_success "Restored package.json"
        fi

        # Reinstall original version
        log_info "Reinstalling original Electron version..."
        if sudo -u "$KIOSK_USER" bash -c "cd '$KIOSK_DIR' && npm install"; then
            log_success "Restored original Electron installation"

            # Restart kiosk display
            log_info "Restarting kiosk display..."
            sudo systemctl start lightdm
            log_success "Kiosk display restarted"
        else
            log_error "Failed to restore original installation"
            log_error "Manual intervention required"
        fi
    fi

    echo ""
    pause
}

system_diagnostics() {
    clear
    echo " ═══ SYSTEM DIAGNOSTICS ═══"
    echo
    
    echo "=== Kiosk Status ==="
    systemctl status lightdm --no-pager -l | head -20
    echo
    
    echo "=== Audio Status ==="
    sudo -u kiosk pactl info 2>/dev/null | grep -E "Server|User" || echo "Not running"
    echo
    
    echo "=== Network ==="
    echo "IP: $(get_ip_address)"
    echo "VPN: $(get_vpn_ips)"
    echo
    
    pause
}

view_logs() {
    clear
    echo " ═══ VIEW LOGS ═══"
    echo
    echo "  1. Electron log (last 50 lines)"
    echo "  2. LightDM log (last 50 lines)"
    echo "  3. PTT service log (last 50 lines)"
    echo "  4. System journal (last 100 lines)"
    echo "  0. Return"
    echo
    read -r -p "Choose [0-4]: " choice
    
    case "$choice" in
        1) 
            if sudo test -f /home/kiosk/electron.log; then
                sudo tail -50 /home/kiosk/electron.log
            else
                echo "No electron log found yet"
            fi
            pause
            ;;
        2) sudo tail -50 /var/log/lightdm/lightdm.log; pause ;;
        3) sudo journalctl -u jitsi-ptt -n 50; pause ;;
        4) sudo journalctl -n 100; pause ;;
        0) return ;;
    esac
}

factory_reset() {
    echo
    echo " ═══ FACTORY RESET ═══"
    echo
    echo "This will reset to default config but keep the system."
    echo
    read -r -p "Continue? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && return
    
    sudo -u "$KIOSK_USER" rm -f "$CONFIG_PATH"
    log_success "Config reset. Reconfigure via Core Settings."
    pause
}

export_config() {
    echo
    local export_file="kiosk-config-$(date +%Y%m%d-%H%M%S).json"
    sudo -u "$KIOSK_USER" cp "$CONFIG_PATH" "/tmp/$export_file" 2>/dev/null
    sudo chmod 644 "/tmp/$export_file"
    log_success "Config exported to /tmp/$export_file"
    pause
}

import_config() {
    echo
    read -r -p "Path to config file: " import_file
    if [[ -f "$import_file" ]]; then
        sudo -u "$KIOSK_USER" cp "$import_file" "$CONFIG_PATH"
        log_success "Config imported"
    else
        log_error "File not found"
    fi
    pause
}

network_test() {
    echo
    echo " ═══ NETWORK TEST ═══"
    echo
    echo "Ping test..."
    ping -c 4 8.8.8.8
    echo
    echo "DNS test..."
    nslookup google.com
    pause
}

audio_test() {
    echo
    echo " ═══ AUDIO TEST ═══"
    echo
    echo "Testing speaker..."
    speaker-test -t sine -f 1000 -l 1 2>/dev/null || echo "speaker-test not available"
    echo
    echo "PipeWire status:"
    pactl info
    pause
}

################################################################################
### SECTION 16: MENU SYSTEM
################################################################################

restart_kiosk_display() {
    clear
    echo " ═══ RESTART KIOSK DISPLAY ═══"
    echo
    echo "This will restart the display (LightDM)."
    echo "All services continue running."
    echo "Takes about 10 seconds."
    echo
    read -r -p "Restart now? (y/n): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Restarting..."
        sudo systemctl restart lightdm
    fi
}

show_main_menu() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════"
        echo "   Ubuntu Based Kiosk (UBK) v${SCRIPT_VERSION}                       "
        echo "════════════════════════════════════════════════════════════"
        echo
        
        show_system_status
        show_addon_status
        show_schedule_status
        
        echo "Main Menu:"
        echo "  1. Core Settings"
        echo "  2. Addons"
        echo "  3. Advanced"
        echo "  4. Restart Kiosk Display"
        echo "  0. Exit"
        echo
        read -r -p "Choose [0-4]: " choice
        
        case "$choice" in
            1) core_menu ;;
            2) addons_menu ;;
            3) advanced_menu ;;
            4) restart_kiosk_display ;;
            0) exit 0 ;;
        esac
    done
}


core_menu() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════"
        echo "   CORE SETTINGS                                             "
        echo "╚════════════════════════════════════════════════════════════╝"
        echo
        show_current_config
        echo
        echo "Options:"
        echo "  1. Timezone"
        echo "  2. Touch controls"
        echo "  3. Navigation security"
        echo "  4. Sites"
        echo "  5. WiFi"
        echo "  6. Power/Display/Quiet Hours"
        echo "  7. Optional Features (Pause/Keyboard)"
        echo "  8. Password Protection & Lockout"
        echo "  9. Full reinstall"
        echo "  10. Complete uninstall"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-10]: " choice

        case "$choice" in
            1) configure_timezone; pause ;;
            2) load_existing_config; configure_touch_controls; save_config ;;
            3) load_existing_config; configure_navigation_security; save_config ;;
            4) configure_sites ;;
            5) configure_wifi ;;
            6) configure_power_display_quiet ;;
            7) load_existing_config; if configure_optional_features; then save_config; fi ;;
            8) load_existing_config; if configure_password_protection; then save_config; fi ;;
            9) full_reinstall; return ;;
            10) complete_uninstall; return ;;
            0) return ;;
        esac
    done
}

addons_menu() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════"
        echo "   ADDONS MANAGEMENT                                             "
        echo "════════════════════════════════════════════════════════════"
        echo
        
        show_addon_status
        
        echo "Available Addons:"
        echo "  1. LMS Server / Squeezelite Player"
        echo "  2. CUPS Printing"
        echo "  3. Jitsi Intercom (web-based)"
        echo "  4. talkkonnect/Murmur Intercom (native audio)"
        echo "  5. On-Screen Keyboard"
        echo "  6. Remote Access (VNC/VPN)"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-6]: " choice
        
        case "$choice" in
            1) addon_lms_squeezelite ;;
            2) addon_cups ;;
            3) addon_jitsi_intercom ;;
            4) addon_talkkonnect_intercom ;;
            5) addon_onscreen_keyboard ;;
            6) remote_access_menu ;;
            0) return ;;
        esac
    done
}

remote_access_menu() {
    while true; do
        clear
        echo "════════════════════════════════════════════════════════════"
        echo "   REMOTE ACCESS                                             "
        echo "════════════════════════════════════════════════════════════"
        echo
        echo "Options:"
        echo "  1. VNC Remote Desktop"
        echo "  2. WireGuard VPN"
        echo "  3. Tailscale VPN"
        echo "  4. Netbird VPN"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-4]: " choice
        
        case "$choice" in
            1) addon_vnc ;;
            2) addon_wireguard ;;
            3) addon_tailscale ;;
            4) addon_netbird ;;
            0) return ;;
        esac
    done
}

audio_diagnostics() {
    clear
    echo "═══ AUDIO DIAGNOSTICS ═══"
    echo
    
    local issue_found=false
    
    echo "[1/8] Checking audio hardware..."
    if lspci 2>/dev/null | grep -i audio || lsusb 2>/dev/null | grep -i audio; then
        log_success "Audio hardware detected"
        lspci 2>/dev/null | grep -i audio || true
        lsusb 2>/dev/null | grep -i audio | head -3 || true
    else
        log_error "No audio hardware detected"
        issue_found=true
    fi
    echo
    
    echo "[2/8] Checking ALSA devices..."
    if aplay -l &>/dev/null; then
        log_success "ALSA devices found"
        aplay -l 2>/dev/null | grep -E "^card|device" || true
    else
        log_error "No ALSA devices"
        issue_found=true
    fi
    echo
    
    echo "[3/8] Checking PipeWire status..."
    local pipewire_running=false
    if sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl info &>/dev/null; then
        log_success "PipeWire accessible"
        pipewire_running=true
        sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl info 2>/dev/null | grep -E "Server|User|Host" || true
    else
        log_error "PipeWire not accessible to kiosk user"
        issue_found=true
        echo "  Try: sudo -u kiosk systemctl --user start pipewire pipewire-pulse"
    fi
    echo
    
    if $pipewire_running; then
        echo "[4/8] Checking audio sinks..."
        local sinks=$(sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl list sinks short 2>/dev/null)
        if [[ -n "$sinks" ]]; then
            echo "$sinks"
            local default_sink=$(sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl get-default-sink 2>/dev/null || echo "none")
            echo "Default: $default_sink"
        else
            log_error "No audio sinks found"
            issue_found=true
        fi
        echo
        
        echo "[5/8] Checking active streams..."
        local sink_inputs=$(sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl list sink-inputs short 2>/dev/null)
        if [[ -n "$sink_inputs" ]]; then
            echo "Active streams:"
            echo "$sink_inputs"
        else
            echo "No active streams"
        fi
        echo
    else
        echo "[4/8] Skipped - PipeWire not running"
        echo "[5/8] Skipped - PipeWire not running"
        echo
    fi
    
    echo "[6/8] Checking Squeezelite..."
    if systemctl is-active --quiet squeezelite; then
        log_success "Squeezelite running"
        
        if $pipewire_running; then
            local sq_pid=$(pgrep -f squeezelite | head -1)
            if [[ -n "$sq_pid" ]]; then
                if sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl list sink-inputs 2>/dev/null | grep -q "application.process.id = \"$sq_pid\""; then
                    log_success "Squeezelite connected to audio"
                else
                    log_warning "Squeezelite NOT connected to audio sink"
                    issue_found=true
                fi
            fi
        fi
    else
        echo "Squeezelite not running"
    fi
    echo
    
    if $pipewire_running; then
        echo "[7/8] Checking volume..."
        local volume=$(sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oE '[0-9]+%' | head -1 || echo "unknown")
        local muted=$(sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null || echo "unknown")
        echo "Volume: $volume"
        echo "Muted: $muted"
    else
        echo "[7/8] Skipped - PipeWire not running"
    fi
    echo
    
    echo "[8/8] Audio test..."
    read -r -p "Play test sound? (y/n): " play_test
    if [[ "$play_test" =~ ^[Yy]$ ]] && $pipewire_running; then
        echo "Playing beep..."
        sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" paplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || \
        sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $KIOSK_USER)" speaker-test -t sine -f 1000 -l 1 2>/dev/null || \
        echo "No test available"
    fi
    echo
    
    echo "═══════════════════════════════"
    if $issue_found; then
        echo "⚠️  ISSUES DETECTED - See above"
    else
        echo "✓ All checks passed"
    fi
    echo "═══════════════════════════════"
    
    pause
}

fix_squeezelite_audio() {
    clear
    echo "╔══ FIX SQUEEZELITE AUDIO ══╗"
    echo
    
    echo "This will attempt to fix Squeezelite audio issues by:"
    echo "  1. Restarting PipeWire"
    echo "  2. Resetting audio configuration"
    echo "  3. Restarting Squeezelite"
    echo
    read -r -p "Continue? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    echo
    echo "[1/6] Stopping Squeezelite..."
    sudo systemctl stop squeezelite
    sleep 2
    
    echo "[2/6] Restarting PipeWire..."
    local kiosk_uid=$(id -u "$KIOSK_USER")
    sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$kiosk_uid" systemctl --user restart pipewire pipewire-pulse wireplumber
    sleep 5
    
    echo "[3/6] Waiting for audio system..."
    for i in {1..10}; do
        if sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$kiosk_uid" pactl info &>/dev/null; then
            break
        fi
        sleep 1
    done
    
    echo "[4/6] Setting audio levels..."
    sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$kiosk_uid" pactl set-sink-volume @DEFAULT_SINK@ 100%
    sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$kiosk_uid" pactl set-source-volume @DEFAULT_SOURCE@ 100%
    sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$kiosk_uid" pactl set-source-mute @DEFAULT_SOURCE@ 0
    
    echo "[5/6] Starting Squeezelite..."
    sudo systemctl start squeezelite
    sleep 3
    
    echo "[6/6] Checking status..."
    if systemctl is-active --quiet squeezelite; then
        log_success "Squeezelite restarted"
        
        local sq_pid=$(pgrep -f squeezelite | head -1)
        if [[ -n "$sq_pid" ]]; then
            sleep 2
            if sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$kiosk_uid" pactl list sink-inputs 2>/dev/null | grep -q "application.process.id = \"$sq_pid\""; then
                log_success "Squeezelite connected to audio"
            else
                log_warning "Squeezelite started but not connected to audio sink"
                echo "  Check LMS server connection"
            fi
        fi
    else
        log_error "Squeezelite failed to start"
        echo "  Check logs: sudo journalctl -u squeezelite -n 50"
    fi
    
    pause
}
advanced_menu() {
    while true; do
        clear
        echo "══════════════════════════════════════════════════════════"
        echo "   ADVANCED OPTIONS                                          "
        echo "══════════════════════════════════════════════════════════"
        echo
        
        echo "Options:"
        echo "  1. Manual Electron Update"
        echo "  2. System Diagnostics"
        echo "  3. View Logs"
        echo "  4. Audio Diagnostics"
        echo "  5. Fix Squeezelite Audio"
        echo "  6. Factory Reset Config"
        echo "  9. Emergency Hotspot"
        echo " 10. Network Test"
        echo "  0. Return"
        echo
        read -r -p "Choose [0-10]: " choice
        
        case "$choice" in
            1) manual_electron_update ;;
            2) system_diagnostics ;;
            3) view_logs ;;
            4) audio_diagnostics ;;
            5) fix_squeezelite_audio ;;
            6) factory_reset ;;
            9) configure_emergency_hotspot ;;
            10) network_test ;;
            0) return ;;
        esac
    done
}
################################################################################
### SECTION 17: MAIN ENTRY POINT
################################################################################

# Verify not running as kiosk user
if [[ "$(whoami)" == "kiosk" ]]; then
    echo "ERROR: Cannot run as user 'kiosk'"
    exit 1
fi

# Verify not running as root
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run as regular user with sudo privileges"
    exit 1
fi

# Main execution
if is_kiosk_installed; then
    show_main_menu
else
    first_time_install
fi

exit 0
