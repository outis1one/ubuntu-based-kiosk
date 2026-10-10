#!/bin/bash
################################################################################
# menus/lockout.sh - "Password Protection & Lockout" menu.
#
# The unlock code and the (optional, separate) boot code are each either
# a password or a 4-8 digit PIN - the kiosk's own codes, independent of
# the admin account's sudo password. A PIN gets an on-screen number pad
# on the lock screen, so it works on a touch-only kiosk.
#
# Fifth menu migrated. Back to config.json (like Display), but with a
# sensitive field: the lockout password is SHA-256 hashed before it's
# ever written to disk (matching the Electron app's comparison logic in
# main.js) - LOCKOUT_PASSWORD must never hold plaintext.
#
# Unlike the legacy configure_password_protection wizard (walk through
# every question once, then one final "save these changes? y/n"), this
# follows the same immediate-save pattern as every other migrated menu:
# each action is a complete, standalone change. Re-running "Enable" to
# change your mind is just as easy as the old "discard changes" path,
# and there's no separate confirm-at-the-end step to forget.
#
# LOCKOUT_ACTIVE_START/LOCKOUT_ACTIVE_END are intentionally never touched
# here - the app doesn't act on them (see Readme "Configuration Files"),
# so lib/config.sh just carries whatever is already in config.json
# through unchanged.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

lockout_status() {
    if [[ "$ENABLE_PASSWORD_PROTECTION" == "true" ]]; then
        echo "Password protection: ENABLED"
        echo "Inactivity lockout:  ${LOCKOUT_TIMEOUT} minutes$( [[ "$LOCKOUT_TIMEOUT" == "0" ]] && echo " (disabled - boot/wake only)")"
        if [[ -n "$LOCKOUT_AT_TIME" ]]; then
            echo "Daily lock time:     $LOCKOUT_AT_TIME"
        else
            echo "Daily lock time:     not set"
        fi
        echo "Unlock code:         $(lockout_code_label "$LOCKOUT_CODE_TYPE")"
        echo "Lock on boot:        $(onoff "$REQUIRE_PASSWORD_ON_BOOT")"
        if [[ "$REQUIRE_PASSWORD_ON_BOOT" == "true" ]]; then
            echo "Boot code:           $(lockout_boot_code_label)"
        fi
    else
        echo "Password protection: disabled"
    fi
}

lockout_menu_builder() {
    if [[ "$ENABLE_PASSWORD_PROTECTION" == "true" ]]; then
        MENU_LABELS=(
            "Change unlock password/PIN (currently: $(lockout_code_label "$LOCKOUT_CODE_TYPE"))"
            "Change inactivity lockout timeout (currently: ${LOCKOUT_TIMEOUT}m)"
            "Set/clear daily lock time (currently: ${LOCKOUT_AT_TIME:-not set})"
            "Toggle lock on boot (currently: $(onoff "$REQUIRE_PASSWORD_ON_BOOT"))"
            "Set boot password/PIN (currently: $(lockout_boot_code_label))"
            "Disable password protection"
        )
        MENU_HANDLERS=(
            action_change_password
            action_change_timeout
            action_change_daily_lock
            action_toggle_boot_password
            action_set_boot_code
            action_disable_protection
        )
    else
        MENU_LABELS=("Enable password protection")
        MENU_HANDLERS=(action_enable_protection)
    fi
}

lockout_menu() {
    load_existing_config
    run_menu "PASSWORD PROTECTION & LOCKOUT" lockout_menu_builder lockout_status
}

################################################################################
# Shared helpers
################################################################################

# "PIN" / "password" for menus and status lines.
lockout_code_label() {
    [[ "$1" == "pin" ]] && echo "PIN" || echo "password"
}

lockout_boot_code_label() {
    if [[ -z "$BOOT_PASSWORD" ]]; then
        echo "same as unlock"
    else
        echo "separate $(lockout_code_label "$BOOT_CODE_TYPE")"
    fi
}

# True if $1 is a valid kiosk PIN: 4-8 digits.
lockout_valid_pin() {
    [[ "$1" =~ ^[0-9]{4,8}$ ]]
}

# prompt_code WHAT - asks whether WHAT (e.g. "unlock") is a password or a
# 4-8 digit PIN, then for the code itself twice. Sets CODE_TYPE ("password"
# or "pin") and CODE_HASH (SHA-256 hex, matching the Electron app's check
# in main.js - never plaintext). These are the kiosk's own codes, not
# any Linux account's password.
prompt_code() {
    local what="$1" choice
    echo "How should the $what code be entered?"
    echo "  1) Password (letters, numbers, anything - needs a keyboard)"
    echo "  2) PIN (4-8 digits - on-screen number pad, works on a touch screen)"
    while true; do
        read -r -p "Choose [1-2]: " choice
        case "$choice" in
            1) CODE_TYPE="password"; break ;;
            2) CODE_TYPE="pin"; break ;;
            *) echo "❌ Enter 1 or 2" ;;
        esac
    done

    local label pass1 pass2
    label=$(lockout_code_label "$CODE_TYPE")
    while true; do
        read -r -s -p "Enter $what $label: " pass1
        echo
        if [[ -z "$pass1" ]]; then
            echo "❌ The $label cannot be empty"
            continue
        fi
        if [[ "$CODE_TYPE" == "pin" ]] && ! lockout_valid_pin "$pass1"; then
            echo "❌ A PIN is 4-8 digits (0-9 only)"
            continue
        fi
        read -r -s -p "Confirm $what $label: " pass2
        echo
        if [[ "$pass1" != "$pass2" ]]; then
            echo "❌ They don't match, try again"
            continue
        fi
        CODE_HASH=$(echo -n "$pass1" | sha256sum | cut -d' ' -f1)
        return 0
    done
}

