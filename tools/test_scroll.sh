#!/bin/sh
# Regression test for the scroll engine: builds an invulnerable test ROM,
# starts a game (presses fire on the title), screenshots a run of frames,
# and checks every playfield line against the map.
#   tools/test_scroll.sh [frames]   (default: 48 frames from 700, 24 past the map's end)
#   STAGE=2 tools/test_scroll.sh    (stage 2)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/test_scroll"
FRAMES=${1:-$(python3 -c "print(','.join(str(f) for f in list(range(700,748))+list(range(5900,5924))))")}
mkdir -p "$ROOT/build"
STAGE=${STAGE:-1}
DEFS="CHEAT"
[ "$STAGE" = 2 ] && DEFS="CHEAT STAGE2TEST"
GF_DEFINES="$DEFS" "$ROOT/tools/build.sh" > /dev/null || exit 1
python3 - "$FRAMES" > "$ROOT/build/test_scroll.txt" <<'PY'
import sys
print("300 press P1 Button 2\n310 release P1 Button 2")
for f in sys.argv[1].split(","):
    print(f"{f} snap\n{f} peek 2231 2")
PY
ROM="$ROOT/build/gammaforce-test.a78" "$ROOT/tools/play.sh" "$ROOT/build/test_scroll.txt" "$OUT" > /dev/null
"$ROOT/.venv/bin/python" "$ROOT/tools/check_scroll.py" "$OUT" "$STAGE"
