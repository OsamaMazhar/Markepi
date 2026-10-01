#!/bin/bash
# tap.sh <udid> <exact label> — tap the centre of the element's CURRENT frame
L=$($(dirname "$0")/ui.sh "$1" "'$2'" | head -1)
[ -z "$L" ] && { echo "NOT FOUND: $2"; exit 1; }
read X Y W H < <(echo "$L" | awk '{split($(NF-1),p,","); split($NF,s,"x"); print p[1],p[2],s[1],s[2]}')
axe tap -x $((X+W/2)) -y $((Y+H/2)) --udid "$1" >/dev/null && echo "tapped $2 @ $((X+W/2)),$((Y+H/2))"
