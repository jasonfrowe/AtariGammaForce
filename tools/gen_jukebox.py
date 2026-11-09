#!/usr/bin/env python3
"""The jukebox: every song in the game, from the title (past STAGE 9).

    .venv/bin/python tools/gen_jukebox.py   -> src/gen/jukebox.asm, jbtitle.asm

A song plays from its own bank (a stage's, a cutscene's), so the jukebox's
screen can't be in any one: it is built in RAM (the engine's idle ring
buffers, $1900-$1FFF), its display list list, its lists and its text, in
the game's font from the last bank (fixed). Bank 11 builds it
(jukebox.asm, its entry at $8803: jb_setup) and copies the track list
into RAM; the fixed bank's loop (gammaforce.bas jukebox) then switches in
whichever bank a track needs. Left and right choose a track, fire plays
or stops it, button 2 goes back to the title.
"""

from pathlib import Path

import gen_assets as ga

GEN = ga.GEN

# (song, its bank, the name, the line below it). SPIRE WARDEN's is GAMMA
# CORE's song (its bank's copy): once.
TRACKS = [
    ("SONG_TITLE", 2, "ATARI GAMMA FORCE", "TITLE"),
    ("SONG_PROLOGUE", 11, "SCRAMBLE ORDER", "PROLOGUE"),
    ("SONG_STAGE1", 2, "SKY FORTRESS", "STAGE 1"),
    ("SONG_BOSS", 2, "GAMMA CORE", "STAGE 1 AND 2 BOSS"),
    ("SONG_BRIEFING", 12, "SECTOR ALERT", "BRIEFING"),
    ("SONG_STAGE2", 3, "NEON SPIRES", "STAGE 2"),
    ("SONG_STAGE3", 4, "IRON TIDE", "STAGE 3"),
    ("SONG_BOSS3", 4, "LEVIATHAN", "STAGE 3 BOSS"),
    ("SONG_STAGE4", 5, "SCORCHED SANDS", "STAGE 4"),
    ("SONG_BOSS4", 5, "DUNE WYRM", "STAGE 4 BOSS"),
    ("SONG_STAGE5", 6, "FROZEN STRAIT", "STAGE 5"),
    ("SONG_BOSS5", 6, "GLACIER CRAWLER", "STAGE 5 BOSS"),
    ("SONG_ACTBREAK", 13, "BREAKING THE TETHER", "ACT BREAK"),
    ("SONG_STAGE6", 7, "ASCENT", "STAGE 6"),
    ("SONG_BOSS6", 7, "HALO STATION", "STAGE 6 BOSS"),
    ("SONG_STAGE7", 8, "SEA OF TRANQUILITY", "STAGE 7"),
    ("SONG_BOSS7", 8, "MASS DRIVER", "STAGE 7 BOSS"),
    ("SONG_STAGE8", 9, "DEEP FIELD", "STAGE 8"),
    ("SONG_BOSS8", 9, "HIVE MOTHERSHIP", "STAGE 8 BOSS"),
    ("SONG_STAGE9", 10, "CORONA", "STAGE 9"),
    ("SONG_BOSS9", 10, "GAMMA PRIME", "FINAL BOSS"),
    ("SONG_EPILOGUE", 16, "A QUIET SUN", "EPILOGUE"),
]

# RAM (the ring buffers: idle with the game's screen gone)
DLL, DLS, BARDL, EMPTY, ROWS = 0x1900, 0x1980, 0x19C0, 0x19E0, 0x1A00
TABLES = 0x1AA0                       # bank, song, name lo/hi, line lo/hi: 32 each
NAMES = TABLES + 6 * 32               # each track's name and line, 20 characters each
STATUS = 0x1ED0                       # "PLAYING", "STOPPED", 20 each
BARGFX = 0x1F00                       # 32 bytes of $FF: the meters' bars (160A: color 3)
CODE = 0x1F20                         # jb_anim, copied from bank 11 (it only branches: it runs anywhere)
CODE_END = 0x2000
HUES = 0x19E4                         # jb_anim's tables, a byte a bar: its hue (high nibble),
DLOFF = HUES + 3                      # its display list's offset (from BARDL),
PREG = HUES + 6                       # its color register's (from P0C3),
PALB = HUES + 9                       # its palette (palette | width's top 3 bits)
VARS = 0x19F0                         # jb_anim's: each bar's level [3], the drum's last level,
                                      # the title's hue, the flash, a frame count, each
                                      # bar's width this frame [3]

