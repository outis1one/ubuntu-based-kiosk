#!/bin/bash
################################################################################
# menus/addon_cups.sh - "CUPS Printing" addon (from the legacy Addons menu).
#
# First Addon migrated. Genuinely mutates real system state - installs/
# purges apt packages, writes /etc/cups/cupsd.conf and a polkit rule,
# touches ufw - at fixed paths CUPS itself doesn't let us relocate the
# way $SYSTEMD_DIR/$CRON_D_DIR/etc let us relocate our own files. Only
# the polkit rule's directory is parameterized ($POLKIT_DIR, since that's
# ours to place); everything else (cupsd.conf, apt, systemctl, ufw) gets
# full command-level `sudo` stubbing in every test - there is no scratch
# equivalent for a real apt-managed subsystem's own file layout.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

cups_is_installed() {
    dpkg -l 2>/dev/null | grep -q "^ii\s\+cups\s"
}

cups_is_active() {
    systemctl is-active --quiet cups
}

addon_cups_status() {
    if cups_is_installed && cups_is_active; then
        echo "CUPS: installed and running (http://$(get_ip_address):631)"
    elif cups_is_installed; then
        echo "CUPS: installed but not running"
    else
        echo "CUPS: not installed"
    fi
}

addon_cups_menu_builder() {
    if cups_is_installed && cups_is_active; then
        MENU_LABELS=("Reconfigure for network access" "Complete uninstall (purge)")
        MENU_HANDLERS=(action_reconfigure_cups action_cups_uninstall)
    elif cups_is_installed; then
        MENU_LABELS=("Start CUPS" "Complete uninstall (purge)")
        MENU_HANDLERS=(action_start_cups action_cups_uninstall)
    else
        MENU_LABELS=("Install CUPS printing")
        MENU_HANDLERS=(action_install_cups)
    fi
}

addon_cups_menu() {
    run_menu "CUPS PRINTING SUPPORT" addon_cups_menu_builder addon_cups_status
}

################################################################################
# Actions
################################################################################

action_install_cups() {
    echo
    ask_yes_no "Install CUPS printing?" "n" || { echo "Cancelled"; return; }

    echo "Installing CUPS from scratch..."
    if ! sudo apt update; then
        log_error "apt update failed - check network/package sources and try again"
        return 1
    fi
    if ! sudo apt install -y cups cups-client cups-filters printer-driver-all \
        printer-driver-cups-pdf hplip printer-driver-gutenprint \
        foomatic-db-compressed-ppds openprinting-ppds; then
        log_error "CUPS package installation failed"
        return 1
    fi

    sudo systemctl enable cups 2>/dev/null || true
    sudo systemctl start cups 2>/dev/null || true

    echo "Waiting for CUPS to start..."
    for _ in {1..30}; do
        # Must stay in an `if` - a bare `cmd1 && cmd2` statement is
        # subject to set -e itself when cmd1 fails, which is virtually
        # guaranteed on early iterations right after install.
        if cups_is_active && lpstat -r &>/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    # $BUILD_USER already resolves to $SUDO_USER when the tool was run via
    # sudo, so a single usermod covers it - the legacy code ran this twice
    # (once for a hardcoded computed user, once again for $SUDO_USER
    # directly), which was harmless but genuinely redundant.
    sudo usermod -aG lpadmin "$BUILD_USER"

    action_reconfigure_cups

    log_success "CUPS installed"
    echo "  Web interface: http://$(get_ip_address):631"
}

action_start_cups() {
    sudo systemctl enable cups
    sudo systemctl start cups
    log_success "CUPS started"
}

action_reconfigure_cups() {
    if [[ -f /etc/cups/cupsd.conf ]]; then
        sudo cp /etc/cups/cupsd.conf "/etc/cups/cupsd.conf.backup-$(date +%Y%m%d-%H%M%S)"
    fi

    if command -v cupsctl &>/dev/null; then
        sudo cupsctl --remote-admin --remote-any --share-printers 2>/dev/null || true
    fi

    sudo sed -i 's/^Listen localhost:631/Port 631/' /etc/cups/cupsd.conf 2>/dev/null || true
    sudo sed -i 's/^Listen 127.0.0.1:631/Port 631/' /etc/cups/cupsd.conf 2>/dev/null || true

    sudo mkdir -p "$POLKIT_DIR"
    sudo tee "$POLKIT_DIR/kiosk-printing.pkla" > /dev/null <<EOF
[Allow kiosk printing]
Identity=unix-user:${KIOSK_USER}
Action=org.opensuse.cupspkhelper.mechanism.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

    sudo ufw allow 631/tcp comment 'CUPS' 2>/dev/null || true
    sudo systemctl restart cups 2>/dev/null || true

    log_success "CUPS configured for network access"
}

action_cups_uninstall() {
    echo
    ask_yes_no "Completely remove CUPS, including all queues and settings (purge)?" "n" || { echo "Cancelled"; return; }

    echo "Performing complete CUPS uninstall..."

    sudo systemctl stop cups cups-browsed 2>/dev/null || true
    sudo systemctl disable cups cups-browsed 2>/dev/null || true

    sudo apt remove --purge -y cups cups-daemon cups-client cups-filters \
        cups-common cups-core-drivers cups-server-common cups-browsed \
        cups-ppdc cups-bsd libcups2 libcupsimage2 2>/dev/null || true

    sudo apt remove --purge -y printer-driver-all printer-driver-cups-pdf \
        hplip printer-driver-gutenprint foomatic-db-compressed-ppds \
        openprinting-ppds 2>/dev/null || true

    sudo rm -rf /etc/cups /var/cache/cups /var/spool/cups /var/log/cups /usr/share/cups
    sudo rm -f "$POLKIT_DIR/kiosk-printing.pkla"

    sudo apt autoremove -y
    sudo apt clean

    log_success "CUPS completely removed"
}
