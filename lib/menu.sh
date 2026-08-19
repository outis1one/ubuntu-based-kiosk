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

# Shared "true"/"false" -> "ON"/"OFF" label for status lines and menu
# entries showing a boolean setting's current value.
onoff() {
    [[ "$1" == "true" ]] && echo "ON" || echo "OFF"
}

# Current primary IP, or the literal "No IP" if there isn't one (e.g. no
# network yet). Callers that only care whether there's an address should
# still check for -n on top of this, since "No IP" is itself non-empty.
get_ip_address() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        echo "No IP"
    fi
}

# "WireGuard: 10.x.x.x | Tailscale: 100.x.x.x" for whichever VPN clients
# are installed and connected, or "None" if none are.
get_vpn_ips() {
    local vpn_info=""

    if command -v wg &>/dev/null && sudo wg show 2>/dev/null | grep -q interface; then
        local wg_ip
        wg_ip=$(sudo wg show all | grep "allowed ips" | head -1 | awk '{print $3}' | cut -d'/' -f1)
        [[ -n "$wg_ip" ]] && vpn_info="${vpn_info}WireGuard: $wg_ip | "
    fi

    if command -v tailscale &>/dev/null; then
        local ts_ip
        ts_ip=$(tailscale ip -4 2>/dev/null)
        [[ -n "$ts_ip" ]] && vpn_info="${vpn_info}Tailscale: $ts_ip | "
    fi

    if command -v netbird &>/dev/null; then
        local nb_ip
        nb_ip=$(netbird status 2>/dev/null | grep "NetBird IP:" | awk '{print $3}')
        [[ -n "$nb_ip" ]] && vpn_info="${vpn_info}Netbird: $nb_ip | "
    fi

    vpn_info="${vpn_info% | }"
    [[ -n "$vpn_info" ]] && echo "$vpn_info" || echo "None"
}

# enable_and_start_units UNIT [UNIT...]
# Reloads systemd and enables+starts the given unit(s) - services or
# timers - returning non-zero if enable or start fails (e.g. systemd/
# D-Bus unreachable, or a real failure on real hardware). Always call
# this from an `if`/`&&`/`||` context: this whole tool runs under
# set -e, so a bare, unguarded call whose last command fails would take
# down the entire session instead of just this one action.
enable_and_start_units() {
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable "$@" 2>/dev/null && sudo systemctl start "$@" 2>/dev/null
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

validate_time() {
    local time="$1"
    [[ $time =~ ^([0-1][0-9]|2[0-3]):([0-5][0-9])$ ]]
}

ask_time() {
    local prompt="$1"
    local default="$2"
    local time

    while true; do
        read -r -p "$prompt [$default]: " time
        time="${time:-$default}"

        if validate_time "$time"; then
            echo "$time"
            return 0
        else
            echo "❌ Invalid time format. Please use HH:MM (00:00 to 23:59)" >&2
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
#
# The handler is called as `handler "$choice"` (the 1-based number picked),
# so a data-driven list (e.g. a set of timezones) can share one handler
# instead of needing a distinct wrapper function per entry. Handlers that
# don't care can just ignore the argument.
run_menu() {
    local title="$1"
    local builder="$2"
    local status_func="${3:-}"
    local exit_label="${4:-Return}"

    while true; do
        clear
        print_menu_header "$title"

        if [[ -n "$status_func" ]]; then
            # `|| true`: same reasoning as the handler call below - a
            # status function's job is read-only display, and a
            # legitimately failing command inside it (e.g. a pipeline
            # whose grep matches nothing, which pipefail turns into a
            # pipeline failure even though the actual last command
            # succeeded) must not be allowed to kill the whole session
            # over what should be, at worst, incomplete status text.
            "$status_func" || true
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

        # `|| true`: this whole tool runs under `set -e`. A handler that
        # legitimately fails (invalid input, a guard clause, etc) and
        # returns non-zero as its last statement must not be allowed to
        # take the entire session down - it should just redraw the menu.
        # Absorbing that here means no menus/*.sh file has to think about
        # set -e at all.
        "${MENU_HANDLERS[$((choice - 1))]}" "$choice" || true
    done
}