# Prompts for the unlock code into LOCKOUT_PASSWORD/LOCKOUT_CODE_TYPE.
prompt_and_hash_password() {
    prompt_code "unlock"
    LOCKOUT_CODE_TYPE="$CODE_TYPE"
    LOCKOUT_PASSWORD="$CODE_HASH"
}

################################################################################
# Actions
################################################################################

action_enable_protection() {
    echo
    echo "Add password protection with automatic lockout:"
    echo "  • Blank screen after an inactivity period"
    echo "  • Password or PIN required to unlock"
    echo "  • Required after display schedule wake-up"
    echo "  • Optional: lock at a specific time daily"
    echo "  • Optional: locked on system boot, with the same or its own code"
    echo
    echo "These are the kiosk's own codes - not your admin (sudo) password."
    echo

    prompt_and_hash_password

    echo
    echo "Session lockout time (minutes of inactivity)."
    echo "Enter 0 to only require a password after display wake or boot."
    LOCKOUT_TIMEOUT=$(ask_integer "Lockout timeout in minutes" "30" 0 1440)

    echo
    if ask_yes_no "Lock automatically at a specific time each day?" "n"; then
        LOCKOUT_AT_TIME=$(ask_time "Time to lock (24-hour HH:MM)" "17:00")
    else
        LOCKOUT_AT_TIME=""
    fi

    echo
    BOOT_PASSWORD=""
    BOOT_CODE_TYPE="password"
    if ask_yes_no "Lock the kiosk on system boot/power on?" "y"; then
        REQUIRE_PASSWORD_ON_BOOT="true"
        echo
        if ask_yes_no "Use a different password/PIN at boot than for unlocking?" "n"; then
            prompt_code "boot"
            BOOT_CODE_TYPE="$CODE_TYPE"
            BOOT_PASSWORD="$CODE_HASH"
        fi
    else
        REQUIRE_PASSWORD_ON_BOOT="false"
    fi

    ENABLE_PASSWORD_PROTECTION="true"
    log_success "Password protection enabled (lockout: ${LOCKOUT_TIMEOUT}m)"
    save_config
}

action_disable_protection() {
    ENABLE_PASSWORD_PROTECTION="false"
    LOCKOUT_PASSWORD=""
    LOCKOUT_TIMEOUT=0
    LOCKOUT_AT_TIME=""
    REQUIRE_PASSWORD_ON_BOOT="false"
    LOCKOUT_CODE_TYPE="password"
    BOOT_PASSWORD=""
    BOOT_CODE_TYPE="password"
    log_success "Password protection disabled"
    save_config
}

action_change_password() {
    echo
    prompt_and_hash_password
    log_success "Unlock $(lockout_code_label "$LOCKOUT_CODE_TYPE") updated"
    save_config
}

action_change_timeout() {
    echo
    echo "Session lockout time (minutes of inactivity)."
    echo "Enter 0 to only require a password after display wake or boot."
    LOCKOUT_TIMEOUT=$(ask_integer "Lockout timeout in minutes" "$LOCKOUT_TIMEOUT" 0 1440)
    log_success "Lockout timeout: ${LOCKOUT_TIMEOUT}m"
    save_config
}

action_change_daily_lock() {
    echo
    local default_prompt
    [[ -n "$LOCKOUT_AT_TIME" ]] && default_prompt="y" || default_prompt="n"

    if ask_yes_no "Lock automatically at a specific time each day?" "$default_prompt"; then
        LOCKOUT_AT_TIME=$(ask_time "Time to lock (24-hour HH:MM)" "${LOCKOUT_AT_TIME:-17:00}")
        log_success "Will lock at ${LOCKOUT_AT_TIME} daily"
    else
        LOCKOUT_AT_TIME=""
        log_success "Daily lock time cleared"
    fi
    save_config
}

action_toggle_boot_password() {
    if [[ "$REQUIRE_PASSWORD_ON_BOOT" == "true" ]]; then
        REQUIRE_PASSWORD_ON_BOOT="false"
        log_warning "Lock on boot disabled"
    else
        REQUIRE_PASSWORD_ON_BOOT="true"
        log_success "Lock on boot enabled (boot code: $(lockout_boot_code_label))"
    fi
    save_config
}

action_set_boot_code() {
    echo
    echo "The boot lock screen can use its own password/PIN, or the unlock one."
    echo "Currently: $(lockout_boot_code_label)"
    echo
    if ask_yes_no "Use a separate password/PIN at boot?" "y"; then
        prompt_code "boot"
        BOOT_CODE_TYPE="$CODE_TYPE"
        BOOT_PASSWORD="$CODE_HASH"
        REQUIRE_PASSWORD_ON_BOOT="true"
        log_success "Boot $(lockout_code_label "$BOOT_CODE_TYPE") set (lock on boot: on)"
    else
        BOOT_PASSWORD=""
        BOOT_CODE_TYPE="password"
        log_success "Boot uses the unlock $(lockout_code_label "$LOCKOUT_CODE_TYPE")"
    fi
    save_config
}
