#!/bin/bash
################################################################################
# menus/lockout.sh - "Password Protection & Lockout" menu.
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
        echo "Password on boot:    $(onoff "$REQUIRE_PASSWORD_ON_BOOT")"
    else
        echo "Password protection: disabled"
    fi
}

lockout_menu_builder() {
    if [[ "$ENABLE_PASSWORD_PROTECTION" == "true" ]]; then
        MENU_LABELS=(
            "Change lockout password"
            "Change inactivity lockout timeout (currently: ${LOCKOUT_TIMEOUT}m)"
            "Set/clear daily lock time (currently: ${LOCKOUT_AT_TIME:-not set})"
            "Toggle require password on boot (currently: $(onoff "$REQUIRE_PASSWORD_ON_BOOT"))"
            "Disable password protection"
        )
        MENU_HANDLERS=(
            action_change_password
            action_change_timeout
            action_change_daily_lock
            action_toggle_boot_password
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

# Prompts for a new password twice, hashes it, and assigns to
# LOCKOUT_PASSWORD. Returns 1 (without saving) if the user gives up.
prompt_and_hash_password() {
    local pass1 pass2
    while true; do
        read -r -s -p "Enter password: " pass1
        echo
        read -r -s -p "Confirm password: " pass2
        echo

        if [[ -z "$pass1" ]]; then
            echo "❌ Password cannot be empty"
            continue
        fi

        if [[ "$pass1" != "$pass2" ]]; then
            echo "❌ Passwords don't match, try again"
            continue
        fi

        LOCKOUT_PASSWORD=$(echo -n "$pass1" | sha256sum | cut -d' ' -f1)
        return 0
    done
}

################################################################################
# Actions
################################################################################

action_enable_protection() {
    echo
    echo "Add password protection with automatic lockout:"
    echo "  • Blank screen after an inactivity period"
    echo "  • Password required to unlock"
    echo "  • Password required after display schedule wake-up"
    echo "  • Optional: lock at a specific time daily"
    echo "  • Optional: require password on system boot"
    echo

    echo "Set lockout password:"
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
    if ask_yes_no "Require password on system boot/power on?" "y"; then
        REQUIRE_PASSWORD_ON_BOOT="true"
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
    log_success "Password protection disabled"
    save_config
}

action_change_password() {
    echo
    prompt_and_hash_password
    log_success "Password updated"
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
        log_warning "Password on boot disabled"
    else
        REQUIRE_PASSWORD_ON_BOOT="true"
        log_success "Password on boot enabled"
    fi
    save_config
}
