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
# single linear wizard, same as the legacy configure_wifi. wifi_menu runs
# it (wifi_configure) and then pauses: run_menu clears the screen as soon
# as a handler returns, which used to wipe every error message here
# before it could be read - the menu just seemed to bounce back.
#
# The WiFi config goes in its own file, $NETPLAN_DIR/60-kiosk-wifi.yaml,
# which netplan merges with the rest - not over the first *.yaml it finds,
# which on a fresh install is the installer's wired config.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

WIFI_NETPLAN_FILE="$NETPLAN_DIR/60-kiosk-wifi.yaml"

wifi_menu() {
    local rc=0
    wifi_configure || rc=$?
    echo
    pause
    return "$rc"
}

# The first wireless interface, by what it is (it has a wireless/ or
# phy80211 entry in sysfs) rather than by name - adapters aren't always
# named wl*. Falls back to the wl* naming convention.
wifi_detect_iface() {
    local d
    for d in /sys/class/net/*; do
        if [[ -d "$d/wireless" || -e "$d/phy80211" ]]; then
            basename "$d"
            return 0
        fi
    done
    local name
    for d in /sys/class/net/wl*; do
        [[ -e "$d" ]] || continue
        name=$(basename "$d")
        echo "$name"
        return 0
    done
    return 1
}

# Clear a software WiFi block (the rfkill "soft" switch) - with it set,
# `ip link set up` fails with "RF-kill". The rfkill tool isn't installed
# on a server, so via sysfs. A hard block (physical switch / BIOS) can't
# be cleared from here and is reported instead.
wifi_unblock() {
    local r type
    for r in /sys/class/rfkill/rfkill*; do
        [[ -e "$r/type" ]] || continue
        type=$(cat "$r/type" 2>/dev/null)
        [[ "$type" == "wlan" ]] || continue
        if [[ "$(cat "$r/soft" 2>/dev/null)" == "1" ]]; then
            echo "WiFi is switched off in software (rfkill) - switching it on..."
            echo 0 | sudo tee "$r/soft" >/dev/null || true
        fi
        if [[ "$(cat "$r/hard" 2>/dev/null)" == "1" ]]; then
            log_warning "WiFi is switched off by a hardware switch or the BIOS/UEFI - turn it on there"
        fi
    done
}

# YAML single-quoted scalar: the only special character inside is the
# quote itself, doubled. Safe for any SSID/password (", \, #, : ...) -
# double quotes broke on a password containing " or \.
wifi_yaml_quote() {
    local v="$1"
    printf "'%s'" "${v//\'/\'\'}"
}

# IFACE's first IPv4 address (without the /prefix), or nothing.
wifi_iface_ip() {
    ip -4 -o addr show dev "$1" 2>/dev/null \
        | awk '{for (i = 1; i < NF; i++) if ($i == "inet") { sub("/.*", "", $(i+1)); print $(i+1); exit }}'
}

# True if IFACE has an IPv4 address.
wifi_iface_has_ip() {
    ip -4 addr show dev "$1" 2>/dev/null | grep -q "inet "
}

wifi_configure() {
    echo
    echo " ═══ WIFI CONFIGURATION ═══"
    echo

    # netplan needs wpa_supplicant to join WiFi at all; iw/wpa_cli scan.
    # Missing on a server install that skipped WiFi in the installer -
    # install them here (from the offline bundle if there's no internet,
    # which is exactly the situation this menu is usually opened in).
    if ! command -v wpa_supplicant &>/dev/null || ! command -v iw &>/dev/null; then
        echo "WiFi support (wpasupplicant, iw) isn't installed yet - installing..."
        if ! run_with_offline_fallback sudo apt install -y wpasupplicant iw; then
            log_error "Couldn't install WiFi support (needs internet, wired, or an --offline install ISO)"
            return 1
        fi
    fi

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
    if ! wifi_iface=$(wifi_detect_iface); then
        log_warning "No WiFi hardware detected"
        echo "Network interfaces found: $(ls /sys/class/net 2>/dev/null | tr '\n' ' ')"
        echo "If you have a USB WiFi adapter, make sure it's plugged in. A built-in"
        echo "adapter with no driver shows up in 'lspci -k' / 'lsusb' but not above."
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

    wifi_unblock
    echo "Bringing up interface..."
    local link_err
    if ! link_err=$(sudo ip link set "$wifi_iface" up 2>&1); then
        log_error "Failed to bring up $wifi_iface: ${link_err:-unknown error}"
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

    # Our own file, merged by netplan with the others (wired config etc).
    local netplan_file="$WIFI_NETPLAN_FILE"
    sudo mkdir -p "$NETPLAN_DIR"

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
        $(wifi_yaml_quote "$ssid"):
          password: $(wifi_yaml_quote "$password")
EOF

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        # Reverts if the WiFi interface still has no address after 60s -
        # not "can't ping 8.8.8.8", which on a network without internet
        # would undo a perfectly good connection every time. No backup
        # means there was no WiFi file before: revert = remove ours.
        local watchdog
        watchdog=$(mktemp --suffix=.sh)
        cat > "$watchdog" <<'WATCHEOF'
#!/bin/bash
# $1 = backup ("" if none), $2 = netplan file, $3 = WiFi interface
sleep 60
if ! ip -4 addr show dev "$3" 2>/dev/null | grep -q "inet "; then
    if [[ -n "$1" && -f "$1" ]]; then cp "$1" "$2"; else rm -f "$2"; fi
    netplan apply 2>/dev/null
    echo "WiFi config reverted - $3 got no address" | wall
fi
rm -f "$0"
WATCHEOF
        chmod +x "$watchdog"
        nohup sudo bash "$watchdog" "$backup" "$netplan_file" "$wifi_iface" >/dev/null 2>&1 &
        echo "Watchdog started - will revert in 60s if $wifi_iface gets no address"
    fi

    sudo cp "$temp_plan" "$netplan_file"
    sudo chmod 0600 "$netplan_file"
    rm -f "$temp_plan"

    echo "Applying configuration..."
    local netplan_log
    netplan_log=$(mktemp)
    if sudo netplan apply > "$netplan_log" 2>&1; then
        cat "$netplan_log"
        echo "Waiting for $wifi_iface to connect (up to 30 seconds)..."
        local _
        for _ in {1..30}; do
            wifi_iface_has_ip "$wifi_iface" && break
            sleep 1
        done
        if wifi_iface_has_ip "$wifi_iface"; then
            log_success "Connected to $ssid: $(wifi_iface_ip "$wifi_iface")"
            [[ -n "${SSH_CONNECTION:-}" ]] && echo "Connection successful - watchdog will not revert"
        else
            log_warning "Config applied but $wifi_iface has no address yet"
            echo "Wrong password or network name is the usual cause. Details:"
            echo "  sudo journalctl -b -u 'netplan-wpa-*' -u systemd-networkd -n 30 --no-pager"
        fi
    else
        log_error "netplan apply failed"
        echo "Error log:"
        cat "$netplan_log"
        if ask_yes_no "Undo this WiFi change?" "y"; then
            if [[ -n "$backup" ]]; then
                sudo cp "$backup" "$netplan_file"
            else
                sudo rm -f "$netplan_file"
            fi
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
