#!/bin/bash
################################################################################
# menus/power_schedule.sh - "Power / Display / Quiet Hours" menu.
#
# Sixth menu migrated, and the biggest and riskiest so far: it writes
# systemd timers/services, a cron entry, and shell scripts that can power
# off the physical machine, blank the display, mute audio, and (via RTC)
# wake the machine back up on a schedule. Every write goes through
# $SYSTEMD_DIR / $CRON_D_DIR / $BIN_DIR (lib/config.sh) rather than
# hardcoded /etc/systemd/system, /etc/cron.d, /usr/local/bin, so tests can
# point them at a scratch directory - this file must never assume it's
# safe to actually mutate the real system just because it's running.
#
# Deliberately out of scope: the legacy dispatcher's "6. Test schedules &
# system" led into a shared diagnostics submenu (audio test, network
# test, keyboard test, ...) that isn't specific to scheduling and belongs
# with a future Advanced/Diagnostics migration instead. What *is* in
# scope - testing the schedule you just configured - stays here as the
# same inline "test now?" prompts the legacy menu already had.
#
# Bug fixed vs. the legacy configure_power_display_quiet: it refused to
# even open "Configure power schedule" when no RTC wake was detected,
# even though shutdown-only scheduling (configure_power_schedule's own
# fallback) never needed RTC in the first place. Also: none of shutdown
# time/wake time/display off/on/quiet start/end/custom Electron reload
# time were validated as HH:MM in the legacy menu (plain `read`, no
# format check) - a typo would silently produce a broken OnCalendar=
# value. All of those now go through ask_time.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

################################################################################
# Shared helpers
################################################################################

rtc_wake_available() {
    [[ -w /sys/class/rtc/rtc0/wakealarm ]] || sudo test -w /sys/class/rtc/rtc0/wakealarm 2>/dev/null
}

timer_exists() {
    [[ -f "$SYSTEMD_DIR/$1" ]]
}

timer_oncalendar() {
    grep "^OnCalendar=" "$SYSTEMD_DIR/$1" 2>/dev/null | cut -d'=' -f2 | sed 's/\*-\*-\* //' | sed 's/:00$//'
}

# enable_and_start_timers TIMER [TIMER...]
# Reloads systemd and enables+starts the given timer units, returning
# non-zero if enable or start fails (e.g. systemd/D-Bus unreachable).
# Always call this from an `if`/`&&`/`||` context: this whole tool runs
# under set -e, so a bare, unguarded call whose last command fails would
# take down the entire session instead of just this one action.
enable_and_start_timers() {
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable "$@" 2>/dev/null && sudo systemctl start "$@" 2>/dev/null
}

################################################################################
# Top-level menu
################################################################################

power_schedule_status() {
    local any=false

    if timer_exists kiosk-shutdown.timer; then
        any=true
        local t; t=$(timer_oncalendar kiosk-shutdown.timer)
        echo "Power:    shutdown daily at ${t:-an unknown time}"
    fi
    if timer_exists kiosk-display-off.timer; then
        any=true
        echo "Display:  off at $(timer_oncalendar kiosk-display-off.timer), on at $(timer_oncalendar kiosk-display-on.timer)"
    fi
    if timer_exists kiosk-quiet-start.timer; then
        any=true
        echo "Quiet:    $(timer_oncalendar kiosk-quiet-start.timer) to $(timer_oncalendar kiosk-quiet-end.timer)"
    fi
    if timer_exists kiosk-electron-reload.timer; then
        any=true
        echo "Reload:   enabled ($(timer_oncalendar kiosk-electron-reload.timer))"
    fi
    $any || echo "No schedules configured"

    echo
    if rtc_wake_available; then
        echo "RTC wake: available (can schedule power on/off)"
    else
        echo "RTC wake: not available (display/quiet/reload scheduling still works)"
    fi
}

