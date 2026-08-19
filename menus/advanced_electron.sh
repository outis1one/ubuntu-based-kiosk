#!/bin/bash
################################################################################
# menus/advanced_electron.sh - "Electron Maintenance" (Advanced): the
# legacy "Manual Electron Update" and "Fix Blank Screen" items, combined
# under one submenu since both maintain the same Electron installation
# and share the binary-repair logic (electron_install_binary).
#
# Real system state: $KIOSK_DIR/node_modules, package.json, lightdm.
# Every write goes through `sudo`/`sudo -u "$KIOSK_USER"`, stubbed at the
# command level in tests - there's no relocatable equivalent for another
# project's (npm/Electron's) own directory layout.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
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

# Re-verify/download the Electron binary and fix chrome-sandbox
# permissions, without touching package.json or reinstalling anything
# else. Shared by both actions below.
electron_install_binary() {
    local electron_bin="$KIOSK_DIR/node_modules/electron/dist/electron"

    if ! sudo -u "$KIOSK_USER" test -f "$electron_bin"; then
        log_warning "Electron binary missing - retrying via install.js..."
        sudo -u "$KIOSK_USER" bash -lc "cd '$KIOSK_DIR' && ELECTRON_FORCE_DOWNLOAD=true node node_modules/electron/install.js" || true
    fi

    if ! sudo -u "$KIOSK_USER" test -f "$electron_bin"; then
        log_warning "Attempting direct download of Electron binary (~120MB)..."
        local electron_ver
        electron_ver=$(sudo -u "$KIOSK_USER" node -e \
            "try{console.log(require('$KIOSK_DIR/node_modules/electron/package.json').version)}catch(e){}" 2>/dev/null || true)
        if [[ -n "$electron_ver" ]]; then
            local electron_url="https://github.com/electron/electron/releases/download/v${electron_ver}/electron-v${electron_ver}-linux-x64.zip"
            log_info "Downloading Electron v${electron_ver} directly..."
            local tmp_zip
            tmp_zip=$(mktemp --suffix=.zip)
            if wget --timeout=300 --tries=3 -O "$tmp_zip" "$electron_url"; then
                command -v unzip &>/dev/null || sudo apt install -y unzip
                chmod 644 "$tmp_zip"
                sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR/node_modules/electron/" 2>/dev/null || true
                sudo -u "$KIOSK_USER" mkdir -p "$KIOSK_DIR/node_modules/electron/dist"
                sudo -u "$KIOSK_USER" unzip -o "$tmp_zip" -d "$KIOSK_DIR/node_modules/electron/dist/" || true
                sudo -u "$KIOSK_USER" chmod +x "$electron_bin" || true
            fi
            rm -f "$tmp_zip"
        fi
    fi

    if ! sudo -u "$KIOSK_USER" test -f "$electron_bin"; then
        log_error "Electron binary download failed after all attempts."
        log_error "Check your internet connection and try again."
        return 1
    fi
    log_success "Electron binary verified"

    # chrome-sandbox MUST be owned by root and setuid, or Electron shows a blank screen.
    local sandbox="$KIOSK_DIR/node_modules/electron/dist/chrome-sandbox"
    if sudo -u "$KIOSK_USER" test -f "$sandbox"; then
        sudo chown root:root "$sandbox"
        sudo chmod 4755 "$sandbox"
        log_success "Chrome sandbox permissions set (required for display)"
    fi
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

    if ! electron_install_binary; then
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
