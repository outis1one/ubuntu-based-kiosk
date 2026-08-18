#!/bin/bash
################################################################################
# menus/display.sh - "Display & Interaction" menu.
#
# Second menu migrated off the old single-file installer, folding together
# three small settings screens that used to be separate Core Settings
# entries (Touch controls, Navigation security, Optional Features). All
# three are simple scalar/boolean fields on config.json, so this is a
# deliberately different shape from menus/sites.sh's list CRUD - a toggle
# list where each entry shows its current value and flips/edits itself,
# saving immediately (same immediate-save pattern as Sites, so behavior
# stays consistent no matter which menu you're in).
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

display_status() {
    echo "Touch gesture mode: $SWIPE_MODE"
    echo "Link navigation:    $ALLOW_NAVIGATION"
    echo "Pause button:       $(display_onoff "$ENABLE_PAUSE_BUTTON")"
    echo "Keyboard button:    $(display_onoff "$ENABLE_KEYBOARD_BUTTON")"
    echo "Navigation button:  $(display_onoff "$ENABLE_NAV_BUTTON")"
}

display_onoff() {
    [[ "$1" == "true" ]] && echo "ON" || echo "OFF"
}

display_menu_builder() {
    MENU_LABELS=(
        "Touch gesture mode (currently: $SWIPE_MODE)"
        "Link navigation security (currently: $ALLOW_NAVIGATION)"
        "Toggle pause button (currently: $(display_onoff "$ENABLE_PAUSE_BUTTON"))"
        "Toggle on-screen keyboard button (currently: $(display_onoff "$ENABLE_KEYBOARD_BUTTON"))"
        "Toggle navigation/help button (currently: $(display_onoff "$ENABLE_NAV_BUTTON"))"
    )
    MENU_HANDLERS=(
        action_set_touch_mode
        action_set_navigation_security
        action_toggle_pause_button
        action_toggle_keyboard_button
        action_toggle_nav_button
    )
}

display_menu() {
    load_existing_config
    run_menu "DISPLAY & INTERACTION" display_menu_builder display_status
}

################################################################################
# Touch gesture mode
################################################################################

action_set_touch_mode() {
    echo
    echo "DUAL-DIRECTION (recommended for touchscreens):"
    echo "  2-finger swipe = switch pages, 1-finger swipe = navigate within page"
    echo "STANDARD (simpler):"
    echo "  2-finger swipe = switch pages only, 1-finger swipes do nothing"
    echo

    local default
    [[ "$SWIPE_MODE" == "dual" ]] && default="y" || default="n"

    if ask_yes_no "Use dual-direction mode?" "$default"; then
        SWIPE_MODE="dual"
    else
        SWIPE_MODE="standard"
    fi

    log_success "Touch mode: $SWIPE_MODE"
    save_config
}

################################################################################
# Navigation security
################################################################################

action_set_navigation_security() {
    echo
    echo "  r) restricted   - only the loaded URL, no link clicking"
    echo "  s) same-origin  - can click links within the same domain (recommended)"
    echo "  o) open         - can click any link, browse anywhere"
    echo

    local choice
    read -r -p "(r)estricted / (s)ame-origin / (o)pen [${ALLOW_NAVIGATION}]: " choice

    case "${choice,,}" in
        r) ALLOW_NAVIGATION="restricted" ;;
        o) ALLOW_NAVIGATION="open" ;;
        s) ALLOW_NAVIGATION="same-origin" ;;
        "") ;; # keep current value
        *) log_warning "Unrecognized choice, keeping '$ALLOW_NAVIGATION'" ;;
    esac

    log_success "Link navigation: $ALLOW_NAVIGATION"
    save_config
}

################################################################################
# On-screen button toggles
################################################################################

action_toggle_pause_button() {
    if [[ "$ENABLE_PAUSE_BUTTON" == "true" ]]; then
        ENABLE_PAUSE_BUTTON="false"
        log_warning "Pause button disabled"
    else
        ENABLE_PAUSE_BUTTON="true"
        log_success "Pause button enabled"
    fi
    save_config
}

action_toggle_keyboard_button() {
    if [[ "$ENABLE_KEYBOARD_BUTTON" == "true" ]]; then
        ENABLE_KEYBOARD_BUTTON="false"
        log_warning "On-screen keyboard button disabled"
    else
        ENABLE_KEYBOARD_BUTTON="true"
        log_success "On-screen keyboard button enabled"
    fi
    save_config
}

action_toggle_nav_button() {
    if [[ "$ENABLE_NAV_BUTTON" == "true" ]]; then
        ENABLE_NAV_BUTTON="false"
        log_warning "Navigation/help button disabled"
    else
        ENABLE_NAV_BUTTON="true"
        log_success "Navigation/help button enabled"
    fi
    save_config
}
