#!/bin/bash
################################################################################
# Pause Button Diagnostic Script
# Checks the actual state of pause button code in installed kiosk
################################################################################

echo "===================================="
echo "  Pause Button Diagnostic Tool"
echo "===================================="
echo ""

# Find kiosk directory
KIOSK_DIR=""
if [ -f "/home/kiosk/kiosk-app/main.js" ]; then
    KIOSK_DIR="/home/kiosk/kiosk-app"
elif systemctl show -p WorkingDirectory kiosk.service 2>/dev/null | grep -q "/"; then
    KIOSK_DIR=$(systemctl show -p WorkingDirectory kiosk.service 2>/dev/null | cut -d= -f2)
fi

if [ -z "$KIOSK_DIR" ] || [ ! -f "$KIOSK_DIR/main.js" ]; then
    echo "✗ Cannot find kiosk installation"
    echo "  Please run this on the kiosk machine"
    exit 1
fi

echo "Found kiosk at: $KIOSK_DIR"
echo ""

echo "=== CHECK 1: Pause button visibility logic in main.js ==="
echo ""
grep -A 2 "pause-button-visibility" "$KIOSK_DIR/main.js" | head -5
echo ""

echo "=== CHECK 2: Duration check logic ==="
echo ""
grep -B 1 -A 1 "siteDuration>0\|siteDuration!==0\|siteDuration===0" "$KIOSK_DIR/main.js" | head -10
echo ""

echo "=== CHECK 3: Pause button auto-hide in preload.js ==="
echo ""
if grep -q "PAUSE_BUTTON_HIDE_DELAY" "$KIOSK_DIR/preload.js"; then
    echo "✓ Auto-hide timer found"
    grep "PAUSE_BUTTON_HIDE_DELAY" "$KIOSK_DIR/preload.js"
else
    echo "✗ Auto-hide timer NOT found"
fi
echo ""

echo "=== CHECK 4: Return-to-home logic ==="
echo ""
grep -A 3 "ONLY show inactivity prompt\|Don't show inactivity prompt" "$KIOSK_DIR/main.js" | head -8
echo ""

echo "=== CHECK 5: User interaction handler ==="
echo ""
if grep -q "function handleUserInteraction(eventType)" "$KIOSK_DIR/preload.js"; then
    echo "✓ Event type parameter found"
else
    echo "✗ Event type parameter NOT found - might be broken"
fi
echo ""

echo "===================================="
echo "RECOMMENDATIONS:"
echo "===================================="
echo ""

# Check each issue
NEEDS_FIX=0

if ! grep -q "siteDuration>0" "$KIOSK_DIR/main.js"; then
    echo "⚠ Pause button visibility logic needs update"
    echo "   Current: Should check siteDuration>0"
    NEEDS_FIX=1
fi

if ! grep -q "PAUSE_BUTTON_HIDE_DELAY" "$KIOSK_DIR/preload.js"; then
    echo "⚠ Pause button auto-hide not implemented"
    NEEDS_FIX=1
fi

if ! grep -q "Rotation site - skip return-to-home" "$KIOSK_DIR/main.js"; then
    echo "⚠ Return-to-home logic needs update"
    NEEDS_FIX=1
fi

if [ $NEEDS_FIX -eq 1 ]; then
    echo ""
    echo ">> Run a full reinstall with install_kiosk_0.9.2.sh"
    echo "   The update script may not have applied correctly"
else
    echo "✓ All fixes appear to be in place!"
    echo ""
    echo "If pause button still not showing:"
    echo "  1. Open Electron DevTools (if available)"
    echo "  2. Check console for [MAIN] and [PAUSE-BTN] messages"
    echo "  3. Verify site duration is > 0 for rotation sites"
    echo "  4. Try clicking/touching the screen on a rotation site"
fi

echo ""
