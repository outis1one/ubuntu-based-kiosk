#!/bin/bash
# Power button handler - sends SIGUSR1 to Electron to show power menu
# This runs as ROOT from acpid, so it can signal any process

logger "KIOSK POWER: Button pressed"

# Find the Electron main process (runs as kiosk user)
PIDS=$(pgrep -u kiosk -f "electron" 2>/dev/null)

if [ -z "$PIDS" ]; then
    logger "KIOSK POWER: No Electron process found"
    exit 1
fi

# Send SIGUSR1 to all Electron processes (the main one will handle it)
for PID in $PIDS; do
    logger "KIOSK POWER: Sending SIGUSR1 to PID $PID"
    kill -USR1 $PID 2>/dev/null
done

logger "KIOSK POWER: Signal sent"
