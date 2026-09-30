#!/bin/bash
# style.sh <udid> <Style> — scroll the frame strip until "<Style> frame" is on screen, then tap it
H=/private/tmp/claude-501/-Users-osama--superset-worktrees-Markepi-we-need-to-now-agressively-ask/bcd87282-d5ab-4b7d-a6be-cbf9ad46ae70/scratchpad
for i in $(seq 1 12); do
  L=$($H/ui.sh "$1" "'$2 frame'" | head -1); X=$(echo "$L" | awk '{split($(NF-1),p,","); print p[1]}'); Y=$(echo "$L" | awk '{split($(NF-1),p,","); print p[2]+50}')
  [ -z "$X" ] && { echo "no strip"; exit 1; }
  SW=${SW:-440}; if [ "$X" -lt 20 ]; then axe swipe --start-x 120 --start-y $Y --end-x $((SW-120)) --end-y $Y --duration 1.0 --udid "$1" >/dev/null 2>&1
  elif [ "$X" -gt $((SW-120)) ]; then axe swipe --start-x $((SW-120)) --start-y $Y --end-x 120 --end-y $Y --duration 1.0 --udid "$1" >/dev/null 2>&1
  else $H/tap.sh "$1" "$2 frame"; exit 0; fi
  sleep 1
done; echo "gave up"; exit 1
