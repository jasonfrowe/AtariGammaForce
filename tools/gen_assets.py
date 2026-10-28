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
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
MGF = ASSETS / "mgf"
GFX = ROOT / "src" / "gfx"
GEN = ROOT / "src" / "gen"
PREVIEW = ROOT / "build" / "preview"

PAL7800 = [tuple(c) for c in json.loads((ROOT / "tools" / "a7800_ntsc_palette.json").read_text())["rgb"]]


def nearest(rgb):
    """The 7800 color byte closest to an RGB triple (weighted for the eye);
    a number is a 7800 color already."""
    if isinstance(rgb, int):
        return rgb
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
    [(52, 56, 72), (96, 104, 124), (240, 170, 40)],      # P2 deck detail, gray enemies: P1's dark and
                                                         # plate, and amber
    [(40, 60, 150), (170, 180, 200), (250, 250, 255)],   # P3 player: blue, silver, white
    [(100, 10, 20), (220, 40, 40), (255, 200, 150)],     # P4 red enemies: dark, red, glow
    [(10, 30, 110), (50, 120, 255), (190, 240, 255)],    # P5 blue enemies
    [(110, 60, 0), (240, 200, 0), (255, 255, 200)],      # P6 yellow enemies
    [0x58, 0x96, (255, 255, 255)],                       # P7 bullets: pink, sky blue (hues far apart:
                                                         # told apart at a glance), white; the sword
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
FONT_CHARS = "0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ<>%^_"  # x is drawn as X; ^ _ are up, down arrows
# Glyphs Astrowing's font doesn't have, 8 x 7 like it
EXTRA_GLYPHS = {
    "<": ["....11..", "...11...", "..11....", ".11.....", "..11....", "...11...", "....11.."],
    ">": ["..11....", "...11...", "....11..", ".....11.", "....11..", "...11...", "..11...."],
    "%": [".11...1.", ".11..11.", "....11..", "...11...", "..11....", ".11..11.", ".1...11."],
    "^": ["...11...", "..1111..", ".11..11.", "11....11", "........", "........", "........"],
    "_": ["........", "........", "........", "11....11", ".11..11.", "..1111..", "...11..."],
}

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


def font_glyphs():
    """Astrowing's 8-pixel glyphs (7 lines tall), placed on lines 9-15: the
    HUD's zone shows only those 7 lines (engine.asm pf_init), so MARIA reads
    the HUD 7 lines a frame instead of 16."""
    font = np.array(Image.open(ASSETS / "font_astrowing.png"))
    glyphs = []
    for i, ch in enumerate(FONT_CHARS):
        g = np.zeros((TILE_H, TILE_W), dtype=np.uint8)
        if ch in EXTRA_GLYPHS:
            src = np.array([[c == "1" for c in r] for r in EXTRA_GLYPHS[ch]])
        else:
            src = font[0:7, i * 8:(i + 1) * 8]
        g[9:16, :] = np.where(src > 0, 3, 0)  # one color: slot 3
        glyphs.append(g)
    return glyphs


# Every stage's character block starts with the font, so text (the HUD,
# messages) uses the same character numbers whichever stage is in; the
# stage's tiles follow it. Tile t is character 2 * (NFONT + t).
NFONT = len(FONT_CHARS)


def build_charset(label, t_slots, pal):
    sheet = np.concatenate(font_glyphs() + list(t_slots), axis=1)
    save_160a(GFX / f"{label}.png", sheet, PAL_CODES[pal])


TEXTS = {
    "hudinit": " SCORE 0000000   x3 ",
    "hudover": "GAMEOVER",
    "hudwarn": "WARNING",
    "hudstage": "STAGE ",
}


# Texts shown in the playfield (title, messages), up to 20 characters.
SCREEN_TEXTS = {
    "atari": "ATARI",
    "push": "PRESS FIRE",
    "b1": "B1 VULCAN  B2 SWORD",
    "credit": "2026 JASON ROWE",
    "over": "GAME OVER",
    "clear": "STAGE CLEAR",
    "escaped": "BOSS ESCAPED",
    "perfect": "PERFECT DESTRUCTION",
    # the stages' names (TXT_NAME1 + stage - 1), and the title's choice
    "name1": "SKY FORTRESS",
    "name2": "NEON SPIRES",
    "name3": "IRON TIDE",
    "name4": "SCORCHED SANDS",
    "sel1": "<   STAGE 1   >",
    "sel2": "<   STAGE 2   >",
    "sel3": "<   STAGE 3   >",
    "sel4": "<   STAGE 4   >",
    # the title's difficulty (TXT_MODE0 + easy): up and down choose
    "mode0": "^   NORMAL   _",
    "mode1": "^ TEDDY BEAR _",
}
# Playfield texts that are lines of RAM (20 characters, written by the
# game): the results screen's figures. Templates below fill them.
SCREEN_RAM = {"resa": 0x23A0, "resb": 0x23B4, "resc": 0x23C8}
# 16 shown of each 20-character RAM line (digits written by the game at
# rtline 12, 33 and 51)
RESULT_LINES = ["DESTRUCTION 000%    ", "MAX CHAIN    000    ", "BONUS      00000    "]
RESULT_LEN = 16


def char_index(ch, font_base=0):
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

# Palette for each sprite drawn in assets/art7800.txt
SPRITE_PAL = {"ship": 3, "vulcan": 3, "dart": 4, "saucer": 5, "drone": 6, "gunship": 2, "wasp": 4,
              "pinkbullet": 7, "bluebullet": 7, "needle": 7, "expl": 4, "turret": 4, "sword": 7,
              "hudcell0": 7, "hudcell1": 7, "hudgem": 4, "hudgem0": 3, "hudship": 3}

BOSS_SLOTS = {1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 2, 7: 1, 8: 2, 9: 3, 10: 3, 11: 3, 12: 1, 13: 1, 14: 2, 15: 2}

