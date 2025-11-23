#!/usr/bin/env bash
# ======================================================================
# File: fix_talkkonnect_audio.sh
# Purpose: Fix talkkonnect audio configuration
# ======================================================================

echo "======================================================================="
echo "TalkKonnect Audio Configuration Fix"
echo "======================================================================="
echo ""

# Prompt for target user
read -p "Which user is talkkonnect running as? [kiosk]: " TARGET_USER
TARGET_USER=${TARGET_USER:-kiosk}

# Verify the target user exists
if ! id "$TARGET_USER" &>/dev/null; then
    echo "[!] Error: User '$TARGET_USER' does not exist"
    exit 1
fi

TARGET_UID=$(id -u "$TARGET_USER")
TARGET_HOME=$(eval echo ~"$TARGET_USER")
CONFIG_FILE="$TARGET_HOME/.config/talkkonnect/talkkonnect.xml"

echo "[+] Target user: $TARGET_USER (UID: $TARGET_UID)"
echo "[+] Config file: $CONFIG_FILE"
echo ""

# Check PipeWire session
echo "[1] Checking PipeWire/PulseAudio session..."
if [ -S "/run/user/$TARGET_UID/pipewire-0" ]; then
    echo "    ✓ PipeWire socket found: /run/user/$TARGET_UID/pipewire-0"
    HAS_PIPEWIRE=true
else
    echo "    ✗ No PipeWire socket found at /run/user/$TARGET_UID/pipewire-0"
    HAS_PIPEWIRE=false
fi

if [ -S "/run/user/$TARGET_UID/pulse/native" ]; then
    echo "    ✓ PulseAudio socket found: /run/user/$TARGET_UID/pulse/native"
    HAS_PULSE=true
else
    echo "    ✗ No PulseAudio socket found"
    HAS_PULSE=false
fi
echo ""

# Check audio devices as target user
echo "[2] Checking audio devices for user $TARGET_USER..."
echo ""
echo "Available ALSA output devices:"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR=/run/user/$TARGET_UID aplay -L 2>/dev/null | grep -E "^(default|hw:|pulse)" | head -10
echo ""

echo "Available ALSA input devices:"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR=/run/user/$TARGET_UID arecord -L 2>/dev/null | grep -E "^(default|hw:|pulse)" | head -10
echo ""

# If PipeWire/Pulse is available, check sinks
if [ "$HAS_PIPEWIRE" = true ] || [ "$HAS_PULSE" = true ]; then
    echo "PipeWire/PulseAudio sinks:"
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR=/run/user/$TARGET_UID pactl list sinks short 2>/dev/null || echo "(pactl not available)"
    echo ""

    echo "PipeWire/PulseAudio sources:"
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR=/run/user/$TARGET_UID pactl list sources short 2>/dev/null || echo "(pactl not available)"
    echo ""
fi

# Check current config
echo "[3] Current talkkonnect audio configuration:"
if [ -f "$CONFIG_FILE" ]; then
    echo ""
    echo "Input device:"
    grep -A1 '<input>' "$CONFIG_FILE" | grep 'device=' | sed 's/.*device="\([^"]*\)".*/    \1/'

    echo ""
    echo "Output device:"
    grep -A1 '<output>' "$CONFIG_FILE" | grep 'device=' | sed 's/.*device="\([^"]*\)".*/    \1/'
    echo ""
else
    echo "    Config file not found!"
    exit 1
fi

# Recommendations
echo "======================================================================="
echo "Recommendations"
echo "======================================================================="
echo ""

if [ "$HAS_PIPEWIRE" = false ] && [ "$HAS_PULSE" = false ]; then
    echo "⚠️  No PipeWire or PulseAudio session found"
    echo ""
    echo "Option 1: Use direct ALSA (best for dedicated audio hardware)"
    echo "   Edit $CONFIG_FILE"
    echo "   Change both input and output device to: hw:0,0"
    echo ""
    echo "Option 2: Start PipeWire for the $TARGET_USER user"
    echo "   Ensure $TARGET_USER has an active graphical session"
    echo ""
else
    echo "✓ Audio system detected (PipeWire/PulseAudio)"
    echo ""
    echo "The 'Unable to Unmute' error is usually non-fatal."
    echo "If audio is working, you can ignore it."
    echo ""
    echo "To fix the unmute error, you can:"
    echo "  1. Keep device as 'default' (usually works)"
    echo "  2. OR use specific device like 'pulse' or 'hw:0,0'"
    echo ""
fi

echo "Testing audio output as $TARGET_USER:"
echo "  sudo -u $TARGET_USER XDG_RUNTIME_DIR=/run/user/$TARGET_UID speaker-test -t wav -c 2 -l 1"
echo ""

echo "Testing audio input as $TARGET_USER:"
echo "  sudo -u $TARGET_USER XDG_RUNTIME_DIR=/run/user/$TARGET_UID arecord -d 3 -f cd test.wav && aplay test.wav"
echo ""

echo "To edit config:"
echo "  sudo nano $CONFIG_FILE"
echo ""

echo "After making changes, restart talkkonnect:"
echo "  sudo systemctl restart talkkonnect"
echo ""
