#!/bin/bash
# Assumes DISPLAY/XAUTHORITY are set (for xrandr) and pactl already has a
# working PipeWire/pulse socket for the invoking context.

QUERY=$(xrandr --query 2>/dev/null)
[ -z "$QUERY" ] && exit 0

PRIMARY_OUTPUT=$(echo "$QUERY" | awk '/ primary/{print $1; exit}')
[ -z "$PRIMARY_OUTPUT" ] && exit 0

EXTERNAL_CONNECTED=$(echo "$QUERY" | awk -v p="$PRIMARY_OUTPUT" '/ connected/ && $1!=p{f=1} END{print (f==1)?"yes":"no"}')

HDMI_SINK=$(pactl list sinks short 2>/dev/null | awk 'tolower($2) ~ /hdmi/{print $2; exit}')
NON_HDMI_SINK=$(pactl list sinks short 2>/dev/null | awk 'tolower($2) !~ /hdmi/{print $2; exit}')

route_to() {
  local sink="$1" label="$2"
  if [ -z "$sink" ]; then
    logger "KIOSK: no $label audio sink found, leaving routing unchanged"
    return
  fi
  pactl set-default-sink "$sink" 2>/dev/null \
    && logger "KIOSK: audio routed to $label sink ($sink)" \
    || logger "KIOSK: failed to route audio to $label sink ($sink)"
  pactl list sink-inputs short 2>/dev/null | awk '{print $1}' | while read -r sid; do
    pactl move-sink-input "$sid" "$sink" 2>/dev/null
  done
  pactl set-sink-volume "$sink" 100% 2>/dev/null
  pactl set-sink-mute "$sink" 0 2>/dev/null
}

if [ "$EXTERNAL_CONNECTED" = "yes" ]; then
  route_to "$HDMI_SINK" "HDMI"
else
  route_to "$NON_HDMI_SINK" "built-in"
fi