# the screen's text rows: (zone, palette, fixed text or None: written by the loop)
W = 20
LINES = [(1, 7, "JUKEBOX"), (3, 3, None), (5, 5, None), (6, 3, None), (8, 6, None),
         (11, 3, "< PREV      NEXT >"), (12, 3, "B1   PLAY OR STOP"), (13, 3, "B2   BACK TO TITLE")]
# the meters, in zones 9 and 10: (lines, bar or None for a gap), 32 lines.
# Each bar's lines are 1-line zones sharing its display list, which reads
# the one line of $FF bytes at BARGFX: lead (palette 0), bass, drums.
METERS = [(9, None), (5, 0), (3, None), (5, 1), (3, None), (5, 2), (2, None)]
METER_ZONES = (9, 10)
BAR_HUES = [0x40, 0x90, 0x10]         # lead pink, bass blue, drums gold
TRACKROW = 1                          # its text: "TRACK 07 OF 22"


def centre(t):
    t = t[:W]
    pad = (W - len(t)) // 2
    return (" " * pad + t).ljust(W)


def chars(t):
    return [ga.char_index(ch) for ch in t]


def anim_code():
    """jb_anim (the jukebox loop's, each frame, in vblank): the meters from
    the music's three voices (each one's volume, times 3: its envelope's next value;
    the drums': their next AUDC), growing out from the middle and falling
    back a step a frame, brighter as they rise; a drum hit steps the
    title's hue and brightens it for a moment (not the background: a
    flash there is hard on the eyes). Copied to CODE: only relative
    branches, and its tables are in RAM."""
    lev, raw2, hue, flash, tick, tgt = VARS, VARS + 3, VARS + 4, VARS + 5, VARS + 6, VARS + 7
    assert PALB + 3 <= VARS and tgt + 3 <= ROWS and EMPTY + 2 <= HUES
    return f"""; jb_anim: runs at ${CODE:04X} (copied by jb_setup)
jb_code
     inc ${tick:04X}
     ldx #2
ja_voice
     lda #0
     ldy mus_on
     beq ja_level
     lda mus_envlo,x         ; (voices 0, 1: the envelope's next volume;
     sta temp1               ; the drums: their next AUDC)
     lda mus_envhi,x
     sta temp2
     ldy #0
     lda (temp1),y
     and #$0F
ja_level
     sta temp3               ; the bar's width: 3 bytes a step of volume, up
     asl                     ; to 30 (most of the tunes play at 2-8 of 15)
     adc temp3
     cmp #30
     bcc ja_width
     lda #30
ja_width
     sta ${tgt:04X},x
     cmp ${lev:04X},x            ; up at once, down a byte a frame
     bcs ja_set
     lda ${lev:04X},x
     sbc #0                  ; (carry clear: less 1)
ja_set
     sta ${lev:04X},x
     sta temp3
     ldy ${DLOFF:04X},x          ; Y = the bar's display list
     lda temp3
     beq ja_hide
     eor #$FF                ; palette X, width -w
     clc
     adc #1
     and #$1F
     ora ${PALB:04X},x
     sta ${BARDL + 1:04X},y
     lda temp3               ; x = 80 - 2w: the middle
     asl
     eor #$FF
     sec
     adc #80
     sta ${BARDL + 3:04X},y
     bne ja_color
ja_hide
     lda #160
     sta ${BARDL + 3:04X},y
ja_color
     ldy ${PREG:04X},x           ; its color: brighter with its level
     lda temp3
     lsr
     lsr
     clc
     adc #4
     ora ${HUES:04X},x
     sta P0C3,y
     dex
     bpl ja_voice
     lda ${tgt + 2:04X}              ; a drum hit: up by 6 or more since last frame
     tax
     sec
     sbc ${raw2:04X}
     stx ${raw2:04X}
     bcc ja_nohit
     cmp #6
     bcc ja_nohit
     inc ${hue:04X}
     lda #4
     sta ${flash:04X}
ja_nohit
     lda mus_on              ; (stopped: the title's hue drifts)
     bne ja_title
     lda ${tick:04X}
     and #15
     bne ja_title
     inc ${hue:04X}
ja_title
     lda ${hue:04X}              ; (not hue 0: grey)
     and #15
     bne ja_title2
     inc ${hue:04X}
     lda #1
ja_title2
     asl
     asl
     asl
     asl
     ora #$0A
     clc
     adc ${flash:04X}
     sta P7C3
     lda ${flash:04X}
     beq ja_done
     dec ${flash:04X}
ja_done
     rts
jb_code_end
""".splitlines()


