#!/bin/bash
# Difficulty curve: a human-ish "rookie" bot (sloppy timing, can't see late
# movement) plays each match N times. Win rates should fall steadily from
# match 1 to 10, with dips at the tough ones. Usage: checks/difficulty.sh [N] [skill 0-1]
cd "$(dirname "$0")/.."
N=${1:-8}
SKILL=${2:-0.6}
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
count=$("$GODOT" --headless --path . --script res://tests/level_count.gd 2>/dev/null | grep -o 'LEVELS [0-9]*' | cut -d' ' -f2)
for ((i = 0; i < count; i++)); do
	wins=0; runs=0; wk=0
	for ((s = 1; s <= N; s++)); do
		line=$("$GODOT" --headless --fixed-fps 60 --path . -- --level=$i --seed=$((s * 977 + i)) --rookie=$SKILL --rookie-seed=$s --exit-on-end --no-save --timeout=900 2>&1 | grep '^RESULT')
		echo "$line" | grep -q ' won ' && wins=$((wins + 1))
		r=$(echo "$line" | sed -E 's/.*runs=([0-9]+)\/([0-9]+).*/\1 \2/')
		runs=$((runs + ${r% *})); wk=$((wk + ${r#* }))
	done
	printf "match %2d  wins %d/%d  avg runs %5.1f  avg wickets %4.1f\n" $((i + 1)) $wins $N $(echo "$runs / $N" | bc -l) $(echo "$wk / $N" | bc -l)
done
