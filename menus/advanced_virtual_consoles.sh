#!/bin/bash
################################################################################
# menus/advanced_virtual_consoles.sh - "Virtual Consoles" (Advanced): toggle
# Ctrl+Alt+F1-F8 terminal login access for troubleshooting.
#
# Real system state: masks/unmasks the getty@ttyN systemd units and writes
# a fixed-path X11 server-flags file. Neither is relocatable (X11 only
# reads /etc/X11/xorg.conf.d/, and getty units are always system units),
# so tests use full command-level `sudo` stubbing, same approach as CUPS.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

vconsoles_are_disabled() {
    local getty_masked=false
    local vt_switch_disabled=false

    if systemctl is-masked --quiet getty@tty1.service 2>/dev/null; then
        getty_masked=true
    fi

    if [[ -f /etc/X11/xorg.conf.d/10-serverflags.conf ]] && \
       grep -q 'Option.*"DontVTSwitch".*"true"' /etc/X11/xorg.conf.d/10-serverflags.conf 2>/dev/null; then
        vt_switch_disabled=true
    fi

    [[ "$getty_masked" == "true" || "$vt_switch_disabled" == "true" ]]
}

advanced_virtual_consoles_status() {
    if vconsoles_are_disabled; then
        echo "Virtual consoles: Disabled"
    else
        echo "Virtual consoles: Enabled"
    fi
}

advanced_virtual_consoles_menu_builder() {
    if vconsoles_are_disabled; then
        MENU_LABELS=("Enable virtual consoles (Ctrl+Alt+F1-F8 for manual login)")
        MENU_HANDLERS=(action_enable_virtual_consoles)
    else
        MENU_LABELS=("Disable virtual consoles (more secure, kiosk only)")
        MENU_HANDLERS=(action_disable_virtual_consoles)
    fi
}

advanced_virtual_consoles_menu() {
    run_menu "VIRTUAL CONSOLES" advanced_virtual_consoles_menu_builder advanced_virtual_consoles_status
}

################################################################################
# Actions
################################################################################

action_enable_virtual_consoles() {
    echo
    echo "Enabling virtual consoles..."

    for i in {1..8}; do
        sudo systemctl unmask "getty@tty${i}.service" 2>/dev/null || true
    done
    sudo systemctl daemon-reload 2>/dev/null || true

    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/10-serverflags.conf > /dev/null <<'EOF'
Section "ServerFlags"
    # Disable Ctrl+Alt+Backspace (X server kill)
    Option "DontZap" "true"

    # ALLOW VT switching (Ctrl+Alt+F1-F12)
    Option "DontVTSwitch" "false"

    # Don't allow clients to disconnect on exit
    Option "AllowClosedownGrabs" "false"
EndSection
EOF

    log_success "Virtual consoles enabled"
    echo "  Access with Ctrl+Alt+F1 through Ctrl+Alt+F8"
    echo "  (Ctrl+Alt+F7 typically returns to the kiosk)"
    echo
    if ask_yes_no "Restart kiosk display now to apply?" "n"; then
        sudo systemctl restart lightdm
    else
        log_warning "Remember to restart: sudo systemctl restart lightdm"
    fi

    pause
}

action_disable_virtual_consoles() {
    echo
    ask_yes_no "Disable all virtual consoles?" "n" || { echo "Cancelled"; pause; return; }

    echo "Disabling virtual consoles..."

    for i in {1..8}; do
        sudo systemctl mask "getty@tty${i}.service" 2>/dev/null || true
    done
    sudo systemctl daemon-reload 2>/dev/null || true

    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/10-serverflags.conf > /dev/null <<'EOF'
Section "ServerFlags"
    # Disable Ctrl+Alt+Backspace (X server kill)
    Option "DontZap" "true"

    # DISABLE VT switching (Ctrl+Alt+F1-F12)
    Option "DontVTSwitch" "true"

    # Don't allow clients to disconnect on exit
    Option "AllowClosedownGrabs" "false"
EndSection
EOF

    log_success "Virtual consoles disabled"
    echo "  You can re-enable them from this menu at any time."
    echo
    if ask_yes_no "Restart kiosk display now to apply?" "n"; then
        sudo systemctl restart lightdm
    else
        log_warning "Remember to restart: sudo systemctl restart lightdm"
    fi

    pause
}
