#!/bin/bash
################################################################################
# menus/advanced_emergency_hotspot.sh - "Emergency Hotspot" (Advanced):
# auto-starts a WiFi hotspot if no internet is detected 60 seconds after
# boot, so the kiosk can be reached and reconfigured remotely.
#
# Writes a standalone runtime script ($BIN_DIR/kiosk-emergency-hotspot)
# plus a oneshot systemd unit ($SYSTEMD_DIR) that runs it at boot - both
# of those paths are ours to place, so (like power_schedule and every
# other addon) they're parameterized instead of hardcoded. hostapd/
# dnsmasq/iptables themselves are real apt packages with their own fixed
# config locations, stubbed at the command level in tests like CUPS.
#
# The runtime script itself is a template: everything written with `\$`
# below stays literal and only resolves when the script actually runs at
# boot (on the real machine, not in this tool); only the un-escaped
# $wifi_iface/$hotspot_ssid/$hotspot_pass/$hotspot_ip/$KIOSK_USER/
# $KIOSK_DIR are substituted once, at configuration time.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

EMERGENCY_HOTSPOT_SCRIPT="$BIN_DIR/kiosk-emergency-hotspot"

emergency_hotspot_is_configured() {
    [[ -f "$EMERGENCY_HOTSPOT_SCRIPT" ]]
}

emergency_hotspot_ssid() {
    grep '^HOTSPOT_SSID=' "$EMERGENCY_HOTSPOT_SCRIPT" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true
}

advanced_emergency_hotspot_status() {
    if emergency_hotspot_is_configured; then
        local ssid
        ssid=$(emergency_hotspot_ssid)
        echo "Emergency Hotspot: Configured (SSID: ${ssid:-unknown})"
    else
        echo "Emergency Hotspot: Not configured"
    fi
    echo "ℹ Auto-starts a WiFi hotspot if no internet is detected 60"
    echo "  seconds after boot, so you can connect and reconfigure remotely."
}

advanced_emergency_hotspot_menu_builder() {
    if emergency_hotspot_is_configured; then
        MENU_LABELS=("Reconfigure" "Disable")
        MENU_HANDLERS=(action_configure_emergency_hotspot action_disable_emergency_hotspot)
    else
        MENU_LABELS=("Enable emergency hotspot")
        MENU_HANDLERS=(action_configure_emergency_hotspot)
    fi
}

advanced_emergency_hotspot_menu() {
    run_menu "EMERGENCY HOTSPOT" advanced_emergency_hotspot_menu_builder advanced_emergency_hotspot_status
}

################################################################################
# Actions
################################################################################

