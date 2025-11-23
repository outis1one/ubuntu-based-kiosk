#!/bin/bash
################################################################################
# Check if talkkonnect terminal fix is applied
################################################################################

echo "================================"
echo "  Talkkonnect Fix Status Check"
echo "================================"
echo

# Check if service file exists
if [ ! -f /etc/systemd/system/talkkonnect.service ]; then
    echo "❌ Service file not found: /etc/systemd/system/talkkonnect.service"
    exit 1
fi

echo "Service file found. Checking configuration..."
echo

# Check for TERM=dumb
if grep -q 'Environment="TERM=dumb"' /etc/systemd/system/talkkonnect.service; then
    echo "✓ TERM=dumb is configured"
    TERM_OK=1
else
    echo "✗ TERM=dumb is MISSING"
    TERM_OK=0
fi

# Check for StandardInput=null
if grep -q 'StandardInput=null' /etc/systemd/system/talkkonnect.service; then
    echo "✓ StandardInput=null is configured"
    STDIN_OK=1
else
    echo "✗ StandardInput=null is MISSING"
    STDIN_OK=0
fi

echo
echo "Current service file:"
echo "-------------------"
cat /etc/systemd/system/talkkonnect.service
echo "-------------------"
echo

if [ $TERM_OK -eq 1 ] && [ $STDIN_OK -eq 1 ]; then
    echo "✓ Fix is properly applied!"
    echo
    echo "If you're still seeing errors, check:"
    echo "  sudo journalctl -u talkkonnect -n 100"
else
    echo "❌ Fix is NOT applied. Run the fix script:"
    echo "  cd /home/user/ubk"
    echo "  sudo bash fix_talkkonnect_terminal.sh"
fi

echo
