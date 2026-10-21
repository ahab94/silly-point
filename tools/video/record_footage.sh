#!/bin/bash
# Records raw gameplay (game sound effects, no music) for the marketing
# videos into build/footage/. Each clip is one innings with a chosen bot and
# seed (picked by scanning for the moment the video needs, see CLAUDE.md),
# in portrait 1080x1920 (p-*) or landscape 1920x1080 (l-*). Each clip gets a
# .events file of timestamped moments from --log-events, so captions and cuts
# can be timed exactly.
# Usage: bash tools/video/record_footage.sh [clip-name ...]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
out=build/footage
mkdir -p "$out"

# Movie Maker records at the project's window size and ignores --resolution,
# so each recording writes a temporary override.cfg with the exact size.
trap 'rm -f override.cfg' EXIT
window() {
	printf '[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$1" "$2" "$1" "$2" > override.cfg
}

record() {  # name resolution seconds flags...
	local name=$1 res=$2 secs=$3; shift 3
	if [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $name "* ]]; then return; fi
	if [ "$res" = 1080x1920 ]; then window 1080 1920; else window 1920 1080; fi
	"$GODOT" --path . --write-movie "$out/$name.avi" --fixed-fps 30 \
		-- --no-save --log-events --timeout="$secs" "$@" | grep -E "^(EVENT|RESULT)" > "$out/$name.events" || true
	rm -f override.cfg
	ffmpeg -loglevel error -y -i "$out/$name.avi" -c:v libx264 -preset fast -crf 16 \
		-pix_fmt yuv420p -c:a aac -b:a 192k "$out/$name.mp4"
	rm "$out/$name.avi"
	local size; size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x "$out/$name.mp4")
	[ "$size" = "$res" ] || { echo "$name recorded at $size, expected $res"; exit 1; }
	echo "$name: $(grep -c EVENT "$out/$name.events") events"
}

ONLY="$*"
source tools/video/clips.sh
