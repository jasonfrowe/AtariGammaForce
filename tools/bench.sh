#!/bin/sh
# Speed benchmark: stage 1 (or STAGE=2..4) with an invulnerable ship that
# holds fire and never moves, so every build plays the same game. Reports
# game speed and display rate (tools/fps.py).
#   tools/bench.sh            STAGE=3 tools/bench.sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEFS="CHEAT"
[ -n "$STAGE" ] && [ "$STAGE" != 1 ] && DEFS="CHEAT STAGE${STAGE}TEST"
GF_DEFINES="$DEFS" "$ROOT/tools/build.sh" > /dev/null || exit 1
ROM="$ROOT/build/gammaforce-test.a78" "$ROOT/tools/play.sh" "$ROOT/tests/bench_still.txt" "$ROOT/build/bench" > /dev/null
"$ROOT/.venv/bin/python" "$ROOT/tools/fps.py" "$ROOT/build/bench/play.txt"
