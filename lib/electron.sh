#!/bin/bash
################################################################################
# lib/electron.sh - Electron binary install/repair, shared between fresh
# provisioning (lib/provision.sh) and ongoing maintenance
# (menus/advanced_electron.sh's "Fix blank screen" action) - the exact
# same repair sequence applies whether the binary never downloaded during
# `npm install` or went missing later.
#
# Depends on: lib/config.sh being sourced first (for $KIOSK_DIR/$KIOSK_USER).
################################################################################

# Re-verify/download the Electron binary and fix chrome-sandbox
# permissions, without touching package.json or reinstalling anything else.
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
