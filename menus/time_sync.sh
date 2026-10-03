#!/bin/bash
################################################################################
# menus/time_sync.sh - "Time Server (NTP)" (Core Settings).
#
# The kiosk keeps its clock right with systemd-timesyncd, which by default
# asks Ubuntu's time servers on the internet. On a network with no
# internet that never works and the clock slowly drifts - which matters
# here, because lockout times, quiet hours and power schedules all go by
# it. This menu points timesyncd at a time server on the local network
# instead (most routers, Windows domain controllers and NAS boxes can
# serve NTP), or, with no time server at all, sets the clock by hand.
#
# Writes one drop-in, $TIMESYNCD_CONF_DIR/50-kiosk-ntp.conf - removing it
# (the "internet time servers" option, or Complete Uninstall via
# time_sync_do_reset) puts Ubuntu's defaults back untouched.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

TIMESYNC_DROPIN="$TIMESYNCD_CONF_DIR/50-kiosk-ntp.conf"

# The time server(s) this menu configured, or empty for Ubuntu's defaults.
time_sync_servers() {
    sed -n 's/^NTP=//p' "$TIMESYNC_DROPIN" 2>/dev/null | head -1
}

time_sync_status() {
    local servers synced
    servers=$(time_sync_servers)
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo "unknown")
    echo "Current time:  $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Time servers:  ${servers:-Ubuntu defaults (internet)}"
    echo "Synchronized:  $([[ "$synced" == "yes" ]] && echo "yes" || echo "no")"
}

time_sync_menu_builder() {
    MENU_LABELS=(
        "Use a time server on my network"
        "Use the internet time servers (Ubuntu default)"
        "Set the date and time manually"
        "Show sync details"
    )
    MENU_HANDLERS=(
        action_time_sync_lan
        action_time_sync_default
        action_time_sync_manual
        action_time_sync_details
    )
}

time_sync_menu() {
    run_menu "TIME SERVER (NTP)" time_sync_menu_builder time_sync_status
}

# Validate a space-separated list of hostnames / IPv4 / IPv6 addresses.
time_sync_valid_servers() {
    local s
    [[ -n "$1" ]] || return 1
    for s in $1; do
        [[ "$s" =~ ^[A-Za-z0-9.:-]+$ ]] || return 1
    done
}

time_sync_apply() {
    sudo systemctl enable systemd-timesyncd 2>/dev/null || true
    sudo timedatectl set-ntp true 2>/dev/null || true
    sudo systemctl restart systemd-timesyncd 2>/dev/null || true
}

# Remove this menu's drop-in, back to Ubuntu's default time servers.
# Also used by Complete Uninstall.
time_sync_do_reset() {
    sudo rm -f "$TIMESYNC_DROPIN"
    time_sync_apply
}

################################################################################
# Actions
################################################################################

action_time_sync_lan() {
    echo
    echo "Enter the address of a time (NTP) server on your network - often"
    echo "the router (e.g. 192.168.1.1), a Windows domain controller, or a"
    echo "NAS. Several can be given, separated by spaces."
    local current servers
    current=$(time_sync_servers)
    servers=$(ask_text "Time server(s)" "${current:-$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')}")
    if ! time_sync_valid_servers "$servers"; then
        log_error "Not a valid address list: '$servers'"
        pause
        return 1
    fi

    sudo mkdir -p "$TIMESYNCD_CONF_DIR"
    sudo tee "$TIMESYNC_DROPIN" > /dev/null <<EOF
# Written by ubuntu-based-kiosk (Core Settings -> Time Server).
# Delete this file to go back to Ubuntu's default time servers.
[Time]
NTP=$servers
EOF
    time_sync_apply

    echo "Checking the time server (up to 15 seconds)..."
    local i
    for i in {1..15}; do
        if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]]; then
            log_success "Clock synchronized with $servers"
            pause
            return
        fi
        sleep 1
    done
    log_warning "Saved, but no sync yet. timesyncd keeps retrying in the background."
    echo "If it never syncs, check the address and that the server answers"
    echo "NTP (UDP port 123): Core Settings -> Time Server -> Show sync details."
    pause
}

action_time_sync_default() {
    echo
    if [[ ! -f "$TIMESYNC_DROPIN" ]]; then
        echo "Already using Ubuntu's default (internet) time servers."
        pause
        return
    fi
    time_sync_do_reset
    log_success "Back on Ubuntu's default (internet) time servers"
    pause
}

# For a network with no time server at all: set the clock by hand.
# Automatic sync stays on afterwards - it just has nothing to sync with
# until a server becomes reachable, and then takes over again.
action_time_sync_manual() {
    echo
    echo "Current time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Enter the correct local date and time (timezone: $(timedatectl show -p Timezone --value 2>/dev/null))."
    local when
    when=$(ask_text "Date and time (YYYY-MM-DD HH:MM)" "$(date '+%Y-%m-%d %H:%M')")
    if [[ ! "$when" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]] || ! date -d "$when" &>/dev/null; then
        log_error "Not a valid date/time: '$when' (expected e.g. 2026-10-03 14:30)"
        pause
        return 1
    fi
    [[ "$when" =~ :[0-9]{2}:[0-9]{2}$ ]] || when="$when:00"

    # timedatectl refuses set-time while automatic sync is on.
    sudo timedatectl set-ntp false 2>/dev/null || true
    if sudo timedatectl set-time "$when"; then
        # Keep the hardware clock in step so the time survives a reboot.
        sudo hwclock --systohc 2>/dev/null || true
        log_success "Clock set to $(date '+%Y-%m-%d %H:%M:%S %Z')"
    else
        log_error "Couldn't set the clock"
    fi
    sudo timedatectl set-ntp true 2>/dev/null || true
    pause
}

action_time_sync_details() {
    echo
    timedatectl status 2>/dev/null || true
    echo
    timedatectl timesync-status 2>/dev/null || echo "(timesync-status not available)"
    pause
}
