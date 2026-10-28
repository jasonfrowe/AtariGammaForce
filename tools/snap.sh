#!/bin/sh
# Run a ROM headless in the a7800 emulator and save screenshots.
#   tools/snap.sh build/gammaforce.a78 out_dir 60,120,180
# A7800 points at the emulator binary (default: ../../a7800/mame64).
ROOT=$(cd "$(dirname "$0")/.." && pwd)
A7800=${A7800:-$ROOT/../../a7800/mame64}
ROM=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUT=$2
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/a7800"
cd "$(dirname "$A7800")"
SNAP_FRAMES=$3 "$A7800" a7800 -cart "$ROM" -video none -sound none -nothrottle \
  -seconds_to_run 120 -snapshot_directory "$OUT" -autoboot_script "$ROOT/tools/emu/snap.lua" \
  -skip_gameinfo -nomouse > /dev/null 2>&1
ls "$OUT/a7800" 2>/dev/null
