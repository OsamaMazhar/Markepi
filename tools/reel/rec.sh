#!/bin/bash
# rec.sh start <udid> <out.mp4> | rec.sh stop — simulator screen recording in the background.
# Recordings are variable frame rate; build.py makes a CFR copy before cutting.
P=$(dirname "$0")/rec/.rec.pid
if [ "$1" = start ]; then
  mkdir -p "$(dirname "$P")"
  xcrun simctl io "$2" recordVideo --codec h264 --force "$3" >/dev/null 2>&1 & echo $! > "$P"; sleep 2
else
  kill -INT "$(cat "$P")" 2>/dev/null; sleep 3
fi