action_configure_emergency_hotspot() {
    echo
    if ! sudo apt install -y hostapd dnsmasq iptables; then
        log_error "Failed to install hostapd/dnsmasq/iptables"
        pause
        return 1
    fi

    sudo systemctl stop hostapd dnsmasq 2>/dev/null || true
    sudo systemctl disable hostapd dnsmasq 2>/dev/null || true

    local wifi_iface
    wifi_iface=$(ls /sys/class/net 2>/dev/null | grep -E "^wl" | head -1 || true)
    if [[ -z "$wifi_iface" ]]; then
        log_error "No WiFi interface found"
        pause
        return 1
    fi
    echo "WiFi interface: $wifi_iface"
    echo

    local hotspot_ssid
    hotspot_ssid=$(ask_text "Hotspot SSID" "Kiosk-Emergency")

    local hotspot_pass=""
    while [[ ${#hotspot_pass} -lt 8 ]]; do
        read -r -s -p "Hotspot password (8+ chars): " hotspot_pass
        echo
        [[ ${#hotspot_pass} -lt 8 ]] && log_error "Password must be at least 8 characters"
    done

    local hotspot_ip="192.168.50.1"

    sudo mkdir -p "$BIN_DIR"
    sudo tee "$EMERGENCY_HOTSPOT_SCRIPT" > /dev/null <<EOF
#!/bin/bash
################################################################################
### KIOSK EMERGENCY HOTSPOT
### Auto-starts if no internet connection 60 seconds after boot
################################################################################

WIFI_IFACE="$wifi_iface"
HOTSPOT_SSID="$hotspot_ssid"
HOTSPOT_PASS="$hotspot_pass"
HOTSPOT_IP="$hotspot_ip"
KIOSK_USER="$KIOSK_USER"

# Wait 60 seconds after boot
sleep 60

# Check for internet connectivity
if ping -c 3 -W 5 8.8.8.8 >/dev/null 2>&1; then
    logger "KIOSK: Internet connected - emergency hotspot not needed"
    exit 0
fi

logger "KIOSK: No internet detected - starting emergency hotspot"

# Stop any conflicting services
systemctl stop wpa_supplicant 2>/dev/null || true
ip link set \$WIFI_IFACE down 2>/dev/null || true
sleep 2

# Configure static IP for hotspot
ip addr flush dev \$WIFI_IFACE
ip addr add \${HOTSPOT_IP}/24 dev \$WIFI_IFACE
ip link set \$WIFI_IFACE up

# Configure dnsmasq
cat > /tmp/dnsmasq-hotspot.conf <<DNSMASQ
interface=\$WIFI_IFACE
dhcp-range=192.168.50.10,192.168.50.50,12h
dhcp-option=3,\$HOTSPOT_IP
dhcp-option=6,\$HOTSPOT_IP
server=8.8.8.8
log-queries
log-dhcp
DNSMASQ

# Start dnsmasq
dnsmasq -C /tmp/dnsmasq-hotspot.conf

# Configure hostapd
cat > /tmp/hostapd-hotspot.conf <<HOSTAPD
interface=\$WIFI_IFACE
driver=nl80211
ssid=\$HOTSPOT_SSID
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=\$HOTSPOT_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
HOSTAPD

# Start hostapd
hostapd -B /tmp/hostapd-hotspot.conf

# Enable IP forwarding (optional - for internet sharing if wired connection exists)
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# Show notification on kiosk display
sudo -u \$KIOSK_USER DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u \$KIOSK_USER)/bus \\
    notify-send -u critical -t 0 "Emergency Hotspot Active" \\
    "SSID: \$HOTSPOT_SSID\\nPassword: \$HOTSPOT_PASS\\nConnect to: http://\$HOTSPOT_IP" 2>/dev/null || true

logger "KIOSK: Emergency hotspot started - SSID: \$HOTSPOT_SSID, IP: \$HOTSPOT_IP"

# Create on-screen notification HTML
sudo -u \$KIOSK_USER tee /tmp/hotspot-notification.html > /dev/null <<'NOTIFY'
<!DOCTYPE html>
<html>
<head>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: rgba(0,0,0,0.95);
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
}
.container {
  text-align: center;
  padding: 40px;
  background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
  border-radius: 20px;
  box-shadow: 0 10px 40px rgba(0,0,0,0.5);
  max-width: 600px;
}
h1 { font-size: 48px; margin-bottom: 20px; }
.icon { font-size: 72px; margin-bottom: 20px; }
.info { font-size: 24px; margin: 20px 0; line-height: 1.6; }
.credential {
  background: rgba(0,0,0,0.3);
  padding: 15px;
  border-radius: 10px;
  margin: 10px 0;
  font-family: monospace;
  font-size: 20px;
}
.dismiss {
  margin-top: 30px;
  padding: 15px 40px;
  font-size: 18px;
  background: white;
  color: #e74c3c;
  border: none;
  border-radius: 10px;
  cursor: pointer;
  font-weight: bold;
}
.dismiss:hover { background: #ecf0f1; }
</style>
</head>
<body>
<div class="container">
  <div class="icon">📡</div>
  <h1>Emergency Hotspot Active</h1>
  <div class="info">No internet connection detected<br>Hotspot created for remote access</div>
  <div class="credential">SSID: <strong>\$HOTSPOT_SSID</strong></div>
  <div class="credential">Password: <strong>\$HOTSPOT_PASS</strong></div>
  <div class="credential">Connect to: <strong>http://\$HOTSPOT_IP</strong></div>
  <button class="dismiss" onclick="window.close()">Dismiss</button>
</div>
<script>
// Auto-dismiss after 5 minutes
setTimeout(() => window.close(), 300000);
</script>
</body>
</html>
NOTIFY

# Show notification window if Electron is running
if pgrep -f "electron.*main.js" >/dev/null 2>&1; then
    sudo -u \$KIOSK_USER DISPLAY=:0 \\
        "$KIOSK_DIR/node_modules/electron/dist/electron" \\
        /tmp/hotspot-notification.html &
fi

exit 0
EOF

    sudo chmod +x "$EMERGENCY_HOTSPOT_SCRIPT"

    sudo mkdir -p "$SYSTEMD_DIR"
    sudo tee "$SYSTEMD_DIR/kiosk-emergency-hotspot.service" > /dev/null <<UNITEOF
[Unit]
Description=Kiosk Emergency Hotspot
After=network.target lightdm.service
Wants=network.target

[Service]
Type=oneshot
ExecStart=${EMERGENCY_HOTSPOT_SCRIPT}
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEOF

    sudo systemctl daemon-reload 2>/dev/null || true
    # Enable only, not start: this is a boot-time oneshot that waits 60s
    # and checks connectivity - starting it right now would just run that
    # wait/check immediately, which isn't what "configure" means here.
    if ! sudo systemctl enable kiosk-emergency-hotspot.service 2>/dev/null; then
        log_warning "Hotspot files written, but 'systemctl enable' failed - check 'systemctl status kiosk-emergency-hotspot.service'"
    fi

    echo
    log_success "Emergency hotspot configured"
    echo "  SSID:     $hotspot_ssid"
    echo "  Password: $hotspot_pass"
    echo "  IP:       $hotspot_ip"
    echo
    echo "Hotspot auto-starts if no internet is detected 60 seconds after boot."

    pause
}

action_disable_emergency_hotspot() {
    echo
    ask_yes_no "Disable emergency hotspot?" "n" || { echo "Cancelled"; pause; return; }

    sudo systemctl stop kiosk-emergency-hotspot.service 2>/dev/null || true
    sudo systemctl disable kiosk-emergency-hotspot.service 2>/dev/null || true
    sudo rm -f "$SYSTEMD_DIR/kiosk-emergency-hotspot.service"
    sudo rm -f "$EMERGENCY_HOTSPOT_SCRIPT"
    sudo systemctl daemon-reload 2>/dev/null || true
    log_success "Emergency hotspot disabled"

    pause
}
