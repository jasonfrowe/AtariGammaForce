#!/bin/sh
# Convert the soundtrack: shared tables, the song table and the title song
# go in the fixed bank (musiccommon.asm); each stage's songs in its bank
# (stage 2 has its own copy of the boss tune, as boss2, in another part of
# its bank than its stage tune: they don't fit in one). Stage 5's songs are
# split by voice (NAME.vN) between its bank's main area and its DMA hole.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
M="$ROOT/assets/mgf/music"
G="$ROOT/src/gen"
"$ROOT/.venv/bin/python" "$ROOT/tools/vgm2pokey.py" \
    "$M/Stage1.vgm" "$M/Boss.vgm" "$M/Title.vgm" "$M/Stage2.vgm" "$M/Boss.vgm:boss2" \
    "$M/Stage3.vgm" "$M/Boss3.vgm" "$M/Stage4.vgm" "$M/Boss4.vgm" "$M/Stage5_cut.vgm:stage5" "$M/Boss5_cut.vgm:boss5" \
    -o "$G/musicdata.asm" --fixed "$G/musiccommon.asm" \
    --to "$G/musicdata2.asm=stage2" --to "$G/musicdata2b.asm=boss2" \
    --to "$G/musicdata3.asm=stage3" --to "$G/musicdata3b.asm=boss3" \
    --to "$G/musicdata4.asm=stage4" --to "$G/musicdata4b.asm=boss4" \
    --to "$G/musicdata5.asm=stage5,boss5.v1" --to "$G/musicdata5b.asm=boss5" \
    --to "$G/musicdata5c.asm=stage5.v0,stage5.v2"
