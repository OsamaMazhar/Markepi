#!/bin/bash
# shot.sh <udid> <out.png> — full-res capture + 900px preview at <out>_s.png
timeout 30 xcrun simctl io "$1" screenshot "$2" >/dev/null 2>&1 && sips -Z 900 "$2" --out "${2%.png}_s.png" >/dev/null
