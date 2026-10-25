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
import math
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
    [(56, 64, 84), (156, 168, 196), (255, 40, 60)],      # P0 boss: steel, light steel, core
                                                         # (open sea is the background color,
                                                         # so the sea tiles don't need P0)
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
    for k, t in enumerate(tiles):
        p = tile_palette(t)
        t_pals.append(p)
        if SKIP_SEA and k in SEA_TILES:
            # Open sea is the background color. Its tiles stay in the set as
            # blanks, so a sea tile caught inside a run of deck draws as sea.
            t_slots.append(np.zeros((TILE_H, TILE_W), dtype=np.uint8))
        else:
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
    "hudover": "GAMEOVER",
    "hudwarn": "WARNING",
    "hudclear": "CLEARED!",
}


# Texts shown in the playfield (title, messages), up to 20 characters.
SCREEN_TEXTS = {
    "atari": "ATARI",
    "gamma": "GAMMA FORCE",
    "push": "PRESS FIRE",
    "b1": "BUTTON 1  VULCAN",
    "b2": "BUTTON 2  SWORD",
    "credit": "2026 JASON ROWE",
    "demake": "AFTER MEGAGAMMAFORCE",
    "warning": "WARNING",
    "boss": "GAMMA CORE",
    "clear": "STAGE CLEAR",
    "over": "GAME OVER",
    "ready": "STAGE 1",
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

BOSS_SLOTS = {1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 2, 7: 1, 8: 2, 9: 3, 10: 3, 11: 3, 12: 1, 13: 1, 14: 2, 15: 2}

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
    ("gunship", "enemy32.png", 32, 32, [0, 1], ENEMY_SLOTS, 2),
    ("sword", "sword.png", 48, 32, None, SWORD_SLOTS, 7),
    # GAMMA CORE, the stage 1 boss. Its 64-line parts are drawn as top and
    # bottom halves (the plotter does two strips), the right wing mirrored.
    ("bcoret", "stage1_boss_core.png", 64, 64, None, BOSS_SLOTS, 0, (0, 32)),
    ("bcoreb", "stage1_boss_core.png", 64, 64, None, BOSS_SLOTS, 0, (32, 64)),
    ("bwinglt", "stage1_boss_wing.png", 32, 64, None, BOSS_SLOTS, 0, (0, 32)),
    ("bwinglb", "stage1_boss_wing.png", 32, 64, None, BOSS_SLOTS, 0, (32, 64)),
    ("bwingrt", "stage1_boss_wing.png", 32, 64, None, BOSS_SLOTS, 0, (0, 32), True),
    ("bwingrb", "stage1_boss_wing.png", 32, 64, None, BOSS_SLOTS, 0, (32, 64), True),
    ("bcannon", "stage1_boss_cannon.png", 32, 32, None, BOSS_SLOTS, 0),
    ("bturret", "stage1_boss_turret.png", 16, 16, None, BOSS_SLOTS, 0),
]


