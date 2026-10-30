#!/bin/sh
# Slowdown survey: play each stage (or STAGES="2 4") start to boss with an
# invulnerable ship that holds fire and never moves, logging every 10
# frames the game speed, frames drawn, scroll position, boss state, live
# enemies and bullets and MARIA's load (needs the a7800 fork), and each
# line's DMA (A7800_DMA_LOG). tools/survey.py summarizes each run.
#   tools/survey.sh                -> build/survey/stageN/{play.txt,dma.log}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/survey"
FRAMES=${FRAMES:-15000}
mkdir -p "$OUT"
SCRIPT="$OUT/script.txt"
{
  echo "700 press P1 Button 2"; echo "710 release P1 Button 2"; echo "750 press P1 Button 1"
  f=800
  while [ $f -lt "$FRAMES" ]; do
    echo "$f peek 2312"; echo "$f peek 22c3"; echo "$f peek 2231 2"; echo "$f peek 2344"
    echo "$f peek 2600 13"; echo "$f peek 2480 16"; echo "$f dma"
    f=$((f + 10))
  done
  echo "$FRAMES exit"
} > "$SCRIPT"
for s in ${STAGES:-1 2 3 4 5 6}; do
  DEFS="CHEAT"; [ "$s" != 1 ] && DEFS="CHEAT STAGE${s}TEST"
  GF_DEFINES="$DEFS" "$ROOT/tools/build.sh" > /dev/null || exit 1
  cp "$ROOT/build/gammaforce-test.a78" "$OUT/stage$s.a78"
done
for s in ${STAGES:-1 2 3 4 5 6}; do
  A7800_DMA_LOG="$OUT/stage$s.dma" ROM="$OUT/stage$s.a78" \
    "$ROOT/tools/play.sh" "$SCRIPT" "$OUT/stage$s" > /dev/null &
done
wait
for s in ${STAGES:-1 2 3 4 5 6}; do
  echo "== stage $s"
  "$ROOT/.venv/bin/python" "$ROOT/tools/survey.py" "$OUT/stage$s/play.txt" "$OUT/stage$s.dma"
done