SPRITES = [
    # name, file, fw, fh, frames (None = all), slots, preview palette
    # "art" = drawn for the 7800 in assets/art7800.txt
    ("ship", "art", 0, 0, None, None, 3),
    ("vulcan", "art", 0, 0, None, None, 3),
    ("dart", "art", 0, 0, None, None, 4),
    ("saucer", "art", 0, 0, None, None, 5),
    ("drone", "art", 0, 0, None, None, 6),
    ("pinkbullet", "art", 0, 0, None, None, 7),
    ("needle", "art", 0, 0, None, None, 7),
    ("bluebullet", "art", 0, 0, None, None, 7),
    ("expl", "art", 0, 0, None, None, 4),
    ("gunship", "art", 0, 0, None, None, 2),
    ("turret", "art", 0, 0, None, None, 4),
    # Stage 2's own enemies (in its bank's graphics block)
    ("wasp", "art", 0, 0, None, None, 4),
    ("tank", "tank", 0, 0, None, None, 5),
    ("tower", "tower", 0, 0, None, None, 0),
    # SPIRE WARDEN, stage 2's boss (tools/boss7800.py), in its bank too
    ("b2coret", "boss2", 0, 0, None, None, 0),
    ("b2coreb", "boss2", 0, 0, None, None, 0),
    ("b2pod", "boss2", 0, 0, None, None, 0),
    ("b2cannon", "boss2", 0, 0, None, None, 0),
    # Stage 3's: the gunboat, and LEVIATHAN's parts (in its bank)
    ("gunboat", "boss3", 0, 0, None, None, 5),
    ("b3bridget", "boss3", 0, 0, None, None, 0),
    ("b3bridgeb", "boss3", 0, 0, None, None, 0),
    ("b3reactor", "boss3", 0, 0, None, None, 0),
    ("b3gun", "boss3", 0, 0, None, None, 0),
    ("b3bay", "boss3", 0, 0, None, None, 0),
    # Stage 4's: the train, and DUNE WYRM's parts (in its bank)
    ("train", "boss4", 0, 0, None, None, 4),
    ("b4headt", "boss4", 0, 0, None, None, 0),
    ("b4headb", "boss4", 0, 0, None, None, 0),
    ("b4seg", "boss4", 0, 0, None, None, 0),
    ("b4tail", "boss4", 0, 0, None, None, 0),
    ("sword", "sword", 0, 0, None, None, 7),
    # GAMMA CORE, the stage 1 boss (tools/boss7800.py). Its 64-line parts are
    # top and bottom halves (the plotter does two strips).
    ("bcoret", "boss", 0, 0, None, None, 0),
    ("bcoreb", "boss", 0, 0, None, None, 0),
    ("bwinglt", "boss", 0, 0, None, None, 0),
    ("bwinglb", "boss", 0, 0, None, None, 0),
    ("bwingrt", "boss", 0, 0, None, None, 0),
    ("bwingrb", "boss", 0, 0, None, None, 0),
    ("bcannon", "boss", 0, 0, None, None, 0),
    ("bturret", "boss", 0, 0, None, None, 0),
    # The title logo (tools/logo7800.py), in palette 4, which the title
    # cycles (enemies don't use it there).
    ("logo_gamma", "logo", 0, 0, None, None, 4),
    ("logo_force", "logo", 0, 0, None, None, 4),
    # The HUD's sprites (engine.asm hud_sprites): the sword gauge's
    # segments, the chain's gems, the lives' fighter
    ("hudcell0", "art", 0, 0, None, None, 7),
    ("hudcell1", "art", 0, 0, None, None, 7),
    ("hudgem", "art", 0, 0, None, None, 4),
    ("hudgem0", "art", 0, 0, None, None, 3),
    ("hudship", "art", 0, 0, None, None, 3),
]
BOSS_PARTS = {e[0] for e in SPRITES if e[1] in ("boss", "boss2", "boss3", "boss4")} - {"gunboat", "train"}
# Sprites that live in stage 2's graphics block (its bank), by strip label
# (the wasp and the tank are in the last bank's sprite block: they don't fit)
STAGE2_SPRITES = {"tower", "b2coret", "b2coreb", "b2pod", "b2cannon"}
STAGE3_SPRITES = {"gunboat", "b3bridget", "b3bridgeb", "b3reactor", "b3gun"}
STAGE3_STRIPS = {"gunboat0", "gunboat1", "b3bridget0", "b3bridget1", "b3bridgeb0", "b3bridgeb1",
                 "b3reactor0", "b3reactor1", "b3gun"}  # (b3bay: in the last bank, no room here)
STAGE4_STRIPS = {"train0", "train1", "b4headt0", "b4headt1", "b4headb", "b4seg0", "b4seg1", "b4tail0", "b4tail1"}
STAGE2_STRIPS = {"tower0", "tower1", "b2coret0", "b2coret1", "b2coreb0", "b2coreb1", "b2pod0", "b2pod1",
                 "b2cannon0", "b2cannon1"}


def sword_frames():
    """The Radiant Sword: an arc over the ship, 24 pixels by 32 lines (48 x
    32 on screen). Blue edges (2), a white blade (3), and a pink glint (1)
    that runs along it from frame to frame."""
    frames = []
    W, H = 24, 32
    cx, cy = 11.75, 30.0      # arc centre in pixels/lines (visual x = 2 * px)
    for f in range(4):
        a = np.zeros((H, W), dtype=np.uint8)
        glint = math.pi * (0.15 + 0.7 * f / 3)
        for y in range(H):
            for x in range(W):
                dx, dy = (x - cx) * 2, (y - cy) * 1.0
                r = math.hypot(dx, dy)
                ang = math.atan2(-dy, dx)
                if not (0.05 < ang < math.pi - 0.05):
                    continue
                if 15.5 <= r < 23:
                    a[y, x] = 2
                if 17.5 <= r < 21.5:
                    a[y, x] = 3
                if 15.5 <= r < 23 and abs(ang - glint) < 0.14:
                    a[y, x] = 1
        frames.append(a)
    return frames


def tank_frames():
    """Stage 2's tank, seen from above as it drives along a road: treads
    top and bottom, a hull, and a turret whose barrel points one of eight
    ways (frame 0 down, then turning clockwise as the aim angle grows, as
    the ground turret's frames do). 8 pixels by 16 lines."""
    hull = ["........",
            "11111111",
            "31313131",
            "12222221",
            "12233221",
            "12333321",
            "12333321",
            "12233221",
            "12222221",
            "31313131",
            "11111111",
            "........"]
    base = np.array([[".123".index(c) for c in r] for r in hull] + [[0] * 8] * 4, dtype=np.uint8)
    dirs = [(0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1), (1, 0), (1, 1)]
    frames = []
    for dx, dy in dirs:
        a = base.copy()
        for t in range(1, 4):
            for ox in ((0, 1) if dx == 0 else (0,)):
                x = (3 if dx <= 0 else 4) + dx * t + ox
                for oy in ((0, 1) if dy == 0 else (0,)):
                    y = (5 if dy <= 0 else 6) + dy * 2 * t + oy
                    for yy in (y, y + (1 if dy > 0 else -1) if dy else y):
                        if 0 <= x < 8 and 0 <= yy < 16:
                            a[yy, x] = 3
        frames.append(a)
    return frames


def tower_frame():
    """Stage 2's obstacle: a neon tower seen from above, its roof (with a
    beacon) and below it the lit face it leans out over. 16 pixels by 32
    lines, in the neon palette (1 dark violet, 2 violet, 3 pink)."""
    a = np.zeros((32, 16), dtype=np.uint8)
    a[0:12, 0:16] = 1                    # roof, outlined
    a[1:11, 1:15] = 2
    a[1, 1:15] = 3                       # lit parapet
    a[1:11, 1] = 3
    a[4:8, 6:10] = 1                     # the beacon on its housing
    a[5:7, 7:9] = 3
    a[12:31, 1:15] = 1                   # the face, dark
    for y in range(13, 30, 4):           # bands of windows
        for x in range(2, 14, 3):
            a[y:y + 2, x:x + 2] = 3 if (x + y) % 7 else 2
    a[12:31, 0] = 1
    a[12:31, 15] = 1
    a[31, 1:15] = 1
    return a


