#!/bin/bash
################################################################################
# menus/advanced_electron.sh - "Electron Maintenance" (Advanced): the
# legacy "Manual Electron Update" and "Fix Blank Screen" items, combined
# under one submenu since both maintain the same Electron installation.
# The binary-repair logic itself (electron_install_binary) now lives in
# lib/electron.sh, shared with fresh provisioning (lib/provision.sh) -
# the same repair sequence applies whether the binary never downloaded
# during the initial `npm install` or went missing later.
#
# Real system state: $KIOSK_DIR/node_modules, package.json, lightdm.
# Every write goes through `sudo`/`sudo -u "$KIOSK_USER"`, stubbed at the
# command level in tests - there's no relocatable equivalent for another
# project's (npm/Electron's) own directory layout.
#
# Depends on: lib/menu.sh, lib/config.sh, lib/electron.sh being sourced first.
################################################################################

electron_installed_version() {
    local package_json="$KIOSK_DIR/package.json"
    if ! sudo test -f "$package_json" 2>/dev/null; then
        echo "not installed"
        return
    fi

    local version
    version=$(sudo grep -oP '"electron"\s*:\s*"\^?\K[0-9.]+' "$package_json" 2>/dev/null || true)
    if [[ -z "$version" ]]; then
        local electron_pkg="$KIOSK_DIR/node_modules/electron/package.json"
        if sudo test -f "$electron_pkg" 2>/dev/null; then
            version=$(sudo grep -oP '"version"\s*:\s*"\K[0-9.]+' "$electron_pkg" 2>/dev/null || true)
        fi
    fi
    echo "${version:-unknown}"
}

electron_is_running() {
    pgrep -f "electron.*main.js" &>/dev/null || pgrep -f "node.*electron" &>/dev/null
}

advanced_electron_status() {
    local ver
    ver=$(electron_installed_version)
    echo "Electron: v${ver}"
    if electron_is_running; then
        echo "  Running"
    else
        echo "  Not running"
    fi
}

advanced_electron_menu_builder() {
    MENU_LABELS=(
        "Check for updates / update Electron"
        "Fix blank screen (repair Electron binary + sandbox)"
    )
    MENU_HANDLERS=(action_update_electron action_repair_electron)
}

advanced_electron_menu() {
    run_menu "ELECTRON MAINTENANCE" advanced_electron_menu_builder advanced_electron_status
}

################################################################################
# Actions
################################################################################

