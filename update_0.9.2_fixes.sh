#!/bin/bash
################################################################################
# Kiosk 0.9.2 Critical Fixes Update Script
# Applies fixes for:
# - Return-to-home logic (manual sites only)
# - Pause button auto-hide (5 second timeout)
# - Display schedule overnight/same-day logic
################################################################################

set -e

KIOSK_USER="${KIOSK_USER:-kiosk}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  Kiosk 0.9.2 Critical Fixes Updater"
echo "========================================"
echo ""

# Find kiosk installation
find_kiosk_dir() {
    local DETECTED_DIR=""

    # Method 1: Check default kiosk user
    if id "$KIOSK_USER" &>/dev/null; then
        local kiosk_home=$(eval echo ~$KIOSK_USER)
        if [ -f "$kiosk_home/kiosk-app/main.js" ]; then
            DETECTED_DIR="$kiosk_home/kiosk-app"
        fi
    fi

    # Method 2: Search all /home directories
    if [ -z "$DETECTED_DIR" ]; then
        for user_home in /home/*; do
            if [ -f "$user_home/kiosk-app/main.js" ]; then
                DETECTED_DIR="$user_home/kiosk-app"
                break
            fi
        done
    fi

    # Method 3: Check systemd service
    if [ -z "$DETECTED_DIR" ]; then
        if systemctl list-units --all kiosk.service | grep -q kiosk.service; then
            local service_dir=$(systemctl show -p WorkingDirectory kiosk.service 2>/dev/null | cut -d= -f2)
            if [ -n "$service_dir" ] && [ -f "$service_dir/main.js" ]; then
                DETECTED_DIR="$service_dir"
            fi
        fi
    fi

    echo "$DETECTED_DIR"
}

KIOSK_DIR=$(find_kiosk_dir)

if [ -z "$KIOSK_DIR" ] || [ ! -d "$KIOSK_DIR" ]; then
    echo "✗ Kiosk installation not found!"
    echo ""
    echo "Searched:"
    echo "  - /home/$KIOSK_USER/kiosk-app"
    echo "  - /home/*/kiosk-app"
    echo "  - systemd kiosk.service location"
    echo ""
    echo "Please ensure kiosk is installed first"
    exit 1
fi

echo "Found kiosk at: $KIOSK_DIR"
echo ""

# Detect kiosk user
KIOSK_OWNER=$(stat -c '%U' "$KIOSK_DIR")
echo "Kiosk owner: $KIOSK_OWNER"
echo ""

# Backup existing files
echo "Creating backups..."
sudo -u "$KIOSK_OWNER" cp "$KIOSK_DIR/main.js" "$KIOSK_DIR/main.js.backup.$(date +%Y%m%d_%H%M%S)"
sudo -u "$KIOSK_OWNER" cp "$KIOSK_DIR/preload.js" "$KIOSK_DIR/preload.js.backup.$(date +%Y%m%d_%H%M%S)"
sudo -u "$KIOSK_OWNER" cp "$KIOSK_DIR/autostart.sh" "$KIOSK_DIR/autostart.sh.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
echo "✓ Backups created"
echo ""

################################################################################
# Fix 1: Return-to-home logic in main.js
################################################################################
echo "Applying Fix 1: Return-to-home logic (manual sites only)..."

sudo -u "$KIOSK_OWNER" sed -i '/\/\/ 7\. HOME RETURN CHECK/,/if(homeViewIdx>=0&&currentIndex!==homeViewIdx){/ {
    /\/\/ Don'"'"'t show inactivity prompt on manual sites (duration=0)/ {
        s/.*/      \/\/ ONLY show inactivity prompt on manual sites (duration=0)/
        a\      \/\/ Rotation sites handle their own timing and should NOT show inactivity prompt
    }
    /if(currentSiteDuration===0){/ s/===0/>0/
    /\/\/ Manual site - skip return-to-home logic/ s/Manual site/Rotation site/
    /\/\/ Manual site - skip return-to-home logic/ s/return-to-home logic/return-to-home logic (uses auto-rotation instead)/
}' "$KIOSK_DIR/main.js"

echo "✓ Fix 1 applied"

################################################################################
# Fix 2: Pause button auto-hide in preload.js
################################################################################
echo "Applying Fix 2: Pause button auto-hide..."

