#!/usr/bin/env bash
# ======================================================================
# File: update_setup_intercom.sh
# Purpose: Replace talkkonnect installation function with proven method
# ======================================================================

echo "Updating setup_intercom.sh with proven talkkonnect installation method..."
echo ""

# Backup original
cp setup_intercom.sh setup_intercom.sh.backup
echo "[+] Created backup: setup_intercom.sh.backup"

# The function starts at line 197 and ends at line 732 (before install_talkkonnect_only)
# We'll extract the header, insert the new function, then append the rest

# Get everything before the function (lines 1-196)
head -n 196 setup_intercom.sh > setup_intercom.sh.new

# Add the new function
cat setup_intercom_talkkonnect_function.txt >> setup_intercom.sh.new

# Add everything after line 732 (from install_talkkonnect_only onwards)
tail -n +733 setup_intercom.sh >> setup_intercom.sh.new

# Replace the original
mv setup_intercom.sh.new setup_intercom.sh
chmod +x setup_intercom.sh

echo "[+] Updated setup_intercom.sh with proven installation method"
echo ""
echo "Changes made:"
echo "  ✓ Uses working Opus patch from talkkonnect_complete_install.sh"
echo "  ✓ Installs to /usr/local/bin/talkkonnect"
echo "  ✓ Config in ~/.config/talkkonnect/"
echo "  ✓ Sets <insecure>true</insecure> by default (for self-signed certs)"
echo "  ✓ Proper XDG_RUNTIME_DIR in systemd service"
echo "  ✓ Enables service automatically"
echo "  ✓ Better error handling and user feedback"
echo ""
echo "The old version is saved as: setup_intercom.sh.backup"
echo ""
