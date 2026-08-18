#!/bin/bash
################################################################################
# lib/menu.sh - Reusable numbered-menu framework + validated input helpers.
#
# Goal: menu *behavior* (numbering, "0 to exit/return", input validation)
# lives here once. Individual menus/*.sh files only supply their content
# (labels + handler functions) and never re-implement the loop/echo/case
# boilerplate that made the old single-file installer hard to change safely.
#
# Usage:
#   my_menu_builder() {
#       MENU_LABELS=("Do thing A" "Do thing B")
#       MENU_HANDLERS=(action_a action_b)
#   }
#   run_menu "MY MENU TITLE" my_menu_builder [my_status_func]
#
# The builder runs fresh on every redraw, so labels/handlers can change
# based on current state (e.g. "no sites yet" vs "5 sites configured").
################################################################################

################################################################################
# Logging
################################################################################

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "✓ $*"
}

log_warning() {
    echo "⚠ $*"
}

pause() {
    read -r -p "Press Enter to continue..."
}

################################################################################
# Validated input helpers
################################################################################

validate_yes_no() {
    local answer="$1"
    case "${answer,,}" in
        y|yes|yeah|yep|yup|sure|ok|okay) return 0 ;;
        n|no|nope|nah) return 1 ;;
        *) return 2 ;;  # invalid
    esac
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local answer

    while true; do
        read -r -p "$prompt (y/n) [$default]: " answer
        answer="${answer:-$default}"

        validate_yes_no "$answer"
        local result=$?

        if [[ $result -eq 0 ]]; then
            return 0
        elif [[ $result -eq 1 ]]; then
            return 1
        else
            echo "❌ Invalid input. Please enter 'y' for yes or 'n' for no"
            echo
        fi
    done
}

validate_integer() {
    local value="$1"
    local min="${2:--2147483648}"
    local max="${3:-2147483647}"

    if [[ $value =~ ^-?[0-9]+$ ]]; then
        if [[ $value -ge $min && $value -le $max ]]; then
            return 0
        fi
    fi
    return 1
}

ask_integer() {
    local prompt="$1"
    local default="$2"
    local min="${3:--2147483648}"
    local max="${4:-2147483647}"
    local value

    while true; do
        read -r -p "$prompt [$default]: " value
        value="${value:-$default}"

        if validate_integer "$value" "$min" "$max"; then
            echo "$value"
            return 0
        else
            echo "❌ Invalid number. Please enter an integer between $min and $max" >&2
            echo >&2
        fi
    done
}

validate_url() {
    local url="$1"
    if [[ $url =~ ^(https?|file|data)://.*$ ]] || [[ $url =~ ^about: ]]; then
        return 0
    else
        return 1
    fi
}

ask_url() {
    local prompt="$1"
    local default="$2"
    local url

    while true; do
        read -r -p "$prompt [$default]: " url
        url="${url:-$default}"

        if validate_url "$url"; then
            echo "$url"
            return 0
        else
            echo "❌ Invalid URL. Must start with http://, https://, file://, data:, or about:" >&2
            echo >&2
        fi
    done
}

ask_text() {
    local prompt="$1"
    local default="${2:-}"
    local value

    read -r -p "$prompt [$default]: " value
    echo "${value:-$default}"
}

validate_menu_choice() {
    local choice="$1"
    local max="$2"
    validate_integer "$choice" 0 "$max"
}

ask_menu_choice() {
    local max="$1"
    local choice

    while true; do
        read -r -p "Choose [0-$max]: " choice

        if validate_menu_choice "$choice" "$max"; then
            echo "$choice"
            return 0
        else
            echo "❌ Invalid choice. Please enter a number between 0 and $max" >&2
            echo >&2
        fi
    done
}

################################################################################
# Menu framework
################################################################################

print_menu_header() {
    local title="$1"
    echo "══════════════════════════════════════════════════════════"
    printf "   %s\n" "$title"
    echo "══════════════════════════════════════════════════════════"
    echo
}

# run_menu TITLE BUILDER_FUNC [STATUS_FUNC] [EXIT_LABEL]
#
# BUILDER_FUNC must set the globals MENU_LABELS and MENU_HANDLERS (parallel
# indexed arrays). It is called once per redraw, so it can reflect current
# state. STATUS_FUNC, if given, is called right after the header to print
# read-only context (current settings, current list, etc).
#
# Entries are auto-numbered 1..N. "0" always returns from run_menu - no
# menu file needs to hand-roll its own exit case.
run_menu() {
    local title="$1"
    local builder="$2"
    local status_func="${3:-}"
    local exit_label="${4:-Return}"

    while true; do
        clear
        print_menu_header "$title"

        if [[ -n "$status_func" ]]; then
            "$status_func"
            echo
        fi

        local -a MENU_LABELS=()
        local -a MENU_HANDLERS=()
        "$builder"

        if [[ "${#MENU_LABELS[@]}" -eq 0 ]]; then
            log_warning "Nothing to do here yet."
            echo "   0. $exit_label"
            echo
            ask_menu_choice 0 >/dev/null
            return 0
        fi

        local i=1
        for label in "${MENU_LABELS[@]}"; do
            printf "  %2d. %s\n" "$i" "$label"
            i=$((i + 1))
        done
        echo "   0. $exit_label"
        echo

        local choice
        choice=$(ask_menu_choice "${#MENU_LABELS[@]}")

        if [[ "$choice" == "0" ]]; then
            return 0
        fi

        "${MENU_HANDLERS[$((choice - 1))]}"
    done
}
