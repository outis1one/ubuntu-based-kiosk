#!/bin/bash
################################################################################
# lib/config.sh - config.json read/write for the kiosk Electron app.
#
# Every menu that touches sites/timing/settings works against the same
# in-memory bash arrays (URLS, DURS, USERS, PASSES, NAMES, ...) and the same
# two functions below. Load once when a menu opens, save after each change.
#
# IMPORTANT: save_config() rewrites config.json from these globals in full.
# Any menu that calls save_config() MUST call load_existing_config() first
# (even if it only touches sites), otherwise settings it doesn't know about
# (swipe mode, navigation security, lockout, etc) get silently reset to
# script defaults. This bit the old single-file Sites menu, which read
# tabs directly via jq but never loaded the rest of the settings - fixed
# here by making load_existing_config() the one canonical loader.
################################################################################

: "${KIOSK_USER:=kiosk}"
: "${KIOSK_HOME:=/home/${KIOSK_USER}}"
: "${KIOSK_DIR:=${KIOSK_HOME}/kiosk-app}"
: "${CONFIG_PATH:=${KIOSK_DIR}/config.json}"

# Site/tab arrays
declare -a URLS=()
declare -a DURS=()
declare -a USERS=()
declare -a PASSES=()
declare -a NAMES=()

# Other top-level config.json settings we must round-trip even though the
# Sites menu doesn't edit most of them.
AUTOSWITCH="true"
SWIPE_MODE="dual"
ALLOW_NAVIGATION="same-origin"
HOME_TAB_INDEX=-1
INACTIVITY_TIMEOUT=120
ENABLE_PAUSE_BUTTON="true"
ENABLE_KEYBOARD_BUTTON="true"
ENABLE_NAV_BUTTON="true"
ENABLE_PASSWORD_PROTECTION="false"
LOCKOUT_PASSWORD=""
LOCKOUT_TIMEOUT=0
LOCKOUT_AT_TIME=""
LOCKOUT_ACTIVE_START=""
LOCKOUT_ACTIVE_END=""
REQUIRE_PASSWORD_ON_BOOT="false"

kiosk_user_exists() {
    id "$KIOSK_USER" &>/dev/null
}

is_kiosk_installed() {
    kiosk_user_exists && sudo -u "$KIOSK_USER" test -f "$KIOSK_DIR/main.js" 2>/dev/null
}

