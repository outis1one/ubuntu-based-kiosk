#!/bin/bash
################################################################################
# menus/hidden_pin.sh - "Hidden Site PIN" menu.
#
# Guards access to hidden pages (duration = -1, see menus/sites.sh) via a
# flat PIN file rather than config.json - a fourth shape for the framework
# to prove out (plain file, not JSON at all).
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

hidden_pin_file() {
    echo "$KIOSK_DIR/.jitsi-pin"
}

hidden_pin_status() {
    local pin_file
    pin_file=$(hidden_pin_file)

    if sudo -u "$KIOSK_USER" test -f "$pin_file" 2>/dev/null; then
        local current_pin
        current_pin=$(sudo -u "$KIOSK_USER" cat "$pin_file" 2>/dev/null)
        if [[ "$current_pin" == "NOPIN" ]]; then
            echo "Current: no PIN (hidden pages open to anyone)"
        else
            echo "Current: PIN set (${#current_pin} digits)"
        fi
    else
        echo "Current: not configured (default: 1234)"
    fi
}

hidden_pin_menu_builder() {
    MENU_LABELS=("Set new PIN (4-8 digits)" "Disable PIN (open access)" "Reset to default (1234)")
    MENU_HANDLERS=(action_set_pin action_disable_pin action_reset_pin)
}

hidden_pin_menu() {
    run_menu "HIDDEN SITE PIN" hidden_pin_menu_builder hidden_pin_status
}

################################################################################
# Actions
################################################################################

write_pin() {
    local value="$1"
    local pin_file
    pin_file=$(hidden_pin_file)

    sudo mkdir -p "$KIOSK_DIR"
    echo "$value" | sudo -u "$KIOSK_USER" tee "$pin_file" > /dev/null
    sudo -u "$KIOSK_USER" chmod 600 "$pin_file"
    log_warning "Restart the kiosk display for this to take effect"
}

action_set_pin() {
    echo
    local new_pin confirm_pin
    while true; do
        read -r -p "Enter new PIN (4-8 digits): " new_pin

        if [[ ! "$new_pin" =~ ^[0-9]{4,8}$ ]]; then
            echo "❌ PIN must be 4-8 digits"
            continue
        fi

        read -r -p "Confirm PIN: " confirm_pin

        if [[ "$new_pin" == "$confirm_pin" ]]; then
            write_pin "$new_pin"
            log_success "PIN updated"
            break
        else
            echo "❌ PINs don't match, try again"
        fi
    done
}

action_disable_pin() {
    write_pin "NOPIN"
    log_success "PIN disabled - hidden pages accessible without a PIN"
}

action_reset_pin() {
    write_pin "1234"
    log_success "PIN reset to default (1234)"
}
