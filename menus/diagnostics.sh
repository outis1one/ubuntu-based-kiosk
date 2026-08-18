#!/bin/bash
################################################################################
# menus/diagnostics.sh - "Diagnostics" menu (from the legacy Advanced menu).
#
# A deliberate change of pace after Sites/WiFi/Power: everything here is
# read-only (system/audio status, log tailing, ping+DNS) except one
# optional "play a test sound?" prompt, so there's no destructive-action
# risk profile to design around. Straight port, using $KIOSK_USER/
# $KIOSK_HOME instead of the legacy code's mix of the variable and a
# hardcoded "kiosk" literal.
#
# Only 4 of the legacy Advanced menu's 12 items are here (System
# Diagnostics, View Logs, Audio Diagnostics, Network Test) - Manual
# Electron Update, Factory Reset, Export/Import Settings, Emergency
# Hotspot, and Fix Blank Screen are mutating/destructive and belong with
# a later, more careful pass (some, like Manual Electron Update, share
# Upgrade's issue of being coupled to the legacy script's own
# self-extraction mechanism - see ubuntu-based-kiosk.sh's changelog for
# why Upgrade/Reinstall/Uninstall aren't migrated yet either).
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

diagnostics_menu_builder() {
    MENU_LABELS=("System status" "View logs" "Audio diagnostics" "Network test")
    MENU_HANDLERS=(action_system_diagnostics view_logs_menu action_audio_diagnostics action_network_test)
}

diagnostics_menu() {
    run_menu "DIAGNOSTICS" diagnostics_menu_builder
}

################################################################################
# System status
################################################################################

action_system_diagnostics() {
    clear
    echo " ═══ SYSTEM DIAGNOSTICS ═══"
    echo

    echo "=== Kiosk Status ==="
    systemctl status lightdm --no-pager -l 2>&1 | head -20 || true

    echo
    echo "=== Audio Status ==="
    sudo -u "$KIOSK_USER" pactl info 2>/dev/null | grep -E "Server|User" || echo "Not running"

    echo
    echo "=== Network ==="
    echo "IP: $(get_ip_address)"
    echo "VPN: $(get_vpn_ips)"
    echo

    pause
}

################################################################################
# Logs
################################################################################

view_logs_menu_builder() {
    MENU_LABELS=("Electron log (last 50 lines)" "LightDM log (last 50 lines)" "System journal (last 100 lines)")
    MENU_HANDLERS=(action_view_electron_log action_view_lightdm_log action_view_journal)
}

view_logs_menu() {
    run_menu "VIEW LOGS" view_logs_menu_builder
}

action_view_electron_log() {
    echo
    if sudo test -f "$KIOSK_HOME/electron.log"; then
        sudo tail -50 "$KIOSK_HOME/electron.log" || true
    else
        echo "No electron log found yet"
    fi
    pause
}

action_view_lightdm_log() {
    echo
    sudo tail -50 /var/log/lightdm/lightdm.log 2>&1 || echo "No lightdm log found"
    pause
}

action_view_journal() {
    echo
    sudo journalctl -n 100 || log_error "Could not read the system journal"
    pause
}

################################################################################
# Audio diagnostics
################################################################################

audio_diagnostics_pactl() {
    sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$KIOSK_USER")" pactl "$@"
}

action_audio_diagnostics() {
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
    if audio_diagnostics_pactl info &>/dev/null; then
        log_success "PipeWire accessible"
        pipewire_running=true
        audio_diagnostics_pactl info 2>/dev/null | grep -E "Server|User|Host" || true
    else
        log_error "PipeWire not accessible to kiosk user"
        issue_found=true
        echo "  Try: sudo -u ${KIOSK_USER} systemctl --user start pipewire pipewire-pulse"
    fi
    echo

    if $pipewire_running; then
        echo "[4/8] Checking audio sinks..."
        local sinks
        sinks=$(audio_diagnostics_pactl list sinks short 2>/dev/null) || true
        if [[ -n "$sinks" ]]; then
            echo "$sinks"
            local default_sink
            default_sink=$(audio_diagnostics_pactl get-default-sink 2>/dev/null || echo "none")
            echo "Default: $default_sink"
        else
            log_error "No audio sinks found"
            issue_found=true
        fi
        echo

        echo "[5/8] Checking active streams..."
        local sink_inputs
        sink_inputs=$(audio_diagnostics_pactl list sink-inputs short 2>/dev/null) || true
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
            local sq_pid
            sq_pid=$(pgrep -f squeezelite | head -1) || true
            if [[ -n "$sq_pid" ]]; then
                if audio_diagnostics_pactl list sink-inputs 2>/dev/null | grep -q "application.process.id = \"$sq_pid\""; then
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
        local volume muted
        volume=$(audio_diagnostics_pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oE '[0-9]+%' | head -1 || echo "unknown")
        muted=$(audio_diagnostics_pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null || echo "unknown")
        echo "Volume: $volume"
        echo "Muted: $muted"
    else
        echo "[7/8] Skipped - PipeWire not running"
    fi
    echo

    echo "[8/8] Audio test..."
    if ask_yes_no "Play test sound?" "n" && $pipewire_running; then
        echo "Playing beep..."
        audio_diagnostics_pactl_play_test
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

audio_diagnostics_pactl_play_test() {
    sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$KIOSK_USER")" paplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || \
    sudo -u "$KIOSK_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$KIOSK_USER")" speaker-test -t sine -f 1000 -l 1 2>/dev/null || \
    echo "No test available"
}

################################################################################
# Network test
################################################################################

action_network_test() {
    echo
    echo " ═══ NETWORK TEST ═══"
    echo
    echo "Ping test..."
    ping -c 4 8.8.8.8 || log_error "Ping failed"
    echo
    echo "DNS test..."
    nslookup google.com || log_error "DNS lookup failed"
    pause
}
