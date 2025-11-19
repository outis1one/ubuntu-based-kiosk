#!/bin/bash
echo "=== Checking Pause Button Deployment ==="
echo
echo "1. Checking if pause-dialog.html exists:"
ls -lh /home/kiosk/kiosk-app/pause-dialog.html 2>&1
echo
echo "2. Checking if preload.js has pause button code:"
grep -c "pauseButton" /home/kiosk/kiosk-app/preload.js
echo
echo "3. Checking if main.js has showPauseDialog:"
grep -c "showPauseDialog" /home/kiosk/kiosk-app/main.js
echo
echo "4. Checking recent electron logs for PAUSE-BTN messages:"
tail -100 /home/kiosk/electron.log | grep "PAUSE-BTN" | tail -20
echo
echo "5. Checking recent electron logs for pause-button-visibility:"
tail -100 /home/kiosk/electron.log | grep "pause-button-visibility" | tail -20
echo
echo "6. Checking what sites are configured:"
cat /home/kiosk/kiosk-app/config.json | jq '.tabs[] | {url: .url, duration: .duration}' 2>/dev/null || echo "Config check failed"
echo
echo "=== Instructions ==="
echo "If pause-dialog.html is missing, the installer didn't run properly"
echo "If grep counts are 0, the files weren't updated"
echo "If no PAUSE-BTN logs appear, the button logic isn't running"
echo "Check that at least one site has duration > 0"
