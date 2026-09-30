#!/bin/bash
# cap.sh <udid> <dir> <name> — screenshot + the preview's rect in pixels (points x3) as <name>.json
H=/private/tmp/claude-501/-Users-osama--superset-worktrees-Markepi-we-need-to-now-agressively-ask/bcd87282-d5ab-4b7d-a6be-cbf9ad46ae70/scratchpad
$H/shot.sh "$1" "$2/$3.png"
R=$($H/ui.sh "$1" "'Watermark preview'" | head -1 | awk -v K=${K:-3} '{split($(NF-1),p,","); split($NF,s,"x"); printf "[%d,%d,%d,%d]", p[1]*K,p[2]*K,s[1]*K,s[2]*K}')
echo "{\"preview\": ${R:-null}}" > "$2/$3.json"; cat "$2/$3.json"