action_update_electron() {
    echo
    if ! sudo test -d "$KIOSK_DIR" 2>/dev/null; then
        log_error "Kiosk directory not found: $KIOSK_DIR"
        pause
        return 1
    fi

    local current_version
    current_version=$(electron_installed_version)
    log_info "Current Electron version: $current_version"

    if electron_is_running; then
        log_success "Electron app is running"
    else
        log_warning "Electron app does not appear to be running"
    fi
    echo

    ask_yes_no "Check for latest Electron version?" "y" || { echo "Cancelled"; pause; return; }

    local latest_version
    latest_version=$(npm view electron version 2>/dev/null || true)
    if [[ -z "$latest_version" ]]; then
        latest_version=$(curl -s https://registry.npmjs.org/electron/latest 2>/dev/null | grep -oP '"version"\s*:\s*"\K[0-9.]+' || true)
    fi
    if [[ -z "$latest_version" ]]; then
        latest_version=$(curl -s https://api.github.com/repos/electron/electron/releases/latest 2>/dev/null | grep -oP '"tag_name"\s*:\s*"v\K[0-9.]+' || true)
    fi

    if [[ -z "$latest_version" ]]; then
        log_error "Could not fetch latest Electron version - check your internet connection"
        pause
        return 1
    fi
    log_success "Latest stable Electron version: $latest_version"
    echo

    if [[ "$current_version" == "$latest_version" ]]; then
        log_success "Already running the latest version"
        ask_yes_no "Reinstall Electron $latest_version anyway?" "n" || { echo "Cancelled"; pause; return; }
    fi

    echo "──────────────────────────────────────────────────────────"
    echo "UPDATE SUMMARY"
    echo "──────────────────────────────────────────────────────────"
    echo "Current version: $current_version"
    echo "Target version:  $latest_version"
    echo "Installation:    $KIOSK_DIR"
    echo

    local current_major="${current_version%%.*}"
    local latest_major="${latest_version%%.*}"
    log_warning "Review breaking changes before updating:"
    echo "  https://www.electronjs.org/docs/latest/breaking-changes"
    if [[ "$latest_major" != "$current_major" ]]; then
        log_warning "MAJOR VERSION CHANGE (v${current_major} -> v${latest_major})"
    fi
    echo

    ask_yes_no "Reviewed breaking changes and want to proceed?" "n" || { echo "Cancelled"; pause; return; }

    echo
    log_info "Creating backup..."
    local kiosk_owner
    kiosk_owner=$(sudo stat -c '%U' "$KIOSK_DIR" 2>/dev/null || echo "$KIOSK_USER")
    local backup_dir="${KIOSK_DIR}/backups/electron_backup_$(date +%Y%m%d_%H%M%S)"
    sudo -u "$kiosk_owner" mkdir -p "$backup_dir"

    if sudo test -f "$KIOSK_DIR/package.json" 2>/dev/null; then
        sudo -u "$kiosk_owner" cp "$KIOSK_DIR/package.json" "$backup_dir/"
    fi
    if sudo test -f "$KIOSK_DIR/package-lock.json" 2>/dev/null; then
        sudo -u "$kiosk_owner" cp "$KIOSK_DIR/package-lock.json" "$backup_dir/"
    fi
    echo "$current_version" | sudo -u "$kiosk_owner" tee "$backup_dir/electron_version.txt" > /dev/null
    log_success "Backup created at: $backup_dir"
    echo

    ask_yes_no "Proceed with Electron update to $latest_version?" "n" || {
        log_info "Update cancelled - backup preserved at: $backup_dir"
        pause
        return
    }

    echo
    log_info "Stopping kiosk display..."
    sudo systemctl stop lightdm 2>/dev/null || true
    sleep 2

    sudo -u "$KIOSK_USER" sed -i "s/\"electron\": \".*\"/\"electron\": \"^${latest_version}\"/" "$KIOSK_DIR/package.json"

    if sudo test -d "$KIOSK_DIR/node_modules/electron" 2>/dev/null; then
        sudo -u "$KIOSK_USER" rm -rf "$KIOSK_DIR/node_modules/electron"
    fi

    log_info "Installing Electron $latest_version (this may take a few minutes)..."
    if sudo -u "$KIOSK_USER" bash -c "cd '$KIOSK_DIR' && npm install electron@'$latest_version'"; then
        log_success "Electron updated to $latest_version"

        local sandbox="$KIOSK_DIR/node_modules/electron/dist/chrome-sandbox"
        if sudo test -f "$sandbox" 2>/dev/null; then
            sudo chown root:root "$sandbox"
            sudo chmod 4755 "$sandbox"
        fi

        if ask_yes_no "Restart kiosk display now?" "y"; then
            sudo systemctl start lightdm
            sleep 3
            if systemctl is-active --quiet lightdm; then
                log_success "Kiosk display started"
            else
                log_error "Kiosk display failed to start - check: sudo journalctl -u lightdm -n 50"
            fi
        else
            log_info "Start manually with: sudo systemctl start lightdm"
        fi
        log_success "Backup preserved at: $backup_dir (delete once confirmed working)"
    else
        log_error "Electron install failed - restoring from backup..."
        if sudo test -f "$backup_dir/package.json" 2>/dev/null; then
            sudo -u "$KIOSK_USER" cp "$backup_dir/package.json" "$KIOSK_DIR/"
        fi
        if sudo -u "$KIOSK_USER" bash -c "cd '$KIOSK_DIR' && npm install"; then
            log_success "Restored original Electron installation"
            sudo systemctl start lightdm
        else
            log_error "Failed to restore - manual intervention required"
        fi
    fi

    pause
}

action_repair_electron() {
    echo
    echo "This will:"
    echo "  1. Check if the Electron binary is present"
    echo "  2. Download it if missing (~120MB)"
    echo "  3. Fix chrome-sandbox permissions (setuid root)"
    echo "  4. Restart the kiosk display"
    echo
    ask_yes_no "Continue?" "y" || { echo "Cancelled"; pause; return; }

    sudo systemctl stop lightdm 2>/dev/null || true
    sleep 1

    # Bare call, not `if ! electron_install_binary; then`: testing a
    # multi-statement function as an if-condition exempts everything
    # inside it from set -e for the duration (e.g. the sandbox chown/
    # chmod below would silently continue past an earlier failure).
    # Capturing $? right after a bare call doesn't have that problem -
    # the exemption only affects whether a nonzero status halts the
    # script, never the actual value $? holds.
    electron_install_binary
    local electron_rc=$?
    if [[ $electron_rc -ne 0 ]]; then
        log_error "Could not install Electron. Check internet and retry."
        pause
        return 1
    fi

    log_info "Restarting kiosk display..."
    sudo systemctl restart lightdm
    sleep 3
    if systemctl is-active --quiet lightdm && pgrep -f "electron.*main.js" &>/dev/null; then
        log_success "Kiosk display is running"
    else
        log_warning "LightDM started but Electron may still be loading."
        echo "  Check: sudo tail -20 $KIOSK_DIR/../electron.log"
    fi

    pause
}
