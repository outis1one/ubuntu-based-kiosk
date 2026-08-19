#!/bin/bash
cd /home/kiosk/kiosk-app

# Wait for network
for i in {1..30}; do
  ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && break
  sleep 2
done

export DISPLAY=:0
export XAUTHORITY=/home/kiosk/.Xauthority
export ELECTRON_ENABLE_LOGGING=1

# Ensure PipeWire is running
systemctl --user is-active --quiet pipewire || systemctl --user start pipewire
systemctl --user is-active --quiet pipewire-pulse || systemctl --user start pipewire-pulse
systemctl --user is-active --quiet wireplumber || systemctl --user start wireplumber

# Wait for PipeWire
for i in {1..10}; do
    pactl info >/dev/null 2>&1 && break
    sleep 1
done

exec node_modules/electron/dist/electron . \
  --no-sandbox --disable-gpu-sandbox --disable-dev-shm-usage \
  --enable-features=UseOzonePlatform --ozone-platform=x11 \
  --enable-audio-service-sandbox=false --autoplay-policy=no-user-gesture-required \
  --password-store=basic \
  2>&1 | tee -a /home/kiosk/electron.log
