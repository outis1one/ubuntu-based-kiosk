#!/bin/bash
################################################################################
### Integration Helper for Intercom Setup
################################################################################
#
# This script shows how to integrate the standalone intercom setup
# into the main UBK install script.
#
# Usage:
#   1. Copy this code block into your main install script
#   2. Add a menu option to call launch_intercom_setup()
#   3. The intercom setup will run as a subshell and return control
#
################################################################################

# Get the directory where scripts are located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

launch_intercom_setup() {
    local intercom_script="$SCRIPT_DIR/setup_intercom.sh"

    if [[ ! -f "$intercom_script" ]]; then
        echo "[ERROR] Intercom setup script not found at: $intercom_script"
        echo "Please ensure setup_intercom.sh is in the same directory as this script"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    # Make sure it's executable
    chmod +x "$intercom_script"

    # Launch the intercom setup
    bash "$intercom_script"

    # Return code will be passed through
    return $?
}

################################################################################
### Example Integration into Main Install Script
################################################################################

# Add this to your addon menu section:
#
# addon_menu() {
#     while true; do
#         clear
#         echo "════════════════════════════════════════════════════════════"
#         echo "   ADDONS MENU"
#         echo "════════════════════════════════════════════════════════════"
#         echo
#         echo "  1. VNC Remote Desktop"
#         echo "  2. WireGuard VPN"
#         echo "  3. Tailscale"
#         echo "  4. Netbird"
#         echo "  5. Jitsi Intercom"
#         echo "  6. Mumble/Talkkonnect Intercom"  # <-- Add this line
#         echo "  0. Return to main menu"
#         echo
#         read -r -p "Choose: " addon_choice
#
#         case "$addon_choice" in
#             1) addon_vnc ;;
#             2) addon_wireguard ;;
#             3) addon_tailscale ;;
#             4) addon_netbird ;;
#             5) addon_jitsi_intercom ;;
#             6) launch_intercom_setup ;;  # <-- Add this line
#             0) return ;;
#         esac
#     done
# }

################################################################################
### Alternative: Direct Function Call
################################################################################

# If you want even tighter integration, you can source the intercom script
# and call its functions directly. This requires modifying setup_intercom.sh
# to check if it's being sourced or run directly:
#
# In setup_intercom.sh, replace the main entry point section with:
#
# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#     # Script is being run directly
#     main_menu
# fi
#
# Then you can source it:
#
# source "$SCRIPT_DIR/setup_intercom.sh"
# install_murmur_and_talkkonnect  # Call functions directly

################################################################################
### Quick Test
################################################################################

# Uncomment to test this integration helper:
# launch_intercom_setup