def main():
    assert len(TRACKS) <= 32
    for _, _, name, line in TRACKS:
        assert len(name) <= W and len(line) <= W, (name, line)
    n = len(TRACKS)
    out = ["; Generated by tools/gen_jukebox.py. Do not edit.",
           "; The jukebox's screen and track list, copied into RAM (bank 11's: its",
           "; entry at $8803). The fixed bank's loop (gammaforce.bas jukebox) plays.",
           "jb_setup",
           "     jsr waitforvblankstart",
           "     lda #$70                ; (DMA off while it is built)",
           "     sta CTRL",
           "     ; the templates into RAM",
           "     ldx #0",
           "jb_copy",
           "     lda jb_ram0,x",
           f"     sta ${DLL:04X},x",
           "     lda jb_ram1,x",
           f"     sta ${DLL + 0x100:04X},x",
           "     lda jb_ram2,x",
           f"     sta ${DLL + 0x200:04X},x",
           "     lda jb_ram3,x",
           f"     sta ${DLL + 0x300:04X},x",
           "     lda jb_ram4,x",
           f"     sta ${DLL + 0x400:04X},x",
           "     lda jb_ram5,x",
           f"     sta ${DLL + 0x500:04X},x",
           "     lda jb_ram6,x",
           f"     sta ${DLL + 0x600:04X},x",
           "     inx",
           "     bne jb_copy",
           "     ldx #0                  ; jb_anim into RAM",
           "jb_copyc",
           "     lda jb_code,x",
           f"     sta ${CODE:04X},x",
           "     inx",
           "     cpx #jb_code_end-jb_code",
           "     bne jb_copyc",
           "     ; the colors: a dark blue, the font's (its slot 3) in palettes 3, 5, 6",
           f"     lda #${ga.nearest((0, 20, 60)):02X}",
           "     sta BACKGRND",
           "     lda #$0F",
           "     sta P3C3",
           "     sta P7C3",
           f"     lda #${ga.nearest((120, 220, 255)):02X}",
           "     sta P5C3",
           f"     lda #${ga.nearest((250, 200, 40)):02X}",
           "     sta P6C3",
           "     lda #0",
           "     sta cutvec+1",
           "     sta cutvec2+1",
           "     sta bgwant",
           "     sta fadeon",
           "     jsr waitforvblankstart",
           f"     lda #>${DLL:04X}",
           "     sta DPPH",
           f"     lda #<${DLL:04X}",
           "     sta DPPL",
           "     lda #$C0                ; (the game's font: the last bank's block)",
           "     sta CHARBASE",
           "     lda #$50",
           "     sta CTRL",
           "     rts",
           ""] + anim_code()
    ram = bytearray(0x700)

    def put(addr, data):
        o = addr - DLL
        ram[o:o + len(data)] = bytes(data)
    # the display list list: 7800basic's top border, 14 zones of 16 lines
    # (the first's NMI: 7800basic counts three a frame), its non-visible
    # entries (the other two)
    dll = [(0x46, EMPTY), (0x40, EMPTY), (0x40, EMPTY)]
    zone_dl = {}
    for k, (zone, pal, text) in enumerate(LINES):
        zone_dl[zone] = (DLS + 8 * k, ROWS + W * k, pal)
    assert sum(n for n, _ in METERS) == 16 * len(METER_ZONES)
    for z in range(14):
        if z == METER_ZONES[0]:
            for lines, bar in METERS:
                if bar is None:
                    dll.append((lines - 1, EMPTY))
                else:
                    dll += [(0, BARDL + 6 * bar)] * lines
            continue
        if z in METER_ZONES:
            continue
        flags = 0x0F | (0x80 if z == 0 else 0)
        dll.append((flags, zone_dl[z][0] if z in zone_dl else EMPTY))
    dll += [(0xC3, EMPTY), (0xCF, EMPTY), (0x4F, EMPTY), (0x4F, EMPTY), (0x4F, EMPTY)]
    assert 3 * len(dll) <= DLS - DLL, len(dll)
    b = []
    for f, a in dll:
        b += [f, a >> 8, a & 255]
    put(DLL, b)
    for z, (dl, row, pal) in zone_dl.items():
        put(dl, [row & 255, 0x60, row >> 8, (pal << 5) | ((-W) & 31), 0, 0, 0])
    put(EMPTY, [0, 0])
    for bar in range(3):                   # hidden (x 160) until it has a level
        put(BARDL + 6 * bar, [BARGFX & 255, (bar << 5) | 31, BARGFX >> 8, 160, 0, 0])
    put(BARGFX, [0xFF] * 32)
    put(HUES, BAR_HUES + [0, 6, 12] + [0, 4, 8] + [0, 32, 64])
    for k, (zone, pal, text) in enumerate(LINES):
        put(ROWS + W * k, chars(centre(text or "")))
    put(ROWS + W * TRACKROW, chars(centre(f"TRACK 00 OF {n:02d}")))
    # the tables, the names
    for i, (song, bank, name, line) in enumerate(TRACKS):
        put(TABLES + 2 * 32 + i, [(NAMES + 40 * i) & 255])
        put(TABLES + 3 * 32 + i, [(NAMES + 40 * i) >> 8])
        put(TABLES + 4 * 32 + i, [(NAMES + 40 * i + W) & 255])
        put(TABLES + 5 * 32 + i, [(NAMES + 40 * i + W) >> 8])
        put(NAMES + 40 * i, chars(centre(name)) + chars(centre(line)))
    assert NAMES + 40 * n <= STATUS and STATUS + 2 * W <= BARGFX
    put(STATUS, chars(centre("PLAYING")) + chars(centre("STOPPED")))
    for p in range(7):
        out.append(f"jb_ram{p}")
        page = ram[p * 256:(p + 1) * 256]
        for k in range(0, 256, 32):
            row = [str(v) for v in page[k:k + 32]]
            out.append("  .byte " + ",".join(row))
    # the banks and songs (symbols: put in the tables after the copy)
    out.append("; each track's bank (as SuperGame's bank select wants it: bank - 2), its song")
    out.append("jb_banks .byte " + ",".join(str(b - 2) for _, b, _, _ in TRACKS))
    out.append("jb_songs .byte " + ",".join(s for s, _, _, _ in TRACKS))
    out.append(f"JB_N = {n}")
    out.append(f"JB_ANIM = ${CODE:04X}")
    out.append(f" if jb_code_end - jb_code > ${CODE_END - CODE:02X}")
    out.append('   echo "ERROR: jb_anim is too long for its RAM"')
    out.append("   err")
    out.append(" endif")
    out.append(f"JB_TABLES = ${TABLES:04X}")
    out.append(f"JB_ROWS = ${ROWS:04X}")
    out.append(f"JB_STATUS = ${STATUS:04X}")
    out.append(f"JB_W = {W}")
    out.append(f"JB_TRACKDIGIT = ${ROWS + W * TRACKROW + centre('TRACK 00 OF 00').index('0'):04X}")
    out.append(f"JB_COUNTDIGIT = ${ROWS + W * TRACKROW + centre('TRACK 00 OF 00').rindex('00'):04X}")
    out.append("JB_NAMEROW = $%04X" % (ROWS + W * 2))
    out.append("JB_LINEROW = $%04X" % (ROWS + W * 3))
    out.append("JB_STATUSROW = $%04X" % (ROWS + W * 4))
    # the copy above leaves the tables' first two (bank, song) to fill
    out.insert(out.index("     ; the colors: a dark blue, the font's (its slot 3) in palettes 3, 5, 6"),
               "     ldx #JB_N-1\njb_tab\n     lda jb_banks,x\n     sta JB_TABLES,x\n"
               "     lda jb_songs,x\n     sta JB_TABLES+32,x\n     dex\n     bpl jb_tab")
    (GEN / "jukebox.asm").write_text("\n".join(out) + "\n")
    # the title's choice past STAGE 9 (title.bas: written into its RAM lines)
    t = ["; Generated by tools/gen_jukebox.py. Do not edit.",
         "; The title's choice past STAGE 9: its two lines (title.bas)."]
    t.append("jb_sel .byte " + ",".join(str(v) for v in chars("<   JUKEBOX   >")))
    t.append("jb_room .byte " + ",".join(str(v) for v in chars(centre("MUSIC ROOM")[2:18])))
    (GEN / "jbtitle.asm").write_text("\n".join(t) + "\n")
    print(f"jukebox: {n} tracks")


if __name__ == "__main__":
    main()
