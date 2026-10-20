#!/bin/bash
# Done when: the project imports, the physics, smoke and gameplay tests pass,
# and the autopilot wins every match.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || true)
[ -z "$GODOT" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ] && GODOT=/Applications/Godot.app/Contents/MacOS/Godot
[ -n "$GODOT" ] || { echo "Godot is not installed"; exit 1; }
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
run() {
	local script=$1 ok=$2
	local out
	out=$("$GODOT" --headless --fixed-fps 60 --path . --script "res://tests/$script" 2>&1) || { echo "$out"; echo "$script failed"; exit 1; }
	if echo "$out" | grep -qE "SCRIPT ERROR|FAIL:" || ! echo "$out" | grep -q "$ok"; then echo "$out"; echo "$script failed"; exit 1; fi
	echo "$ok"
}
run sim_test.gd "SIM OK"
run smoke_test.gd "SMOKE OK"
run game_test.gd "GAME OK"
bash "$(dirname "$0")/autoplay.sh" | tail -1
echo "silly-point: all good"
