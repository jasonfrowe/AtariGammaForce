#!/usr/bin/env python3
"""Convert the art in assets/ into 7800 graphics and data for the build.

Writes:
  src/gfx/*.png        160A images (indexed, 4 colors: 0 = transparent)
  src/gen/gfx.bas      the incgraphic lines, in block order
  src/gen/data.asm     palettes, sprite image table, stage maps
  build/preview/*.png  what the converted art looks like in 7800 colors

Run it after changing anything in assets/ (the outputs are committed, so
the game builds without Python):

    .venv/bin/python tools/gen_assets.py

How the 7800 sees the art
-------------------------
160A pixels are twice as wide as they are tall, so MegaGammaForce art is
halved horizontally: a 16x16 sprite becomes 8 pixels by 16 lines and looks
the same shape on screen. Each sprite or tile then has three colors plus
transparent, picked from one of eight hardware palettes:

  P0 sea      P1 deck     P2 deck detail / gray enemies
  P3 player and its shots
  P4 red enemies   P5 blue enemies   P6 yellow enemies
  P7 bullets (pink = color 1, blue = color 2, white = 3) and the sword

Background tiles and the HUD font share one character block, because MARIA
reads every character on screen from the one block CHARBASE points at.
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
MGF = ASSETS / "mgf"
GFX = ROOT / "src" / "gfx"
GEN = ROOT / "src" / "gen"
PREVIEW = ROOT / "build" / "preview"

PAL7800 = [tuple(c) for c in json.loads((ROOT / "tools" / "a7800_ntsc_palette.json").read_text())["rgb"]]


def nearest(rgb):
    """The 7800 color byte closest to an RGB triple (weighted for the eye)."""
    r, g, b = rgb
    best, bd = 0, 1e18
    for i, (pr, pg, pb) in enumerate(PAL7800):
        d = 3 * (r - pr) ** 2 + 4 * (g - pg) ** 2 + 2 * (b - pb) ** 2
        if d < bd:
            best, bd = i, d
    return best


# ---------------------------------------------------------------------------
# Palettes: three colors each, given as RGB targets from MegaGammaForce's
# palettes and snapped to the nearest 7800 color.
BACKGROUND = (18, 54, 112)  # the open sea; edge tiles show it as water too
PALETTES = [
    [(10, 30, 70), (40, 90, 152), (200, 230, 255)],      # P0 sea: troughs, crests, foam
    [(52, 56, 72), (96, 104, 124), (160, 168, 188)],     # P1 deck
    [(82, 88, 108), (230, 190, 60), (255, 60, 60)],      # P2 deck detail
    [(48, 70, 150), (156, 168, 196), (235, 245, 255)],   # P3 player
    [(150, 20, 30), (120, 126, 144), (255, 150, 110)],   # P4 red
    [(30, 70, 200), (120, 126, 144), (160, 215, 255)],   # P5 blue
    [(190, 140, 0), (120, 126, 144), (255, 240, 150)],   # P6 yellow
    [(230, 40, 150), (40, 110, 255), (255, 255, 255)],   # P7 bullets
]
BG_CODE = nearest(BACKGROUND)
PAL_CODES = [[nearest(c) for c in p] for p in PALETTES]


def rgb_of(code):
    return PAL7800[code]


# ---------------------------------------------------------------------------
# Halving and slot mapping.

def halve(src, slotmap, prefer_solid=True):
    """2D array of source indices -> half-width array of 160A slots (0-3).

    Pairs of pixels become one. Where one of the pair is transparent the
    other wins, so thin details survive; otherwise rows alternate between
    the left and right pixel, which keeps textures from smearing."""
    h, w = src.shape
    out = np.zeros((h, w // 2), dtype=np.uint8)
    for y in range(h):
        for x in range(w // 2):
            a, b = slotmap.get(int(src[y, 2 * x]), 0), slotmap.get(int(src[y, 2 * x + 1]), 0)
            if prefer_solid and (a == 0 or b == 0):
                out[y, x] = a or b
            else:
                out[y, x] = a if (y & 1) == 0 else b
    return out


def frames_of(path, fw, fh):
    a = np.array(Image.open(path))
    n = a.shape[1] // fw
    return [a[0:fh, i * fw:(i + 1) * fw] for i in range(n)]


def save_160a(path, slots, pal_codes):
    """Save a slot array as an indexed PNG 7800basic can import."""
    img = Image.new("P", (slots.shape[1], slots.shape[0]))
    flat = list(rgb_of(BG_CODE))
    for c in pal_codes:
        flat += list(rgb_of(c))
    img.putpalette(flat)  # exactly 4 entries: 7800basic rejects bigger palettes
    img.paste(Image.fromarray(slots.astype(np.uint8), "P"))
    img.save(path, bits=2)


def preview(slots, pal_codes, scale=4, bg=None):
    """RGB image of slots in 7800 colors, each pixel 2:1 like a TV."""
    h, w = slots.shape
    cols = [rgb_of(BG_CODE) if bg is None else bg] + [rgb_of(c) for c in pal_codes]
    rgb = np.array(cols, dtype=np.uint8)[slots]
    img = Image.fromarray(rgb, "RGB")
    return img.resize((w * 2 * scale, h * scale), Image.NEAREST)


# ---------------------------------------------------------------------------
# Character block: background tiles, then the font.

TILE_W, TILE_H = 8, 16
FONT_CHARS = "0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ"  # x is drawn as X

# MegaGammaForce stage 1 tile indices (palettes.TILES) -> 160A slot, per
# palette. Index 1 (darkest sea) and 10 (shadow) fall to the background.
TILE_SLOTS = {
    0: {1: 1, 3: 2, 4: 2, 15: 3},                                  # sea
    1: {5: 1, 6: 1, 10: 1, 7: 2, 8: 3, 9: 3, 15: 3},               # deck
    2: {5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1, 11: 2, 12: 2, 13: 3, 14: 3},  # detail
}


def tile_palette(tile):
    s = set(int(v) for v in np.unique(tile))
    if s <= {1, 2, 3, 4, 15}:
        return 0
    if s & {11, 12, 13, 14}:
        return 2
    return 1


def build_charset():
    tiles = frames_of(MGF / "stage1_tiles.png", 16, 16)
    t_slots, t_pals = [], []
    for t in tiles:
        p = tile_palette(t)
        t_pals.append(p)
        t_slots.append(halve(t, TILE_SLOTS[p], prefer_solid=False))

    # Font: Astrowing's 8-pixel glyphs (7 lines tall), placed on lines 4-10.
    font = np.array(Image.open(ASSETS / "font_astrowing.png"))
    glyphs = []
    for i, _ch in enumerate(FONT_CHARS):
        g = np.zeros((TILE_H, TILE_W), dtype=np.uint8)
        src = font[0:7, i * 8:(i + 1) * 8]
        g[4:11, :] = np.where(src > 0, 3, 0)  # one color: slot 3
        glyphs.append(g)

    chars = t_slots + glyphs
    sheet = np.concatenate(chars, axis=1)
    save_160a(GFX / "charset.png", sheet, PAL_CODES[1])
    font_base = len(t_slots)
    return t_pals, font_base, t_slots


TEXTS = {
    "hudinit": " SCORE 0000000   x3 ",
}


def char_index(ch, font_base):
    i = FONT_CHARS.index(ch.upper()) if ch.upper() in FONT_CHARS else FONT_CHARS.index(" ")
    return 2 * (font_base + i)


# ---------------------------------------------------------------------------
# Sprites. Each entry: name, source file, frame size, slot map, palette for
# preview. Frames are halved and sliced into 16-line strips; the image table
# lists every strip so the plotter can draw tall sprites strip by strip.

PLAYER_SLOTS = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 1, 7: 1, 8: 2, 9: 1, 10: 3, 11: 3, 12: 3, 13: 3, 14: 3, 15: 1}
ENEMY_SLOTS = {1: 1, 2: 2, 3: 2, 4: 2, 5: 3, 6: 1, 7: 1, 8: 1, 9: 3, 10: 3, 11: 3, 12: 1, 13: 2, 14: 1, 15: 3}
SHOT_SLOTS = {1: 1, 2: 1, 3: 2, 4: 3, 5: 3, 6: 1, 7: 2, 8: 3, 9: 3}
PINK_SLOTS = {1: 1, 2: 1, 3: 1, 4: 3, 5: 3}
BLUE_SLOTS = {1: 2, 2: 2, 3: 2, 4: 3, 5: 3}
SWORD_SLOTS = {1: 2, 2: 2, 3: 2, 4: 3, 5: 3, 6: 2, 7: 2, 8: 3, 9: 3, 10: 2, 11: 3, 12: 3, 13: 3, 14: 2, 15: 3}
EXPL_SLOTS = {1: 0, 2: 2, 3: 1, 4: 1, 5: 3, 6: 3, 7: 3, 8: 3, 9: 2, 10: 2, 11: 0, 12: 2, 13: 1, 14: 3, 15: 3}

def _art(rows):
    return [[".123".index(ch) for ch in r] for r in rows]


# Small things drawn here directly, in 160A pixels (2:1).
HAND_DRAWN = {
    # Twin Vulcan bolts: white cores, blue tips, 12 lines long.
    "vulcan": [_art(["2..2", "3..3", "3..3", "3..3", "3..3", "3..3",
                     "3..3", "3..3", "3..3", "2..2", "2..2", "1..1"] + ["...."] * 4)],
    # Pink needle pointing down.
    "needle": [_art([".1..", ".1..", ".3..", ".3..", ".3..", ".1.."] + ["...."] * 10)],
}

SPRITES = [
    # name, file, fw, fh, frames (None = all), slots, preview palette
    ("ship", "player.png", 24, 24, None, PLAYER_SLOTS, 3),
    ("vulcan", None, 4, 16, None, None, 3),
    ("dart", "enemy16.png", 16, 16, [0, 1], ENEMY_SLOTS, 4),
    ("saucer", "enemy16.png", 16, 16, [2, 3, 4, 5], ENEMY_SLOTS, 5),
    ("drone", "enemy16.png", 16, 16, [6, 7], ENEMY_SLOTS, 6),
    ("pinkbullet", "bullet8.png", 8, 8, [0, 1], PINK_SLOTS, 7),
    ("needle", None, 4, 16, None, None, 7),
    ("bluebullet", "bullet8.png", 8, 8, [0, 1], BLUE_SLOTS, 7),
    ("expl", "expl16.png", 16, 16, None, EXPL_SLOTS, 4),
    ("sword", "sword.png", 48, 32, None, SWORD_SLOTS, 7),
]


def build_sprites():
    """Returns the image table: list of (label, width_bytes, strips)."""
    table = []
    incs = []
    previews = []
    for name, fn, fw, fh, pick, slots, pal in SPRITES:
        if fn is None:
            conv = [np.array(f, dtype=np.uint8) for f in HAND_DRAWN[name]]
        else:
            frames = frames_of(MGF / fn, fw, fh)
            if pick is not None:
                frames = [frames[i] for i in pick]
            conv = [halve(f, slots) for f in frames]
        # Pad to a multiple of 16 lines; small sprites sit at the top.
        h = conv[0].shape[0]
        strips = (h + 15) // 16
        pad = strips * 16 - h
        conv = [np.pad(c, ((0, pad), (0, 0))) for c in conv]
        w = conv[0].shape[1]
        if w % 4:
            conv = [np.pad(c, ((0, 0), (0, 4 - w % 4))) for c in conv]
            w = conv[0].shape[1]
        for s in range(strips):
            label = f"{name}{s}" if strips > 1 else name
            sheet = np.concatenate([c[s * 16:(s + 1) * 16] for c in conv], axis=1)
            save_160a(GFX / f"{label}.png", sheet, PAL_CODES[pal])
            incs.append(label)
        table.append((name, w // 4, strips, len(conv)))
        previews.append(preview(np.concatenate(conv, axis=1), PAL_CODES[pal], bg=(40, 0, 40)))
    return table, incs, previews


# ---------------------------------------------------------------------------
# Stage map. Each row becomes the bytes of its background display list
# objects, ready to copy into a zone: one 5-byte indirect (character)
# object per run of tiles that share a palette.

MAX_RUNS = 6


def row_runs(pals):
    runs = []
    for c, p in enumerate(pals):
        if runs and runs[-1][2] == p:
            runs[-1][1] += 1
        else:
            runs.append([c, 1, p])
    # Too many objects for one zone: fold the shortest run into a neighbor.
    while len(runs) > MAX_RUNS:
        i = min(range(len(runs)), key=lambda k: runs[k][1])
        j = i - 1 if i > 0 else i + 1
        a, b = sorted((i, j))
        runs[a] = [runs[a][0], runs[a][1] + runs[b][1], runs[j][2]]
        del runs[b]
    return runs


def build_stage(t_pals):
    meta = json.loads((MGF / "stage1.json").read_text())
    cols, rows = meta["cols"], meta["rows"]
    m = np.frombuffer((MGF / "stage1_map.bin").read_bytes(), dtype=np.uint8).reshape(rows, cols)
    lines = []
    lines.append(f"S1_ROWS = {rows}")
    lines.append(f"S1_LOOP_ROWS = {meta['loop_rows']}")
    lines.append("")
    lines.append("; Row r (stage order, 0 = bottom of the stage) as character indices.")
    lines.append("; Doublewide characters are two bytes each, so tile t is character 2t.")
    obj_lines = []
    max_bytes = 0
    for r in range(rows):
        idx = [2 * int(t) for t in m[r]]
        lines.append(f"s1r{r} .byte " + ",".join(str(v) for v in idx))
        runs = row_runs([t_pals[int(t)] for t in m[r]])
        max_bytes = max(max_bytes, 5 * len(runs))
        obj_lines.append(f"s1o{r} .byte {5 * len(runs)}")
        for start, n, p in runs:  # one object a line: dasm allows 32 operators a line
            obj_lines.append(f"  .byte <(s1r{r}+{start}),$60,>(s1r{r}+{start}),{(p << 5) | ((-n) & 31)},{start * TILE_W}")
    lines.append("")
    lines.append("; Row r's background objects: a length byte, then the 5-byte headers.")
    lines += obj_lines
    lines.append("")
    lines.append("s1rowlo")
    for r in range(0, rows, 8):
        lines.append("  .byte " + ",".join(f"<s1o{k}" for k in range(r, min(rows, r + 8))))
    lines.append("s1rowhi")
    for r in range(0, rows, 8):
        lines.append("  .byte " + ",".join(f">s1o{k}" for k in range(r, min(rows, r + 8))))
    return lines, max_bytes, m


def map_preview(m, t_slots, t_pals, rows=48):
    out = []
    for r in range(min(rows, m.shape[0]) - 1, -1, -1):
        out.append(np.concatenate([t_slots[int(t)] + 0 for t in m[r]], axis=1))
    # Color with each tile's palette.
    h = len(out) * 16
    img = Image.new("RGB", (160 * 2 * 2, h * 2))
    y = 0
    for r in range(min(rows, m.shape[0]) - 1, -1, -1):
        for c, t in enumerate(m[r]):
            tile = preview(t_slots[int(t)], PAL_CODES[t_pals[int(t)]], scale=2)
            img.paste(tile, (c * 32, y))
        y += 32
    return img


def main():
    GFX.mkdir(parents=True, exist_ok=True)
    GEN.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)

    t_pals, font_base, t_slots = build_charset()
    table, incs, previews = build_sprites()
    stage_lines, max_bg, m = build_stage(t_pals)

    # gfx.bas: the character block first, so charset sits at offset 0 of
    # its block and a character index is simply 2 x tile number.
    bas = ["  rem Generated by tools/gen_assets.py. Do not edit.",
           "  incgraphic gfx/charset.png 160A 0 1 2 3", "  newblock"]
    bas += [f"  incgraphic gfx/{n}.png 160A 0 1 2 3" for n in incs]
    (GEN / "gfx.bas").write_text("\n".join(bas) + "\n")

    consts = ["  rem Generated by tools/gen_assets.py. Do not edit.",
              "  rem Constants shared by BASIC and the assembly (const lands in both)."]
    asm = ["; Generated by tools/gen_assets.py. Do not edit.", ""]
    consts.append(f"  const BGCOLOR = ${BG_CODE:02X}")
    consts.append(f"  const FONTBASE = {2 * font_base}")
    consts.append(f"  const BGMAXBYTES = {max_bg}")
    asm.append("; FONTBASE is the character index of '0'; ' ' is +20, 'A' is +22.")
    asm.append("; Text strings, as character indices.")
    for label, text in TEXTS.items():
        asm.append(f"{label} .byte " + ",".join(str(char_index(ch, font_base)) for ch in text) + f" ; {text!r}")
    asm.append("")
    asm.append("; P0C1..P7C3, in register order")
    asm.append("palettedata")
    for i, p in enumerate(PAL_CODES):
        asm.append(f"  .byte " + ",".join(f"${c:02X}" for c in p) + f" ; P{i}")
    asm.append("")
    asm.append("; Sprite images. IMG_x = image number; imglo/imghi = graphics of the")
    asm.append("; first strip of frame 0; imgw = width in bytes; imgstrips = 16-line strips;")
    asm.append("; imgframes = frame count. Frame f of strip s is at (strip label) + f*w.")
    lo, hi, lo2, hi2, w, st, fr = [], [], [], [], [], [], []
    for i, (name, wb, strips, frames) in enumerate(table):
        assert strips <= 2, f"{name}: the plotter draws at most 2 strips"
        consts.append(f"  const IMG_{name.upper()} = {i}")
        first = f"{name}0" if strips > 1 else name
        second = f"{name}1" if strips > 1 else name
        lo.append(f"<{first}")
        hi.append(f">{first}")
        lo2.append(f"<{second}")
        hi2.append(f">{second}")
        w.append(str(wb))
        st.append(str(strips))
        fr.append(str(frames))
    asm += ["imglo .byte " + ",".join(lo), "imghi .byte " + ",".join(hi),
            "imglo2 .byte " + ",".join(lo2), "imghi2 .byte " + ",".join(hi2),
            "imgw .byte " + ",".join(w), "imgstrips .byte " + ",".join(st),
            "imgframes .byte " + ",".join(fr), ""]
    asm += stage_lines
    (GEN / "data.asm").write_text("\n".join(asm) + "\n")
    (GEN / "consts.bas").write_text("\n".join(consts) + "\n")

    # Previews.
    W = max(p.size[0] for p in previews)
    H = sum(p.size[1] + 8 for p in previews)
    sheet = Image.new("RGB", (W, H), (40, 0, 40))
    y = 0
    for p in previews:
        sheet.paste(p, (0, y))
        y += p.size[1] + 8
    sheet.save(PREVIEW / "sprites.png")
    map_preview(m, t_slots, t_pals).save(PREVIEW / "stage1_map.png")
    print(f"BG ${BG_CODE:02X}; palettes " + " ".join("/".join(f"{c:02X}" for c in p) for p in PAL_CODES))
    print(f"{len(t_slots)} tiles, font at char {2 * font_base}; {len(incs)} sprite strips; "
          f"largest row background {max_bg} bytes")


if __name__ == "__main__":
    main()