is_service_active() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Load every setting config.json has into the bash globals above.
# Safe to call with no existing config file - leaves script defaults in place.
load_existing_config() {
    if ! sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        return 0
    fi

    URLS=()
    DURS=()
    USERS=()
    PASSES=()
    NAMES=()

    local tab_count
    tab_count=$(sudo -u "$KIOSK_USER" jq -r '.tabs | length' "$CONFIG_PATH" 2>/dev/null || echo "0")
    if [[ "$tab_count" -gt 0 ]]; then
        for ((i = 0; i < tab_count; i++)); do
            URLS+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].url" "$CONFIG_PATH")")
            DURS+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].duration" "$CONFIG_PATH")")
            USERS+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].username // empty" "$CONFIG_PATH")")
            PASSES+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].password // empty" "$CONFIG_PATH")")
            NAMES+=("$(sudo -u "$KIOSK_USER" jq -r ".tabs[$i].name // empty" "$CONFIG_PATH")")
        done
    fi

    HOME_TAB_INDEX=$(sudo -u "$KIOSK_USER" jq -r '.homeTabIndex // -1' "$CONFIG_PATH" 2>/dev/null || echo "-1")
    INACTIVITY_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.inactivityTimeout // 120' "$CONFIG_PATH" 2>/dev/null || echo "120")
    ALLOW_NAVIGATION=$(sudo -u "$KIOSK_USER" jq -r '.allowNavigation // "same-origin"' "$CONFIG_PATH" 2>/dev/null || echo "same-origin")
    SWIPE_MODE=$(sudo -u "$KIOSK_USER" jq -r '.swipeMode // "dual"' "$CONFIG_PATH" 2>/dev/null || echo "dual")

    local pause_btn keyboard_btn nav_btn password_enabled boot_password
    pause_btn=$(sudo -u "$KIOSK_USER" jq -r '.enablePauseButton // true' "$CONFIG_PATH" 2>/dev/null)
    [[ "$pause_btn" == "true" ]] && ENABLE_PAUSE_BUTTON="true" || ENABLE_PAUSE_BUTTON="false"

    keyboard_btn=$(sudo -u "$KIOSK_USER" jq -r '.enableKeyboardButton // true' "$CONFIG_PATH" 2>/dev/null)
    [[ "$keyboard_btn" == "true" ]] && ENABLE_KEYBOARD_BUTTON="true" || ENABLE_KEYBOARD_BUTTON="false"

    nav_btn=$(sudo -u "$KIOSK_USER" jq -r '.enableNavButton // true' "$CONFIG_PATH" 2>/dev/null)
    [[ "$nav_btn" == "true" ]] && ENABLE_NAV_BUTTON="true" || ENABLE_NAV_BUTTON="false"

    password_enabled=$(sudo -u "$KIOSK_USER" jq -r '.enablePasswordProtection // false' "$CONFIG_PATH" 2>/dev/null)
    [[ "$password_enabled" == "true" ]] && ENABLE_PASSWORD_PROTECTION="true" || ENABLE_PASSWORD_PROTECTION="false"

    LOCKOUT_PASSWORD=$(sudo -u "$KIOSK_USER" jq -r '.lockoutPassword // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
    LOCKOUT_TIMEOUT=$(sudo -u "$KIOSK_USER" jq -r '.lockoutTimeout // 0' "$CONFIG_PATH" 2>/dev/null || echo "0")
    LOCKOUT_AT_TIME=$(sudo -u "$KIOSK_USER" jq -r '.lockoutAtTime // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
    LOCKOUT_ACTIVE_START=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveStart // ""' "$CONFIG_PATH" 2>/dev/null || echo "")
    LOCKOUT_ACTIVE_END=$(sudo -u "$KIOSK_USER" jq -r '.lockoutActiveEnd // ""' "$CONFIG_PATH" 2>/dev/null || echo "")

    boot_password=$(sudo -u "$KIOSK_USER" jq -r '.requirePasswordOnBoot // false' "$CONFIG_PATH" 2>/dev/null)
    [[ "$boot_password" == "true" ]] && REQUIRE_PASSWORD_ON_BOOT="true" || REQUIRE_PASSWORD_ON_BOOT="false"
}

# Write every bash global back out to config.json, then offer to reload the
# kiosk display so the change takes effect immediately.
save_config() {
    if ! kiosk_user_exists; then
        log_error "Kiosk user doesn't exist - run the full installer first"
        return 1
    fi

    sudo mkdir -p "$KIOSK_DIR"
    sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"

    local tmp
    tmp=$(mktemp)

    local dual_json="false"
    [[ "$SWIPE_MODE" == "dual" ]] && dual_json="true"

    local pause_btn_json="true"
    [[ "$ENABLE_PAUSE_BUTTON" == "false" ]] && pause_btn_json="false"

    local keyboard_btn_json="true"
    [[ "$ENABLE_KEYBOARD_BUTTON" == "false" ]] && keyboard_btn_json="false"

    local nav_btn_json="true"
    [[ "$ENABLE_NAV_BUTTON" == "false" ]] && nav_btn_json="false"

    local password_json="false"
    [[ "$ENABLE_PASSWORD_PROTECTION" == "true" ]] && password_json="true"

    local boot_password_json="false"
    [[ "$REQUIRE_PASSWORD_ON_BOOT" == "true" ]] && boot_password_json="true"

    jq -n \
        --argjson autoswitch true \
        --argjson enableTouch true \
        --argjson dualSwipe "$dual_json" \
        --arg swipeMode "$SWIPE_MODE" \
        --arg allowNavigation "$ALLOW_NAVIGATION" \
        --argjson homeTabIndex "${HOME_TAB_INDEX:--1}" \
        --argjson inactivityTimeout "${INACTIVITY_TIMEOUT:-120}" \
        --argjson enablePauseButton "$pause_btn_json" \
        --argjson enableKeyboardButton "$keyboard_btn_json" \
        --argjson enableNavButton "$nav_btn_json" \
        --argjson enablePasswordProtection "$password_json" \
        --arg lockoutPassword "${LOCKOUT_PASSWORD:-}" \
        --argjson lockoutTimeout "${LOCKOUT_TIMEOUT:-0}" \
        --arg lockoutAtTime "${LOCKOUT_AT_TIME:-}" \
        --arg lockoutActiveStart "${LOCKOUT_ACTIVE_START:-}" \
        --arg lockoutActiveEnd "${LOCKOUT_ACTIVE_END:-}" \
        --argjson requirePasswordOnBoot "$boot_password_json" \
        '{autoswitch:$autoswitch,enableTouch:$enableTouch,dualSwipe:$dualSwipe,swipeMode:$swipeMode,allowNavigation:$allowNavigation,homeTabIndex:$homeTabIndex,inactivityTimeout:$inactivityTimeout,enablePauseButton:$enablePauseButton,enableKeyboardButton:$enableKeyboardButton,enableNavButton:$enableNavButton,enablePasswordProtection:$enablePasswordProtection,lockoutPassword:$lockoutPassword,lockoutTimeout:$lockoutTimeout,lockoutAtTime:$lockoutAtTime,lockoutActiveStart:$lockoutActiveStart,lockoutActiveEnd:$lockoutActiveEnd,requirePasswordOnBoot:$requirePasswordOnBoot,tabs:[]}' > "$tmp"

    if [[ ${#URLS[@]} -gt 0 ]]; then
        for idx in "${!URLS[@]}"; do
            local url="${URLS[$idx]:-}"
            local dur="${DURS[$idx]:-0}"
            local user="${USERS[$idx]:-}"
            local pass="${PASSES[$idx]:-}"
            local name="${NAMES[$idx]:-}"

            jq --arg u "$url" \
               --argjson d "$dur" \
               --arg user "$user" \
               --arg pass "$pass" \
               --arg name "$name" \
               '.tabs += [{"url":$u,"duration":$d,"username":$user,"password":$pass,"name":$name}]' \
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
        if ask_yes_no "Reload kiosk now to apply changes?" "y"; then
            echo "Reloading kiosk..."
            sudo systemctl restart lightdm
            sleep 2
            log_success "Kiosk reloaded"
        else
            log_warning "Remember to reload: sudo systemctl restart lightdm"
        fi
    fi
}
