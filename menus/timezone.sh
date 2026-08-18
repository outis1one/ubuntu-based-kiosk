#!/bin/bash
################################################################################
# menus/timezone.sh - "Timezone" menu.
#
# Third menu migrated off the old single-file installer, and a different
# shape again: not config.json at all - talks to timedatectl/system state
# directly. Also the clearest demonstration of the framework's value: the
# original hand-numbered an 18-entry list ("1) America/New_York ... 18)
# Enter manually") in a single case statement. Here the common-zone list
# is just data, one handler (action_pick_common_timezone) handles all of
# them using the number run_menu hands it, and adding/removing a zone
# from the list never touches numbering anywhere else.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

TIMEZONE_COMMON_ZONES=(
    "America/New_York" "America/Chicago" "America/Denver" "America/Los_Angeles"
    "America/Phoenix" "America/Anchorage" "Pacific/Honolulu" "Europe/London"
    "Europe/Paris" "Europe/Berlin" "Europe/Rome" "Asia/Tokyo" "Asia/Shanghai"
    "Asia/Dubai" "Australia/Sydney" "Pacific/Auckland"
)
TIMEZONE_COMMON_LABELS=(
    "US Eastern" "US Central" "US Mountain" "US Pacific" "US Arizona" "US Alaska"
    "US Hawaii" "UK" "Central Europe" "Germany" "Italy" "Japan" "China" "UAE"
    "Australia East" "New Zealand"
)

timezone_status() {
    echo "Current timezone: $(timedatectl show -p Timezone --value)"
}

timezone_menu_builder() {
    MENU_LABELS=()
    MENU_HANDLERS=()
    for i in "${!TIMEZONE_COMMON_ZONES[@]}"; do
        MENU_LABELS+=("${TIMEZONE_COMMON_ZONES[$i]} (${TIMEZONE_COMMON_LABELS[$i]})")
        MENU_HANDLERS+=(action_pick_common_timezone)
    done
    MENU_LABELS+=("Search for timezone by region" "Enter timezone manually")
    MENU_HANDLERS+=(action_search_timezone action_manual_timezone)
}

timezone_menu() {
    run_menu "TIMEZONE" timezone_menu_builder timezone_status
}

################################################################################
# Actions
################################################################################

# Called by run_menu as `action_pick_common_timezone "$choice"` - $choice is
# the 1-based menu number, which lines up directly with TIMEZONE_COMMON_ZONES.
action_pick_common_timezone() {
    local choice="$1"
    set_timezone "${TIMEZONE_COMMON_ZONES[$((choice - 1))]}"
}

action_search_timezone() {
    echo
    echo "Available regions:"
    local regions
    regions=($(timedatectl list-timezones | cut -d'/' -f1 | sort -u))
    for i in "${!regions[@]}"; do
        printf "  %2d) %s\n" "$((i + 1))" "${regions[$i]}"
    done
    echo

    local region_num
    region_num=$(ask_integer "Select region number (0=cancel)" "0" 0 "${#regions[@]}")
    [[ "$region_num" == "0" ]] && { echo "Cancelled"; return; }
    local selected_region="${regions[$((region_num - 1))]}"

    echo
    echo "Timezones in $selected_region:"
    local timezones
    timezones=($(timedatectl list-timezones | grep "^${selected_region}/"))
    for i in "${!timezones[@]}"; do
        printf "  %3d) %s\n" "$((i + 1))" "${timezones[$i]}"
    done
    echo

    local tz_num
    tz_num=$(ask_integer "Select timezone number (0=cancel)" "0" 0 "${#timezones[@]}")
    [[ "$tz_num" == "0" ]] && { echo "Cancelled"; return; }
    set_timezone "${timezones[$((tz_num - 1))]}"
}

action_manual_timezone() {
    echo
    local new_tz
    read -r -p "Enter timezone (e.g., America/New_York): " new_tz
    [[ -z "$new_tz" ]] && { echo "Cancelled"; return; }
    set_timezone "$new_tz"
}

################################################################################
# Shared apply logic
################################################################################

set_timezone() {
    local new_tz="$1"

    # A few legacy US/* aliases users might type manually - normalize before
    # validating against the canonical IANA list.
    case "$new_tz" in
        "US/Eastern") new_tz="America/New_York" ;;
        "US/Central") new_tz="America/Chicago" ;;
        "US/Mountain") new_tz="America/Denver" ;;
        "US/Pacific") new_tz="America/Los_Angeles" ;;
        "US/Alaska") new_tz="America/Anchorage" ;;
        "US/Hawaii") new_tz="Pacific/Honolulu" ;;
        "US/Arizona") new_tz="America/Phoenix" ;;
    esac

    if ! timedatectl list-timezones | grep -qx "$new_tz"; then
        log_error "Invalid timezone: $new_tz"
        return 1
    fi

    if sudo timedatectl set-timezone "$new_tz"; then
        log_success "Timezone updated to $new_tz"
    else
        # Fallback: set timezone directly without D-Bus
        sudo ln -sf "/usr/share/zoneinfo/$new_tz" /etc/localtime
        echo "$new_tz" | sudo tee /etc/timezone > /dev/null
        log_success "Timezone updated to $new_tz (direct)"
    fi
}
