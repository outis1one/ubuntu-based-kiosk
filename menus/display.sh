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
    echo "Pause button:       $(onoff "$ENABLE_PAUSE_BUTTON")"
    echo "Keyboard button:    $(onoff "$ENABLE_KEYBOARD_BUTTON")"
    echo "Navigation button:  $(onoff "$ENABLE_NAV_BUTTON")"
    echo "Back/home/fwd btns: $(onoff "$ENABLE_HISTORY_BUTTONS") (opacity ${HISTORY_BUTTONS_OPACITY}%)"
}

display_menu_builder() {
    MENU_LABELS=(
        "Touch gesture mode (currently: $SWIPE_MODE)"
        "Link navigation security (currently: $ALLOW_NAVIGATION)"
        "Toggle pause button (currently: $(onoff "$ENABLE_PAUSE_BUTTON"))"
        "Toggle on-screen keyboard button (currently: $(onoff "$ENABLE_KEYBOARD_BUTTON"))"
        "Toggle navigation/help button (currently: $(onoff "$ENABLE_NAV_BUTTON"))"
        "Toggle on-screen back/home/forward buttons (currently: $(onoff "$ENABLE_HISTORY_BUTTONS"))"
        "Back/home/forward button opacity (currently: ${HISTORY_BUTTONS_OPACITY}%)"
    )
    MENU_HANDLERS=(
        action_set_touch_mode
        action_set_navigation_security
        action_toggle_pause_button
        action_toggle_keyboard_button
        action_toggle_nav_button
        action_toggle_history_buttons
        action_set_history_opacity
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

# Page back/forward: Alt+Left / Alt+Right and the mouse's side buttons
# always work; this adds clickable buttons (top middle, half transparent,
# shown on mouse movement or a tap) for screens with no keyboard or mouse
# buttons. Off by default.
action_toggle_history_buttons() {
    if [[ "$ENABLE_HISTORY_BUTTONS" == "true" ]]; then
        ENABLE_HISTORY_BUTTONS="false"
        log_warning "On-screen back/home/forward buttons disabled"
    else
        ENABLE_HISTORY_BUTTONS="true"
        log_success "On-screen back/home/forward buttons enabled"
    fi
    save_config
}

# How see-through the back/forward buttons are: 100 = solid, 10 = faint.
# They get a little more solid while the mouse is over them.
action_set_history_opacity() {
    echo
    echo "How solid the on-screen back/home/forward buttons look (10 = faint, 100 = solid)."
    HISTORY_BUTTONS_OPACITY=$(ask_integer "Opacity percent" "$HISTORY_BUTTONS_OPACITY" 10 100)
    save_config
    log_success "Back/home/forward button opacity: ${HISTORY_BUTTONS_OPACITY}%"
    if [[ "$ENABLE_HISTORY_BUTTONS" != "true" ]]; then
        log_info "The buttons are off - turn them on with the entry above."
    fi
}
