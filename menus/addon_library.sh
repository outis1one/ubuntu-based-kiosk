#!/bin/bash
################################################################################
# menus/addon_library.sh - "Library Catalog" addon: a self-hosted library
# catalogue (Koha) running in Docker, with a "Find a book" page on the kiosk.
#
# What gets installed (all from this checkout's library/ directory, deployed to
# $LIBRARY_DIR - see library/README.md for the stack itself):
#   - Koha: cataloguing, Z39.50 lookup, label printing, people and lending.
#   - Quick Add: the "scan an ISBN, the book is added" page, with a Find a book tab.
#   - MariaDB.
# Docker itself is installed on demand (lib/docker.sh).
#
# Everything needs a login. The kiosk shows the "Find a book" page signed in as a
# READ-ONLY guest login (Find a book is search only; the guest has no Koha account at
# all, because Koha's own search permission also allows editing label layouts); the page
# list stores that guest login like any other Basic Auth site. The admin login never
# goes into the kiosk's config. The public catalogue (OPAC) is off by default.
#
# Whether other devices on the LAN can reach the library site is the "Network access"
# choice below. NOTE: Docker publishes ports straight through iptables and bypasses
# ufw, so "this kiosk only" is enforced by binding the published ports to 127.0.0.1
# (BIND_ADDR in library/.env), not by firewall rules.
#
# Depends on: lib/menu.sh, lib/config.sh, lib/docker.sh being sourced first.
################################################################################

LIBRARY_CATALOGUE_TAB_NAME="Find a book"

################################################################################
# Detection / state
################################################################################

