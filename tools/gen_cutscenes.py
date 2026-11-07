#!/usr/bin/env python3
"""The cutscenes: a bank each (banks 11-16), from storyboard/script.txt and
the pictures in storyboard/panels/.

    .venv/bin/python tools/gen_cutscenes.py   -> src/gen/cutN.asm, cutgfxN.bas

A cutscene takes over the screen: MARIA is pointed at its own display list
list (in its bank's ROM), and the game's is put back after. Two kinds:

  full      a 160 x 96 picture (tools/cutscene7800.py), the hazard stripe,
            13 rows of 40-column text
  briefing  the speaker's portrait (32 x 48) and two header lines, the
            stripe, 16 rows of text

The picture, portraits and stripe are 160A (the portraits' and the
picture's palettes come from the pictures; the stripe is palette 7). The
text is 320A: an interrupt at the stripe (7800basic's top-of-screen NMI,
which the cutscene's display list puts there; gammaforce.bas
topscreenroutine jumps through cutvec) switches CTRL to 320A with 1-byte
characters, CHARBASE to the bank's font and palette 7 to white; the
end-of-screen NMI (bottomscreenroutine, cutvec2) puts them back for the
next frame. The text is typed onto rows in RAM a letter a frame; fire
finishes a page, then turns it.

Each bank: at $8000 the font (8 pages, 64 glyphs a page, one byte each:
glyph line 7 - p in page p, as an 8-line zone reads them); at $8800 the
entry (jmp, A = the scene); then the bank's song (gen_music.sh: the act
breaks' three banks hold the same song at the same address, so one song
table entry serves them); then the player and its data. The pictures
and portraits go in the bank's graphics block ($A000).
"""

import re
from pathlib import Path

import numpy as np
from PIL import Image

import cutscene7800 as cs
import gen_assets as ga

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "storyboard" / "script.txt"
PANELS = ROOT / "storyboard" / "panels"
GEN, GFX = ga.GEN, ga.GFX

# where each scene lives (scene n plays before stage n; 10 after the last)
BANKS = {1: 11, 2: 12, 3: 12, 4: 12, 5: 12, 7: 12, 6: 13, 8: 14, 9: 15, 10: 16}
SONGS = {11: "SONG_PROLOGUE", 12: "SONG_BRIEFING", 13: "SONG_ACTBREAK", 14: "SONG_ACTBREAK",
         15: "SONG_ACTBREAK", 16: "SONG_EPILOGUE"}
PORTRAITS = ["thorne", "maya", "gamma"]

FONT320 = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?'\"-:/()%"
EXTRA320 = {
    ".": ["........", "........", "........", "........", "........", "...11...", "...11..."],
    ",": ["........", "........", "........", "........", "...11...", "...11...", "..11...."],
    "!": ["...11...", "...11...", "...11...", "...11...", "...11...", "........", "...11..."],
    "?": [".11111..", "11...11.", "....11..", "...11...", "...11...", "........", "...11..."],
    "'": ["...11...", "...11...", "..11....", "........", "........", "........", "........"],
    '"': [".11..11.", ".11..11.", ".1...1..", "........", "........", "........", "........"],
    "-": ["........", "........", "........", ".111111.", "........", "........", "........"],
    ":": ["........", "...11...", "...11...", "........", "...11...", "...11...", "........"],
    "/": [".....11.", "....11..", "....11..", "...11...", "..11....", "..11....", ".11....."],
    "(": ["....11..", "...11...", "..11....", "..11....", "..11....", "...11...", "....11.."],
    ")": ["..11....", "...11...", "....11..", "....11..", "....11..", "...11...", "..11...."],
    "%": ga.EXTRA_GLYPHS["%"],
}
NL, PAGE, END = 0x40, 0x41, 0x42      # text codes: new line, end of page, end of scene

COLS = 36                              # text columns (two 18-character objects, x 8 and 80)
ROWS = {"full": 13, "briefing": 16}    # text rows (row 0: the callsign, amber)
CUTBUF = 0x1900                        # the text rows in RAM (the engine's ring buffers: idle)
CUTPDL = 0x1C00                        # a briefing's portrait zones' display lists, in RAM
WHITE, AMBER = 0x0F, 0x2A
STRIPE = [(220, 40, 40), (250, 140, 20), (250, 230, 40)]   # red, orange, yellow

CTRL_TEXT = 0x43                       # DMA on, 1-byte characters, 320A
CTRL_GAME = 0x50                       # (gammaforce.bas: DMA on, 2-byte characters, 160A)
GAMEFONT = 0xC0                        # the game's font (the last bank's character block)


def font_pages():
    """The 320A font: 8 pages of 64 bytes (the rest of each page unused)."""
    sheet = np.array(Image.open(ga.ASSETS / "font_astrowing.png"))
    glyphs = []
    for ch in FONT320:
        if ch in EXTRA320:
            g = np.array([[c == "1" for c in r] for r in EXTRA320[ch]])
        elif ch == " ":
            g = np.zeros((7, 8), dtype=bool)
        else:
            i = ga.FONT_CHARS.index(ch)
            g = sheet[0:7, i * 8:(i + 1) * 8] > 0
        g = np.vstack([g, np.zeros((1, 8), dtype=bool)])       # line 7: the gap below
        glyphs.append([sum(1 << (7 - x) for x in range(8) if g[y, x]) for y in range(8)])
    assert len(glyphs) <= 64
    pages = []
    for p in range(8):
        pages.append([g[7 - p] for g in glyphs] + [0] * (64 - len(glyphs)))
    return pages


def encode(text):
    out = []
    for ch in text.upper():
        if ch not in FONT320:
            raise SystemExit(f"script: {ch!r} is not in the font ({FONT320})")
        out.append(FONT320.index(ch))
    return out