power_schedule_menu_builder() {
    MENU_LABELS=(
        "Configure power schedule$(rtc_wake_available || echo ' (shutdown only - no RTC wake)')"
        "Configure display schedule"
        "Configure quiet hours"
        "Configure Electron reload schedule"
        "Remove all schedules"
    )
    MENU_HANDLERS=(
        action_configure_power_schedule
        action_configure_display_schedule
        action_configure_quiet_hours
        electron_reload_menu
        action_remove_all_schedules
    )
}

power_schedule_menu() {
    run_menu "POWER / DISPLAY / QUIET HOURS" power_schedule_menu_builder power_schedule_status
}

################################################################################
# Power schedule
################################################################################

action_configure_power_schedule() {
    echo
    local rtc_ok=false
    rtc_wake_available && rtc_ok=true

    if $rtc_ok; then
        echo "RTC wake capability detected - can schedule shutdown and wake."
    else
        echo "RTC wake not available - shutdown only, no auto-wake."
    fi
    echo

    local shutdown_time wake_time=""
    shutdown_time=$(ask_time "Shutdown time (24-hour HH:MM)" "22:00")
    $rtc_ok && wake_time=$(ask_time "Wake time (24-hour HH:MM)" "06:00")

    sudo systemctl stop kiosk-shutdown.timer 2>/dev/null || true
    sudo systemctl disable kiosk-shutdown.timer 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR/kiosk-shutdown.service" "$SYSTEMD_DIR/kiosk-shutdown.timer"
    sudo rm -f "$BIN_DIR/kiosk-power-off.sh" "$BIN_DIR/rtc-wake.sh"
    sudo rm -f "$CRON_D_DIR/kiosk-rtc-wake"

    sudo tee "$BIN_DIR/kiosk-power-off.sh" > /dev/null <<'EOF'
#!/bin/bash
logger "KIOSK: Scheduled shutdown initiated"
systemctl poweroff
EOF
    sudo chmod +x "$BIN_DIR/kiosk-power-off.sh"

    sudo tee "$SYSTEMD_DIR/kiosk-shutdown.service" > /dev/null <<EOF
[Unit]
Description=Kiosk Scheduled Shutdown

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/kiosk-power-off.sh
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-shutdown.timer" > /dev/null <<EOF
[Unit]
Description=Kiosk Shutdown Timer

[Timer]
OnCalendar=*-*-* ${shutdown_time}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    if $rtc_ok && [[ -n "$wake_time" ]]; then
        sudo tee "$BIN_DIR/rtc-wake.sh" > /dev/null <<'RTCSCRIPT'
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
        sudo chmod +x "$BIN_DIR/rtc-wake.sh"

        local shutdown_hour="${shutdown_time%%:*}"
        local shutdown_min="${shutdown_time##*:}"
        local wake_min=$((10#$shutdown_min - 5))
        local wake_hour=$((10#$shutdown_hour))
        [[ $wake_min -lt 0 ]] && { wake_min=$((wake_min + 60)); wake_hour=$((wake_hour - 1)); }
        [[ $wake_hour -lt 0 ]] && wake_hour=$((wake_hour + 24))

        sudo tee "$CRON_D_DIR/kiosk-rtc-wake" > /dev/null <<EOF
# Set RTC wake alarm 5 minutes before shutdown
$wake_min $wake_hour * * * root ${BIN_DIR}/rtc-wake.sh "$wake_time" >> /var/log/kiosk-rtc.log 2>&1
EOF
        log_info "RTC wake cron job created"
    fi

    if enable_and_start_timers kiosk-shutdown.timer; then
        log_success "Power schedule configured: shutdown at ${shutdown_time}$( [[ -n "$wake_time" ]] && echo ", wake at ${wake_time}")"
    else
        log_warning "Schedule files written, but systemctl enable/start failed - check 'systemctl status kiosk-shutdown.timer'"
    fi
}

################################################################################
# Display schedule
################################################################################

action_configure_display_schedule() {
    echo
    if timer_exists kiosk-shutdown.timer; then
        log_warning "Power shutdown configured at $(timer_oncalendar kiosk-shutdown.timer) - display will already be off by then"
        echo
    fi

    local doff don
    doff=$(ask_time "Display OFF time (24-hour HH:MM)" "22:00")
    don=$(ask_time "Display ON time (24-hour HH:MM)" "06:00")

    sudo systemctl stop kiosk-display-off.timer kiosk-display-on.timer 2>/dev/null || true
    sudo systemctl disable kiosk-display-off.timer kiosk-display-on.timer 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR"/kiosk-display-off.{service,timer} "$SYSTEMD_DIR"/kiosk-display-on.{service,timer}
    sudo rm -f "$BIN_DIR/kiosk-display-off.sh" "$BIN_DIR/kiosk-display-on.sh"

    sudo tee "$BIN_DIR/kiosk-display-off.sh" > /dev/null <<EOF
#!/bin/bash
# Turn off display using multiple methods for reliability
export DISPLAY=:0
export XAUTHORITY=${KIOSK_HOME}/.Xauthority

logger "KIOSK: Display OFF script starting"

# Method 1: xset via kiosk user
sudo -u ${KIOSK_USER} DISPLAY=:0 XAUTHORITY=${KIOSK_HOME}/.Xauthority xset dpms force off 2>/dev/null && logger "KIOSK: xset dpms off success" || logger "KIOSK: xset dpms off failed"

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
    sudo chmod +x "$BIN_DIR/kiosk-display-off.sh"

    sudo tee "$BIN_DIR/kiosk-display-on.sh" > /dev/null <<EOF
#!/bin/bash
# Turn on display using multiple methods for reliability
export DISPLAY=:0
export XAUTHORITY=${KIOSK_HOME}/.Xauthority

logger "KIOSK: Display ON script starting"

# Method 1: xset via kiosk user
sudo -u ${KIOSK_USER} DISPLAY=:0 XAUTHORITY=${KIOSK_HOME}/.Xauthority xset dpms force on 2>/dev/null && logger "KIOSK: xset dpms on success" || logger "KIOSK: xset dpms on failed"

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
sudo -u ${KIOSK_USER} DISPLAY=:0 XAUTHORITY=${KIOSK_HOME}/.Xauthority xdotool mousemove 1 1 2>/dev/null && logger "KIOSK: mouse wiggle success" || logger "KIOSK: mouse wiggle failed"

# Method 5: Signal Electron app to require password if enabled
sudo -u ${KIOSK_USER} touch ${KIOSK_DIR}/.display-wake 2>/dev/null && logger "KIOSK: password flag set" || logger "KIOSK: password flag failed"

logger "KIOSK: Display turned ON (scheduled)"
EOF
    sudo chmod +x "$BIN_DIR/kiosk-display-on.sh"

    sudo tee "$SYSTEMD_DIR/kiosk-display-off.service" > /dev/null <<EOF
[Unit]
Description=Kiosk Display Off

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/kiosk-display-off.sh
StandardOutput=journal
StandardError=journal
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-display-on.service" > /dev/null <<EOF
[Unit]
Description=Kiosk Display On

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/kiosk-display-on.sh
StandardOutput=journal
StandardError=journal
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-display-off.timer" > /dev/null <<EOF
[Unit]
Description=Kiosk Display Off Timer

[Timer]
OnCalendar=*-*-* ${doff}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-display-on.timer" > /dev/null <<EOF
[Unit]
Description=Kiosk Display On Timer

[Timer]
OnCalendar=*-*-* ${don}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    if enable_and_start_timers kiosk-display-off.timer kiosk-display-on.timer; then
        log_success "Display schedule configured: off at ${doff}, on at ${don}"
    else
        log_warning "Schedule files written, but systemctl enable/start failed - check 'systemctl status kiosk-display-off.timer'"
    fi

    echo
    if ask_yes_no "Test display control now?" "n"; then
        echo "Testing display OFF in 3 seconds..."
        sleep 3
        sudo "$BIN_DIR/kiosk-display-off.sh"
        echo "Waiting 5 seconds..."
        sleep 5
        echo "Testing display ON..."
        sudo "$BIN_DIR/kiosk-display-on.sh"
        log_success "Display test complete"
    fi
}

################################################################################
# Quiet hours
################################################################################

action_configure_quiet_hours() {
    echo
    timer_exists kiosk-shutdown.timer && echo "Power shutdown: $(timer_oncalendar kiosk-shutdown.timer)"
    if timer_exists kiosk-display-off.timer; then
        echo "Display: off at $(timer_oncalendar kiosk-display-off.timer), on at $(timer_oncalendar kiosk-display-on.timer)"
    fi
    echo

    local qstart qend qmode
    qstart=$(ask_time "Quiet hours start (24-hour HH:MM)" "22:00")
    qend=$(ask_time "Quiet hours end (24-hour HH:MM)" "07:00")

    echo
    echo "What should be muted during quiet hours?"
    echo "  1. All audio (mute system)"
    echo "  2. Squeezelite only (stop music player)"
    read -r -p "Choice [1]: " qmode
    qmode="${qmode:-1}"

    sudo systemctl stop kiosk-quiet-start.timer kiosk-quiet-end.timer 2>/dev/null || true
    sudo systemctl disable kiosk-quiet-start.timer kiosk-quiet-end.timer 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR"/kiosk-quiet-start.{service,timer} "$SYSTEMD_DIR"/kiosk-quiet-end.{service,timer}
    sudo rm -f "$BIN_DIR/kiosk-quiet-start.sh" "$BIN_DIR/kiosk-quiet-end.sh"

    case "$qmode" in
        2)
            sudo tee "$BIN_DIR/kiosk-quiet-start.sh" > /dev/null <<'EOF'
#!/bin/bash
systemctl stop squeezelite 2>/dev/null
logger "KIOSK: Quiet hours started - Squeezelite stopped"
echo "✓ Quiet hours: Squeezelite stopped"
EOF
            sudo tee "$BIN_DIR/kiosk-quiet-end.sh" > /dev/null <<'EOF'
#!/bin/bash
systemctl start squeezelite 2>/dev/null
logger "KIOSK: Quiet hours ended - Squeezelite started"
echo "✓ Quiet hours ended: Squeezelite started"
EOF
            ;;
        *)
            qmode=1
            sudo tee "$BIN_DIR/kiosk-quiet-start.sh" > /dev/null <<'EOF'
#!/bin/bash
# Save current volume before muting
pactl get-sink-volume @DEFAULT_SINK@ | grep -oE '[0-9]+%' | head -1 | tr -d '%' > /tmp/kiosk-vol-backup 2>/dev/null || echo "100" > /tmp/kiosk-vol-backup
pactl set-sink-mute @DEFAULT_SINK@ 1 2>/dev/null
logger "KIOSK: Quiet hours started - all audio muted"
echo "✓ Quiet hours: All audio muted"
EOF
            sudo tee "$BIN_DIR/kiosk-quiet-end.sh" > /dev/null <<'EOF'
#!/bin/bash
# Restore previous volume
VOL=$(cat /tmp/kiosk-vol-backup 2>/dev/null || echo "100")
pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null
pactl set-sink-volume @DEFAULT_SINK@ ${VOL}% 2>/dev/null
logger "KIOSK: Quiet hours ended - audio restored to ${VOL}%"
echo "✓ Quiet hours ended: Audio restored to ${VOL}%"
EOF
            ;;
    esac
    sudo chmod +x "$BIN_DIR/kiosk-quiet-start.sh" "$BIN_DIR/kiosk-quiet-end.sh"

    sudo tee "$SYSTEMD_DIR/kiosk-quiet-start.service" > /dev/null <<EOF
[Unit]
Description=Kiosk Quiet Hours Start

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/kiosk-quiet-start.sh
StandardOutput=journal
StandardError=journal
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-quiet-end.service" > /dev/null <<EOF
[Unit]
Description=Kiosk Quiet Hours End

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/kiosk-quiet-end.sh
StandardOutput=journal
StandardError=journal
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-quiet-start.timer" > /dev/null <<EOF
[Unit]
Description=Kiosk Quiet Hours Start Timer

[Timer]
OnCalendar=*-*-* ${qstart}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-quiet-end.timer" > /dev/null <<EOF
[Unit]
Description=Kiosk Quiet Hours End Timer

[Timer]
OnCalendar=*-*-* ${qend}:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    local mode_label="All audio muted"
    [[ "$qmode" == "2" ]] && mode_label="Squeezelite stopped"

    if enable_and_start_timers kiosk-quiet-start.timer kiosk-quiet-end.timer; then
        log_success "Quiet hours configured: ${qstart} to ${qend} (${mode_label})"
    else
        log_warning "Schedule files written, but systemctl enable/start failed - check 'systemctl status kiosk-quiet-start.timer'"
    fi

    echo
    if ask_yes_no "Test quiet hours now?" "n"; then
        echo "Testing quiet START..."
        sudo "$BIN_DIR/kiosk-quiet-start.sh"
        echo "Waiting 5 seconds..."
        sleep 5
        echo "Testing quiet END..."
        sudo "$BIN_DIR/kiosk-quiet-end.sh"
        log_success "Quiet hours test complete"
    fi
}

################################################################################
# Electron reload schedule (its own small nested menu, mirroring the
# legacy configure_electron_reload's "configured vs not" dispatch)
################################################################################

electron_reload_menu_builder() {
    if timer_exists kiosk-electron-reload.timer; then
        MENU_LABELS=("Change schedule" "Disable automatic reload")
        MENU_HANDLERS=(electron_reload_custom action_disable_electron_reload)
    else
        MENU_LABELS=("Daily at 3am" "Every 3 days at 3am" "Custom schedule")
        MENU_HANDLERS=(action_electron_reload_daily action_electron_reload_every_3_days electron_reload_custom)
    fi
}

electron_reload_status() {
    if timer_exists kiosk-electron-reload.timer; then
        echo "Automatic reload: enabled ($(timer_oncalendar kiosk-electron-reload.timer))"
    else
        echo "Automatic reload: not configured"
    fi
}

electron_reload_menu() {
    run_menu "ELECTRON RELOAD SCHEDULE" electron_reload_menu_builder electron_reload_status
}

# setup_electron_reload_timer SCHEDULE DESCRIPTION
# SCHEDULE is a systemd OnCalendar= expression, not just a time - unlike
# the shutdown/display/quiet timers above, so it isn't run through ask_time.
setup_electron_reload_timer() {
    local schedule="$1"
    local description="$2"

    sudo systemctl stop kiosk-electron-reload.timer 2>/dev/null || true
    sudo systemctl disable kiosk-electron-reload.timer 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR"/kiosk-electron-reload.{service,timer}
    sudo rm -f "$BIN_DIR/kiosk-reload-electron"

    sudo tee "$BIN_DIR/kiosk-reload-electron" > /dev/null <<'RELOADSCRIPT'
#!/bin/bash
logger "KIOSK: Scheduled Electron reload"
systemctl restart lightdm
RELOADSCRIPT
    sudo chmod +x "$BIN_DIR/kiosk-reload-electron"

    sudo tee "$SYSTEMD_DIR/kiosk-electron-reload.service" > /dev/null <<EOF
[Unit]
Description=Reload Electron App

[Service]
Type=oneshot
ExecStart=${BIN_DIR}/kiosk-reload-electron
EOF

    sudo tee "$SYSTEMD_DIR/kiosk-electron-reload.timer" > /dev/null <<EOF
[Unit]
Description=Electron Reload Timer

[Timer]
OnCalendar=$schedule
Persistent=true

[Install]
WantedBy=timers.target
EOF

    if enable_and_start_timers kiosk-electron-reload.timer; then
        log_success "Electron reload configured: $description"
    else
        log_warning "Schedule files written, but systemctl enable/start failed - check 'systemctl status kiosk-electron-reload.timer'"
    fi
}

action_electron_reload_daily() {
    setup_electron_reload_timer "*-*-* 03:00:00" "daily at 3am"
}

action_electron_reload_every_3_days() {
    setup_electron_reload_timer "*-*-1,4,7,10,13,16,19,22,25,28,31 03:00:00" "every 3 days at 3am"
}

electron_reload_custom() {
    echo
    echo "Custom schedule options:"
    echo "  1. Every X days at a specific time"
    echo "  2. Daily at a custom time"
    echo "  3. Specific weekday"
    echo "  0. Cancel"
    echo

    local choice
    choice=$(ask_integer "Choose" "0" 0 3)
    [[ "$choice" == "0" ]] && { echo "Cancelled"; return; }

    local schedule="" description=""
    case "$choice" in
        1)
            local days time day_list=""
            days=$(ask_integer "Reload every X days" "3" 1 31)
            time=$(ask_time "Time (24-hour HH:MM)" "03:00")
            for ((d = 1; d <= 31; d += days)); do
                day_list="${day_list}${d},"
            done
            day_list="${day_list%,}"
            schedule="*-*-${day_list} ${time}:00"
            description="every ${days} days at ${time}"
            ;;
        2)
            local time
            time=$(ask_time "Time (24-hour HH:MM)" "03:00")
            schedule="*-*-* ${time}:00"
            description="daily at ${time}"
            ;;
        3)
            local day time
            echo "Days: Mon Tue Wed Thu Fri Sat Sun"
            read -r -p "Enter day: " day
            time=$(ask_time "Time (24-hour HH:MM)" "03:00")
            schedule="${day} *-*-* ${time}:00"
            description="every ${day} at ${time}"
            ;;
    esac

    setup_electron_reload_timer "$schedule" "$description"
}