def build_sprites():
    """Returns the image table: list of (label, width_bytes, strips)."""
    table = []
    incs = []
    previews = []
    for entry in SPRITES:
        name, fn, fw, fh, pick, slots, pal = entry[:7]
        rows = entry[7] if len(entry) > 7 else None
        flip = entry[8] if len(entry) > 8 else False
        if fn is None:
            conv = [np.array(f, dtype=np.uint8) for f in HAND_DRAWN[name]]
        else:
            frames = frames_of(MGF / fn, fw, fh)
            if pick is not None:
                frames = [frames[i] for i in pick]
            if rows is not None:
                frames = [f[rows[0]:rows[1]] for f in frames]
            if flip:
                frames = [f[:, ::-1] for f in frames]
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
        used = max((int(np.nonzero(c.any(axis=1))[0].max()) + 1) if c.any() else 1 for c in conv)
        last_h = used - 16 * (strips - 1)  # lines used in the last strip
        table.append((name, w // 4, strips, len(conv), max(1, last_h)))
        previews.append(preview(np.concatenate(conv, axis=1), PAL_CODES[pal], bg=(40, 0, 40)))
    return table, incs, previews


# ---------------------------------------------------------------------------
# Stage map. Each row becomes the bytes of its background display list
# objects, ready to copy into a zone: one 5-byte indirect (character)
# object per run of tiles that share a palette.

MAX_RUNS = 6
SKIP_SEA = True
SEA_TILES = {0, 1, 2, 3}  # MegaGammaForce stage 1 sea0-sea3


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
        if SKIP_SEA:  # open sea is the background color: no objects
            runs = [rn for rn in runs if not all(int(m[r, c]) in SEA_TILES for c in range(rn[0], rn[0] + rn[1]))]
        max_bytes = max(max_bytes, 5 * len(runs))
        obj_lines.append(f"s1o{r} .byte {5 * len(runs)}")
        if not runs:
            continue
        for start, n, p in runs:  # one object a line: dasm allows 32 operators a line
            obj_lines.append(f"  .byte <(s1r{r}+{start}),$60,>(s1r{r}+{start}),{(p << 5) | ((-n) & 31)},{start * TILE_W}")
    lines.append("")
    lines.append("; Row r's background objects: a length byte, then the 5-byte headers.")
    lines += obj_lines
    lines.append("")
    lines.append("; Direct-mode palette|width byte for each character (zone 14 draws its")
    lines.append("; tiles as one 2-byte-wide object each), indexed by character number.")
    pw = []
    for c in range(2 * len(t_pals)):
        pw.append((t_pals[c // 2] << 5) | ((-2) & 31))
    lines.append("tilepw .byte " + ",".join(str(v) for v in pw))
    lines.append("")
    lines.append("; Row r's characters (for zone 14's direct-mode tiles).")
    lines.append("s1charlo")
    for r in range(0, rows, 8):
        lines.append("  .byte " + ",".join(f"<s1r{k}" for k in range(r, min(rows, r + 8))))
    lines.append("s1charhi")
    for r in range(0, rows, 8):
        lines.append("  .byte " + ",".join(f">s1r{k}" for k in range(r, min(rows, r + 8))))
    lines.append(f"SEATILES = {len(SEA_TILES)} ; characters below 2*SEATILES are open sea")
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


def bcd3(v):
    d = f"{v:06d}"
    return [int(d[0:2], 16), int(d[2:4], 16), int(d[4:6], 16)]


def chain_table():
    """The chain bonus for chain levels 0-41 as 3 BCD bytes (MegaGammaForce's
    score.c: 100, 200, 500, then 250 more a step, up to 10,000)."""
    vals = []
    for lv in range(42):
        vals.append(lv * 100 if lv <= 2 else (10000 if lv >= 41 else 500 + (lv - 3) * 250))
    b = [bcd3(v) for v in vals]
    lines = ["", "; Chain bonus by chain level (0-41), BCD, high byte first."]
    for k, name in enumerate(("chainb2", "chainb1", "chainb0")):
        lines.append(name)
        for i in range(0, 42, 14):
            lines.append("  .byte " + ",".join(f"${x[k]:02X}" for x in b[i:i + 14]))
    return lines


# MegaGammaForce coordinates to ours: its playfield is 192 x 240, ours is
# 160 x 209 (y stored + 32).
ENEMY_TYPES = {"ET_DART": 1, "ET_SAUCER": 2, "ET_DRONE": 3, "ET_GUNSHIP": 4}
ENEMY_WIDTH = {"ET_GUNSHIP": 16}
COLOR_PAL = {"COL_RED": 4, "COL_BLUE": 5, "COL_YELLOW": 6, "COL_GRAY": 2}


def wave_table(consts):
    data = json.loads((MGF / "stage1_waves.json").read_text())["waves"]
    data = [w for w in data if w[1] in ENEMY_TYPES]
    cols = {k: [] for k in ("watl", "wath", "wtype", "wpal", "wx", "wdx", "wcount", "wgap", "wparam")}
    for at, typ, color, x, dx, count, gap, param in data:
        w = ENEMY_WIDTH.get(typ, 8)
        cols["watl"].append(at & 255)
        cols["wath"].append(at >> 8)
        cols["wtype"].append(ENEMY_TYPES[typ])
        cols["wpal"].append(COLOR_PAL[color])
        cols["wx"].append(max(0, min(159 - w, round(x * 160 / 192) - w // 2)))
        cols["wdx"].append(round(dx * 160 / 192) & 255)
        cols["wcount"].append(count)
        cols["wgap"].append(gap)
        if typ == "ET_SAUCER":  # weave half-width in pixels
            cols["wparam"].append(round(param * 160 / 192))
        else:  # the line where it stops or dives: MGF centre y -> our top + 32
            cols["wparam"].append(round(param * 209 / 240) + 32 - (16 if typ == "ET_GUNSHIP" else 8))
    consts.append(f"  const WAVES = {len(data)}")
    lines = ["", "; Stage 1 waves (MegaGammaForce waves.py, scaled). One array per field."]
    for name, vals in cols.items():
        lines.append(f"{name} .byte " + ",".join(str(v) for v in vals))
    return lines


def trig_tables():
    """cos8: cos of angle a (256 per turn) x 127, signed. atan32[t]: the
    angle (256 per turn) of a slope t/32, t = 0..32."""
    cos8 = [round(127 * math.cos(2 * math.pi * a / 256)) & 255 for a in range(256)]
    atan32 = [round(math.atan(t / 32) * 128 / math.pi) for t in range(33)]
    lines = ["", "; Trig: angles are 256 per turn, 0 = right, 64 = down.", "cos8"]
    for i in range(0, 256, 16):
        lines.append("  .byte " + ",".join(str(v) for v in cos8[i:i + 16]))
    lines.append("atan32 .byte " + ",".join(str(v) for v in atan32))
    return lines


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
    asm.append("; Playfield texts for pf_text: TXT_ numbers index these.")
    for i, (label, text) in enumerate(SCREEN_TEXTS.items()):
        asm.append(f"txt_{label} .byte " + ",".join(str(char_index(ch, font_base)) for ch in text) + f" ; {text!r}")
        consts.append(f"  const TXT_{label.upper()} = {i}")
    names = list(SCREEN_TEXTS)
    asm.append("txtlo .byte " + ",".join(f"<txt_{n}" for n in names[:8]))
    for i in range(8, len(names), 8):
        asm.append("  .byte " + ",".join(f"<txt_{n}" for n in names[i:i + 8]))
    asm.append("txthi .byte " + ",".join(f">txt_{n}" for n in names[:8]))
    for i in range(8, len(names), 8):
        asm.append("  .byte " + ",".join(f">txt_{n}" for n in names[i:i + 8]))
    asm.append("txtlen .byte " + ",".join(str(len(SCREEN_TEXTS[n])) for n in names))
    asm.append("")
    asm.append("; P0C1..P7C3, in register order")
    asm.append("palettedata")
    for i, p in enumerate(PAL_CODES):
        asm.append(f"  .byte " + ",".join(f"${c:02X}" for c in p) + f" ; P{i}")
    asm.append("")
    asm.append("; Sprite images. IMG_x = image number; imglo/imghi = graphics of the")
    asm.append("; first strip of frame 0; imgw = width in bytes; imgstrips = 16-line strips;")
    asm.append("; imgframes = frame count. Frame f of strip s is at (strip label) + f*w.")
    lo, hi, lo2, hi2, w, st, fr, hh = [], [], [], [], [], [], [], []
    for i, (name, wb, strips, frames, last_h) in enumerate(table):
        hh.append(str(last_h))
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
            "imgframes .byte " + ",".join(fr),
            "; lines used in the image's last strip (the plotter skips the part",
            "; of a strip that would only be empty lines)",
            "imgh .byte " + ",".join(hh),
            "; -width & 31, the width bits of a 4-byte header",
            "imgnegw .byte " + ",".join(str((-int(x)) & 31) for x in w), ""]
    asm += trig_tables()
    asm += chain_table()
    stage = ["; Generated by tools/gen_assets.py. Do not edit.",
             "; Stage 1's data, in its own ROM bank (switched in at $8000 for the stage)."]
    stage += wave_table(consts)
    for ch, name in ((" ", "SPACE"), ("X", "X"), ("I", "I"), ("H", "H"), ("Y", "Y"), ("P", "P"),
                     ("E", "E"), ("R", "R"), ("C", "C")):
        consts.append(f"  const CH_{name} = {char_index(ch, font_base)}")
    stage += stage_lines
    (GEN / "data.asm").write_text("\n".join(asm) + "\n")
    (GEN / "stage1.asm").write_text("\n".join(stage) + "\n")
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
