#!/bin/sh
# Convert the soundtrack: shared tables, the song table and the title song
# go in the fixed bank (musiccommon.asm); stage 1's songs in its bank.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
M="$ROOT/assets/mgf/music"
"$ROOT/.venv/bin/python" "$ROOT/tools/vgm2pokey.py" "$M/Stage1.vgm" "$M/Boss.vgm" "$M/Title.vgm" \
    -o "$ROOT/src/gen/musicdata.asm" --fixed "$ROOT/src/gen/musiccommon.asm" --fixed-songs Title