def wrap(par):
    """A paragraph into lines of at most COLS."""
    lines, cur = [], ""
    for w in par.split():
        if len(cur) + len(w) + (1 if cur else 0) > COLS:
            lines.append(cur)
            cur = w
        else:
            cur = f"{cur} {w}" if cur else w
    if cur:
        lines.append(cur)
    return lines


def parse():
    """scene -> {kind, picture or headers, pages: [(portrait, lines)]}"""
    scenes, cur, page = {}, None, None
    for raw in SCRIPT.read_text().splitlines():
        line = raw.rstrip()
        if line.startswith("#"):
            continue
        m = re.match(r"== (\d+) (full|briefing) (.*)", line)
        if m:
            n, kind, rest = int(m.group(1)), m.group(2), m.group(3).strip()
            cur = scenes[n] = {"kind": kind, "pages": []}
            if kind == "full":
                cur["picture"] = rest
            else:
                cur["headers"] = [h.strip() for h in rest.split("|")]
            page = None
            continue
        m = re.match(r">> (\w+): (.*)", line)
        if m:
            page = [PORTRAITS.index(m.group(1)), [m.group(2).strip()], []]
            cur["pages"].append(page)
            continue
        if page is None:
            continue
        if not line.strip():
            if page[2]:
                page[2].append("")
            continue
        page[2].append(line.strip())
    out = {}
    for n, sc in scenes.items():
        pages = []
        for portrait, head, body in sc["pages"]:
            lines = list(head)
            par = []
            for b in body + [""]:
                if b:
                    par.append(b)
                elif par:
                    lines += wrap(" ".join(par))
                    lines.append("")
                    par = []
            while lines and not lines[-1]:
                lines.pop()
            cap = ROWS[sc["kind"]]
            assert len(lines) <= cap, f"scene {n}: a page of {len(lines)} lines (room for {cap})"
            for l in lines:
                assert len(l) <= COLS, (n, l)
            pages.append((portrait, lines))
        sc["pages"] = pages
        out[n] = sc
    return out


