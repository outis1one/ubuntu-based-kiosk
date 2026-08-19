#!/bin/bash
# Assumes it's run with DISPLAY/XAUTHORITY already set for the kiosk user's
# X session (either inherited, as from Openbox autostart, or exported by the
# caller). Mirrors every connected non-primary output at the primary's exact
# current resolution so kiosk content isn't cropped/letterboxed/blank on a
# TV/monitor with a different native resolution than the kiosk panel.

QUERY=$(xrandr --query 2>/dev/null)
[ -z "$QUERY" ] && exit 0

PRIMARY_OUTPUT=$(echo "$QUERY" | awk '/ primary/{print $1; exit}')
[ -z "$PRIMARY_OUTPUT" ] && exit 0

PRIMARY_RES=$(echo "$QUERY" | awk -v p="$PRIMARY_OUTPUT" '$1==p{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+/){split($i,a,"+"); print a[1]; exit}}')
[ -z "$PRIMARY_RES" ] && exit 0

for OUT in $(echo "$QUERY" | awk '/ connected/{print $1}'); do
  [ "$OUT" = "$PRIMARY_OUTPUT" ] && continue

  HAS_NATIVE=$(echo "$QUERY" | awk -v out="$OUT" -v res="$PRIMARY_RES" '
    $0 ~ "^"out" " {infound=1; next}
    /^[^ \t]/ {infound=0}
    infound && $1==res {print "yes"; exit}
  ')

  if [ "$HAS_NATIVE" = "yes" ]; then
    xrandr --output "$OUT" --mode "$PRIMARY_RES" --same-as "$PRIMARY_OUTPUT" 2>/dev/null \
      && logger "KIOSK: mirrored $OUT at native $PRIMARY_RES" \
      || logger "KIOSK: mirror of $OUT at $PRIMARY_RES failed"
    continue
  fi

  # $OUT doesn't natively list the primary's resolution - force a matching mode
  CVT_LINE=$(cvt "${PRIMARY_RES%x*}" "${PRIMARY_RES#*x}" 2>/dev/null | grep Modeline)
  MODENAME=$(echo "$CVT_LINE" | sed -n 's/^Modeline "\([^"]*\)".*/\1/p')
  TIMINGS=$(echo "$CVT_LINE" | sed -n 's/^Modeline "[^"]*" *//p')

  if [ -z "$MODENAME" ] || [ -z "$TIMINGS" ]; then
    logger "KIOSK: could not generate a $PRIMARY_RES mode for $OUT (cvt failed or missing)"
    continue
  fi

  xrandr --newmode "$MODENAME" $TIMINGS 2>/dev/null
  xrandr --addmode "$OUT" "$MODENAME" 2>/dev/null
  xrandr --output "$OUT" --mode "$MODENAME" --same-as "$PRIMARY_OUTPUT" 2>/dev/null \
    && logger "KIOSK: mirrored $OUT at forced $PRIMARY_RES ($MODENAME)" \
    || logger "KIOSK: mirror of $OUT at forced $PRIMARY_RES failed"
done
