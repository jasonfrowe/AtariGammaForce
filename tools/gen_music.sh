#!/bin/sh
# Convert the soundtrack: shared tables, the song table and the title song
# go in the fixed bank (musiccommon.asm); each stage's songs in its bank
# (stage 2 has its own copy of the boss tune, as boss2, in another part of
# its bank than its stage tune: they don't fit in one). Stage 5's songs are
# split by voice (NAME.vN) between its bank's main area and its DMA hole,
# and so are stage 6's (the boss's song and one voice of the stage's in
# the hole, the stage song's other two in the main area). Stage 7's
# stage song is the shortened cut (MegaGammaForce's Stage7_cut.fur): its
# voices 0 and 1 and the boss's voice 0 in its bank's main area; its
# voice 2 and the rest of the boss's (with MASS DRIVER's code) in the hole.
# Stage 8's (the cut too): the stage song in its bank's main area, the
# boss's in the hole with HIVE MOTHERSHIP's code. The cutscenes' songs
# (assets/music: the story's) each in their cutscene bank. Stage 9's (the cut, and
# MegaGammaForce's Final for GAMMA PRIME): the boss's song and the stage
# song's voice 0 in the main area, the rest of the stage's in the hole
# with GAMMA PRIME's code.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
M="$ROOT/assets/mgf/music"
S="$ROOT/assets/music"          # the story's (tools/generate_music.py)
G="$ROOT/src/gen"
"$ROOT/.venv/bin/python" "$ROOT/tools/vgm2pokey.py" \
    "$M/Stage1.vgm" "$M/Boss.vgm" "$M/Title.vgm" "$M/Stage2.vgm" "$M/Boss.vgm:boss2" \
    "$M/Stage3.vgm" "$M/Boss3.vgm" "$M/Stage4.vgm" "$M/Boss4.vgm" "$M/Stage5_cut.vgm:stage5" "$M/Boss5_cut.vgm:boss5" \
    "$M/Stage6.vgm:stage6" "$M/Boss6.vgm:boss6" \
    "$M/Stage7_cut.vgm:stage7" "$M/Boss7.vgm:boss7" \
    "$M/Stage8_cut.vgm:stage8" "$M/Boss8.vgm:boss8" \
    "$M/Stage9_cut.vgm:stage9" "$M/Final.vgm:boss9" \
    "$S/Prologue.vgm:prologue" "$S/Briefing.vgm:briefing" "$S/ActBreak.vgm:actbreak" "$S/Epilogue.vgm:epilogue" \
    -o "$G/musicdata.asm" --fixed "$G/musiccommon.asm" \
    --to "$G/musicdata2.asm=stage2" --to "$G/musicdata2b.asm=boss2" \
    --to "$G/musicdata3.asm=stage3" --to "$G/musicdata3b.asm=boss3" \
    --to "$G/musicdata4.asm=stage4" --to "$G/musicdata4b.asm=boss4" \
    --to "$G/musicdata5.asm=stage5,boss5.v1" --to "$G/musicdata5b.asm=boss5" \
    --to "$G/musicdata5c.asm=stage5.v0,stage5.v2" \
    --to "$G/musicdata6.asm=boss6,stage6.v0" --to "$G/musicdata6b.asm=stage6" \
    --to "$G/musicdata7.asm=boss7,stage7.v2" --to "$G/musicdata7b.asm=stage7,boss7.v0" \
    --to "$G/musicdata8.asm=boss8" --to "$G/musicdata8b.asm=stage8" \
    --to "$G/musicdata9.asm=stage9" --to "$G/musicdata9b.asm=boss9,stage9.v0" \
    --to "$G/musiccut11.asm=prologue" --to "$G/musiccut12.asm=briefing" \
    --to "$G/musiccut13.asm=actbreak" --to "$G/musiccut16.asm=epilogue" \
    --to "$G/musictitle.asm=title"
# The title song plays on into the high score table (bank 12): it is at
# the same address ($B700: src/asm/titlepad.asm) in both banks, so it runs
# on through the bank switch: bank 12 gets bank 2's copy, its labels
# renamed.
sed "s/mus_title_/mus_title12_/g" "$G/musictitle.asm" > "$G/musictitle12.asm"
# The act breaks' banks (13-15) each hold the same song at the same
# address (after the cutscene font and entry, gen_cutscenes.py), so one
# song table entry serves all three: banks 14 and 15 get bank 13's copy,
# its labels renamed.
for b in 14 15; do
    sed "s/mus_actbreak_/mus_actbreak${b}_/g" "$G/musiccut13.asm" > "$G/musiccut$b.asm"
done
