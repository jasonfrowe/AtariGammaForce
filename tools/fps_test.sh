#!/bin/sh
# Frame rate over stage 1 with an invulnerable ship (so the run is all
# gameplay), overall and by stretch of the map.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GF_DEFINES="CHEAT NOCUT" "$ROOT/tools/build.sh" > /dev/null || exit 1
ROM="$ROOT/build/gammaforce-test.a78" "$ROOT/tools/play.sh" "$ROOT/tests/stage1_fps.txt" > /dev/null
"$ROOT/.venv/bin/python" "$ROOT/tools/fps.py" "$ROOT/build/play/play.txt"
