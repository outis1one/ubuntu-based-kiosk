#!/bin/bash
################################################################################
# menus/sites.sh - "Sites & Page Timing" menu.
#
# First real menu built on lib/menu.sh + lib/config.sh, as a proof of
# concept for pulling menus out of the old 12k-line installer one at a
# time. Covers exactly what was asked for first: adding, deleting, and
# changing pages, and the timing (duration) of each.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

# Index of the page currently being edited by the nested "edit page" menu.
SITE_EDIT_IDX=""

################################################################################
# Small helpers
################################################################################

# Normalize whatever the user typed into a URL, same rules the old
# installer used: bare host -> https://, bare IP -> http://.
sites_parse_url() {
    local raw="$1"
    if [[ "$raw" =~ ^https?:// ]]; then
        echo "$raw"
    elif [[ "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        echo "http://${raw}"
    else
        echo "https://${raw}"
    fi
}

# Human label for a duration value: >0 seconds = auto-rotate, 0 = manual,
# -1 = hidden (PIN-gated).
sites_duration_label() {
    local dur="$1"
    if [[ "$dur" == "-1" ]]; then
        echo "hidden"
    elif [[ "$dur" == "0" ]]; then
        echo "manual"
    else
        echo "auto-rotate ${dur}s"
    fi
}

sites_display_label() {
    local idx="$1"
    local label="${URLS[$idx]}"
    [[ -n "${NAMES[$idx]:-}" ]] && label="\"${NAMES[$idx]}\" - ${URLS[$idx]}"
    echo "$label"
}

################################################################################
# Status line shown above the main Sites menu
################################################################################

sites_status() {
    if [[ "${#URLS[@]}" -eq 0 ]]; then
        echo "No pages configured yet."
        return
    fi

    echo "Current pages:"
    local has_rotation=false
    for idx in "${!URLS[@]}"; do
        local dur="${DURS[$idx]}"
        local flags=""
        [[ "$dur" != "0" && "$dur" != "-1" ]] && has_rotation=true
        [[ -n "${USERS[$idx]:-}" ]] && flags+=" [auth]"
        [[ "$HOME_TAB_INDEX" == "$idx" ]] && flags+=" [HOME]"

        printf "  %2d. %s (%s)%s\n" "$((idx + 1))" "$(sites_display_label "$idx")" "$(sites_duration_label "$dur")" "$flags"
    done
    echo
    if $has_rotation; then
        echo "Auto-rotation: active (pages with duration > 0)"
    else
        echo "Auto-rotation: off (all pages manual/hidden)"
    fi
    if [[ "$HOME_TAB_INDEX" != "-1" ]]; then
        echo "Home page: #$((HOME_TAB_INDEX + 1)), ${INACTIVITY_TIMEOUT}s inactivity timeout"
    else
        echo "Home page: disabled"
    fi
}

################################################################################
# Top-level Sites menu
################################################################################

sites_menu_builder() {
    MENU_LABELS=("Add a page")
    MENU_HANDLERS=(action_add_page)

    if [[ "${#URLS[@]}" -gt 0 ]]; then
        MENU_LABELS+=("Edit a page" "Delete a page")
        MENU_HANDLERS+=(action_pick_and_edit_page action_delete_page)
    fi

    if [[ "${#URLS[@]}" -gt 1 ]]; then
        MENU_LABELS+=("Reorder pages")
        MENU_HANDLERS+=(action_reorder_page)
    fi

    if [[ "${#URLS[@]}" -gt 0 ]]; then
        MENU_LABELS+=("Set/clear home page")
        MENU_HANDLERS+=(action_set_home_page)
    fi
}

sites_menu() {
    load_existing_config
    run_menu "SITES & PAGE TIMING" sites_menu_builder sites_status
}

################################################################################
# Add
################################################################################

action_add_page() {
    echo
    echo "Duration controls rotation:"
    echo "  > 0  = auto-rotates every X seconds"
    echo "    0  = manual only (swipe/nav menu to reach it)"
    echo "   -1  = hidden (PIN-gated, F10 or 3-finger swipe)"
    echo

    local raw_url url dur name needs_auth user pass
    read -r -p "URL: " raw_url
    if [[ -z "$raw_url" ]]; then
        echo "Cancelled"
        return
    fi
    url=$(sites_parse_url "$raw_url")

    dur=$(ask_integer "Duration in seconds (-1=hidden, 0=manual)" "180" -1 86400)
    name=$(ask_text "Page name (optional, blank = show URL)" "")

    user=""
    pass=""
    if ask_yes_no "Does this page need HTTP Basic Auth?" "n"; then
        read -r -p "  Username: " user
        read -r -s -p "  Password: " pass
        echo
    fi

    URLS+=("$url")
    DURS+=("$dur")
    USERS+=("$user")
    PASSES+=("$pass")
    NAMES+=("$name")

    log_success "Added: $url ($(sites_duration_label "$dur"))"
    save_config
}

################################################################################
# Edit (nested menu on the selected page)
################################################################################

action_pick_and_edit_page() {
    echo
    for idx in "${!URLS[@]}"; do
        echo "  $((idx + 1)). $(sites_display_label "$idx")"
    done
    echo
    local num
    num=$(ask_integer "Edit which page? (0=cancel)" "0" 0 "${#URLS[@]}")
    [[ "$num" == "0" ]] && return

    SITE_EDIT_IDX=$((num - 1))
    run_menu "EDIT PAGE #${num}" edit_page_menu_builder edit_page_status
}

edit_page_status() {
    local idx="$SITE_EDIT_IDX"
    echo "URL:      ${URLS[$idx]}"
    echo "Name:     ${NAMES[$idx]:-(none)}"
    echo "Timing:   $(sites_duration_label "${DURS[$idx]}")"
    if [[ -n "${USERS[$idx]:-}" ]]; then
        echo "Basic auth: enabled (user: ${USERS[$idx]})"
    else
        echo "Basic auth: disabled"
    fi
}

edit_page_menu_builder() {
    MENU_LABELS=("Change URL" "Change name" "Change timing (duration)" "Change Basic Auth")
    MENU_HANDLERS=(action_edit_url action_edit_name action_edit_duration action_edit_auth)
}

action_edit_url() {
    local idx="$SITE_EDIT_IDX"
    local raw_url
    raw_url=$(ask_text "New URL" "${URLS[$idx]}")
    URLS[$idx]=$(sites_parse_url "$raw_url")
    log_success "URL updated"
    save_config
}

action_edit_name() {
    local idx="$SITE_EDIT_IDX"
    NAMES[$idx]=$(ask_text "New name (blank = show URL)" "${NAMES[$idx]:-}")
    log_success "Name updated"
    save_config
}

action_edit_duration() {
    local idx="$SITE_EDIT_IDX"
    echo
    echo "  > 0  = auto-rotates every X seconds"
    echo "    0  = manual only"
    echo "   -1  = hidden (PIN-gated)"
    DURS[$idx]=$(ask_integer "Duration in seconds" "${DURS[$idx]}" -1 86400)
    log_success "Timing updated: $(sites_duration_label "${DURS[$idx]}")"
    save_config
}

action_edit_auth() {
    local idx="$SITE_EDIT_IDX"
    if ask_yes_no "Enable HTTP Basic Auth for this page?" "$([[ -n "${USERS[$idx]:-}" ]] && echo y || echo n)"; then
        read -r -p "  Username: " USERS_new
        read -r -s -p "  Password: " PASSES_new
        echo
        USERS[$idx]="$USERS_new"
        PASSES[$idx]="$PASSES_new"
        log_success "Basic Auth updated"
    else
        USERS[$idx]=""
        PASSES[$idx]=""
        log_success "Basic Auth disabled"
    fi
    save_config
}

################################################################################
# Delete
################################################################################

action_delete_page() {
    echo
    for idx in "${!URLS[@]}"; do
        echo "  $((idx + 1)). $(sites_display_label "$idx")"
    done
    echo
    local num
    num=$(ask_integer "Delete which page? (0=cancel)" "0" 0 "${#URLS[@]}")
    [[ "$num" == "0" ]] && { echo "Cancelled"; return; }

    local del_idx=$((num - 1))
    echo "Deleting: $(sites_display_label "$del_idx")"

    unset 'URLS[del_idx]' 'DURS[del_idx]' 'USERS[del_idx]' 'PASSES[del_idx]' 'NAMES[del_idx]'
    URLS=("${URLS[@]}")
    DURS=("${DURS[@]}")
    USERS=("${USERS[@]}")
    PASSES=("${PASSES[@]}")
    NAMES=("${NAMES[@]}")

    if [[ "$HOME_TAB_INDEX" == "$del_idx" ]]; then
        HOME_TAB_INDEX=-1
        log_warning "Home page was deleted - home feature disabled"
    elif [[ "$HOME_TAB_INDEX" -gt "$del_idx" ]]; then
        HOME_TAB_INDEX=$((HOME_TAB_INDEX - 1))
    fi

    log_success "Page deleted"
    save_config
}

################################################################################
# Reorder
################################################################################

action_reorder_page() {
    echo
    echo "Current order:"
    for idx in "${!URLS[@]}"; do
        echo "  $((idx + 1)). $(sites_display_label "$idx")"
    done
    echo

    local max="${#URLS[@]}"
    local from_num to_num
    from_num=$(ask_integer "Move which page? (0=cancel)" "0" 0 "$max")
    [[ "$from_num" == "0" ]] && { echo "Cancelled"; return; }
    to_num=$(ask_integer "Move to position?" "1" 1 "$max")

    local from_idx=$((from_num - 1))
    local to_idx=$((to_num - 1))
    if [[ "$from_idx" == "$to_idx" ]]; then
        echo "Same position - no change"
        return
    fi

    # Work out where the home page (if any, and not the one being moved)
    # will land, before we touch the arrays. Removing the moved item and
    # then re-inserting it at $to_idx always places it at index $to_idx of
    # the *final* array - no further adjustment needed there. Everything
    # else only shifts by the remove and the insert individually.
    local new_home_idx="$HOME_TAB_INDEX"
    if [[ "$HOME_TAB_INDEX" == "$from_idx" ]]; then
        new_home_idx="$to_idx"
    elif [[ "$HOME_TAB_INDEX" != "-1" ]]; then
        [[ "$from_idx" -lt "$HOME_TAB_INDEX" ]] && new_home_idx=$((new_home_idx - 1))
        [[ "$to_idx" -le "$new_home_idx" ]] && new_home_idx=$((new_home_idx + 1))
    fi
    HOME_TAB_INDEX="$new_home_idx"

    local move_url="${URLS[$from_idx]}" move_dur="${DURS[$from_idx]}" \
          move_user="${USERS[$from_idx]}" move_pass="${PASSES[$from_idx]}" move_name="${NAMES[$from_idx]}"

    unset 'URLS[from_idx]' 'DURS[from_idx]' 'USERS[from_idx]' 'PASSES[from_idx]' 'NAMES[from_idx]'
    URLS=("${URLS[@]}")
    DURS=("${DURS[@]}")
    USERS=("${USERS[@]}")
    PASSES=("${PASSES[@]}")
    NAMES=("${NAMES[@]}")

    URLS=("${URLS[@]:0:$to_idx}" "$move_url" "${URLS[@]:$to_idx}")
    DURS=("${DURS[@]:0:$to_idx}" "$move_dur" "${DURS[@]:$to_idx}")
    USERS=("${USERS[@]:0:$to_idx}" "$move_user" "${USERS[@]:$to_idx}")
    PASSES=("${PASSES[@]:0:$to_idx}" "$move_pass" "${PASSES[@]:$to_idx}")
    NAMES=("${NAMES[@]:0:$to_idx}" "$move_name" "${NAMES[@]:$to_idx}")

    log_success "Pages reordered"
    save_config
}

################################################################################
# Home page
################################################################################

action_set_home_page() {
    echo
    if [[ "$HOME_TAB_INDEX" != "-1" ]]; then
        echo "Current home page: #$((HOME_TAB_INDEX + 1)), ${INACTIVITY_TIMEOUT}s timeout"
    else
        echo "Home page currently disabled"
    fi
    echo
    for idx in "${!URLS[@]}"; do
        echo "  $((idx + 1)). $(sites_display_label "$idx")"
    done
    echo

    local num
    num=$(ask_integer "Set which page as home? (0=disable)" "0" 0 "${#URLS[@]}")
    if [[ "$num" == "0" ]]; then
        HOME_TAB_INDEX=-1
        log_success "Home page disabled"
        save_config
        return
    fi

    HOME_TAB_INDEX=$((num - 1))
    local timeout_min
    timeout_min=$(ask_integer "Inactivity timeout in minutes" "2" 1 240)
    INACTIVITY_TIMEOUT=$((timeout_min * 60))

    log_success "Home page: #${num} (${timeout_min}m inactivity timeout)"
    save_config
}