action_disable_electron_reload() {
    if ask_yes_no "Disable automatic Electron reload?" "n"; then
        sudo systemctl stop kiosk-electron-reload.timer 2>/dev/null || true
        sudo systemctl disable kiosk-electron-reload.timer 2>/dev/null || true
        sudo rm -f "$SYSTEMD_DIR"/kiosk-electron-reload.{service,timer}
        sudo rm -f "$BIN_DIR/kiosk-reload-electron"
        sudo systemctl daemon-reload 2>/dev/null || true
        log_success "Automatic Electron reload disabled"
    fi
}

################################################################################
# Remove all
################################################################################

action_remove_all_schedules() {
    echo
    ask_yes_no "Remove ALL power/display/quiet/reload schedules?" "n" || { echo "Cancelled"; return; }

    for timer in kiosk-shutdown kiosk-display-off kiosk-display-on kiosk-quiet-start kiosk-quiet-end kiosk-electron-reload; do
        sudo systemctl stop "${timer}.timer" 2>/dev/null || true
        sudo systemctl disable "${timer}.timer" 2>/dev/null || true
    done

    sudo rm -f "$SYSTEMD_DIR"/kiosk-shutdown.{service,timer}
    sudo rm -f "$SYSTEMD_DIR"/kiosk-display-off.{service,timer} "$SYSTEMD_DIR"/kiosk-display-on.{service,timer}
    sudo rm -f "$SYSTEMD_DIR"/kiosk-quiet-start.{service,timer} "$SYSTEMD_DIR"/kiosk-quiet-end.{service,timer}
    sudo rm -f "$SYSTEMD_DIR"/kiosk-electron-reload.{service,timer}
    sudo rm -f "$BIN_DIR/kiosk-power-off.sh" "$BIN_DIR/kiosk-display-off.sh" "$BIN_DIR/kiosk-display-on.sh"
    sudo rm -f "$BIN_DIR/kiosk-quiet-start.sh" "$BIN_DIR/kiosk-quiet-end.sh"
    sudo rm -f "$BIN_DIR/rtc-wake.sh" "$BIN_DIR/kiosk-reload-electron"
    sudo rm -f "$CRON_D_DIR/kiosk-rtc-wake"

    sudo systemctl daemon-reload 2>/dev/null || true

    log_success "All schedules removed"
}