def build_sprites():
    """Returns the image table: list of (label, width_bytes, strips)."""
    table = []
    incs = []
    previews = []
    for entry in SPRITES:
        name, fn, fw, fh, pick, slots, pal = entry[:7]
        rows = entry[7] if len(entry) > 7 else None
        flip = entry[8] if len(entry) > 8 else False
        if fn == "art":
            conv = ART[name]
        elif fn == "boss":
            import boss7800
            conv = boss7800.parts()[name]
        elif fn == "boss2":
            import boss7800
            conv = boss7800.parts2()[name]
        elif fn == "boss3":
            import boss7800
            conv = boss7800.parts3()[name]
        elif fn == "boss4":
            import boss7800
            conv = boss7800.parts4()[name]
        elif fn == "logo":
            import logo7800
            conv = [logo7800.words()[name]]
        elif fn == "sword":
            conv = sword_frames()
        elif fn == "tank":
            conv = tank_frames()
        elif fn == "tower":
            conv = [tower_frame()]
        elif fn is None:
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
        if name in BOSS_PARTS:
            # Boss parts count as full strips, so each always takes the
            # same number of display objects (see pf_plot in engine.asm).
            last_h = 16
        table.append((name, w // 4, strips, len(conv), max(1, last_h)))
        previews.append(preview(np.concatenate(conv, axis=1), PAL_CODES[pal], bg=(40, 0, 40)))
    return table, incs, previews


# ---------------------------------------------------------------------------
# Stage banks. Each stage has a ROM bank of its own, switched in at $8000
# for the whole stage. It starts with a header of fixed layout (STG below),
# so the engine and the BASIC read whichever stage is in through the same
# addresses: counts, colors, songs, then fixed-size tables (waves, ground
# units, tile palettes, row pointers). The map rows follow.
#
# A map row is stored as the characters of its used columns (col0 to
# col1-1; outside them is background) and the bytes of its background
# display list objects, ready to copy into a zone: one 5-byte indirect
# (character) object per run of tiles that share a palette. Rows that are
# the same are stored once.

MAX_RUNS = 6
MAX_ROWS = 208
MAX_WAVES = 40
MAX_GROUND = 40
MAX_TILES = 64
WAVE_FIELDS = ("watl", "wath", "wtype", "wpal", "wx", "wdx", "wcount", "wgap", "wparam")
GROUND_FIELDS = ("gtl", "gth", "gtx", "gtbase", "gtype", "gpal", "gparam")


def stg_layout():
    """name -> (offset from $8000, size) of the stage header's fields."""
    lay, off = {}, 0
    for name, size in (("stg_rows", 1), ("stg_loop", 1), ("stg_charbase", 1), ("stg_blank", 1),
                       ("stg_nwaves", 1), ("stg_nground", 1), ("stg_bg", 1), ("stg_pal", 9),
                       ("stg_song", 1), ("stg_bosssong", 1), ("stg_col0", 1), ("stg_col1", 1),
                       ("stg_number", 1), ("stg_bossat", 1)):
        lay[name] = (off, size)
        off += size
    off = 32
    for f in WAVE_FIELDS:
        lay[f] = (off, MAX_WAVES)
        off += MAX_WAVES
    for f in GROUND_FIELDS:
        lay[f] = (off, MAX_GROUND)
        off += MAX_GROUND
    for name, size in (("stg_rowlo", MAX_ROWS), ("stg_rowhi", MAX_ROWS), ("stg_rowshift", MAX_ROWS)):
        lay[name] = (off, size)
        off += size
    lay["stg_end"] = (off, 0)
    return lay


STG = stg_layout()


SPLIT_COL = 10   # the column at x 80, where a row's gap opens (pf_shiftx)


def row_runs(pals, split=None, drawn=None):
    """Runs of tiles that share a palette (and are drawn: drawn[c] false
    for background), at most MAX_RUNS."""
    runs = []
    for c, p in enumerate(pals):
        if drawn is not None and not drawn[c]:
            continue
        if runs and runs[-1][2] == p and c != split and runs[-1][0] + runs[-1][1] == c:
            runs[-1][1] += 1
        else:
            runs.append([c, 1, p])
    # Too many objects for one zone: fold the shortest run into a neighbor
    # it touches (taking the longer one's palette), never across the split.
    while len(runs) > MAX_RUNS:
        pairs = [a for a in range(len(runs) - 1) if runs[a + 1][0] != split
                 and runs[a][0] + runs[a][1] == runs[a + 1][0]]
        a = min(pairs, key=lambda k: min(runs[k][1], runs[k + 1][1]))
        keep = runs[a] if runs[a][1] >= runs[a + 1][1] else runs[a + 1]
        runs[a] = [runs[a][0], runs[a][1] + runs[a + 1][1], keep[2]]
        del runs[a + 1]
    return runs


def table(name, vals, size, per=16):
    """A table padded to its fixed size in the header."""
    assert len(vals) <= size, f"{name}: {len(vals)} entries, room for {size}"
    vals = list(vals) + [0] * (size - len(vals))
    out = [name]
    for i in range(0, size, per):
        out.append("  .byte " + ",".join(str(v) for v in vals[i:i + per]))
    return out


def stage_bank(st):
    """Assembly for a stage's bank. st: dict with
    n, map (rows x 20 tile numbers), t_pals, blank (tile numbers drawn as
    background), col0, col1, loop, charset (label), pals (P0-P2 codes),
    bg, song, bosssong, waves (field -> list), ground (field -> list)."""
    n, m, t_pals = st["n"], st["map"], st["t_pals"]
    rows = m.shape[0]
    assert rows <= MAX_ROWS
    col0, col1 = st["col0"], st["col1"]
    p = f"s{n}"
    first_tile_char = 2 * NFONT
    blank = st["blank"]
    assert all(int(t) in blank for r in m for c, t in enumerate(r) if not col0 <= c < col1), \
        "map tiles outside col0..col1 must be background"
    # Blank tiles must be the first ones (characters below stg_blank are
    # background), which tiles7800 arranges.
    assert blank == set(range(len(blank)))
    chars = lambda t: first_tile_char + 2 * int(t)  # noqa: E731
    assert len(t_pals) <= MAX_TILES
    shift = st.get("shift") or [(0, 0)] * rows

    lines = [f"; Generated by tools/gen_assets.py. Do not edit.",
             f"; Stage {n}'s bank: switched in at $8000 for the whole stage.",
             f"; The header has the same layout in every stage bank (STG_ consts).",
             f"stage{n}_header"]
    hdr = [rows, st["loop"], f">{st['charset']}", chars(len(blank)),
           len(st["waves"]["watl"]), len(st["ground"]["gtl"]), st["bg"]] + list(st["pals"]) + \
          [st["song"], st["bosssong"], col0, col1, n, st.get("bossat", 12)]
    lines.append("  .byte " + ",".join(str(v) for v in hdr))
    lines.append(f"  ds {32 - len(hdr)},0")
    for f in WAVE_FIELDS:
        lines += table(f"{p}_{f}", st["waves"][f], MAX_WAVES, per=20)
    for f in GROUND_FIELDS:
        lines += table(f"{p}_{f}", st["ground"][f], MAX_GROUND)

    # Rows: the same row is stored once.
    uniq, which = {}, []
    for r in range(rows):
        key = tuple(int(t) for t in m[r][col0:col1])
        if key not in uniq:
            uniq[key] = len(uniq)
        which.append(uniq[key])
    for part, op, lab in (("rowlo", "<", "o"), ("rowhi", ">", "o")):
        lines.append(f"{p}_{part}")
        for r in range(0, rows, 8):
            lines.append("  .byte " + ",".join(f"{op}{p}{lab}{which[k]}" for k in range(r, min(rows, r + 8))))
        if rows < MAX_ROWS:
            lines.append(f"  ds {MAX_ROWS - rows},0")
    # each row's shift: high nibble a signed whole-row shift in tiles, low
    # nibble a gap in tiles opened at x 80 (engine.asm pf_rowshift)
    for dx, gap in shift:
        assert -8 <= dx <= 7 and 0 <= gap <= 15
    lines += table(f"{p}_rowshift", [((dx & 15) << 4) | gap for dx, gap in shift], MAX_ROWS)
    lines.append(f"  if . - stage{n}_header != {STG['stg_end'][0]}")
    lines.append(f'    echo "ERROR: stage {n} header layout"')
    lines.append("    err")
    lines.append("  endif")
    lines.append("")
    lines.append("; Row u's characters: those of its runs of drawn tiles, one after the")
    lines.append("; other (2 bytes a tile: doublewide). Background tiles aren't drawn.")
    obj_lines = []
    max_bytes = 0
    for key, u in uniq.items():
        # background tiles are the background color: no objects
        runs = row_runs([t_pals[t] for t in key], split=SPLIT_COL - col0,
                        drawn=[t not in blank for t in key])
        packed, at = [], []
        for start, k, pal in runs:
            at.append(len(packed))
            packed += [chars(t) for t in key[start:start + k]]
        if packed:
            lines.append(f"{p}r{u} .byte " + ",".join(str(v) for v in packed))
        max_bytes = max(max_bytes, 5 * len(runs))
        obj_lines.append(f"{p}o{u} .byte {5 * len(runs)}")
        for (start, k, pal), off in zip(runs, at):  # one object a line: dasm allows 32 operators a line
            obj_lines.append(f"  .byte <({p}r{u}+{off}),$60,>({p}r{u}+{off}),{(pal << 5) | ((-k) & 31)},"
                             f"{(start + col0) * TILE_W}")
    lines.append("")
    lines.append("; Row u's background objects: a length byte, then the 5-byte headers.")
    lines += obj_lines
    return lines, max_bytes, len(uniq)


# Stage 1's map, rearranged from MegaGammaForce's (stage order, row 0 at the
# start): runs of its rows, in order. Its 32 rows of open sea at the start
# are cut to 14, so the first islet comes in within a second; the fortress's
# second half (rows 95-141, full-width deck at both ends, so the joins are
# seamless) is repeated, so the fortress runs on almost to the boss; then
# its tapering end, a little sea, and the 16-row boss loop. Same 208 rows.
STAGE1_RUNS = [(18, 141), (95, 141), (142, 162), (192, 207)]


def stage1_map():
    meta = json.loads((MGF / "stage1.json").read_text())
    cols, rows = meta["cols"], meta["rows"]
    src = np.frombuffer((MGF / "stage1_map.bin").read_bytes(), dtype=np.uint8).reshape(rows, cols)
    m = np.concatenate([src[a:b + 1] for a, b in STAGE1_RUNS])
    assert m.shape[0] == rows and STAGE1_RUNS[-1][1] - STAGE1_RUNS[-1][0] + 1 == meta["loop_rows"]
    return m


def stage1_ground():
    """The ground turrets (on the big hatches) moved with their rows, and
    repeated with a repeated run: (centre y up from the map's start, x in
    16-pixel tiles), in order of y."""
    g = json.loads((MGF / "stage1.json").read_text())["ground"]
    out, start = [], 0
    for a, b in STAGE1_RUNS:
        for y, c in g:
            r = y // 16 - 1                  # the hatch's lower row
            if a <= r and r + 1 <= b:
                out.append([(r - a + start + 1) * 16, c])
        start += b - a + 1
    return sorted(out)


def stg_consts():
    """The header's fields as BASIC dims (which the assembly sees too)."""
    out = ["  rem The stage header: the same addresses in every stage bank ($8000)."]
    for name, (off, _size) in STG.items():
        if name == "stg_end":
            continue
        out.append(f"  dim {name} = ${0x8000 + off:04X}")
    return out


def map_preview(m, t_slots, t_pals, rows=48, pals=None, bg=None):
    """The map's first rows (bottom of the stage at the bottom), in the
    stage's colors: pals = codes for P0-P2 (else the global ones)."""
    codes = list(PAL_CODES)
    if pals:
        codes[0:3] = pals
    bgrgb = rgb_of(bg if bg is not None else BG_CODE)
    n = min(rows, m.shape[0])
    img = Image.new("RGB", (160 * 2 * 2, n * 32))
    y = 0
    for r in range(n - 1, -1, -1):
        for c, t in enumerate(m[r]):
            tile = preview(t_slots[int(t)], codes[t_pals[int(t)]], scale=2, bg=bgrgb)
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
ENEMY_TYPES = {"ET_DART": 1, "ET_SAUCER": 2, "ET_DRONE": 3, "ET_GUNSHIP": 4, "ET_TURRET": 5,
               "ET_WASP": 6, "ET_TANK": 7, "ET_TOWER": 8, "ET_GUNBOAT": 9, "ET_TRAIN": 10}
ENEMY_WIDTH = {"ET_GUNSHIP": 16}
COLOR_PAL = {"COL_RED": 4, "COL_BLUE": 5, "COL_YELLOW": 6, "COL_GRAY": 2}


def wave_cols(data, scale=1.0):
    """MegaGammaForce air waves -> our wave table fields (their scroll
    positions times scale)."""
    data = [[round(w[0] * scale)] + list(w[1:]) for w in data if w[1] in ENEMY_TYPES]
    cols = {k: [] for k in WAVE_FIELDS}
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
        if typ in ("ET_SAUCER", "ET_WASP"):  # weave half-width in pixels
            cols["wparam"].append(round(param * 160 / 192))
        else:  # the line where it stops or dives: MGF centre y -> our top + 32
            cols["wparam"].append(round(param * 209 / 240) + 32 - (16 if typ == "ET_GUNSHIP" else 8))
    return cols


# ground units 32 lines tall: their y is 8 below their top (as for the
# 16-line ones), and they spawn 16 lines sooner
TALL_UNITS = ("ET_TOWER", "ET_GUNBOAT", "ET_TRAIN")


def ground_cols(units):
    """Ground units: (y up from the map's start, centre x in our pixels,
    type, palette, param) -> the ground table fields: when to spawn
    (scroll position), sprite x, the offset that puts the sprite at the
    right line for any scroll, type, palette, param."""
    cols = {k: [] for k in GROUND_FIELDS}
    def spawn(u):
        y, x, typ, pal, param = u
        if typ == "ET_TRAIN":
            # a train car's line is spos / 2 + 232 - y: in view (its top
            # line 0, 32 above the playfield) at spos = 2 (y - 232)
            return max(0, 2 * (y - 232))
        return max(0, y - 216 - (16 if typ in TALL_UNITS else 0))
    for u in sorted(units, key=spawn):
        y, x, typ, pal, param = u
        # Screen line of world height y is spos + 208 - y; the sprite's top
        # is 8 above its centre, stored + 32: eyh = spos + 232 - y.
        t = spawn(u)
        cols["gtl"].append(t & 255)
        cols["gth"].append(t >> 8)
        cols["gtx"].append(max(0, min(152, x - 4)))
        cols["gtbase"].append((232 - y) & 255)
        cols["gtype"].append(ENEMY_TYPES[typ])
        cols["gpal"].append(pal)
        cols["gparam"].append(param)
    return cols


def stage1():
    import tiles7800
    meta = json.loads((MGF / "stage1.json").read_text())
    t_slots, t_pals = tiles7800.tiles(meta["tile_ids"])
    waves = json.loads((MGF / "stage1_waves.json").read_text())["waves"]
    # ground turrets in red, blue, yellow by turns
    ground = [(y, c * 16 // 2, "ET_TURRET", 4 + k % 3, 0) for k, (y, c) in enumerate(stage1_ground())]
    return {"n": 1, "map": stage1_map(), "t_slots": t_slots, "t_pals": t_pals,
            "blank": {0, 1, 2, 3}, "col0": 4, "col1": 16, "loop": meta["loop_rows"],
            "charset": "charset", "pals": [c for p in PAL_CODES[0:3] for c in p], "bg": BG_CODE,
            "song": "SONG_STAGE1", "bosssong": "SONG_BOSS",
            "waves": wave_cols(waves), "ground": ground_cols(ground)}


# Stage 2, NEON SPIRES: the city. Its colors: the night (the asphalt is
# the background), P0 neon (the boss's too), P1 roofs, P2 the roofs' dark
# and plate with amber (lights, signs; the gunship uses P2 here).
STAGE2_BG = (8, 10, 30)
STAGE2_PALETTES = [
    [(41, 0, 110), (111, 49, 168), (216, 140, 209)],     # P0 neon: dark violet, violet, pink-violet
    [(36, 32, 56), (86, 80, 116), (156, 148, 190)],      # P1 roofs
    [(36, 32, 56), (86, 80, 116), (250, 170, 40)],       # P2 roof dark and plate, amber
]
# The districts (8-row blocks of stage2_blocks.bin) in stage order: each
# of the eight three times or so, then the boss loop.
STAGE2_ORDER = [0, 1, 2, 3, 4, 6, 7, 2, 1, 5, 0, 5, 3, 6, 1, 4, 6, 3, 7, 0, 5, 0, 4, 7]
WAVES_END_2 = 2950   # MegaGammaForce's stage 2: no ground units past this
# The city winds: each district's (shift, gap) in tiles (engine.asm
# pf_rowshift). The shift moves the whole block left or right; the gap
# splits it at its middle (x 80), the right half moving on by the gap, so
# the city parts around a dark channel. Only districts 0 and 5 split: their
# avenue runs down that column, so they part along a street, not through
# buildings. The right edge stays on screen: shift + gap <= 4.
STAGE2_SHIFT = [(0, 0), (-1, 0), (-2, 0), (-3, 0), (-4, 0), (-4, 0), (-3, 0), (-4, 0),
                (-4, 0), (-4, 8), (-4, 8), (-4, 8), (-2, 0), (0, 0), (2, 0), (4, 0),
                (3, 0), (1, 0), (-2, 0), (-4, 8), (-4, 8), (-4, 8), (-2, 0), (0, 0)]
assert all(STAGE2_ORDER[k] in (0, 5) for k, (_, gap) in enumerate(STAGE2_SHIFT) if gap)


def stage2_plaza(ids, lut, rows):
    """The boss's arena (the stage's last rows, which loop): a dark plaza
    between two avenues, crossed by a street every 8 rows, with a few
    lamps. Mostly background, so MARIA has little to draw under the boss
    (a city block there costs it most of the fight's frame rate)."""
    m = np.zeros((rows, 20), dtype=np.uint8)
    rh, rv, cross, lamp = lut[ids["rh0"]], lut[ids["rv0"]], lut[ids["cross"]], lut["lamp"]
    lamps = {2: (7, 12), 5: (9,), 10: (6, 13), 13: (10,)}
    for r in range(rows):
        if r % 8 == 0:
            m[r, 4:16] = rh
            m[r, 4] = m[r, 15] = cross
        else:
            m[r, 4] = m[r, 15] = rv
            for c in lamps.get(r, ()):
                m[r, c] = lamp
    return m


def stage2():
    import tiles7800
    meta = json.loads((MGF / "stage2.json").read_text())
    cols, br = meta["cols"], meta["block_rows"]
    t_slots, t_pals, lut = tiles7800.city_tiles(meta["tile_ids"])
    blocks = np.frombuffer((MGF / "stage2_blocks.bin").read_bytes(), dtype=np.uint8).reshape(-1, cols)
    loop = np.frombuffer((MGF / "stage2_loop.bin").read_bytes(), dtype=np.uint8).reshape(-1, cols)
    city = np.concatenate([blocks[b * br:(b + 1) * br] for b in STAGE2_ORDER])
    rows = city.shape[0] + len(loop)
    m = np.zeros((rows, 20), dtype=np.uint8)
    m[:city.shape[0], 4:16] = np.vectorize(lambda t: lut[int(t)])(city)
    m[city.shape[0]:] = stage2_plaza(meta["tile_ids"], lut, len(loop))
    shift = [STAGE2_SHIFT[r // br] for r in range(city.shape[0])] + [(0, 0)] * len(loop)

    def sx(x, r):
        """A city x (our pixels, unshifted) at map row r, shifted."""
        dx, gap = shift[r]
        return x + dx * 8 + (gap * 8 if x >= 80 else 0)

    # Ground units, by MegaGammaForce's rules (stages.py stage2): guns on
    # three pads in four, tanks on three roads in eight, alternating
    # directions. x: MegaGammaForce pixels halved, the city starts at our x 32.
    pads = []
    for k, b in enumerate(STAGE2_ORDER):
        for r, c in meta["pads"]:
            if b * br <= r < (b + 1) * br:
                pads.append((k * br + r - b * br, c))
    units = []
    for i, (r, c) in enumerate(p for k, p in enumerate(sorted(pads)) if k % 4 != 3):
        y = (r + 1) * 16
        if 300 < y < WAVES_END_2:
            units.append((y, sx(32 + (c + 1) * 8, r), "ET_TURRET", 4 + i % 3, 0))
    k = 0
    for band in range(len(STAGE2_ORDER)):
        r = band * br
        y = r * 16 + 8
        if y < 500 or y > WAVES_END_2 - 100 or band % 8 not in (0, 3, 5) or shift[r][1]:
            continue  # (no tanks on a split road: they'd drive into the channel)
        left = k % 2 == 1
        x = sx(124, r) if left else sx(36, r)
        units.append((y, x, "ET_TANK", 4 + (k // 3) % 3, (0x80 if left else 0) | 10))
        k += 1

    # Towers: obstacles on rooftops (2 x 2 tiles of plain roof), every other
    # district from the third, on alternate sides of the city.
    names = {v: k for k, v in meta["tile_ids"].items()}
    for n, k in enumerate(range(2, len(STAGE2_ORDER) - 1, 2)):
        r0 = k * br
        side = range(0, 5) if n % 2 == 0 else range(7, 11)
        spot = next(((r, c) for r in range(r0 + 2, r0 + 6) for c in side
                     if all(names[int(city[rr, cc])].startswith("roof")
                            for rr in (r, r + 1) for cc in (c, c + 1))), None)
        if spot:
            r, c = spot
            units.append(((r + 2) * 16 - 8, sx(32 + c * 8, r) + 4, "ET_TOWER", 0, 0))

    return {"n": 2, "map": m, "t_slots": t_slots, "t_pals": t_pals, "shift": shift,
            "blank": {0}, "col0": 4, "col1": 16, "loop": meta["loop_rows"],
            "charset": "charset2", "pals": [nearest(c) for p in STAGE2_PALETTES for c in p],
            "bg": nearest(STAGE2_BG), "song": "SONG_STAGE2", "bosssong": "SONG_BOSS2",
            "waves": wave_cols(meta["waves"]), "ground": ground_cols(units),
            "pal_codes": [[nearest(c) for c in p] for p in STAGE2_PALETTES]}


# Stage 3, IRON TIDE: the open ocean (the background), islands, and
# LEVIATHAN's hull, which is part of the map: the scroll brings it in, crawls
# while it closes, stops, and runs on to carry it away as it sinks (open
# sea shows no movement, so only the ship seems to move).
STAGE3_BG = (10, 40, 96)
STAGE3_PALETTES = [
    [(34, 40, 52), (150, 160, 178), (210, 60, 40)],      # P0 the boss: dark steel, steel, naval red
    [(40, 44, 56), (96, 104, 120), (164, 172, 188)],     # P1 steel: the hull, the bunkers
    [(24, 60, 30), (60, 130, 50), (210, 190, 130)],      # P2 islands: shade, jungle, sand
]
STAGE3_ORDER = [0, 1, 2, 3, 1]       # island chunks (30 rows each)
STAGE3_GAP = 16                      # open sea before the ship
HULL_COL = 5                         # the hull's left column (10 wide, centred)


def stage3():
    import tiles7800
    meta = json.loads((MGF / "stage3.json").read_text())
    cols, cr = meta["cols"], meta["chunk_rows"]
    i_tiles, i_pals, i_lut = tiles7800.island_tiles(meta["tile_ids"])
    h_tiles, h_pals, h_lut, h_clear = tiles7800.hull_tiles(meta["hull_tile_ids"])
    base = len(i_tiles)
    t_slots, t_pals = i_tiles + h_tiles, i_pals + h_pals
    chunks = np.frombuffer((MGF / "stage3_chunks.bin").read_bytes(), dtype=np.uint8).reshape(-1, cols).copy()
    ids = meta["tile_ids"]
    land = {ids["land1"], ids["land2"]}
    # More bunkers: on solid land, now and then, apart from each other.
    bunkers = [tuple(b) for b in meta["bunkers"]]
    for k in range(meta["chunks"]):
        for r in range(k * cr + 1, (k + 1) * cr - 2):
            for c in range(cols - 1):
                if all(int(chunks[r + dy, c + dx]) in land for dy in (0, 1) for dx in (0, 1)) and \
                        all(abs((bk * cr + br) - r) > 4 or abs(bc - c) > 3 for bk, br, bc in bunkers) and \
                        (r * 7 + c * 3) % 5 == 0:
                    chunks[r + 1, c], chunks[r + 1, c + 1] = ids["bunker0"], ids["bunker1"]
                    chunks[r, c], chunks[r, c + 1] = ids["bunker2"], ids["bunker3"]
                    bunkers.append((k, r - k * cr, c))
    body = np.concatenate([chunks[k * cr:(k + 1) * cr] for k in STAGE3_ORDER])
    hull = np.frombuffer((MGF / "stage3_hull.bin").read_bytes(), dtype=np.uint8).reshape(meta["hull_h"], meta["hull_w"])
    hh, hw = hull.shape
    loop = 16
    rows = body.shape[0] + STAGE3_GAP + hh + loop
    assert rows == 208, rows
    m = np.zeros((rows, 20), dtype=np.uint8)
    m[:body.shape[0], :] = np.vectorize(lambda t: i_lut[int(t)])(body)
    bow = body.shape[0] + STAGE3_GAP                 # the hull's first row (its bow)
    stern = bow + hh - 1
    for r in range(hh):                              # hull row r (from the stern) is map row stern - r
        for c in range(hw):
            t = int(hull[r, c])
            if t != h_clear:
                m[stern - r, HULL_COL + c] = base + h_lut[t]

    # Ground units: turrets on the bunkers, gunboats in open water.
    units = []
    for i, (k, r, c) in enumerate(sorted(bunkers)):
        for n, kk in enumerate(STAGE3_ORDER):
            if kk == k:
                y = (n * cr + r + 1) * 16
                units.append((y, (c + 1) * 8, "ET_TURRET", 4 + (i + n) % 3, 0))
    # A gunboat sails up the map (en_update) some 5 rows while it is on the
    # screen: open sea all along its way, or it is moved to the nearest
    # column that has it, or left out.
    def sea_ahead(row, c):
        win = body[max(0, row - 2):row + 8, c:c + 2]
        return win.shape[1] == 2 and bool((win <= ids["sea3"]).all())
    for j, (k, r, c) in enumerate(meta["water"]):
        for n, kk in enumerate(STAGE3_ORDER):
            if kk == k and (n + j) % 2 == 0:
                y = (n * cr + r) * 16 + 16           # (32 tall: 8 below its top)
                if 500 < y:
                    row = n * cr + r
                    for c2 in sorted(range(cols - 1), key=lambda x: abs(x - c)):
                        if abs(c2 - c) <= 4 and sea_ahead(row, c2):
                            units.append((y, c2 * 8, "ET_GUNBOAT", 4 + (j // 2) % 3, 0))
                            break

    # The ship's numbers for its boss code: where each part is (x, and the
    # world height of its top edge: a sprite's line is spos + 240 - it),
    # and the scroll positions where the fight starts (the hull's middle a
    # little below the top), where the ship stops (the reactor in reach),
    # and where it has sunk away (its stern below the screen).
    parts = meta["hull_parts"]
    def top(name, dy=0):
        c, r, w, h = parts[name]
        return (stern - r + 1) * 16 - dy
    hull_mid = (bow * 16 + (stern + 1) * 16) // 2
    reactor_mid = top("REACTOR") - 16
    b3 = {
        "b3_fight": hull_mid - 208 + 14,
        "b3_final": reactor_mid - 208 + 66,
        "b3_gone": (stern + 1) * 16 + 8,
    }
    # slots: 0-1 main guns, 2-3 the bridge (top, bottom), 4 and 6 the
    # missile bays (over their hull tiles), 5 the reactor, 7-10 deck
    # turrets (the bow's and the stern's: ground turrets, 10 lines tall,
    # set 3 lines down to sit in the middle of their sockets)
    slot = {0: ("GUN_A", 0, 2), 1: ("GUN_B", 0, 2), 2: ("BRIDGE", 0, 0), 3: ("BRIDGE", 32, 0),
            4: ("BAY_L", 0, 0), 5: ("REACTOR", 0, 0), 6: ("BAY_R", 0, 0),
            7: ("TUR0", 3, 0), 8: ("TUR1", 3, 0), 9: ("TUR4", 3, 0), 10: ("TUR5", 3, 0)}
    xs, ylo, yhi = [], [], []
    for k in range(11):
        if k in slot:
            name, dy, dx = slot[k]
            xs.append(8 * (HULL_COL + parts[name][0]) + dx)
            y = top(name, dy)
        else:
            xs.append(0)
            y = 0
        ylo.append(y & 255)
        yhi.append(y >> 8)
    bays = [(8 * (HULL_COL + parts[b][0]), top(b)) for b in ("BAY_L", "BAY_R")]
    b3_asm = ["; Generated by tools/gen_assets.py. Do not edit.",
              "; LEVIATHAN's parts: x, and the world height of each one's top (lo, hi)."]
    b3_asm.append("b3_x .byte " + ",".join(str(v) for v in xs))
    b3_asm.append("b3_ylo .byte " + ",".join(str(v) for v in ylo))
    b3_asm.append("b3_yhi .byte " + ",".join(str(v) for v in yhi))
    b3_asm.append("b3_bayx .byte " + ",".join(str(x) for x, _ in bays))
    b3_asm.append("b3_bayylo .byte " + ",".join(str(y & 255) for _, y in bays))
    b3_asm.append("b3_bayyhi .byte " + ",".join(str(y >> 8) for _, y in bays))
    for name, v in b3.items():
        b3_asm.append(f"{name.upper()} = {v}")
    (GEN / "boss3tab.asm").write_text("\n".join(b3_asm) + "\n")

    # the warning when the bow is about 9 rows above the screen
    bossat = (bow * 16 - 208 - 144) >> 8
    return {"n": 3, "map": m, "t_slots": t_slots, "t_pals": t_pals,
            "blank": {0}, "col0": 0, "col1": 20, "loop": loop,
            "charset": "charset3", "pals": [nearest(c) for p in STAGE3_PALETTES for c in p],
            "bg": nearest(STAGE3_BG), "song": "SONG_STAGE3", "bosssong": "SONG_BOSS3", "bossat": bossat,
            "waves": wave_cols(stage3_waves(meta["waves"]), 0.8), "ground": ground_cols(units),
            "pal_codes": [[nearest(c) for c in p] for p in STAGE3_PALETTES]}


def stage3_waves(waves):
    """MegaGammaForce's stage 3 waves, with its last two gunships (at 2720
    and 2750, just before LEVIATHAN: here the ship comes in with the map,
    without waiting for a clear sky, so there was no time to shoot them
    down) brought forward, between the wasps and the darts."""
    moved = {2720: 2420, 2750: 2450}
    out = [[moved.get(w[0], w[0])] + list(w[1:]) if w[1] == "ET_GUNSHIP" else list(w) for w in waves]
    return sorted(out, key=lambda w: w[0])


# Stage 4, SCORCHED SANDS: the desert (the sand is the background), rock
# plateaus with bunkers, oases to the west, and a railway up the right
# side, which armored trains drive along. Its boss, DUNE WYRM, is a chain
# of sprites winding a figure of eight.
STAGE4_BG = (196, 140, 72)
STAGE4_PALETTES = [
    [0x10, 0x1E, 0x34],                                  # P0 the wyrm: dark, bone, the maw's glow
                                                         # (7800 colors: nearest() misses bone)
    [(84, 48, 26), (140, 96, 66), (240, 206, 140)],      # P1 rock: shadow, rock, sunlit sand
    [(60, 110, 40), (40, 120, 150), (150, 220, 210)],    # P2 oasis: palm green, water, glint
]
STAGE4_ORDER = [0, 1, 2, 3, 1, 2]    # desert chunks (32 rows each)
WAVES_END_4 = 2950                   # no turrets past this (MegaGammaForce's)
# DUNE WYRM: slots 0 the tail, 1-8 the body (8 nearest the head), 9-10 the
# head (top, bottom). Each follows the head's path B4_GAP frames behind the
# one before it. The path: x = 80 + 52 sin(t), y = 107 + 75 sin(t / 2).
B4_GAP = 11


def boss4_tables():
    lines = ["; Generated by tools/gen_assets.py. Do not edit.",
             "; DUNE WYRM's path: the centre x by t & 255, its line (+ 32) by (t / 2) & 255;",
             "; each slot's lag behind the head (frames) and offset from its centre."]
    px = [round(80 + 52 * math.sin(2 * math.pi * i / 256)) for i in range(256)]
    # the line: from 64 (the head's top just under the HUD) to 214 (its
    # bottom at the foot of the screen, where the ship flies)
    py = [round(32 + 107 + 75 * math.sin(2 * math.pi * i / 256)) for i in range(256)]
    for name, vals in (("b4px", px), ("b4py", py)):
        lines.append(name)
        for i in range(0, 256, 16):
            lines.append("  .byte " + ",".join(str(v) for v in vals[i:i + 16]))
    lag = [(9 - k) * B4_GAP for k in range(9)] + [0, 0]
    dx = [(-8) & 255] * 9 + [(-12) & 255] * 2
    dy = [(-16) & 255] * 9 + [(-24) & 255, 8]
    lines.append("b4lag .byte " + ",".join(str(v) for v in lag))
    lines.append("b4dx .byte " + ",".join(str(v) for v in dx))
    lines.append("b4dy .byte " + ",".join(str(v) for v in dy))
    (GEN / "boss4tab.asm").write_text("\n".join(lines) + "\n")


def stage4():
    import tiles7800
    meta = json.loads((MGF / "stage4.json").read_text())
    cols, cr, rail = meta["cols"], meta["chunk_rows"], meta["rail"]
    t_slots, t_pals, lut = tiles7800.desert_tiles(meta["tile_ids"])
    chunks = np.frombuffer((MGF / "stage4_chunks.bin").read_bytes(), dtype=np.uint8).reshape(-1, cols)
    body = np.concatenate([chunks[k * cr:(k + 1) * cr] for k in STAGE4_ORDER])
    loop = 16
    rows = body.shape[0] + loop
    assert rows == 208, rows
    m = np.zeros((rows, 20), dtype=np.uint8)
    m[:body.shape[0], :] = np.vectorize(lambda t: lut[int(t)])(body)
    rail_ids = [lut[meta["tile_ids"]["rail0"]], lut[meta["tile_ids"]["rail1"]]]
    m[body.shape[0]:, rail:rail + 2] = rail_ids          # the boss's arena: sand and the railway

    units = []
    # Turrets on the bunkers (rows r, r + 1 of their chunk)
    i = 0
    for n, k in enumerate(STAGE4_ORDER):
        for kk, r, c in sorted(meta["bunkers"]):
            if kk == k:
                y = (n * cr + r + 1) * 16
                if 300 < y < WAVES_END_4:
                    units.append((y, (c + 1) * 8, "ET_TURRET", 4 + i % 3, 0))
                    i += 1
    # Armored trains: a locomotive (param 0) and two gun cars (1), one
    # color a train, heading up the track. y: a car's centre + 8 (its top
    # is 16 above its centre; ground units' y is 8 below their top).
    # A car's line is spos / 2 + its base (objects.asm en_update): every
    # car of a train moves together however late it spawned. y here is the
    # car's world height at spos 0 (ground_cols); the locomotive comes into
    # view near scroll y0 - 232, its cars 32 lines behind it.
    for k, y0 in enumerate((700, 1500, 2300)):
        loco = (y0 - 232) // 2 + 232
        for car in range(3):
            units.append((loco - car * 32, rail * 8 + 4, "ET_TRAIN", 4 + k % 3, 0 if car == 0 else 1))
    boss4_tables()
    return {"n": 4, "map": m, "t_slots": t_slots, "t_pals": t_pals,
            "blank": {0}, "col0": 0, "col1": 20, "loop": loop,
            "charset": "charset4", "pals": [nearest(c) for p in STAGE4_PALETTES for c in p],
            "bg": nearest(STAGE4_BG), "song": "SONG_STAGE4", "bosssong": "SONG_BOSS4",
            "waves": spread_waves(wave_cols(meta["waves"]), ground_cols(units)), "ground": ground_cols(units),
            "pal_codes": [[nearest(c) for c in p] for p in STAGE4_PALETTES]}


# What a unit costs the frame, roughly, for spread_waves: train cars and
# gunships are tall (3 objects or more), saucers fire rings of 8
UNIT_WEIGHT = {"ET_TRAIN": 3, "ET_GUNSHIP": 3, "ET_GUNBOAT": 3, "ET_SAUCER": 2}


def spread_waves(w, gr, cap=11, life=260, step=20, most=300, weights=None):
    """Air waves moved later (never earlier, in order, at most `most`
    pixels) where they would pile up: a rough load of the units on the
    screen (each about `life` pixels of scroll, ground units included,
    each 1 or, with weights=UNIT_WEIGHT, by kind) is kept to `cap` if
    moving a wave can do it. (Stage 4 measured best unweighted, cap 11.)"""
    weight = {ENEMY_TYPES[k]: v for k, v in (weights or {}).items()}
    ground = [((h << 8) | l, weight.get(t, 1)) for l, h, t in zip(gr["gtl"], gr["gth"], gr["gtype"])]
    ats = [(h << 8) | l for l, h in zip(w["watl"], w["wath"])]
    placed = []
    def load(x, extra):
        evs = ground + placed + [extra]
        return max(sum(c for a, c in evs if a <= y < a + life) for y in range(x, x + life, 20))
    prev = 0
    for at, n, t in zip(ats, w["wcount"], w["wtype"]):
        count = n * weight.get(t, 1)
        x0 = max(at, prev)
        best = x0
        for x in range(x0, at + most + 1, step):
            if load(x, (x, count)) <= cap:
                best = x
                break
        else:
            best = min(range(x0, at + most + 1, step), key=lambda x: load(x, (x, count)))
        placed.append((best, count))
        prev = best
    out = dict(w)
    out["watl"] = [a & 255 for a, _ in placed]
    out["wath"] = [a >> 8 for a, _ in placed]
    return out


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


import art7800  # noqa: E402
ART = art7800.load()


def main():
    GFX.mkdir(parents=True, exist_ok=True)
    GEN.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)

    font_base = 0
    stages = [stage1(), stage2(), stage3(), stage4()]
    build_charset("charset", stages[0]["t_slots"], 1)
    for st in stages[1:]:
        build_charset(st["charset"], st["t_slots"], 1)
    table, incs, previews = build_sprites()
    max_bg = 0
    for st in stages:
        lines, mb, nuniq = stage_bank(st)
        max_bg = max(max_bg, mb)
        (GEN / f"stage{st['n']}.asm").write_text("\n".join(lines) + "\n")
        print(f"stage {st['n']}: {st['map'].shape[0]} rows ({nuniq} different), "
              f"{len(st['waves']['watl'])} waves, {len(st['ground']['gtl'])} ground units")

    # gfx.bas: the character block first (stage 1's: the font, then its
    # tiles). The title logo, LEVIATHAN's bays and the HUD's gauge and gems
    # fill the character block's spare room (the sprite block is full).
    in_chars = [n for n in incs if n.startswith(("logo_", "b3bay", "hudcell", "hudgem"))]
    bas = ["  rem Generated by tools/gen_assets.py. Do not edit.",
           "  incgraphic gfx/charset.png 160A 0 1 2 3"]
    bas += [f"  incgraphic gfx/{n}.png 160A 0 1 2 3" for n in in_chars]
    bas += ["  newblock"]
    bas += [f"  incgraphic gfx/{n}.png 160A 0 1 2 3" for n in incs
            if n not in in_chars and n not in STAGE2_STRIPS | STAGE3_STRIPS | STAGE4_STRIPS]
    (GEN / "gfx.bas").write_text("\n".join(bas) + "\n")
    # gfxN.bas: stage N's graphics block, in its bank at $A000: the font
    # and the stage's tiles, then its own sprites.
    for n, strips in ((2, STAGE2_STRIPS), (3, STAGE3_STRIPS), (4, STAGE4_STRIPS)):
        bn = ["  rem Generated by tools/gen_assets.py. Do not edit.",
              f"  incgraphic gfx/charset{n}.png 160A 0 1 2 3"]
        bn += [f"  incgraphic gfx/{s}.png 160A 0 1 2 3" for s in incs if s in strips]
        (GEN / f"gfx{n}.bas").write_text("\n".join(bn) + "\n")

    consts = ["  rem Generated by tools/gen_assets.py. Do not edit.",
              "  rem Constants shared by BASIC and the assembly (const lands in both)."]
    asm = ["; Generated by tools/gen_assets.py. Do not edit.", ""]
    consts.append(f"  const BGCOLOR = ${BG_CODE:02X}")
    consts.append(f"  const FONTBASE = {2 * font_base}")
    consts.append(f"  const BGMAXBYTES = {max_bg}")
    consts.append(f"  const NFONTCHARS = {2 * NFONT}")
    consts += stg_consts()
    asm.append("; FONTBASE is the character index of '0'; ' ' is +20, 'A' is +22.")
    asm.append("; Text strings, as character indices.")
    for label, text in TEXTS.items():
        asm.append(f"{label} .byte " + ",".join(str(char_index(ch, font_base)) for ch in text) + f" ; {text!r}")
    asm.append("; Playfield texts for pf_text: TXT_ numbers index these.")
    for i, (label, text) in enumerate(SCREEN_TEXTS.items()):
        asm.append(f"txt_{label} .byte " + ",".join(str(char_index(ch, font_base)) for ch in text) + f" ; {text!r}")
        consts.append(f"  const TXT_{label.upper()} = {i}")
    for i, (label, addr) in enumerate(SCREEN_RAM.items()):
        asm.append(f"txt_{label} = ${addr:04X} ; a RAM line")
        consts.append(f"  const TXT_{label.upper()} = {len(SCREEN_TEXTS) + i}")
    asm.append("; the results lines' templates, copied into their RAM lines")
    asm.append("restmpl .byte " + ",".join(str(char_index(ch, font_base)) for ch in RESULT_LINES[0]))
    for line in RESULT_LINES[1:]:
        asm.append("  .byte " + ",".join(str(char_index(ch, font_base)) for ch in line))
    lens = {**{k: len(v) for k, v in SCREEN_TEXTS.items()}, **{k: RESULT_LEN for k in SCREEN_RAM}}
    names = list(SCREEN_TEXTS) + list(SCREEN_RAM)
    asm.append("txtlo .byte " + ",".join(f"<txt_{n}" for n in names[:8]))
    for i in range(8, len(names), 8):
        asm.append("  .byte " + ",".join(f"<txt_{n}" for n in names[i:i + 8]))
    asm.append("txthi .byte " + ",".join(f">txt_{n}" for n in names[:8]))
    for i in range(8, len(names), 8):
        asm.append("  .byte " + ",".join(f">txt_{n}" for n in names[i:i + 8]))
    asm.append("txtlen .byte " + ",".join(str(lens[n]) for n in names))
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
    for ch, name in ((" ", "SPACE"), ("X", "X"), ("I", "I"), ("H", "H"), ("Y", "Y"), ("P", "P"), ("0", "0"),
                     ("E", "E"), ("R", "R"), ("C", "C")):
        consts.append(f"  const CH_{name} = {char_index(ch, font_base)}")
    (GEN / "data.asm").write_text("\n".join(asm) + "\n")
    # Stage 2's boss: its pods' orbit (29 pixels across, 35 lines up and
    # down), as each pod's top-left offset from the centre, by angle / 2.
    ox = [(round(29 * math.cos(2 * math.pi * i / 128)) - 8) & 255 for i in range(128)]
    oy = [(round(35 * math.sin(2 * math.pi * i / 128)) - 16) & 255 for i in range(128)]
    b2 = ["; Generated by tools/gen_assets.py. Do not edit.",
          "; SPIRE WARDEN's pods: top-left offset from the boss centre by orbit angle / 2."]
    for name, vals in (("orb2x", ox), ("orb2y", oy)):
        b2.append(name)
        for i in range(0, 128, 16):
            b2.append("  .byte " + ",".join(str(v) for v in vals[i:i + 16]))
    (GEN / "boss2tab.asm").write_text("\n".join(b2) + "\n")
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
    for st in stages:
        map_preview(st["map"], st["t_slots"], st["t_pals"], pals=st.get("pal_codes"),
                    bg=st["bg"] if st["n"] > 1 else None).save(PREVIEW / f"stage{st['n']}_map.png")
    print(f"BG ${BG_CODE:02X}; palettes " + " ".join("/".join(f"{c:02X}" for c in p) for p in PAL_CODES))
    print(f"{len(incs)} sprite strips; largest row background {max_bg} bytes")


if __name__ == "__main__":
    main()
