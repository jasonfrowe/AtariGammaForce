#!/bin/sh
# Convert the soundtrack: shared tables, the song table and the title song
# go in the fixed bank (musiccommon.asm); each stage's songs in its bank
# (stage 2 has its own copy of the boss tune, as boss2, in another part of
# its bank than its stage tune: they don't fit in one).
ROOT=$(cd "$(dirname "$0")/.." && pwd)
M="$ROOT/assets/mgf/music"
G="$ROOT/src/gen"
"$ROOT/.venv/bin/python" "$ROOT/tools/vgm2pokey.py" \
    "$M/Stage1.vgm" "$M/Boss.vgm" "$M/Title.vgm" "$M/Stage2.vgm" "$M/Boss.vgm:boss2" \
    -o "$G/musicdata.asm" --fixed "$G/musiccommon.asm" --fixed-songs Title \
    --to "$G/musicdata2.asm=stage2" --to "$G/musicdata2b.asm=boss2"