library_env_get() {
    sudo grep -m1 "^$1=" "$LIBRARY_DIR/.env" 2>/dev/null | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

library_is_installed() {
    [[ -f "$LIBRARY_DIR/docker-compose.yml" ]] || return 1
    [[ "$(docker_container_state library-koha)" != "missing" ]]
}

library_is_running() {
    [[ "$(docker_container_state library-koha)" == "running" ]]
}

# The page the kiosk shows: Quick Add's Find a book view on the library site.
library_catalogue_url() {
    echo "http://localhost:$(library_env_get STAFF_PORT)/add/#find"
}

# Pages from earlier versions of this add-on pointed at the public catalogue.
library_old_catalogue_url() {
    echo "http://localhost:$(library_env_get OPAC_PORT)/"
}

# True when the kiosk's page list already shows the catalogue.
library_tab_exists() {
    local url idx
    url="$(library_catalogue_url)"
    for idx in "${!URLS[@]}"; do
        [[ "${URLS[$idx]}" == "$url" ]] && return 0
    done
    return 1
}

addon_library_status() {
    if ! library_is_installed; then
        echo "Library Catalog: not installed"
        return
    fi
    local state health ip
    state="$(docker_container_state library-koha)"
    health="$(docker_container_health library-koha)"
    ip="$(get_ip_address)"
    echo "Library Catalog: ${state}${health:+ ($health)}"
    echo "  Find a book:  $(library_catalogue_url) (shown on the kiosk, as the read-only guest)"
    if [[ "$(library_env_get BIND_ADDR)" == "127.0.0.1" ]]; then
        echo "  Network:    this kiosk only"
    else
        echo "  Network:    other devices on the LAN can reach the library site at http://${ip}:$(library_env_get STAFF_PORT)/"
    fi
}

addon_library_menu_builder() {
    if library_is_installed; then
        load_existing_config
        local tab_label="Show Find a book on the kiosk"
        library_tab_exists && tab_label="Stop showing Find a book on the kiosk"
        MENU_LABELS=("Addresses and staff login" "$tab_label" "Network access (this kiosk only / LAN)" "Start" "Stop" "Update" "Uninstall")
        MENU_HANDLERS=(action_library_show_access action_library_toggle_tab action_library_network action_library_start action_library_stop action_library_update action_library_uninstall)
    else
        MENU_LABELS=("Install Library Catalog")
        MENU_HANDLERS=(action_library_install)
    fi
}

addon_library_menu() {
    run_menu "LIBRARY CATALOG" addon_library_menu_builder addon_library_status
}

################################################################################
# Helpers
################################################################################

# Copy library/ from this checkout to $LIBRARY_DIR. Never overwrites the
# deployed .env (passwords) even if a stray one exists in the checkout.
library_sync_files() {
    local src="${SCRIPT_DIR}/library"
    if [[ ! -f "$src/docker-compose.yml" ]]; then
        log_error "library/ not found in this checkout ($src) - re-clone or git pull"
        return 1
    fi
    sudo mkdir -p "$LIBRARY_DIR" || return 1
    tar -C "$src" --exclude=./.env --exclude='*.crt' -cf - . | sudo tar -C "$LIBRARY_DIR" -xf - || return 1
    sudo chmod 755 "$LIBRARY_DIR/install.sh"
}

library_add_tab() {
    load_existing_config
    if library_tab_exists; then
        log_info "Find a book is already one of the kiosk's pages."
        return 0
    fi
    URLS+=("$(library_catalogue_url)")
    DURS+=("0")
    USERS+=("$(library_env_get VIEWER_USER)")        # read-only guest, never the admin login
    PASSES+=("$(library_env_get VIEWER_PASSWORD)")
    NAMES+=("$LIBRARY_CATALOGUE_TAB_NAME")
    save_config
}

# Drop every page that points at the catalogue's local address.
library_remove_tab() {
    load_existing_config
    local url old idx
    url="$(library_catalogue_url)"
    old="$(library_old_catalogue_url)"
    local -a nu=() nd=() nus=() np=() nn=()
    for idx in "${!URLS[@]}"; do
        [[ "${URLS[$idx]}" == "$url" || "${URLS[$idx]}" == "$old" ]] && continue
        nu+=("${URLS[$idx]}"); nd+=("${DURS[$idx]:-0}"); nus+=("${USERS[$idx]:-}")
        np+=("${PASSES[$idx]:-}"); nn+=("${NAMES[$idx]:-}")
    done
    if [[ "${#nu[@]}" -eq "${#URLS[@]}" ]]; then
        return 0
    fi
    URLS=("${nu[@]}"); DURS=("${nd[@]}"); USERS=("${nus[@]}"); PASSES=("${np[@]}"); NAMES=("${nn[@]}")
    HOME_TAB_INDEX=-1
    save_config
}

# library_set_bind ADDR - persist BIND_ADDR in .env and recreate the containers.
library_set_bind() {
    local addr="$1"
    if sudo grep -q '^BIND_ADDR=' "$LIBRARY_DIR/.env" 2>/dev/null; then
        sudo sed -i "s|^BIND_ADDR=.*|BIND_ADDR=${addr}|" "$LIBRARY_DIR/.env"
    else
        echo "BIND_ADDR=${addr}" | sudo tee -a "$LIBRARY_DIR/.env" >/dev/null
    fi
    docker_compose "$LIBRARY_DIR" up -d
}

library_warn_if_low_memory() {
    local total_mb
    total_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    if [[ "$total_mb" -gt 0 && "$total_mb" -lt 3000 ]]; then
        log_warning "This machine has about ${total_mb} MB of RAM. The catalogue needs roughly 2 GB on top of the kiosk itself - it may be slow."
    fi
}

################################################################################
# Actions
################################################################################

action_library_install() {
    echo
    echo "This installs a library catalogue (Koha) with Z39.50 book lookup, label"
    echo "printing and a scan-to-add page. It needs Docker (installed for you if"
    echo "missing), about 3 GB of disk space and ~2 GB of RAM. The first build takes"
    echo "5-10 minutes."
    echo
    library_warn_if_low_memory

    local library_name
    library_name=$(ask_text "Library name (shown on the catalogue)" "My Library")
    [[ -z "$library_name" ]] && library_name="My Library"

    local bind="0.0.0.0"
    echo
    echo "Who should be able to open the catalogue, staff interface and Quick Add"
    echo "page besides this kiosk?"
    echo "  - Yes: any device on your network (use it from your own laptop/phone;"
    echo "         the staff pages are protected by a generated password)."
    echo "  - No:  only this kiosk. Safest, but you can only manage the library here."
    if ! ask_yes_no "Allow other devices on the network?" "y"; then
        bind="127.0.0.1"
    fi

    docker_ensure_installed || { pause; return 1; }
    library_sync_files || { pause; return 1; }

    echo
    log_info "Building and starting the stack - this takes a while on the first run..."
    if ! sudo env LIBRARY_NAME="$library_name" BIND_ADDR="$bind" "$LIBRARY_DIR/install.sh"; then
        log_error "The library stack failed to start - see: sudo docker logs library-koha"
        pause
        return 1
    fi

    if ask_yes_no "Show the Find a book page on the kiosk screen (signed in as the read-only guest)?" "y"; then
        library_add_tab
    fi
    echo
    log_success "Library Catalog installed"
    pause
}

action_library_show_access() {
    local ip user pass
    ip="$(get_ip_address)"
    user="$(library_env_get ADMIN_USER)"
    pass="$(library_env_get ADMIN_PASSWORD)"
    echo
    if [[ "$(library_env_get BIND_ADDR)" == "127.0.0.1" ]]; then
        ip="localhost"
        echo "(Network access is limited to this kiosk.)"
    fi
    echo "  Your library (sign in here):  http://${ip}:$(library_env_get STAFF_PORT)/"
    echo "      Find a book / Add books:  http://${ip}:$(library_env_get STAFF_PORT)/add/"
    echo "  Admin login:                  ${user}  /  ${pass}"
    echo "  Read-only login to share:     $(library_env_get VIEWER_USER)  /  $(library_env_get VIEWER_PASSWORD)"
    echo "      Give it out with http://${ip}:$(library_env_get STAFF_PORT)/add/ - it opens Find a book: search only,"
    echo "      it cannot add or change anything (and it has no login on the staff site itself)."
    echo
    echo "  Passwords live in $LIBRARY_DIR/.env (root only)."
    pause
}

action_library_toggle_tab() {
    load_existing_config
    if library_tab_exists; then
        library_remove_tab
    else
        library_add_tab
    fi
    pause
}

action_library_network() {
    local current
    current="$(library_env_get BIND_ADDR)"
    echo
    echo "Currently: $([[ "$current" == "127.0.0.1" ]] && echo "this kiosk only" || echo "other devices on the network can connect")"
    echo
    if ask_yes_no "Allow other devices on the network?" "$([[ "$current" == "127.0.0.1" ]] && echo n || echo y)"; then
        library_set_bind "0.0.0.0" && log_success "Other devices on the network can now connect"
    else
        library_set_bind "127.0.0.1" && log_success "Only this kiosk can connect now"
    fi
    pause
}

action_library_start() {
    docker_compose "$LIBRARY_DIR" start && log_success "Started"
    pause
}

action_library_stop() {
    docker_compose "$LIBRARY_DIR" stop && log_success "Stopped (the kiosk page will show an error until you start it again)"
    pause
}

action_library_update() {
    echo
    echo "This rebuilds the images with the latest Koha release. Your catalogue data is kept."
    if ! ask_yes_no "Update now?" "y"; then
        return 0
    fi
    docker_ensure_installed || { pause; return 1; }
    library_sync_files || { pause; return 1; }
    if sudo "$LIBRARY_DIR/install.sh" --update; then
        log_success "Updated"
    else
        log_error "Update failed - see: sudo docker logs library-koha"
    fi
    pause
}

# library_do_uninstall [purge]
#   no argument: stop and remove the containers but KEEP the data volumes and
#                $LIBRARY_DIR/.env - the database password is baked into the
#                database volume, so a later reinstall needs the same .env.
#   purge:       also delete the data (all books!), the images and $LIBRARY_DIR.
library_do_uninstall() {
    local mode="${1:-}"
    library_remove_tab
    if [[ -f "$LIBRARY_DIR/docker-compose.yml" ]]; then
        if [[ "$mode" == "purge" ]]; then
            docker_compose "$LIBRARY_DIR" down -v --rmi local 2>/dev/null || true
        else
            docker_compose "$LIBRARY_DIR" down 2>/dev/null || true
        fi
    fi
    if [[ "$mode" == "purge" ]]; then
        sudo rm -rf "$LIBRARY_DIR"
        log_success "Library Catalog and all its data removed"
    else
        log_success "Library Catalog stopped and removed (your books are kept)"
    fi
}

action_library_uninstall() {
    echo
    echo "This stops and removes the catalogue containers."
    if ask_yes_no "Also DELETE all catalogue data (every book you have added)?" "n"; then
        local confirm
        confirm=$(ask_text "Type DELETE to confirm" "")
        if [[ "$confirm" != "DELETE" ]]; then
            echo "Cancelled"
            pause
            return 0
        fi
        library_do_uninstall purge
    else
        library_do_uninstall
        echo "Your books are kept; install again from this menu to bring them back."
    fi
    pause
}
