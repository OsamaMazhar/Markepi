#!/bin/bash
# load.sh <udid> <file>... — stage files in the share inbox and relaunch so the app imports them
G=$(xcrun simctl get_app_container "$1" com.osamamazhar.markepi group.com.osamamazhar.markepi); shift
rm -rf "$G/PendingShares"; mkdir -p "$G/PendingShares"
for f in "$@"; do d="$G/PendingShares/$(uuidgen)"; mkdir -p "$d"; cp "$f" "$d/"; sleep 1; done