# Add pause button hide timer variables
sudo -u "$KIOSK_OWNER" sed -i '/let pauseButtonShown=false;/a\  let pauseButtonHideTimer=null;\n  const PAUSE_BUTTON_HIDE_DELAY=5000; \/\/ Hide after 5 seconds of inactivity' "$KIOSK_DIR/preload.js"

# Update showPauseButton function
sudo -u "$KIOSK_OWNER" sed -i '/function showPauseButton(){/,/^  }$/ {
    /pauseButtonShown=true;/a\
\n    \/\/ Clear existing hide timer\
    if(pauseButtonHideTimer){\
      clearTimeout(pauseButtonHideTimer);\
      pauseButtonHideTimer=null;\
    }\
\n    \/\/ Set new hide timer - button will auto-hide after inactivity\
    pauseButtonHideTimer=setTimeout(()=>{\
      console.log('"'"'[PAUSE-BTN] Auto-hiding after '"'"'\''+PAUSE_BUTTON_HIDE_DELAY+'\''ms inactivity'"'"');\
      hidePauseButton();\
    },PAUSE_BUTTON_HIDE_DELAY);
}' "$KIOSK_DIR/preload.js"

# Update hidePauseButton function
sudo -u "$KIOSK_OWNER" sed -i '/function hidePauseButton(){/a\    if(pauseButtonHideTimer){\n      clearTimeout(pauseButtonHideTimer);\n      pauseButtonHideTimer=null;\n    }' "$KIOSK_DIR/preload.js"

# Update handleUserInteraction to reset timer on each interaction
sudo -u "$KIOSK_OWNER" sed -i '/function handleUserInteraction(eventType){/,/^  }$/ {
    /if(pauseButtonShouldShow&&!pauseButtonShown){/ {
        s/.*/    \/\/ Show\/refresh pause button if allowed on this site\
    if(pauseButtonShouldShow){\
      if(!pauseButtonShown){\
        console.log('"'"'[PAUSE-BTN] Showing pause button now'"'"');\
      }else{\
        console.log('"'"'[PAUSE-BTN] Resetting auto-hide timer'"'"');\
      }\
      showPauseButton(); \/\/ This will reset the hide timer/
        N
        N
        d
    }
}' "$KIOSK_DIR/preload.js"

echo "✓ Fix 2 applied"

################################################################################
# Fix 3: Display schedule logic in autostart.sh
################################################################################
if [ -f "$KIOSK_DIR/autostart.sh" ]; then
    echo "Applying Fix 3: Display schedule overnight/same-day logic..."

    sudo -u "$KIOSK_OWNER" sed -i '/# Check if we'"'"'re in the "display off" window/,/fi$/  {
        /if \[\[ \$off_mins -lt \$on_mins \]\]; then/ s/-lt/-gt/
        /# Normal case:.*22:00 to 06:00/ {
            s/Normal case/Overnight case/
            s/off time is before on time/off time is after on time/
            s/turn off at 22:00, on at 06:00)/
            s/# Display is OFF from off_mins to midnight AND from midnight to on_mins/
        }
        /# Overnight case:.*06:00 to 22:00/ {
            s/Overnight case/Same-day case/
            s/off time is after on time/off time is before on time/
            s/turn off at 06:00, on at 22:00)/turn off at 08:00, on at 17:00)/
            s/# Display is OFF from off_mins to on_mins/
        }
    }' "$KIOSK_DIR/autostart.sh"

    echo "✓ Fix 3 applied"
else
    echo "⚠ autostart.sh not found, skipping Fix 3"
fi

################################################################################
# Summary and Restart
################################################################################
echo ""
echo "========================================"
echo "  ✓ All fixes applied successfully!"
echo "========================================"
echo ""
echo "Applied fixes:"
echo "  1. Return-to-home popup now appears ONLY on manual sites"
echo "  2. Pause button auto-hides after 5 seconds of inactivity"
echo "  3. Display schedule overnight/same-day logic corrected"
echo ""
echo "Backups saved in: $KIOSK_DIR/*.backup.*"
echo ""

read -p "Restart kiosk service now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Restarting kiosk service..."
    sudo systemctl restart kiosk
    echo "✓ Kiosk restarted"
else
    echo "Please restart kiosk manually: sudo systemctl restart kiosk"
fi

echo ""
echo "Done!"
