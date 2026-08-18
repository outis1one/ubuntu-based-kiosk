#!/bin/bash
################################################################################
# menus/wifi.sh - "WiFi" configuration.
#
# HIGH RISK, unlike anything migrated so far: this changes live network
# configuration and, if run over SSH, can disconnect the very session
# configuring it. Every safety mechanism from the legacy configure_wifi
# is preserved exactly: a netplan backup before writing, a 60-second
# watchdog (armed only when $SSH_CONNECTION is set) that reverts to the
# backup if the new config never comes up, and an explicit "restore
# backup?" prompt if `netplan apply` itself fails outright.
#
# Netplan's directory is $NETPLAN_DIR (lib/config.sh) rather than a
# hardcoded /etc/netplan, so a test can point it at scratch space. But
# unlike every other migrated menu, there is deliberately no automated
# test - not even a stubbed one - that calls the real `netplan apply`,
# `nmcli`, `iw`, `wpa_cli`, or `sudo ip link set ... up`. Only the pure
# logic (SSID/password handling, YAML generation, backup naming) is
# covered by tests with those commands stubbed; the actual apply step
# is exercised by hand against real hardware only.
#
# Unlike the other migrated menus, this one has no sub-options - it's a
# single linear wizard, same as the legacy configure_wifi - so wifi_menu
# IS the action, not a run_menu wrapper.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

wifi_menu() {
    echo
    echo " ═══ WIFI CONFIGURATION ═══"
    echo

    local has_tools=false
    if command -v nmcli &>/dev/null || command -v iw &>/dev/null || command -v wpa_cli &>/dev/null; then
        has_tools=true
    fi

    if ! $has_tools; then
        log_error "No WiFi tools found (nmcli, iw, or wpa_cli)"
        echo "Install: sudo apt install network-manager wireless-tools wpasupplicant"
        return 1
    fi

    local wifi_iface
    wifi_iface=$(ls /sys/class/net 2>/dev/null | grep -E "^wl" | head -1)

    if [[ -z "$wifi_iface" ]]; then
        log_warning "No WiFi hardware detected"
        echo "If you have a USB WiFi adapter, ensure it's plugged in."
        return 1
    fi

    echo "Interface: $wifi_iface"
    echo "Current IP: $(get_ip_address)"
    echo

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        log_warning "SSH detected - changes auto-revert after 60s if the connection fails"
        echo
    fi

    ask_yes_no "Configure WiFi?" "n" || return 0

    echo "Bringing up interface..."
    if ! sudo ip link set "$wifi_iface" up 2>/dev/null; then
        log_error "Failed to bring up interface"
        return 1
    fi
    sleep 3

    echo "Scanning for networks (this takes 5-10 seconds)..."
    local scan_results=""

    if command -v nmcli &>/dev/null; then
        if sudo nmcli device wifi rescan 2>/dev/null; then
            sleep 5
            scan_results=$(nmcli -t -f SSID,SIGNAL device wifi list 2>/dev/null | sort -t: -k2 -rn | cut -d: -f1 | grep -v "^$" | uniq)
        fi
    fi

    if [[ -z "$scan_results" ]] && command -v iw &>/dev/null; then
        local scan_tmp
        scan_tmp=$(mktemp)
        if sudo iw dev "$wifi_iface" scan 2>/dev/null | grep -E "^BSS|SSID:" > "$scan_tmp"; then
            scan_results=$(grep "SSID:" "$scan_tmp" | sed 's/.*SSID: //' | grep -v "^$" | sort -u)
        fi
        rm -f "$scan_tmp"
    fi

    if [[ -z "$scan_results" ]]; then
        sudo wpa_cli -i "$wifi_iface" scan >/dev/null 2>&1 || true
        sleep 5
        scan_results=$(sudo wpa_cli -i "$wifi_iface" scan_results 2>/dev/null | awk -F'\t' 'NR>1 && $5!="" {print $5}' | sort -u)
    fi

    local ssid=""
    if [[ -z "$scan_results" ]]; then
        log_warning "No networks found in scan"
        echo "This could mean:"
        echo "  • WiFi is disabled in BIOS/UEFI"
        echo "  • Hardware WiFi switch is off"
        echo "  • Driver not loaded"
        echo "  • Networks out of range"
        echo
        if ask_yes_no "Enter SSID manually anyway?" "n"; then
            read -r -p "SSID: " ssid
        else
            return 1
        fi
    else
        echo
        echo "Available networks (strongest first):"
        echo "$scan_results" | nl -w2 -s'. '
        echo "  0. Manual entry"
        echo
        local choice
        read -r -p "Select network number or enter SSID: " choice
        if [[ "$choice" == "0" ]]; then
            read -r -p "SSID: " ssid
        elif [[ "$choice" =~ ^[0-9]+$ ]]; then
            ssid=$(echo "$scan_results" | sed -n "${choice}p")
        else
            ssid="$choice"
        fi
    fi

    if [[ -z "$ssid" ]]; then
        log_error "No SSID provided"
        return 1
    fi

    local password
    read -r -s -p "Password for '$ssid': " password
    echo
    if [[ -z "$password" ]]; then
        log_error "No password provided"
        return 1
    fi

    apply_wifi_config "$wifi_iface" "$ssid" "$password"
}

