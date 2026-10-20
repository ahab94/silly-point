#!/bin/bash
# The autopilot must win every match. A failure usually means a level is
# unwinnable or a physics/rules change broke something; trace it with
#   godot --headless --fixed-fps 60 --path . -- --level=N --autopilot --exit-on-end --trace --no-save
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
count=$("$GODOT" --headless --path . --script res://tests/level_count.gd 2>/dev/null | grep -o 'LEVELS [0-9]*' | cut -d' ' -f2)
fail=0
for ((i = 0; i < count; i++)); do
	line=$("$GODOT" --headless --fixed-fps 60 --path . -- --level=$i --autopilot --exit-on-end --no-save --timeout=600 2>&1 | grep '^RESULT')
	echo "$line"
	echo "$line" | grep -q ' won ' || fail=1
done
[ $fail -eq 0 ] && echo "autoplay: all $count matches won" || { echo "autoplay: FAILED"; exit 1; }