def pic_rows(name, img, bg, pals, which, gfx, bas):
    """A picture's 16-line rows as PNGs for the graphics block (each cell's
    slot, its palette chosen by its object), and its zones' objects."""
    sl = cs.slots(img, bg, pals, which)
    zones = []
    for r in range(img.shape[0] // 16):
        label = f"cut_{name}{r}"
        ga.save_160a(GFX / f"{label}.png", sl[r * 16:(r + 1) * 16], [0x0F, 0x0F, 0x0F])
        bas.append(f"  incgraphic gfx/{label}.png 160A 0 1 2 3")
        objs = []
        for start, w, pal, x in cs.objects(which[r:r + 1])[0]:
            while w > 0:                              # (an object is at most 31 bytes)
                k = min(w, 30)
                objs.append((label, start, k, pal, x))
                start, w, x = start + k, w - k, x + k * 4
        zones.append(objs)
    return zones


def asm_obj4(label, off, w, pal, x):
    return f"  .byte <({label}+{off}),{(pal << 5) | ((-w) & 31)},>({label}+{off}),{x}"


def line_bytes(line):
    """How many bytes an asm line holds (a .byte list; 0 for an equate)."""
    m = re.match(r"\S*\s*\.byte (.*)", line.split(";")[0])
    return len(m.group(1).split(",")) if m else 0


def pack_gaps(blocks, gaps=8, room=192):
    """Data lines (each a labelled .byte line, or an equate) into the font
    pages' unused 192 bytes: returns each page's lines and what was left."""
    pages, left = [[] for _ in range(gaps)], []
    free = [room] * gaps
    for b in blocks:
        n = line_bytes(b)
        for g in range(gaps):
            if n <= free[g]:
                pages[g].append(b)
                free[g] -= n
                break
        else:
            left.append(b)
    return pages, free, left


def bank_files(bank, scenes, pages_font):
    P = f"cs{bank}_"
    lines = [f"; Generated by tools/gen_cutscenes.py. Do not edit.",
             f"; Cutscene bank {bank}: scenes {', '.join(str(n) for n in sorted(scenes))}.",
             f"{P}font"]
    # the font's pages use 64 bytes each: data goes in the rest (the high
    # score screen's, in its bank)
    gap_pages, gap_free, gap_left = pack_gaps(hs_data(P) if bank == HS_BANK else [])
    assert not gap_left, gap_left
    for p, page in enumerate(pages_font):
        lines.append("  .byte " + ",".join(str(v) for v in page[:32]))
        lines.append("  .byte " + ",".join(str(v) for v in page[32:]))
        lines += gap_pages[p]
        lines.append(f"  ds {gap_free[p]},0")
    lines += [f"  if . != $8800", f'    echo "ERROR: cutscene bank {bank}: the font is not 2K"', "    err", "  endif",
              "; the entry: A = the scene", f"  jmp {P}main"]
    if bank == HS_BANK:
        lines += ["; the high score table's: A = 0 to show it, 1 to put a new score in", f"  jmp {P}hs"]
    if bank == JB_BANK:
        lines += ["; the jukebox's screen into RAM (tools/gen_jukebox.py)", "  jmp jb_setup"]
    bas = ["  rem Generated by tools/gen_cutscenes.py. Do not edit."]
    data = []                     # the player's data, after the song
    # the stripe: rows 10-15 of a 16-line strip, red, orange, yellow
    st = np.zeros((16, 32), dtype=np.uint8)
    st[10:12], st[12:14], st[14:16] = 1, 2, 3
    ga.save_160a(GFX / f"cut_stripe{bank}.png", st, [ga.nearest(c) for c in STRIPE])
    bas.append(f"  incgraphic gfx/cut_stripe{bank}.png 160A 0 1 2 3")
    data.append(f"{P}dlstripe")
    for k in range(5):
        data.append(asm_obj4(f"cut_stripe{bank}", 0, 8, 7, k * 32))
    data.append("  .byte 0,0")
    data.append(f"{P}dlnone .byte 0,0")
    # the text rows' display lists: row 0 amber (palette 6), the rest white (7)
    maxrows = max(ROWS[s["kind"]] for s in scenes.values())
    for r in range(maxrows):
        pal = 6 if r == 0 else 7
        a = CUTBUF + r * COLS
        data.append(f"{P}dlrow{r}")
        for half in (0, 1):
            data.append(f"  .byte <${a + half * 18:04X},$60,>${a + half * 18:04X},{(pal << 5) | ((-18) & 31)},{8 + half * 72}")
        data.append("  .byte 0,0")
    data.append(f"{P}rowlo .byte " + ",".join(f"<${CUTBUF + r * COLS:04X}" for r in range(maxrows)))
    data.append(f"{P}rowhi .byte " + ",".join(f">${CUTBUF + r * COLS:04X}" for r in range(maxrows)))

    def dll(name, kind, top):
        """A display list list: 7800basic's top border (9 lines), 224
        visible lines (top: the picture's or the portrait's zones), its
        non-visible entries (the NMIs: 7800basic counts three a frame,
        the first here at the stripe)."""
        e = [(0x46, "dlnone"), (0x40, "dlnone"), (0x40, "dlnone"), (0x07, "dlnone")]   # 9 + 8 lines
        used = 8
        for label in top:
            e.append((0x0F, label))
            used += 16
        e.append((0x03, "dlnone"))                           # 4 lines
        e.append((0x05, "dlstripe"))                         # the stripe
        e.append((0x80 | 0x01, "dlnone"))                    # 2 lines; the NMI as they begin: 320A after
        used += 12
        for r in range(ROWS[kind]):
            e.append((0x07, f"dlrow{r}"))
            used += 8
        rest = 224 - used
        assert rest >= 0, (name, used)
        while rest > 0:
            k = min(rest, 16)
            e.append((k - 1, "dlnone"))
            rest -= k
        e += [(0xC3, "dlnone"), (0xCF, "dlnone"), (0x4F, "dlnone"), (0x4F, "dlnone"), (0x4F, "dlnone")]
        out = [f"{P}{name}"]
        for flags, label in e:
            lab = label if label.startswith(("$", "cs")) else f"{P}{label}"
            out.append(f"  .byte ${flags:02X},>{lab},<{lab}")
        return out

    # scenes
    table = {"kind": [], "pagelo": [], "pagehi": [], "dlllo": [], "dllhi": [], "pal": [], "h0": [], "h1": []}
    pal_lines, text = [], []
    for n in sorted(scenes):
        sc = scenes[n]
        if sc["kind"] == "full":
            img = cs.load(PANELS / f"{sc['picture']}.png")
            img, bg, pals, which, notes = cs.fit(img)
            if notes:
                print(f"  scene {n} ({sc['picture']}): {len(notes)} cells changed to fit")
            zones = pic_rows(sc["picture"], img, bg, pals, which, GFX, bas)
            top = []
            for r, objs in enumerate(zones):
                data.append(f"{P}dlpic{n}_{r}")
                data += [asm_obj4(*o) for o in objs]
                data.append("  .byte 0,0")
                top.append(f"dlpic{n}_{r}")
            data += dll(f"dll{n}", "full", top)
            cols = [bg] + [c for p in pals for c in p] + [0] * 3 * (6 - len(pals))
        else:
            top = [f"${CUTPDL + z * 32:04X}" for z in range(3)]
            data += dll(f"dll{n}", "briefing", top)
            cols = [0] + [0] * 18
            for k, h in enumerate(sc["headers"]):
                assert len(h) <= 14, f"scene {n}: header {h!r} is {len(h)} long (14 fit beside the portrait)"
                data.append(f"{P}head{n}_{k} .byte " + ",".join(str(ga.char_index(ch)) for ch in h))
                data.append(f"{P}headlen{n}_{k} = {len(h)}")
        cols += [AMBER, AMBER, AMBER] + [ga.nearest(c) for c in STRIPE]
        pal_lines.append(f"{P}pal{n} .byte " + ",".join(f"${c:02X}" for c in cols))
        # the pages: the portrait, then the text
        tb = [f"{P}text{n}"]
        for i, (portrait, lines_) in enumerate(sc["pages"]):
            b = [portrait]
            for j, l in enumerate(lines_):
                b += encode(l)
                if j < len(lines_) - 1:
                    b.append(NL)
            b.append(END if i == len(sc["pages"]) - 1 else PAGE)
            for k in range(0, len(b), 24):
                tb.append("  .byte " + ",".join(str(v) for v in b[k:k + 24]))
        text += tb
        table["kind"].append(1 if sc["kind"] == "briefing" else 0)
        for key, lab in (("page", f"text{n}"), ("dll", f"dll{n}"), ("pal", f"pal{n}")):
            if key == "pal":
                table["pal"].append(f"{P}pal{n}")
            else:
                table[key + "lo"].append(f"<{P}{lab}")
                table[key + "hi"].append(f">{P}{lab}")
    # the portraits (briefings): 3 zones of 8 bytes each, palettes 0 and 1
    if any(s["kind"] == "briefing" for s in scenes.values()):
        for i, name in enumerate(PORTRAITS):
            img = cs.load(PANELS / f"{name}.png", cs.PORTRAIT)
            img, bg, pals, which, notes = cs.fit(img, bg=0, npal=cs.PORTRAIT_NPAL)
            sl = cs.slots(img, bg, pals, which)
            while len(pals) < 2:
                pals.append([0, 0, 0])
            for r in range(3):
                label = f"cut_{name}{r}"
                ga.save_160a(GFX / f"{label}.png", sl[r * 16:(r + 1) * 16], [0x0F, 0x0F, 0x0F])
                bas.append(f"  incgraphic gfx/{label}.png 160A 0 1 2 3")
            # each zone's portrait: an object a cell (2 bytes), in its palette
            data.append(f"{P}por{i}pal .byte " + ",".join(f"${c:02X}" for p in pals[:2] for c in p))
            for r in range(3):
                data.append(f"{P}por{i}z{r} .byte " + ",".join(
                    f"<(cut_{name}{r}+{2 * c}),{(int(which[r, c]) << 5) | ((-2) & 31)},>(cut_{name}{r}+{2 * c}),{8 + 8 * c}"
                    for c in range(4)))
        data.append(f"{P}porlo .byte " + ",".join(f"<{P}por{i}z0" for i in range(3)))
        data.append(f"{P}porhi .byte " + ",".join(f">{P}por{i}z0" for i in range(3)))
        data.append(f"{P}porpal_lo .byte " + ",".join(f"<{P}por{i}pal" for i in range(3)))
        data.append(f"{P}porpal_hi .byte " + ",".join(f">{P}por{i}pal" for i in range(3)))
    nums = sorted(scenes)
    data.append(f"{P}scenes .byte " + ",".join(str(n) for n in nums))
    for key in ("kind", "pagelo", "pagehi", "dlllo", "dllhi"):
        data.append(f"{P}{key} .byte " + ",".join(str(v) for v in table[key]))
    data.append(f"{P}pallo .byte " + ",".join(f"<{v}" for v in table["pal"]))
    data.append(f"{P}palhi .byte " + ",".join(f">{v}" for v in table["pal"]))
    # briefings' headers
    if any(s["kind"] == "briefing" for s in scenes.values()):
        hl = []
        for n in nums:
            if scenes[n]["kind"] == "briefing":
                hl.append((f"{P}head{n}_0", f"{P}headlen{n}_0", f"{P}head{n}_1", f"{P}headlen{n}_1"))
            else:
                hl.append((f"{P}dlnone", 1, f"{P}dlnone", 1))
        for k, field in ((0, "h0"), (2, "h1")):
            data.append(f"{P}{field}lo .byte " + ",".join(f"<{h[k]}" for h in hl))
            data.append(f"{P}{field}hi .byte " + ",".join(f">{h[k]}" for h in hl))
            data.append(f"{P}{field}w .byte " + ",".join(f"(-{h[k + 1]})&31" for h in hl))
    code = PLAYER + (HISCORES if bank == HS_BANK else "")
    code = code.replace("P_", P).replace("SONG_X", SONGS[bank]).replace("NSCENES", str(len(nums)))
    code = code.replace("HAS_BRIEF", "1" if any(s["kind"] == "briefing" for s in scenes.values()) else "0")
    out = "\n".join(lines) + "\n"
    rest = "\n".join(["", code] + pal_lines + data + text) + "\n"
    return out, rest, bas


# The high score table (7800basic's hiscore.asm keeps it, on a High Score
# Cart or an AtariVox/SaveKey, inlined in this bank without its display:
# gammaforce.bas) is shown by this bank's player: a table for each
# difficulty, a new score's initials entered.
HS_BANK = 12
JB_BANK = 11                              # the jukebox's (tools/gen_jukebox.py)
HS_ROW0 = 2                               # the first entry's text row (then every other one)
HS_DEFAULTS = [("MAY", 100000), ("NAT", 80000), ("EDC", 60000), ("SOL", 40000), ("GFX", 20000)]
HS_LETTERS = 27                           # initials: A-Z (7800basic's 0-25), and a space


def hs_data(P):
    """The high score screen's texts (the 320A font's codes, row 0's and
    the prompt's; the game font's, the header's)."""
    out = []
    for label, text in (("hstitle", "THE GAMMA FORCE // TOP PILOTS"), ("hsnew", "NEW HIGH SCORE!"),
                        ("hshelp1", "UP AND DOWN CHOOSE A LETTER,"), ("hshelp2", "FIRE TAKES IT.")):
        out.append(f"{P}{label} .byte " + ",".join(str(v) for v in encode(text)) + f",$FF ; {text}")
    head = "HIGH SCORES"
    out.append(f"{P}hshead .byte " + ",".join(str(ga.char_index(ch)) for ch in head))
    out.append(f"{P}hsheadw = (-{len(head)})&31")
    out.append(f"{P}hsheadx = {(160 - 8 * len(head)) // 2}")
    modes = ["EXPERT", "NORMAL", "TEDDY BEAR"]                 # (the title's: easy 0-2)
    for i, m in enumerate(modes):
        out.append(f"{P}hsmode{i} .byte " + ",".join(str(ga.char_index(ch)) for ch in m))
    out.append(f"{P}hsmodelo .byte " + ",".join(f"<{P}hsmode{i}" for i in range(3)))
    out.append(f"{P}hsmodehi .byte " + ",".join(f">{P}hsmode{i}" for i in range(3)))
    out.append(f"{P}hsmodew .byte " + ",".join(f"(-{len(m)})&31" for m in modes))
    out.append(f"{P}hsmodex .byte " + ",".join(str((160 - 8 * len(m)) // 2) for m in modes))
    # an empty table's: 6 BCD digits (the score / 10), initials A-Z = 0-25
    sc, ini = [], []
    for name, v in HS_DEFAULTS:
        d = f"{v // 10:06d}"
        sc += [int(d[0:2], 16), int(d[2:4], 16), int(d[4:6], 16)]
        ini += [ord(c) - 65 for c in name]
    out.append(f"{P}hsdefs .byte " + ",".join(f"${v:02X}" for v in sc))
    out.append(f"{P}hsdefi .byte " + ",".join(str(v) for v in ini))
    # an initial's glyph: A-Z, then the space
    out.append(f"{P}hsglyph .byte " + ",".join(str(FONT320.index(ch)) for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ "))
    return out


# The player (each bank its own copy, P_ its labels' prefix). Enters with
# A = the scene, in vblank-free time; returns (rts) with the game's display
# list list back, DMA off: the caller rebuilds the screen.
PLAYER = f'''
; ---- the player ----
P_main
     ; which of this bank's scenes
     ldx #NSCENES-1
P_find
     cmp P_scenes,x
     beq P_found
     dex
     bpl P_find
     rts                     ; (none: not this bank's)
P_found
     stx cs_idx
     ifconst interrupthold
     lda #$FF
     sta interrupthold
     endif
     lda #0                  ; (stage 6's fade, still on after it: it would
     sta fadeon              ; write palette 1 and the background each frame)
     lda sINPT1              ; (a button already held doesn't count)
     and #$C0
     sta cs_prev
     ; the text rows clear
     lda #0
     ldx #0
P_clr
     sta ${CUTBUF:04X},x
     sta ${CUTBUF + 0x100:04X},x
     sta ${CUTBUF + 0x200:04X},x
     inx
     bne P_clr
     jsr waitforvblankstart
     ldx cs_idx
     ; the palettes: the background, P0-P5 (the picture's), P6, P7 (the
     ; stripe's; white below it, cutvec)
     lda P_pallo,x
     sta pfq
     lda P_palhi,x
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant              ; (the picture's background, put back off the screen)
     ldx #0
P_pals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne P_palnext
     inx
P_palnext
     cpx #32
     bcc P_pals
     ldx cs_idx
     lda P_dlllo,x
     sta DPPL
     lda P_dllhi,x
     sta DPPH
     lda #<P_dli
     sta cutvec
     lda #>P_dli
     sta cutvec+1
     lda #<P_bottom
     sta cutvec2
     lda #>P_bottom
     sta cutvec2+1
     lda #${CTRL_GAME:02X}
     sta CTRL
     lda #${GAMEFONT:02X}
     sta CHARBASE
     ; the first page
     lda P_pagelo,x
     sta pfp
     lda P_pagehi,x
     sta pfp+1
     jsr P_newpage
     lda #SONG_X
     jsr mus_play
P_loop
     jsr waitforvblankstart
     lda #3                  ; (7800basic's NMI count: as pf_drawscreen)
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     lda cs_state
     bne P_wait
     jsr P_type
     jmp P_input
P_wait
P_input
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev             ; (newly down)
     beq P_loop
     lda cs_state
     bne P_turn
P_finish                     ; typing: the rest of the page at once
     jsr P_type
     lda cs_state
     beq P_finish
     jmp P_loop
P_turn
     cmp #2
     beq P_exit
     jsr P_newpage
     jmp P_loop
P_exit
     jsr waitforvblankstart
     lda #0
     sta cutvec+1
     sta cutvec2+1
     sta bgwant
     lda #${CTRL_GAME | 0x20:02X}           ; DMA off: the caller rebuilds the screen
     sta CTRL
     lda #>DLLMEM
     sta DPPH
     lda #<DLLMEM
     sta DPPL
     jmp mus_stop
; (the high score table's: the title song plays on)
P_exitkeep
     jsr waitforvblankstart
     lda #0
     sta cutvec+1
     sta cutvec2+1
     sta bgwant
     lda #${CTRL_GAME | 0x20:02X}
     sta CTRL
     lda #>DLLMEM
     sta DPPH
     lda #<DLLMEM
     sta DPPL
     rts

; A new page: the rows clear, its portrait (a briefing's), typing from its
; text (pfp: its first byte, the portrait)
P_newpage
     lda #0
     sta cs_state
     sta cs_row
     sta cs_col
     ldx #0
P_npclr
     sta ${CUTBUF:04X},x
     sta ${CUTBUF + 0x100:04X},x
     sta ${CUTBUF + 0x200:04X},x
     inx
     bne P_npclr
     ldy #0
     lda (pfp),y
     sta cs_por
     inc pfp
     bne P_np2
     inc pfp+1
P_np2
     if HAS_BRIEF
     ldx cs_idx
     lda P_kind,x
     beq P_npdone
     jsr P_portrait
     endif
P_npdone
     rts

; One letter of the page onto its row (or a code)
P_type
     ldy #0
     lda (pfp),y
     inc pfp
     bne P_t2
     inc pfp+1
P_t2
     cmp #${NL:02X}
     beq P_tnl
     cmp #${PAGE:02X}
     beq P_tpage
     cmp #${END:02X}
     beq P_tend
     pha
     ldx cs_row
     lda P_rowlo,x
     sta pfq
     lda P_rowhi,x
     sta pfq+1
     ldy cs_col
     pla
     sta (pfq),y
     inc cs_col
     rts
P_tnl
     inc cs_row
     lda #0
     sta cs_col
     rts
P_tpage
     lda #1
     sta cs_state
     rts
P_tend
     lda #2
     sta cs_state
     rts

     if HAS_BRIEF
; A briefing's top: the portrait (cs_por) in its three zones, its palettes
; (P0, P1), the two header lines beside it (the game's font: 160A)
P_portrait
     ldx cs_por
     lda P_porpal_lo,x
     sta pfq
     lda P_porpal_hi,x
     sta pfq+1
     ; (P0C1-P0C3 and P1C1-P1C3 are not contiguous: one by one)
     ldy #0
     lda (pfq),y
     sta P0C1
     iny
     lda (pfq),y
     sta P0C2
     iny
     lda (pfq),y
     sta P0C3
     iny
     lda (pfq),y
     sta P1C1
     iny
     lda (pfq),y
     sta P1C2
     iny
     lda (pfq),y
     sta P1C3
     ; the zones' lists (32 bytes apart): the portrait, an object a cell
     ; (16 bytes), then a header line (zones 0, 1), then the end
     lda P_porlo,x
     sta pfq
     lda P_porhi,x
     sta pfq+1
     ldy #0
P_pz
     lda (pfq),y
     sta ${CUTPDL:04X},y
     iny
     cpy #16
     bne P_pz
P_pz1
     lda (pfq),y
     sta ${CUTPDL + 32 - 16:04X},y
     iny
     cpy #32
     bne P_pz1
P_pz2
     lda (pfq),y
     sta ${CUTPDL + 64 - 32:04X},y
     iny
     cpy #48
     bne P_pz2
     ldx cs_idx
     lda P_h0lo,x
     sta ${CUTPDL + 16:04X}
     lda #$60
     sta ${CUTPDL + 17:04X}
     lda P_h0hi,x
     sta ${CUTPDL + 18:04X}
     lda P_h0w,x
     ora #(2<<5)
     sta ${CUTPDL + 19:04X}
     lda #48
     sta ${CUTPDL + 20:04X}
     lda P_h1lo,x
     sta ${CUTPDL + 32 + 16:04X}
     lda #$60
     sta ${CUTPDL + 32 + 17:04X}
     lda P_h1hi,x
     sta ${CUTPDL + 32 + 18:04X}
     lda P_h1w,x
     ora #(3<<5)
     sta ${CUTPDL + 32 + 19:04X}
     lda #48
     sta ${CUTPDL + 32 + 20:04X}
     lda #0
     sta ${CUTPDL + 21:04X}
     sta ${CUTPDL + 22:04X}
     sta ${CUTPDL + 32 + 21:04X}
     sta ${CUTPDL + 32 + 22:04X}
     sta ${CUTPDL + 64 + 16:04X}
     sta ${CUTPDL + 64 + 17:04X}
     ; the header lines' colors: P2 amber, P3 white (the game's font: slot 3)
     lda #${AMBER:02X}
     sta P2C3
     lda #${WHITE:02X}
     sta P3C3
     rts
     endif

; The stripe's NMI (7800basic's top-of-screen one: topscreenroutine,
; cutvec): from the next line, 320A text, the font, a black background,
; palette 7 white
P_dli
     sta WSYNC
     lda #${CTRL_TEXT:02X}
     sta CTRL
     lda #>P_font
     sta CHARBASE
     lda #0
     sta BACKGRND
     lda #${WHITE:02X}
     sta P7C1
     sta P7C2
     sta P7C3
     rts

; The end of the screen (bottomscreenroutine, cutvec2): back for the top of
; the next frame (the background: userinterrupt, off the screen, bgwant)
P_bottom
     lda #${CTRL_GAME:02X}
     sta CTRL
     lda #${GAMEFONT:02X}
     sta CHARBASE
     ldx cs_idx
     lda P_pallo,x
     sta pfq
     lda P_palhi,x
     sta pfq+1
     ldy #22                 ; (the stripe's colors: the scene's last three)
     lda (pfq),y
     sta P7C1
     iny
     lda (pfq),y
     sta P7C2
     iny
     lda (pfq),y
     sta P7C3
     rts
'''

HISCORES = f'''
; ---- the high score table ----
P_hs
     sta hs_mode
     ; the difficulty's table (from the title: Teddy Bear's, then Normal's,
     ; then Expert's)
     lda easy
     ldx hs_mode
     bne P_hs0
     lda #2
P_hs0
     sta hs_d
     jsr P_hsload
     lda #$FF
     sta hs_pos
     lda hs_mode
     beq P_hs1
     jsr P_hsinsert
P_hs1
     jmp P_hsscreen

; Table hs_d loaded (an empty one: the defaults)
P_hsload
     lda hs_d
     sta gamedifficulty
     jsr loaddifficultytable
     ; an empty table (no save device, or nothing saved yet): the defaults
     ldx #14
     lda #0
P_hsempty
     ora HSRAMScores,x
     dex
     bpl P_hsempty
     tax
     bne P_hsfull
     ldx #14
P_hsdef
     lda P_hsdefs,x
     sta HSRAMScores,x
     lda P_hsdefi,x
     sta HSRAMInitials,x
     dex
     bpl P_hsdef
P_hsfull
     rts

; The header's difficulty (hs_d) in zone 1
P_hshdr
     ldx hs_d
     lda P_hsmodelo,x
     sta ${CUTPDL + 32:04X}
     lda P_hsmodehi,x
     sta ${CUTPDL + 32 + 2:04X}
     lda P_hsmodew,x
     ora #(3<<5)
     sta ${CUTPDL + 32 + 3:04X}
     lda P_hsmodex,x
     sta ${CUTPDL + 32 + 4:04X}
     rts

P_hsscreen
     lda #0
     sta cs_idx              ; (the screen of this bank's first briefing)
     sta hs_t
     sta fadeon
     lda #$FF
     sta hs_rep
     lda #0
     ifconst interrupthold
     lda #$FF
     sta interrupthold
     endif
     lda sINPT1
     and #$C0
     sta cs_prev
     lda #0
     tax
P_hsclr
     sta ${CUTBUF:04X},x
     sta ${CUTBUF + 0x100:04X},x
     sta ${CUTBUF + 0x200:04X},x
     inx
     bne P_hsclr
     ; the header (the game's font, centred): HIGH SCORES, the difficulty
     lda #<P_hshead
     sta ${CUTPDL:04X}
     lda #$60
     sta ${CUTPDL + 1:04X}
     sta ${CUTPDL + 32 + 1:04X}
     lda #>P_hshead
     sta ${CUTPDL + 2:04X}
     lda #(P_hsheadw|(2<<5))
     sta ${CUTPDL + 3:04X}
     lda #P_hsheadx
     sta ${CUTPDL + 4:04X}
     jsr P_hshdr
     lda #0
     sta ${CUTPDL + 5:04X}
     sta ${CUTPDL + 6:04X}
     sta ${CUTPDL + 32 + 5:04X}
     sta ${CUTPDL + 32 + 6:04X}
     sta ${CUTPDL + 64:04X}
     sta ${CUTPDL + 64 + 1:04X}
     ; the texts: the title, and (entering) the prompt
     ldx #0
     lda #<P_hstitle
     ldy #>P_hstitle
     jsr P_hsline
     lda hs_pos
     bmi P_hs2
     jsr P_hsprompt
P_hs2
     jsr waitforvblankstart
     lda P_pallo
     sta pfq
     lda P_palhi
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant
     ldx #0
P_hspals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne P_hspaln
     inx
P_hspaln
     cpx #32
     bcc P_hspals
     lda #${AMBER:02X}
     sta P2C3
     lda #${WHITE:02X}
     sta P3C3
     lda P_dlllo
     sta DPPL
     lda P_dllhi
     sta DPPH
     lda #<P_dli
     sta cutvec
     lda #>P_dli
     sta cutvec+1
     lda #<P_bottom
     sta cutvec2
     lda #>P_bottom
     sta cutvec2+1
     lda #${CTRL_GAME:02X}
     sta CTRL
     lda #${GAMEFONT:02X}
     sta CHARBASE
     ; the title song (from the title it plays on: this bank holds it where
     ; stage 1's does)
     lda hs_mode
     beq P_hsloop
     lda #SONG_TITLE
     jsr mus_play
P_hsloop
     jsr waitforvblankstart
     lda #3
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     inc hs_t
     jsr P_hsrows
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev
     sta hs_fire
     lda hs_pos
     bmi P_hsshow
     ; entering: up and down choose the letter (repeating while held),
     ; fire takes it
     lda SWCHA
     and #$30
     cmp #$30
     bne P_hsstick
     lda #$FF                ; (released)
     sta hs_rep
     bne P_hsfire
P_hsstick
     lda hs_rep
     bpl P_hsheld
     lda #20                 ; a press: a letter, and 20 frames before it repeats
     sta hs_rep
     bne P_hsstep
P_hsheld
     dec hs_rep
     bne P_hsfire
     lda #8                  ; held: a letter every 8 frames
     sta hs_rep
P_hsstep
     jsr P_hsletter
     lda SWCHA
     and #$10                ; up: the next letter
     bne P_hsdown
     lda (pfq),y
     clc
     adc #1
     cmp #{HS_LETTERS}
     bcc P_hsput
     lda #0
     beq P_hsput
P_hsdown
     lda (pfq),y
     sec
     sbc #1
     bcs P_hsput
     lda #{HS_LETTERS - 1}
P_hsput
     sta (pfq),y
P_hsfire
     lda hs_fire
     beq P_hsback
     inc hs_cur
     lda hs_cur
     cmp #3
     bcs P_hstaken
P_hsback
     jmp P_hsloop
P_hstaken
     ; the initials taken: saved, and the table shown a while
     jsr savedifficultytable
     lda #$FF
     sta hs_pos
     lda #0
     sta hs_t
     ldx #12
     jsr P_hsblank
     ldx #13
     jsr P_hsblank
     ldx #14
     jsr P_hsblank
     jmp P_hsloop
P_hsshow
     ; the table: until fire, or a while: from the title, each table about 5
     ; seconds, Teddy Bear's, Normal's, Expert's; after an entry, about 8
     lda hs_fire
     bne P_hsdone
     lda hs_mode
     bne P_hsafter
     lda hs_t
     cmp #250
     bcc P_hsagain
     lda #0
     sta hs_t
     dec hs_d                ; the next table
     bmi P_hsdone
     jsr P_hsload
     jsr P_hshdr
     jmp P_hsloop
P_hsafter
     lda hs_t
     cmp #250
     bcc P_hsagain
     inc hs_mode             ; (counting the 250s: 2 of them)
     lda #0
     sta hs_t
     lda hs_mode
     cmp #3
     bcs P_hsdone
P_hsagain
     jmp P_hsloop
P_hsdone
     jmp P_exitkeep

; pfq/y: the initial being entered (HSRAMInitials, hs_pos * 3 + hs_cur)
P_hsletter
     lda hs_pos
     asl
     adc hs_pos
     adc hs_cur
     tay
     lda #<HSRAMInitials
     sta pfq
     lda #>HSRAMInitials
     sta pfq+1
     rts

; The five entries onto rows HS_ROW0 on: the place, the initials (the one
; being entered blinking), the score (its six digits, and the 0 they
; leave off)
P_hsrows
     ldx #0
P_hsr
     stx hs_x
     txa
     asl                     ; (every other row)
     adc #{HS_ROW0}
     tay
     lda P_rowlo,y
     sta pfq
     lda P_rowhi,y
     sta pfq+1
     ldy #9
     txa
     clc
     adc #2                  ; (the font's 1: its code 2)
     sta (pfq),y
     ; the initials
     txa
     asl
     adc hs_x
     tax                     ; (the entry's first initial)
     ldy #13
P_hsri
     lda HSRAMInitials,x
     cmp #{HS_LETTERS}
     bcc P_hsri1
     lda #{HS_LETTERS - 1}
P_hsri1
     stx hs_y
     tax
     lda P_hsglyph,x
     ldx hs_y
     sta hs_c
     ; (the one being entered blinks)
     lda hs_pos
     cmp hs_x
     bne P_hsri2
     tya
     sec
     sbc #13
     cmp hs_cur
     bne P_hsri2
     lda hs_t
     and #16
     beq P_hsri2
     lda #{FONT320.index("-")}
     sta hs_c
P_hsri2
     lda hs_c
     sta (pfq),y
     inx
     iny
     cpy #16
     bne P_hsri
     ; the score
     ldx hs_x
     txa
     asl
     adc hs_x
     tax
     ldy #20
P_hsrs
     lda HSRAMScores,x
     lsr
     lsr
     lsr
     lsr
     clc
     adc #1                  ; (the font's digits from code 1)
     sta (pfq),y
     iny
     lda HSRAMScores,x
     and #$0F
     clc
     adc #1
     sta (pfq),y
     iny
     inx
     cpy #26
     bne P_hsrs
     lda #1                  ; (the 0 left off)
     sta (pfq),y
     ldx hs_x
     inx
     cpx #5
     bcs P_hsrend
     jmp P_hsr
P_hsrend
     rts

; A text (A/Y: its address, $FF-ended) onto row X
P_hsline
     sta pfp
     sty pfp+1
     lda P_rowlo,x
     sta pfq
     lda P_rowhi,x
     sta pfq+1
     ldy #0
P_hsl
     lda (pfp),y
     cmp #$FF
     beq P_hsl2
     sta (pfq),y
     iny
     bne P_hsl
P_hsl2
     rts

; Row X cleared
P_hsblank
     lda P_rowlo,x
     sta pfq
     lda P_rowhi,x
     sta pfq+1
     lda #0
     ldy #{COLS - 1}
P_hsb
     sta (pfq),y
     dey
     bpl P_hsb
     rts

P_hsprompt
     ldx #12
     lda #<P_hsnew
     ldy #>P_hsnew
     jsr P_hsline
     ldx #13
     lda #<P_hshelp1
     ldy #>P_hshelp1
     jsr P_hsline
     ldx #14
     lda #<P_hshelp2
     ldy #>P_hshelp2
     jmp P_hsline

; The score (its six digits past the first, three BCD bytes: the last
; digit, always 0, left off) into the table if it beats an entry: the
; entries below it move down; its initials start as AAA. hs_pos: its
; place, or $FF.
P_hsinsert
     lda score_bcd
     asl
     asl
     asl
     asl
     sta hs_b0
     lda score_bcd+1
     lsr
     lsr
     lsr
     lsr
     ora hs_b0
     sta hs_b0
     lda score_bcd+1
     asl
     asl
     asl
     asl
     sta hs_b1
     lda score_bcd+2
     lsr
     lsr
     lsr
     lsr
     ora hs_b1
     sta hs_b1
     lda score_bcd+2
     asl
     asl
     asl
     asl
     sta hs_b2
     lda score_bcd+3
     lsr
     lsr
     lsr
     lsr
     ora hs_b2
     sta hs_b2
     ldx #0                  ; (each entry's first score byte: 0, 3, ...)
     ldy #0                  ; (its place)
P_hsi
     lda hs_b0
     cmp HSRAMScores,x
     bcc P_hsinext
     bne P_hsiput
     lda hs_b1
     cmp HSRAMScores+1,x
     bcc P_hsinext
     bne P_hsiput
     lda hs_b2
     cmp HSRAMScores+2,x
     bcc P_hsinext
     bne P_hsiput
P_hsinext
     inx
     inx
     inx
     iny
     cpy #5
     bne P_hsi
     rts                     ; (not in the table)
P_hsiput
     sty hs_pos
     stx hs_x3               ; (its first byte: its place * 3)
     lda #0
     sta hs_cur
     ; the entries from its place down move down one (the last is lost)
     ldx #11                 ; (the 4th entry's first byte: copied to the 5th's)
P_hsmove
     cpx hs_x3
     bcc P_hsmoved
     lda HSRAMScores,x
     sta HSRAMScores+3,x
     lda HSRAMInitials,x
     sta HSRAMInitials+3,x
     dex
     bpl P_hsmove
P_hsmoved
     ldx hs_x3
     lda hs_b0
     sta HSRAMScores,x
     lda hs_b1
     sta HSRAMScores+1,x
     lda hs_b2
     sta HSRAMScores+2,x
     lda #0
     sta HSRAMInitials,x
     sta HSRAMInitials+1,x
     sta HSRAMInitials+2,x
     rts
'''


def main():
    scenes = parse()
    font = font_pages()
    for bank in sorted(set(BANKS.values())):
        mine = {n: s for n, s in scenes.items() if BANKS[n] == bank}
        head, rest, bas = bank_files(bank, mine, font)
        (GEN / f"cut{bank}.asm").write_text(head)
        (GEN / f"cut{bank}b.asm").write_text(rest)
        (GEN / f"cutgfx{bank}.bas").write_text("\n".join(bas) + "\n")
        print(f"bank {bank}: scenes {sorted(mine)}")
    lines = ["; Generated by tools/gen_cutscenes.py. Do not edit.",
             "; Each scene's bank, as SuperGame's bank select wants it (bank - 2): scene n at n - 1."]
    lines.append("cut_banks .byte " + ",".join(str(BANKS[n] - 2) for n in range(1, 11)))
    (GEN / "cuttab.asm").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
