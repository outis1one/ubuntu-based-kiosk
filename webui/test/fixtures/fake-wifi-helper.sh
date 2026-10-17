#!/bin/bash
# Stand-in for kiosk-wifi-helper in api.test.js: echoes the action and stdin.
input=$(cat)
case "$1" in
    region-status) echo '{"ok":true,"country":"US","locale":"en_US.UTF-8","keyboard":"us","locales":["en_US.UTF-8"],"keyboards":["us"]}' ;;
    region-set)    jq -cn --arg i "$input" '{ok:true,echo:$i,restart:true}' ;;
    *)             echo '{"ok":false,"error":"unknown"}' ;;
esac