# apply_wifi_config IFACE SSID PASSWORD
# Split out from wifi_menu so a test can drive it directly without going
# through interface detection/scanning, which don't exist in a container.
apply_wifi_config() {
    local wifi_iface="$1"
    local ssid="$2"
    local password="$3"

    # `|| true`: under set -e + pipefail (this whole tool runs under both),
    # `ls` matching nothing exits non-zero even with stderr silenced, which
    # would abort this function outright instead of falling through to the
    # default filename below. Same class of bug as the run_menu fix in
    # lib/menu.sh - masked here in practice because cloud-init almost
    # always leaves a *.yaml file behind, but not guaranteed.
    local netplan_file
    netplan_file=$(ls "$NETPLAN_DIR"/*.yaml 2>/dev/null | head -1) || true
    [[ -z "$netplan_file" ]] && netplan_file="$NETPLAN_DIR/50-cloud-init.yaml"

    local backup=""
    if [[ -f "$netplan_file" ]]; then
        backup="${netplan_file}.backup-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$netplan_file" "$backup"
        log_success "Backup: $backup"
    fi

    local temp_plan
    temp_plan=$(mktemp --suffix=.yaml)
    cat > "$temp_plan" <<EOF
network:
  version: 2
  renderer: networkd
  wifis:
    $wifi_iface:
      dhcp4: true
      dhcp6: false
      optional: true
      access-points:
        "$ssid":
          password: "$password"
EOF

    if [[ -n "${SSH_CONNECTION:-}" ]] && [[ -n "$backup" ]]; then
        local watchdog
        watchdog=$(mktemp --suffix=.sh)
        cat > "$watchdog" <<'WATCHEOF'
#!/bin/bash
sleep 60
if [[ -f "$1" && -f "$2" ]]; then
    ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$ip" ]] || ! ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        cp "$1" "$2"
        netplan apply 2>/dev/null
        echo "WiFi config reverted - connection failed" | wall
    fi
fi
rm -f "$0"
WATCHEOF
        chmod +x "$watchdog"
        nohup sudo bash "$watchdog" "$backup" "$netplan_file" >/dev/null 2>&1 &
        echo "Watchdog started - will revert in 60s if the connection fails"
    fi

    sudo cp "$temp_plan" "$netplan_file"
    sudo chmod 0600 "$netplan_file"
    rm -f "$temp_plan"

    echo "Applying configuration..."
    local netplan_log
    netplan_log=$(mktemp)
    if sudo netplan apply > "$netplan_log" 2>&1; then
        cat "$netplan_log"
        sleep 10
        local new_ip
        new_ip=$(get_ip_address)
        if [[ -n "$new_ip" && "$new_ip" != "No IP" ]]; then
            log_success "Connected: $ssid ($new_ip)"
            [[ -n "${SSH_CONNECTION:-}" ]] && echo "Connection successful - watchdog will not revert"
        else
            log_warning "Config applied but no IP yet"
            echo "Check: sudo journalctl -u systemd-networkd -f"
        fi
    else
        log_error "netplan apply failed"
        echo "Error log:"
        cat "$netplan_log"
        if [[ -n "$backup" ]] && ask_yes_no "Restore backup?" "y"; then
            sudo cp "$backup" "$netplan_file"
            # Last resort after everything else failed: report, don't crash
            # the session if even the restore-and-reapply doesn't work.
            if sudo netplan apply; then
                log_success "Backup restored and applied"
            else
                log_error "Failed to reapply the restored backup - manual intervention needed"
            fi
        fi
    fi
    rm -f "$netplan_log"
}
