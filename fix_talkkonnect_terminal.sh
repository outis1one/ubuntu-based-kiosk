#!/bin/bash
################################################################################
# Fix talkkonnect Terminal Initialization Error
################################################################################
# This script fixes the "Cannot Initialize Terminal" error that occurs when
# talkkonnect is run as a systemd service without a TTY.
#
# The fix adds:
#   - Environment="TERM=dumb" to use minimal terminal mode
#   - StandardInput=null to prevent terminal initialization
################################################################################

set -e

echo "================================"
echo "  Talkkonnect Terminal Fix"
echo "================================"
echo

# Get kiosk user (usually 'kiosk')
KIOSK_USER=$(ls -l /home | grep '^d' | grep -v lost | head -1 | awk '{print $NF}')

if [ -z "$KIOSK_USER" ]; then
    echo "❌ Error: Could not find kiosk user"
    exit 1
fi

echo "Kiosk user: $KIOSK_USER"
echo

# Check if talkkonnect is installed
if ! systemctl list-unit-files | grep -q talkkonnect.service; then
    echo "❌ Error: talkkonnect service not found"
    echo "   Install talkkonnect first using the main install script"
    exit 1
fi

echo "[1/3] Stopping talkkonnect service..."
sudo systemctl stop talkkonnect

echo "[2/3] Updating systemd service..."
sudo tee /etc/systemd/system/talkkonnect.service > /dev/null <<EOF
[Unit]
Description=talkkonnect Mumble Client
After=network.target sound.target pipewire.service
Wants=pipewire.service

[Service]
Type=simple
User=$KIOSK_USER
Environment="PATH=/usr/local/go/bin:/usr/bin:/bin"
Environment="HOME=/home/$KIOSK_USER"
Environment="GOPATH=/home/$KIOSK_USER/go"
Environment="TERM=dumb"
WorkingDirectory=/home/$KIOSK_USER
ExecStartPre=/bin/sleep 10
ExecStart=/home/$KIOSK_USER/go/bin/talkkonnect -config /home/$KIOSK_USER/talkkonnect.xml
Restart=always
RestartSec=10
StandardInput=null
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "[3/3] Reloading and starting service..."
sudo systemctl daemon-reload
sudo systemctl start talkkonnect

echo
echo "Waiting for service to start..."
sleep 5

echo
if systemctl is-active --quiet talkkonnect; then
    echo "✓ SUCCESS: talkkonnect is now running"
    echo
    echo "Check logs with:"
    echo "  sudo journalctl -u talkkonnect -f"
else
    echo "⚠ Warning: Service may still have issues"
    echo
    echo "Check logs:"
    echo "  sudo journalctl -u talkkonnect -n 50"
fi

echo
echo "Fix applied!"
