#!/bin/sh
# Regression test for the scroll engine: runs the ROM headless, screenshots
# a run of frames, and checks every playfield line against the map.
#   tools/test_scroll.sh [frames]   (default: 48 frames from 700, 24 past the map's end)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
A7800=${A7800:-$ROOT/../../a7800/mame64}
OUT="$ROOT/build/test_scroll"
FRAMES=${1:-$(python3 -c "print(','.join(str(f) for f in list(range(700,748))+list(range(5500,5524))))")}
rm -rf "$OUT"; mkdir -p "$OUT"
cd "$(dirname "$A7800")"
PROBE_OUT="$OUT/probe.txt" SNAP_FRAMES="$FRAMES" "$A7800" a7800 -cart "$ROOT/build/gammaforce.a78" \
  -video none -sound none -nothrottle -seconds_to_run 300 -snapshot_directory "$OUT" \
  -autoboot_script "$ROOT/tools/emu/probe.lua" -skip_gameinfo > /dev/null 2>&1
"$ROOT/.venv/bin/python" "$ROOT/tools/check_scroll.py" "$OUT"
