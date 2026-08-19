#!/bin/bash
# Give X a moment to finish enumerating the output after the hotplug event
sleep 2
sudo -u kiosk DISPLAY=:0 XAUTHORITY=/home/kiosk/.Xauthority /usr/local/bin/kiosk-mirror-display.sh

kiosk_uid=$(id -u kiosk)
sudo -u kiosk DISPLAY=:0 XAUTHORITY=/home/kiosk/.Xauthority XDG_RUNTIME_DIR="/run/user/${kiosk_uid}" /usr/local/bin/kiosk-audio-route.sh
