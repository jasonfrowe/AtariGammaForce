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
    "name5": "FROZEN STRAIT",
    "name6": "ASCENT",
    "name7": "SEA OF TRANQUILITY",
    "name8": "DEEP FIELD",
    "name9": "CORONA",
    # (copied into a RAM line, its digit changed: SCREEN_RAM's sel)
    "sel1": "<   STAGE 1   >",
    # the title's difficulty (TXT_MODE0 + easy): up and down choose
    "mode0": "^   EXPERT   _",
    "mode1": "^   NORMAL   _",
    "mode2": "^ TEDDY BEAR _",
}
# Playfield texts that are lines of RAM (20 characters, written by the
# game): the results screen's figures. Templates below fill them.
SCREEN_RAM = {"resa": 0x23A0, "resb": 0x23B4, "resc": 0x23C8, "sel": 0x23A0}
# Playfield texts kept in stage 9's bank (shown only while it is in: the
# ending, after GAMMA PRIME), to spare the fixed bank.
BANK9_TEXTS = {"end1": "ALL CLEAR", "end2": "GAMMA CORE IS DEAD", "end3": "THE SUN BURNS CLEAN"}
# their lengths shown (the title's stage choice, in resa's RAM, is shorter)
SCREEN_RAM_LEN = {"sel": len(SCREEN_TEXTS["sel1"])}
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
    # Stage 5's: the iceberg, and GLACIER CRAWLER's parts (in its bank)
    ("berg", "boss5", 0, 0, None, None, 1),
    ("b5reactor", "boss5", 0, 0, None, None, 0),
    ("b5drill", "boss5", 0, 0, None, None, 0),
    ("b5gun", "boss5", 0, 0, None, None, 0),
    ("b5bridge", "boss5", 0, 0, None, None, 0),
    ("slab", "boss5", 0, 0, None, None, 1),
    ("flake", "boss5", 0, 0, None, None, 1),
    # Stage 6's: the satellite (an obstacle), and HALO STATION's core and
    # orbiting gun satellites (in its bank)
    ("sat", "boss6", 0, 0, None, None, 0),
    ("b6core", "boss6", 0, 0, None, None, 4),
    ("b6pod", "boss6", 0, 0, None, None, 0),
    # Stage 7's: MASS DRIVER's breech (its core), capacitor pods and muzzle
    # (in its bank)
    ("b7breech", "boss7", 0, 0, None, None, 0),
    ("b7cap", "boss7", 0, 0, None, None, 0),
    ("b7muzzle", "boss7", 0, 0, None, None, 0),
    # and the bases' launched canisters (towers rising up the screen: stage7.bas)
    ("b7can", "boss7", 0, 0, None, None, 4),
    # Stage 8's: HIVE MOTHERSHIP's eye (its core), spore pods and mandibles
    # (in its bank)
    ("b8eye", "boss8", 0, 0, None, None, 4),
    ("b8pod", "boss8", 0, 0, None, None, 0),
    ("b8clawl", "boss8", 0, 0, None, None, 0),
    ("b8clawr", "boss8", 0, 0, None, None, 0),
    # Stage 9's: GAMMA PRIME's core, beam emitter and orbiting prisms (in
    # its bank; its ring cannons are GAMMA CORE's, its turrets the shared)
    ("b9core", "boss9", 0, 0, None, None, 1),
    ("b9emit", "boss9", 0, 0, None, None, 0),
    ("b9prism", "boss9", 0, 0, None, None, 5),
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
BOSS_PARTS = {e[0] for e in SPRITES if e[1] in ("boss", "boss2", "boss3", "boss4", "boss5", "boss6", "boss7", "boss8", "boss9")} - \
    {"gunboat", "train", "berg", "slab", "flake", "sat", "b7can"}
# Sprites that live in stage 2's graphics block (its bank), by strip label
# (the wasp and the tank are in the last bank's sprite block: they don't fit)
STAGE2_SPRITES = {"tower", "b2coret", "b2coreb", "b2pod", "b2cannon"}
STAGE3_SPRITES = {"gunboat", "b3bridget", "b3bridgeb", "b3reactor", "b3gun"}
STAGE3_STRIPS = {"gunboat0", "gunboat1", "b3bridget0", "b3bridget1", "b3bridgeb0", "b3bridgeb1",
                 "b3reactor0", "b3reactor1", "b3gun"}  # (b3bay: in the last bank, no room here)
STAGE4_STRIPS = {"train0", "train1", "b4headt0", "b4headt1", "b4headb", "b4seg0", "b4seg1", "b4tail0", "b4tail1"}
STAGE5_STRIPS = {"b5reactor0", "b5reactor1", "b5drill0", "b5drill1", "b5gun", "berg0", "berg1",
                 "b5bridge0", "b5bridge1", "slab", "flake"}
STAGE6_STRIPS = {"sat0", "sat1", "b6core0", "b6core1", "b6pod0", "b6pod1"}
STAGE7_STRIPS = {"b7breech0", "b7breech1", "b7cap0", "b7cap1", "b7muzzle0", "b7muzzle1", "b7can0", "b7can1"}
STAGE8_STRIPS = {"b8eye0", "b8eye1", "b8pod0", "b8pod1", "b8clawl0", "b8clawl1", "b8clawr0", "b8clawr1"}
STAGE9_STRIPS = {"b9core0", "b9core1", "b9emit0", "b9emit1", "b9prism"}
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
        elif fn == "boss5":
            import boss7800
            conv = boss7800.parts5()[name]
        elif fn == "boss6":
            import boss7800
            conv = boss7800.parts6()[name]
        elif fn == "boss7":
            import boss7800
            conv = boss7800.parts7()[name]
        elif fn == "boss8":
            import boss7800
            conv = boss7800.parts8()[name]
        elif fn == "boss9":
            import boss7800
            conv = boss7800.parts9()[name]
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
MAX_ROWS = 240
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
    # the stage's own code (stages 5 on), for jmp (stg_vec + 2k): its boss's
    # build, enter, fight, place, attack, sinking, and its main loop hook
    lay["stg_vec"] = (off, 2 * len(STG_VEC))
    return lay


STG_VEC = ("build", "enter", "fight", "place", "attack", "sinking", "hook", "spare")
# (stage 9's spare: the ending's texts, boss9.bas finale)


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
    bg, song, bosssong, waves (field -> list), ground (field -> list).
    Optional: solid (tile numbers: a mask of them follows each row's
    objects), or masks (a list of such sets: a mask for each, in turn);
    alias (map numbers from len(t_slots) on: (tile, palette) each, the
    tile's characters in another palette)."""
    n, m = st["n"], st["map"]
    _slots, t_pals = virtual_tiles(st)
    alias = st.get("alias") or []
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
    def chars(t):
        t = int(t)
        if t >= len(st["t_slots"]):
            t = alias[t - len(st["t_slots"])][0]
        return first_tile_char + 2 * t
    assert len(st["t_slots"]) <= MAX_TILES
    shift = st.get("shift") or [(0, 0)] * rows

    masks = st.get("masks") or ([st["solid"]] if st.get("solid") is not None else [])
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
    vec = st.get("vec")
    if vec:
        lines.append("; the stage's code: boss build, enter, fight, place, attack, sinking; hook")
        lines.append("  .word " + ",".join(f".{v}" if v else "0" for v in vec))
    else:
        lines.append(f"  ds {2 * len(STG_VEC)},0")
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
        for mask in masks:
            # then which columns are solid (bit c % 8 of byte c / 8, columns
            # from col0): stage8.bas, stage9.bas
            bits = [0, 0, 0]
            for c, t in enumerate(key):
                if int(t) in mask:
                    bits[c // 8] |= 1 << (c % 8)
            obj_lines.append("  .byte " + ",".join(str(b) for b in bits))
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


def virtual_tiles(st):
    """A stage's tiles and their palettes as the map numbers them: its
    tiles, then its aliases (stage_bank)."""
    slots, pals = list(st["t_slots"]), list(st["t_pals"])
    for t, pal in st.get("alias") or []:
        slots.append(st["t_slots"][t])
        pals.append(pal)
    return slots, pals


def boss_vec(n, hook):
    """Stage n's vectors (STG_VEC): its boss's routines, its hook."""
    return [f"boss{n}_{v}" for v in STG_VEC[:6]] + [hook, None]


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
    for k, v in enumerate(STG_VEC):
        out.append(f"  const STGV_{v.upper()} = ${0x8000 + STG['stg_vec'][0] + 2 * k:04X}")
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


# Wasps (each fires a fan of 3 needles as it comes in) are spread out from
# MegaGammaForce's: their waves at least WASP_APART scroll pixels apart
# (its own units), the wasps of a wave WASP_GAP times further apart, and
# their weave WASP_WEAVE times as wide. Whole waves of them at once slowed
# the game, and their loops were too wide.
WASP_APART = 100
WASP_GAP = 1.5
WASP_WEAVE = 0.6


def space_wasps(data):
    """Wasp waves moved later where they come within WASP_APART of the wasp
    wave before; the waves after are kept in order (moved as far, if need
    be)."""
    out, last_wasp, prev = [], None, 0
    for w in sorted(data, key=lambda w: w[0]):
        at = max(w[0], prev)
        if w[1] == "ET_WASP":
            if last_wasp is not None and at < last_wasp + WASP_APART:
                at = last_wasp + WASP_APART
            last_wasp = at
        out.append([at] + list(w[1:]))
        prev = at
    return out


def wave_cols(data, scale=1.0):
    """MegaGammaForce air waves -> our wave table fields (their scroll
    positions times scale)."""
    data = [[round(w[0] * scale)] + list(w[1:]) for w in space_wasps(data) if w[1] in ENEMY_TYPES]
    data = [w[:6] + [round(w[6] * WASP_GAP), round(w[7] * WASP_WEAVE)] if w[1] == "ET_WASP" else w
            for w in data]
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


# Stage 5, FROZEN STRAIT: pack ice (the ice is the background), leads of
# open water, plowed roads with snow tanks, bunkers, icebergs standing out
# of the ice (obstacles: ET_TOWER, with a berg's picture), turrets dug in
# behind some of them, and slabs of shelf ice that break away and fall
# down the screen faster than it scrolls (towers that move: they shove
# the ship, and crush it against the bottom). Its boss, GLACIER CRAWLER,
# is part of the map, as LEVIATHAN is: a tracked fortress longer than the
# first half of the screen. It stops with its front half in view; once
# its command bridge falls it drives on, its front off the bottom of the
# screen, and stops with the cryo reactor at its rear in reach. Its treads
# run (the game swaps two colors of P2).
STAGE5_BG = (128, 156, 196)
STAGE5_PALETTES = [
    [(36, 46, 64), (100, 116, 140), (180, 230, 250)],    # P0 the crawler: dark steel, steel, frost
    [(36, 48, 80), (84, 96, 120), (236, 244, 255)],      # P1 snow: shadow, concrete, snow
    [(8, 20, 48), (24, 56, 104), (236, 244, 255)],       # P2 water: deep, water, white rim
]
STAGE5_ORDER = [1, 0, 3, 2, 1, 0]    # ice chunks (32 rows each)
STAGE5_GAP = 13                      # bare ice before the crawler
WAVES_END_5 = 2950                   # no ground units past this
# The crawler: a reactor sled (rows 0-3) towed on a coupling beam (rows
# 4-10, bare ice either side) by the tractor (rows 11-18: the bridge, guns
# and hatches, the drill), 10 tiles wide. Where each part sits: tile
# column and row of its top left, size in tiles.
B5_PARTS = {"REACTOR": (4, 1, 2, 2), "TUR0": (2, 1, 1, 1), "TUR1": (7, 1, 1, 1),
            "BRIDGE": (4, 11, 2, 2), "GUN_L": (2, 14, 2, 2), "GUN_R": (6, 14, 2, 2),
            "HATCH_L": (4, 14, 1, 2), "HATCH_R": (5, 14, 1, 2),
            "TUR2": (2, 17, 1, 1), "TUR3": (7, 17, 1, 1), "DRILL": (4, 17, 2, 2)}
B5_SLED, B5_TRACTOR, B5_H = (0, 3), (11, 18), 19
# slots: name, lines down, pixels right (guns: 16 lines tall in a 32-line well)
B5_SLOTS = {0: ("GUN_L", 8, 2), 1: ("GUN_R", 8, 2), 2: ("DRILL", 0, 0), 3: ("BRIDGE", 0, 0),
            4: ("HATCH_L", 0, 0), 5: ("REACTOR", 0, 0), 6: ("HATCH_R", 0, 0),
            7: ("TUR0", 3, 0), 8: ("TUR1", 3, 0), 9: ("TUR2", 3, 0), 10: ("TUR3", 3, 0)}
B5_FRONT = 6                         # first stop: the bridge's top at line 6
B5_FINAL = 66                        # last stop: the reactor's top at line 66 (the
                                     # tractor then wholly below the screen)
B5_GUST = (176, 198, 224)            # the ice in the blizzard's gusts: paler, the snow on it lost
# Falling shelves: (scroll position, count, x step) of each fall; their
# x from 16 by the step, wrapping within 0-127; one every 40 frames,
# falling B5_FALL/128 of a line a frame faster than the scroll
B5_FALLS = [(640, 3, 88), (1180, 4, 40), (1720, 4, 88), (2240, 5, 56), (2700, 6, 88)]
B5_FALL = 145
# Stage 5's air waves moved toward the middle or mirrored (whole, as they
# are): (at, type, x, dx) in MegaGammaForce's units (192 px across)
WAVE_X5 = [(480, "ET_DART", 170, -24),     # the second darts: the right, as the first are the left
           (620, "ET_WASP", 96, 0),        # centred
           (820, "ET_DRONE", 50, 46),      # centred
           (1100, "ET_WASP", 54, 14),      # a pair, both pulled in
           (1140, "ET_WASP", 138, -14),
           (1620, "ET_DRONE", 60, 36)]     # centred


def crawler_map(ids):
    """GLACIER CRAWLER's hull, MegaGammaForce's tiles (crawler.py) laid out
    as a tractor towing a reactor sled."""
    m = np.zeros((B5_H, 10), dtype=np.uint8)
    rng = np.random.default_rng(5)
    for r0, r1 in (B5_SLED, B5_TRACTOR):
        for r in range(r0, r1 + 1):
            for c in range(2, 8):
                m[r, c] = ids[f"deck{int(rng.integers(0, 4))}"]
            end = "top" if r == r0 else "bottom" if r == r1 else ""
            m[r, 0], m[r, 1] = ids[f"tread0{end}"], ids[f"tread1{end}"]
            m[r, 9], m[r, 8] = ids[f"treadr0{end}"], ids[f"treadr1{end}"]
    for r in range(B5_SLED[1] + 1, B5_TRACTOR[0]):   # the coupling beam
        m[r, 4], m[r, 5] = ids["deck0"], ids["deck1"]
    for c in range(2, 8):
        m[0, c] = ids["rear"]
        m[3, c] = m[13, c] = ids["paint"]
        m[16, c] = ids["stripe"]
    for r in (3, 11, 13, 16):
        m[r, 2] = m[r, 7] = ids["vent"]
    m[18, 2], m[18, 3], m[18, 6], m[18, 7] = ids["plow_l"], ids["deck0"], ids["deck1"], ids["plow_r"]
    for name, (c, r, w, h) in B5_PARTS.items():
        if w == 2:
            for k in range(4):
                m[r + k // 2, c + k % 2] = ids[f"big{k}"]
        elif name.startswith("TUR"):
            m[r, c] = ids["small"]
        else:
            m[r, c], m[r + 1, c] = ids["hatch0"], ids["hatch1"]
    return m


def stage5():
    import tiles7800
    meta = json.loads((MGF / "stage5.json").read_text())
    cols, cr = meta["cols"], meta["chunk_rows"]
    i_tiles, i_pals, i_lut = tiles7800.arctic_tiles(meta["tile_ids"])
    h_tiles, h_pals, h_lut, h_clear = tiles7800.crawler_tiles(meta["hull_tile_ids"])
    base = len(i_tiles)
    t_slots, t_pals = i_tiles + h_tiles, i_pals + h_pals
    chunks = np.frombuffer((MGF / "stage5_chunks.bin").read_bytes(), dtype=np.uint8).reshape(-1, cols).copy()
    # One bunker in six is kept (each with a turret), the others made
    # bare ice: they cost the bank's room and MARIA's time
    ids = meta["tile_ids"]
    kept = []
    for i, (k, r, c) in enumerate(sorted(meta["bunkers"])):
        if i % 6 == 1:
            kept.append((k, r, c))
        chunks[k * cr + r:k * cr + r + 2, c:c + 2] = ids["snow0"]
    # The kept bunkers go to the screen's edges, left and right by turns
    # (MegaGammaForce's fell mostly left of the middle, and the ship could
    # hug the right side past the turrets): each to clear ice at the edge
    # in its rows or near them (columns 18-19 or 0-1, else one in)
    snow = {ids[f"snow{k}"] for k in range(4)}
    moved = []
    for j, (k, r, c) in enumerate(kept):
        cols = (18, 17, 16) if j % 2 == 0 else (0, 1, 2)
        spot = None
        for dr in (0, -1, 1, -2, 2, -3, 3):
            rr = r + dr
            if not 1 <= rr <= cr - 3:
                continue
            for cc in cols:
                a = chunks[k * cr + rr:k * cr + rr + 2, cc:cc + 2]
                if all(int(t) in snow for t in a.ravel()):
                    spot = (rr, cc)
                    break
            if spot:
                break
        if spot is None:
            continue
        rr, cc = spot
        chunks[k * cr + rr, cc], chunks[k * cr + rr, cc + 1] = ids["bunker2"], ids["bunker3"]
        chunks[k * cr + rr + 1, cc], chunks[k * cr + rr + 1, cc + 1] = ids["bunker0"], ids["bunker1"]
        moved.append((k, rr, cc))
    kept = moved
    # and half the cracks in the snow (each makes its row one more to store)
    cracks = list(zip(*np.nonzero(chunks == ids["snow3"])))
    for j, (r, c) in enumerate(cracks):
        if j % 2:
            chunks[r, c] = ids["snow0"]
    body = np.concatenate([chunks[k * cr:(k + 1) * cr] for k in STAGE5_ORDER])
    # Icebergs: obstacles in three lanes by turns, every 10-14 rows, clear
    # of the roads (the tanks drive along them)
    roads = sorted(n * cr + r for n, k in enumerate(STAGE5_ORDER) for kk, r in meta["roads"] if kk == k)
    lanes = [16, 64, 112]               # (in from the edges: the bunkers are there)
    rng = np.random.default_rng(21)
    bergs = []
    r, lane = 14, 1
    while r < body.shape[0] - 6:
        if all(abs(r - rr) > 3 and abs(r + 1 - rr) > 3 for rr in roads):
            bergs.append((r, lanes[lane]))
            lane = (lane + int(rng.integers(1, 3))) % 3
            r += int(rng.integers(10, 15))
        else:
            r += 1
    # Turrets dug in behind every other berg: a bunker just above it, half
    # out to one side (the right first, else the left), on clear ice. The
    # berg shields it from below, but it can fire round the berg, and the
    # ship can reach it from beside the berg.
    snow = {ids[f"snow{k}"] for k in range(4)}
    dug = []
    for k, (r, x) in enumerate(bergs[1::2]):
        if (r + 3) * 16 >= WAVES_END_5:
            continue
        sides = [(x + 24) // 8, x // 8 - 1]
        if k % 2:
            sides.reverse()
        for c in sides:
            if 0 <= c <= 18 and r + 3 < body.shape[0] and \
                    all(int(t) in snow for t in body[r + 2:r + 4, c:c + 2].ravel()):
                body[r + 3, c], body[r + 3, c + 1] = ids["bunker0"], ids["bunker1"]
                body[r + 2, c], body[r + 2, c + 1] = ids["bunker2"], ids["bunker3"]
                dug.append(((r + 3) * 16, (c + 1) * 8))
                break
    hull = crawler_map(meta["hull_tile_ids"])
    hh, hw = hull.shape
    loop = 16
    rows = body.shape[0] + STAGE5_GAP + hh + loop
    assert rows <= MAX_ROWS, rows
    m = np.zeros((rows, 20), dtype=np.uint8)
    m[:body.shape[0], :] = np.vectorize(lambda t: i_lut[int(t)])(body)
    bow = body.shape[0] + STAGE5_GAP                 # the hull's first row (the drill's end)
    stern = bow + hh - 1
    for r in range(hh):                              # hull row r (from the rear) is map row stern - r
        for c in range(hw):
            t = int(hull[r, c])
            if t != h_clear:
                m[stern - r, HULL_COL + c] = base + h_lut[t]

    units = []
    # Snow tanks along the roads, by turns from the left and the right;
    # bit 6 of their param: veterans (objects.asm think_tank), and slower,
    # so they stay to fight
    for j, r in enumerate(roads):
        y = r * 16 + 8
        if 300 < y < WAVES_END_5:
            left = j % 2 == 1
            units.append((y, 148 if left else 8, "ET_TANK", 4 + j % 3, (0x80 if left else 0) | 0x40 | 6))
    bunkers = sorted((n * cr + r, c) for n, k in enumerate(STAGE5_ORDER) for kk, r, c in kept if kk == k)
    for r, x in bergs:
        units.append(((r + 2) * 16 - 8, x + 4, "ET_TOWER", 1, 0))
    # Turrets on every bunker that no berg stands on (one under a berg
    # can't fire: its shells stop in the berg) ...
    def under_berg(r, x0, x1):
        return any(br - 1 <= r <= br + 3 and x0 < bx + 32 and bx < x1 for br, bx in bergs)
    tur = []
    open_bunkers = [(r, c) for r, c in bunkers
                    if 300 < (r + 1) * 16 < WAVES_END_5 and not under_berg(r, c * 8, c * 8 + 16)]
    for r, c in open_bunkers:
        tur.append(((r + 1) * 16, (c + 1) * 8))
    # ... and the dug-in ones behind the bergs
    tur += dug
    for i, (y, x) in enumerate(sorted(tur)):
        units.append((y, x, "ET_TURRET", 4 + i % 3, 0))

    # The crawler's numbers for its boss code (as LEVIATHAN's): each part's
    # x and the world height of its top (a sprite's line is spos + 240 -
    # it); the scroll's stops: its front half in view, the reactor in
    # reach; and where it has gone (its top below the screen).
    def top(name, dy=0):
        c, r, w, h = B5_PARTS[name]
        return (stern - r + 1) * 16 - dy
    b5 = {"b5_gust": nearest(B5_GUST), "b5_stop": top("BRIDGE") - 208 + B5_FRONT, "b5_final": top("REACTOR") - 208 + B5_FINAL,
          "b5_gone": (stern + 1) * 16 + 8}
    xs, ylo, yhi = [], [], []
    for k in range(11):
        name, dy, dx = B5_SLOTS[k]
        xs.append(8 * (HULL_COL + B5_PARTS[name][0]) + dx)
        y = top(name, dy)
        ylo.append(y & 255)
        yhi.append(y >> 8)
    lines = ["; Generated by tools/gen_assets.py. Do not edit.",
             "; GLACIER CRAWLER's parts: x, and the world height of each one's top (lo, hi).",
             "; Its stops (scroll positions) and where it has gone."]
    lines.append("b5_x .byte " + ",".join(str(v) for v in xs))
    lines.append("b5_ylo .byte " + ",".join(str(v) for v in ylo))
    lines.append("b5_yhi .byte " + ",".join(str(v) for v in yhi))
    for name, v in b5.items():
        lines.append(f"{name.upper()} = {v}")
    (GEN / "boss5tab.asm").write_text("\n".join(lines) + "\n")

    # the air waves, with the falling shelves (towers, palette 1) among them
    gr = ground_cols(units)
    # (MegaGammaForce's last wave, a gunship at 2780, is left out: here it
    # came in as the crawler did)
    waves = [wv for wv in meta["waves"] if not (wv[1] == "ET_GUNSHIP" and wv[0] >= 2780)]
    # toward the middle: MegaGammaForce's stage 5 has several waves left
    # of it with no partner on the right (its units, 192 px across)
    waves = [list(wv) for wv in waves]
    for wv in waves:
        for at, typ, x, dx in WAVE_X5:
            if wv[0] == at and wv[1] == typ:
                wv[3], wv[4] = x, dx
    w = wave_cols(waves)
    rowsw = [tuple(w[f][i] for f in WAVE_FIELDS) for i in range(len(w["watl"]))]
    for at, n, dx in B5_FALLS:
        rowsw.append((at & 255, at >> 8, ENEMY_TYPES["ET_TOWER"], 1, 16, dx, n, 40, B5_FALL))
    rowsw.sort(key=lambda t: (t[1] << 8) | t[0])
    w = {f: [t[i] for t in rowsw] for i, f in enumerate(WAVE_FIELDS)}
    # the warning when its front is about 9 rows above the screen
    bossat = (bow * 16 - 208 - 144) >> 8
    return {"n": 5, "map": m, "t_slots": t_slots, "t_pals": t_pals,
            "blank": {0}, "col0": 0, "col1": 20, "loop": loop,
            "charset": "charset5", "pals": [nearest(c) for p in STAGE5_PALETTES for c in p],
            "bg": nearest(STAGE5_BG), "song": "SONG_STAGE5", "bosssong": "SONG_BOSS5", "vec": boss_vec(5, "blizzard"), "bossat": bossat,
            "waves": spread_waves(w, gr), "ground": gr,
            "pal_codes": [[nearest(c) for c in p] for p in STAGE5_PALETTES]}


STAGE6_OCEAN = (22, 66, 150)                 # the ocean far below: the background color
STAGE6_PALETTES = [
    [(30, 64, 150), (130, 138, 158), (214, 164, 44)],   # P0 the station, satellites: solar blue, steel, gold
    [(60, 100, 180), (214, 222, 240), (255, 255, 255)], # P1 clouds: shadow, cloud, sunlit (they fade)
    [(60, 130, 255), (180, 230, 255), (255, 255, 255)], # P2 sky: atmosphere, its bright rim, stars
]
STAGE6_BODY = 192                    # rows before the station's gap
STAGE6_GAP = 12                      # open space before the station
HULL6_COL = 6                        # the station's left column (8 wide, centred)
LIMB6_ROW = 112                      # the row where the limb is highest
CLOUDS6_END = 94                     # no clouds from here (the limb's glow above)
CLOUD6_CHUNK = 16                    # cloud rows come in chunks, repeated (bank room)
# The fade: from scroll position FADE6_FROM to FADE6_TO the ocean and the
# clouds darken to black (MegaGammaForce's stage 6: 200 to 1600), in steps
# of 64 pixels of scroll
FADE6_FROM, FADE6_TO, FADE6_STEP = 200, 1600, 64
SATS6_FROM, SATS6_TO = 1530, 3000    # satellites: world heights of their rows
# HALO STATION's parts: tile column and row of the top left in the
# station (8 x 8 tiles); slots 0-3 are the orbiting gun satellites (their
# orbit's centre: the hub's), 5 the core, the others the ring's turrets
B6_PARTS = {"CORE": (3, 3), "TUR0": (0, 3), "TUR1": (7, 4), "TUR2": (1, 1), "TUR3": (6, 1),
            "TUR4": (1, 6), "TUR5": (6, 6)}
B6_SLOTS = ["HUB", "HUB", "HUB", "HUB", "TUR0", "CORE", "TUR1", "TUR2", "TUR3", "TUR4", "TUR5"]
B6_TOP = 10                          # the fight: the station's top at line 10


def _noise6(rows, cols, cell, seed):
    """Smooth value noise in 0..1 (bilinear over a random grid)."""
    rng = np.random.default_rng(seed)
    g = rng.random((rows // cell + 2, cols // cell + 2))
    out = np.zeros((rows, cols))
    for r in range(rows):
        for c in range(cols):
            y, x = r / cell, c / cell
            y0, x0 = int(y), int(x)
            fy, fx = y - y0, x - x0
            fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
            out[r, c] = (g[y0, x0] * (1 - fx) * (1 - fy) + g[y0, x0 + 1] * fx * (1 - fy) +
                         g[y0 + 1, x0] * (1 - fx) * fy + g[y0 + 1, x0 + 1] * fx * fy)
    return out


def _limb6(px):
    """The limb's height (world lines) at 160A pixel px, below its top:
    flat over the middle, then 1 line a pixel, then 2 (straight runs a tile
    or more long, so its tiles repeat)."""
    d = px if px < 80 else 159 - px
    if d >= 48:
        return 0
    if d >= 24:
        return 48 - d
    return 24 + 2 * (24 - d)


def _fade_code(rgb):
    """The nearest of the grays, the blues and black (fading colors keep
    their hue: no greens or browns on the way down)."""
    cands = [c for c in range(256) if c >> 4 in (0, 8, 9) and (c & 15) % 2 == 0]
    return min(cands, key=lambda c: sum((a - b) ** 2 for a, b in zip(PAL7800[c], rgb)))


def stage6():
    import tiles7800 as t7
    W8, H16 = TILE_W, TILE_H
    tiles, pals, ids = [np.zeros((H16, W8), dtype=np.uint8)], [t7.SKY6], {}

    def add(t, pal):
        key = (t.tobytes(), pal)
        if key not in ids:
            ids[key] = len(tiles)
            tiles.append(t)
            pals.append(pal)
        return ids[key]

    blank = {0}
    rows = STAGE6_BODY + STAGE6_GAP + 8 + 16
    assert rows <= MAX_ROWS, rows
    m = np.zeros((rows, 20), dtype=np.uint8)
    # Clouds: marching squares over a field of noise; in chunks of
    # CLOUD6_CHUNK rows, three kinds (thick, broken, thin), repeated
    def chunk(seed, cover):
        n = _noise6(CLOUD6_CHUNK + 1, 21, 3, seed) * 0.6 + _noise6(CLOUD6_CHUNK + 1, 21, 2, seed + 7) * 0.4
        g = (n > 1 - cover).astype(int)
        g[0, :] = g[CLOUD6_CHUNK, :] = 0                 # clear at the joins
        out = np.zeros((CLOUD6_CHUNK, 20), dtype=np.uint8)
        for r in range(CLOUD6_CHUNK):
            for c in range(20):
                cfg = (g[r + 1, c], g[r + 1, c + 1], g[r, c + 1], g[r, c])
                if any(cfg):
                    out[r, c] = add(t7.cloud6(cfg, 8 * cfg[0] + 4 * cfg[1] + 2 * cfg[2] + cfg[3]), t7.CLOUD6)
        return out
    kinds = [chunk(61, 0.42), chunk(62, 0.40), chunk(63, 0.30), chunk(64, 0.20)]
    order = [0, 1, 0, 2, 1, 3]                          # thinning out as it climbs
    r = 2
    for k in order:
        if r + CLOUD6_CHUNK > CLOUDS6_END:
            break
        m[r:r + CLOUD6_CHUNK] = kinds[k]
        r += CLOUD6_CHUNK
    # The limb: drawn pixel by pixel over the rows it crosses (world
    # height h from the map's start; a tile's top line is the higher one),
    # then cut into tiles. Below it the ocean (the background, black by
    # then); its glow: a bright rim with the atmosphere either side.
    top = LIMB6_ROW * 16 + 6
    lo_row, hi_row = (top - 80) // 16, LIMB6_ROW
    for row in range(lo_row, hi_row + 1):
        for c in range(20):
            t = np.zeros((H16, W8), dtype=np.uint8)
            for y in range(H16):
                h = row * 16 + 15 - y
                for x in range(W8):
                    px = c * W8 + x
                    d = h - (top - _limb6(px))
                    if -4 <= d <= -3 or 4 <= d <= 5:
                        t[y, x] = 1 if (px + h) % 2 == 0 else 0
                    elif -2 <= d <= -1 or 2 <= d <= 3:
                        t[y, x] = 1
                    elif 0 <= d <= 1:
                        t[y, x] = 2
            if t.any():
                m[row, c] = add(t, t7.SKY6)
    # Stars above it: rows from a few patterns (stored once each), one to
    # three stars a row
    rng = np.random.default_rng(66)
    star_t = [add(t7.star6(k), t7.SKY6) for k in range(4)]
    pats = []
    for k in range(10):
        p = np.zeros(20, dtype=np.uint8)
        for c in rng.choice(20, size=int(rng.integers(1, 4)), replace=False):
            p[c] = star_t[int(rng.choice(4, p=[0.45, 0.3, 0.15, 0.1]))]
        pats.append(p)
    def starry(row, c):
        return all(row * 16 > top - _limb6(px) + 8 for px in range(c * W8, c * W8 + W8))
    for row in range(lo_row, rows):
        p = pats[int(rng.integers(0, len(pats)))]
        for c in range(20):
            if p[c] and not m[row, c] and starry(row, c):
                m[row, c] = p[c]
    # HALO STATION: its 8 x 8 tiles over the stars (their row cleared)
    grid = t7.station6()
    bow = STAGE6_BODY + STAGE6_GAP                     # its lowest row
    stern = bow + 7
    m[bow:stern + 1, :] = 0
    for hr in range(8):                                 # station row hr (from the top) is map row stern - hr
        for hc in range(8):
            t = grid[hr][hc]
            if t.any():
                m[stern - hr, HULL6_COL + hc] = add(t, t7.STATION6)
    print(f"stage 6: {len(tiles)} tiles")
    assert len(tiles) <= 54, f"stage 6: {len(tiles)} tiles (54 fit beside its sprites)"

    # Satellites: obstacles (towers with the satellite's picture, P0), by
    # turns at the left and the right, every 6-8 rows
    units = []
    srng = np.random.default_rng(67)
    h, left = SATS6_FROM, True
    while h < SATS6_TO:
        x = int(srng.integers(0, 3)) * 4 if left else 96 - int(srng.integers(0, 3)) * 4
        units.append((h, x + 4, "ET_TOWER", 0, 0))
        left = not left if srng.random() < 0.8 else left
        h += 16 * int(srng.integers(6, 9))

    # HALO STATION's numbers for its boss code (as the crawler's): each
    # part's x and the world height of its top (a sprite's line + 32 is
    # spos + 240 - it); where the scroll stops; where it has gone.
    def part(name):
        if name == "HUB":                               # the orbit's centre, less
            c, r = 4, 4                                 # half a satellite
            return 8 * (HULL6_COL + c) - 8, (stern - r + 1) * 16 + 16
        c, r = B6_PARTS[name]
        return 8 * (HULL6_COL + c), (stern - r + 1) * 16
    xs, ylo, yhi = [], [], []
    for name in B6_SLOTS:
        x, y = part(name)
        xs.append(x)
        ylo.append(y & 255)
        yhi.append(y >> 8)
    top6 = (stern + 1) * 16
    b6 = {"b6_stop": top6 - 208 + B6_TOP, "b6_gone": top6 + 8}
    lines = ["; Generated by tools/gen_assets.py. Do not edit.",
             "; HALO STATION's parts: x, and the world height of each one's top (lo, hi);",
             "; slots 0-3 (the satellites): their orbit's centre, less half a satellite.",
             "; Its stop (a scroll position) and where it has gone."]
    lines.append("b6_x .byte " + ",".join(str(v) for v in xs))
    lines.append("b6_ylo .byte " + ",".join(str(v) for v in ylo))
    lines.append("b6_yhi .byte " + ",".join(str(v) for v in yhi))
    for name, v in b6.items():
        lines.append(f"{name.upper()} = {v}")
    # the fade: the background and P1 for each 64 pixels of scroll
    steps = (FADE6_TO + FADE6_STEP - 1) // FADE6_STEP + 1
    fbg, fp = [], [[], [], []]
    for k in range(steps):
        f = min(1.0, max(0.0, (k * FADE6_STEP - FADE6_FROM) / (FADE6_TO - FADE6_FROM)))
        dim = lambda c: tuple(v * (1 - f) for v in c)  # noqa: E731
        fbg.append(_fade_code(dim(STAGE6_OCEAN)) if f < 1 else 0)
        for i in range(3):
            fp[i].append(_fade_code(dim(STAGE6_PALETTES[1][i])) if f < 1 else 0)
    lines.append("; the fade, by scroll position / 64: the background and P1's colors")
    lines.append(f"B6_FADEN = {steps}")
    lines.append("b6_fbg .byte " + ",".join(f"${v:02X}" for v in fbg))
    for i in range(3):
        lines.append(f"b6_fp{i} .byte " + ",".join(f"${v:02X}" for v in fp[i]))
    (GEN / "boss6tab.asm").write_text("\n".join(lines) + "\n")

    gr = ground_cols(units)
    w = wave_cols(json.loads((MGF / "stage6.json").read_text())["waves"])
    # the warning when the station is about 9 rows above the screen
    bossat = (bow * 16 - 208 - 144) >> 8
    return {"n": 6, "map": m, "t_slots": tiles, "t_pals": pals,
            "blank": blank, "col0": 0, "col1": 20, "loop": 16,
            "charset": "charset6", "pals": [nearest(c) for p in STAGE6_PALETTES for c in p],
            "bg": _fade_code(STAGE6_OCEAN), "song": "SONG_STAGE6", "bosssong": "SONG_BOSS6", "vec": boss_vec(6, "ascent"), "bossat": bossat,
            "waves": spread_waves(w, gr), "ground": gr,
            "pal_codes": [[nearest(c) for c in p] for p in STAGE6_PALETTES]}


# What a unit costs the frame, roughly, for spread_waves: train cars and
# gunships are tall (3 objects or more), saucers fire rings of 8
# Stage 7, SEA OF TRANQUILITY: the Moon (the regolith is the background),
# craters, three bases (plazas of metal floor with domes, landing pads and
# turret bunkers), rover roads, lone bunkers on the plain; then MASS DRIVER,
# a hovering gun platform round a rail cannon, its hull map rows (as the
# crawler's), which sway from side to side in the fight (boss7.bas).
STAGE7_BG = (118, 118, 128)
STAGE7_PALETTES = [
    [(14, 14, 18), (108, 108, 110), (204, 200, 194)],   # P0 the hull: shadow, gunmetal, light
    [(22, 22, 28), (82, 82, 92), (204, 204, 212)],      # P1 the regolith: deep shadow, dark dust, sunlit
    [(40, 44, 60), (70, 140, 210), (232, 238, 248)],    # P2 the bases: dark metal, dome glass, markings
]
# the rail's coils in the fight (P2, turned round: boss7.bas)
STAGE7_COILS = [(110, 50, 230), (190, 130, 255), (250, 230, 255)]
STAGE7_GAP = 14                      # bare regolith before MASS DRIVER
WAVES_END_7 = 2950                   # no ground units past this
HULL7_COL = 5                        # the hull's left column (10 wide, centred)
B7_TOP = 0                           # the fight: the hull's top at line 0
# MASS DRIVER's hull, repacked from MegaGammaForce's 9 rows to 7 (112
# lines: its 144 left the ship only the bottom of the screen): where
# each part sits, tile column and row of its top left, size in tiles
B7_PARTS = {"BREECH": (4, 0, 2, 2), "TUR0": (1, 0, 1, 1), "TUR1": (8, 0, 1, 1),
            "CAP_L": (1, 2, 2, 2), "HATCH_L": (3, 2, 1, 2), "HATCH_R": (6, 2, 1, 2), "CAP_R": (7, 2, 2, 2),
            "TUR2": (1, 4, 1, 1), "TUR3": (8, 4, 1, 1), "MUZZLE": (4, 5, 2, 2)}
B7_H = 7
B7_SWAY = 15                         # its sway, pixels either side (MegaGammaForce's 18 of 192)
# slots: name, lines down, pixels right. 5 is the core (the shared code's
# reactor slot), 10 is free (a dart from the hatches may take it)
B7_SLOTS = [("CAP_L", 0, 0), ("CAP_R", 0, 0), ("MUZZLE", 0, 0), ("HATCH_L", 0, 0), ("HATCH_R", 0, 0),
            ("BREECH", 0, 0), ("TUR0", 3, 0), ("TUR1", 3, 0), ("TUR2", 3, 0), ("TUR3", 3, 0)]


def driver_map(ids):
    """MASS DRIVER's hull from MegaGammaForce's tiles (driver.py), laid out
    as its own but 7 rows: deck, hover nacelles down both sides, the rail
    up the middle from the breech to the muzzle."""
    m = np.zeros((B7_H, 10), dtype=np.uint8)
    rng = np.random.default_rng(7)
    for r in range(B7_H):
        for c in range(1, 9):
            m[r, c] = ids[f"deck{int(rng.integers(0, 4))}"]
        end = "top" if r == 0 else "bottom" if r == B7_H - 1 else ""
        m[r, 0], m[r, 9] = ids[f"nac0{end}"], ids[f"nac1{end}"]
        m[r, 4], m[r, 5] = ids["rail0"], ids["rail1"]
    for c in (1, 2, 3, 6, 7, 8):
        m[B7_H - 1, c] = ids["stripe"]
    m[5, 1], m[5, 8] = ids["lamp"], ids["lamp"]
    for name, (c, r, w, h) in B7_PARTS.items():
        if w == 2:
            for k in range(4):
                m[r + k // 2, c + k % 2] = ids[f"big{k}"]
        elif name.startswith("TUR"):
            m[r, c] = ids["small"]
        else:
            m[r, c], m[r + 1, c] = ids["hatch0"], ids["hatch1"]
    return m


def stage7():
    import tiles7800
    meta = json.loads((MGF / "stage7.json").read_text())
    cols = meta["cols"]
    body = np.frombuffer((MGF / "stage7_ground.bin").read_bytes(), dtype=np.uint8).reshape(-1, cols).copy()
    ids = meta["tile_ids"]
    m_tiles, m_pals, m_lut = tiles7800.luna_tiles(ids, {int(t) for t in body.ravel()})
    h_tiles, h_pals, h_lut, h_clear = tiles7800.driver_tiles(meta["hull_tile_ids"])
    base = len(m_tiles)
    t_slots, t_pals = m_tiles + h_tiles, m_pals + h_pals
    print(f"stage 7: {len(m_tiles)} + {len(h_tiles)} tiles")
    assert len(t_slots) <= 62, f"stage 7: {len(t_slots)} tiles (62 fit beside its sprites)"
    hull = driver_map(meta["hull_tile_ids"])
    hh, hw = hull.shape
    loop = 16
    rows = body.shape[0] + STAGE7_GAP + hh + loop
    assert rows <= MAX_ROWS, rows
    m = np.zeros((rows, 20), dtype=np.uint8)
    m[:body.shape[0], :] = np.vectorize(lambda t: m_lut[int(t)])(body)
    bow = body.shape[0] + STAGE7_GAP                 # the hull's first row (the muzzle's end)
    stern = bow + hh - 1
    for r in range(hh):                              # hull row r (from the breech) is map row stern - r
        for c in range(hw):
            t = int(hull[r, c])
            if t != h_clear:
                m[stern - r, HULL7_COL + c] = base + h_lut[t]

    units = []
    # Turrets on the bunkers (as MegaGammaForce's: all past the start)
    for i, (r, c) in enumerate(meta["bunkers"]):
        y = (r + 1) * 16
        if 300 < y < WAVES_END_7:
            units.append((y, (c + 1) * 8, "ET_TURRET", 4 + i % 3, 0))
    # A rover on every road, from the left and the right by turns: veterans
    # (bit 6), as stage 5's snow tanks
    for j, r in enumerate(meta["roads"]):
        y = r * 16 + 8
        if 300 < y < WAVES_END_7 - 100:
            left = j % 2 == 1
            units.append((y, 148 if left else 8, "ET_TANK", 4 + (j // 3) % 3, (0x80 if left else 0) | 0x40 | 7))

    # MASS DRIVER's numbers for its boss code: each part's x (with no sway)
    # and the world height of its top; where the scroll stops, and where it
    # has gone; the first hull row (rows from it sway: engine.asm)
    parts = B7_PARTS
    xs, ylo, yhi = [], [], []
    for name, dy, dx in B7_SLOTS:
        c, r, w_, h_ = parts[name]
        xs.append(8 * (HULL7_COL + c) + dx)
        y = (stern - r + 1) * 16 - dy
        ylo.append(y & 255)
        yhi.append(y >> 8)
    top7 = (stern + 1) * 16
    b7 = {"b7_stop": top7 - 208 + B7_TOP, "b7_gone": top7 + 8, "b7_row": bow, "b7_sway": B7_SWAY}
    lines = ["; Generated by tools/gen_assets.py. Do not edit.",
             "; MASS DRIVER's parts (slots 0-9): x, and the world height of each one's top",
             "; (lo, hi). Its stop (a scroll position), where it has gone, its first map",
             "; row, its sway (pixels either side); the rail's coil colors (P2 in the fight)."]
    lines.append("b7_x .byte " + ",".join(str(v) for v in xs))
    lines.append("b7_ylo .byte " + ",".join(str(v) for v in ylo))
    lines.append("b7_yhi .byte " + ",".join(str(v) for v in yhi))
    for name, v in b7.items():
        lines.append(f"{name.upper()} = {v}")
    lines.append("b7_coil .byte " + ",".join(f"${nearest(c):02X}" for c in STAGE7_COILS * 2))
    (GEN / "boss7tab.asm").write_text("\n".join(lines) + "\n")

    gr = ground_cols(units)
    w = wave_cols(meta["waves"])
    # the warning when the hull is about 9 rows above the screen
    bossat = (bow * 16 - 208 - 144) >> 8
    return {"n": 7, "map": m, "t_slots": t_slots, "t_pals": t_pals,
            "blank": {0}, "col0": 0, "col1": 20, "loop": loop,
            "charset": "charset7", "pals": [nearest(c) for p in STAGE7_PALETTES for c in p],
            "bg": nearest(STAGE7_BG), "song": "SONG_STAGE7", "bosssong": "SONG_BOSS7", "vec": boss_vec(7, "lunar"), "bossat": bossat,
            "waves": spread_waves(w, gr, by=b7["b7_stop"] - BOSS_LEAD), "ground": gr,
            "pal_codes": [[nearest(c) for c in p] for p in STAGE7_PALETTES]}


# Stage 8, DEEP FIELD: open space beyond the Moon (black: the background),
# stars, and drifts of asteroids, which are solid: they stop shots and
# enemy bullets, and the ship crashes on them (stage8.bas, by each map
# row's solid columns: stage_bank). The bank has room for few different
# rows, so the drifts are a few chunks of rows, each used more than once,
# with lulls of stars between. Then HIVE MOTHERSHIP, an alien ship grown
# not built, its hull map rows (as MASS DRIVER's), swaying in the fight.
STAGE8_BG = (0, 0, 10)
STAGE8_PALETTES = [
    [(88, 0, 79), (149, 60, 141), (100, 220, 90)],      # P0 the hive: shadow, chitin, vein green
    [(50, 42, 40), (118, 100, 86), (196, 178, 150)],    # P1 the asteroids: shadow, rock, sunlit
    [(90, 90, 130), (170, 170, 210), (255, 255, 255)],  # P2 the stars: dim, pale, white (and gunships)
]
STAGE8_BODY = 176                    # rows before the gap
STAGE8_INTRO = 12                    # stars only, at the start
STAGE8_CHUNK = 18                    # an asteroid drift's rows
STAGE8_GAP = 14                      # open space before the hive
HULL8_COL = 5                        # the hull's left column (10 wide, centred)
B8_TOP = 0                           # the fight: the hull's top at line 0
B8_W, B8_H = 10, 7
# HIVE MOTHERSHIP's parts, repacked from MegaGammaForce's 9 rows to 7:
# tile column and row of each one's top left, size in tiles
B8_PARTS = {"EYE": (4, 2, 2, 2), "POD_L": (1, 1, 2, 2), "POD_R": (7, 1, 2, 2),
            "CLAW_L": (2, 4, 2, 2), "CLAW_R": (6, 4, 2, 2),
            "TUR0": (3, 0, 1, 1), "TUR1": (6, 0, 1, 1), "TUR2": (1, 3, 1, 1), "TUR3": (8, 3, 1, 1)}
B8_SWAY = 16                         # its sway, pixels either side (MegaGammaForce's 20 of 192)
# slots: name, lines down. 5 is the core (the shared code's reactor slot);
# 4 is the shut eye's armor (boss8.bas), 10 free (a saucer may take it)
B8_SLOTS = [("POD_L", 0), ("POD_R", 0), ("CLAW_L", 0), ("CLAW_R", 0), None, ("EYE", 0),
            ("TUR0", 0), ("TUR1", 0), ("TUR2", 0), ("TUR3", 0)]


def _runs8(row, split=SPLIT_COL):
    """Display objects a row of tile numbers takes: its runs of drawn tiles
    (P1 rock and P2 stars apart, cut at the split column)."""
    n, prev = 0, None
    for c, t in enumerate(row):
        kind = 0 if t == 0 else (1 if t >= 5 else 2)
        if kind and (kind != prev or c == split):
            n += 1
        prev = kind
    return n


def deep_drift(rocks, debris, seed, rows=STAGE8_CHUNK, cols=20):
    """A drift of asteroids (rows x cols, stage order: row 0 first seen):
    rocks set down a tile apart, every row keeping four clear columns
    together to fly through, and few enough runs in a row for its
    display list."""
    rng = np.random.default_rng(seed)
    m = np.zeros((rows, cols), dtype=np.uint8)
    used = np.zeros((rows, cols), dtype=bool)
    weights = np.array([5, 5, 4, 4, 3.0])
    weights /= weights.sum()

    def ok(r0, h):
        for r in range(r0, r0 + h):
            run = best = 0
            for c in range(cols):
                run = 0 if used[r, c] else run + 1
                best = max(best, run)
            if best < 4 or _runs8(m[r]) > 5:
                return False
        return True

    r = 1
    while r < rows - 2:
        for _ in range(2):                          # two tries a step: the field is wide
            g = rocks[int(rng.choice(len(rocks), p=weights))]
            h, w = g.shape
            if r + h > rows - 1:
                continue
            for _ in range(8):
                c = int(rng.integers(0, cols - w + 1))
                if used[max(r - 1, 0):r + h + 1, max(c - 1, 0):c + w + 1].any():
                    continue
                keep = m.copy()
                for y in range(h):
                    for x in range(w):
                        if g[y, x]:
                            m[r + h - 1 - y, c + x] = g[y, x]   # stage order: its top row the highest
                used[r:r + h, c:c + w] = True
                if ok(r, h):
                    break
                m[:] = keep
                used[r:r + h, c:c + w] = False
        r += int(rng.integers(1, 3))
    # debris, now and then, where it is clear
    for y in range(rows):
        for x in range(cols):
            if not used[max(y - 1, 0):y + 2, max(x - 1, 0):x + 2].any() and rng.random() < 0.02:
                m[y, x] = debris
                used[y, x] = True
                if _runs8(m[y]) > 6:
                    m[y, x] = 0
    return m


def stage8():
    import tiles7800 as t7
    meta = json.loads((MGF / "stage8.json").read_text())
    s_tiles, s_pals, stars, rocks, debris, solid = t7.deep_tiles()
    h_tiles, h_pals, hull = t7.hive_tiles(B8_W, B8_H, B8_PARTS)
    base = len(s_tiles)
    t_slots, t_pals = s_tiles + h_tiles, s_pals + h_pals
    print(f"stage 8: {len(s_tiles)} + {len(h_tiles)} tiles, {len(solid)} solid")
    assert len(t_slots) <= 54, f"stage 8: {len(t_slots)} tiles (54 fit beside its sprites)"
    loop = 16
    rows = STAGE8_BODY + STAGE8_GAP + B8_H + loop
    assert rows <= MAX_ROWS, rows
    m = np.zeros((rows, 20), dtype=np.uint8)
    # stars: rows from a few patterns (stored once each), one to three a row
    rng = np.random.default_rng(88)
    pats = []
    for k in range(10):
        p = np.zeros(20, dtype=np.uint8)
        for c in rng.choice(20, size=int(rng.integers(1, 4)), replace=False):
            p[c] = stars[int(rng.choice(4, p=[0.4, 0.3, 0.15, 0.15]))]
        pats.append(p)
    for r in range(rows):
        m[r] = pats[int(rng.integers(0, len(pats)))]
    # the drifts: four chunks, used in turn, with lulls of stars between
    chunks = [deep_drift(rocks, debris, 80 + k) for k in range(4)]
    for k, ch in enumerate(chunks):
        # a star or two in each chunk row, where clear
        for y in range(STAGE8_CHUNK):
            if not ch[y].any() or rng.random() < 0.5:
                c = int(rng.integers(0, 20))
                if ch[y, max(c - 1, 0):c + 2].sum() == 0 and _runs8(ch[y]) < 6:
                    ch[y, c] = stars[int(rng.integers(0, 3))]
    order = [0, 1, 2, 3, 1, 0, 2]
    r = STAGE8_INTRO
    for k in order:
        if r + STAGE8_CHUNK > STAGE8_BODY - 4:
            break
        m[r:r + STAGE8_CHUNK] = chunks[k]
        r += STAGE8_CHUNK + int(rng.integers(4, 8))
    # HIVE MOTHERSHIP: its tiles over clear rows
    bow = STAGE8_BODY + STAGE8_GAP                  # its lowest row (the mandibles' tips)
    stern = bow + B8_H - 1
    m[bow:stern + 1, :] = 0
    for hr in range(B8_H):                          # hull row hr (from the top) is map row stern - hr
        for hc in range(B8_W):
            if hull[hr, hc]:
                m[stern - hr, HULL8_COL + hc] = base + hull[hr, hc] - 1
    for r in range(rows):
        assert _runs8(m[r]) <= MAX_RUNS, (r, _runs8(m[r]))

    # HIVE MOTHERSHIP's numbers for its boss code: each part's x (with no
    # sway) and the world height of its top; where the scroll stops, where
    # it has gone; its rows (they sway: engine.asm)
    xs, ylo, yhi = [], [], []
    for sl in B8_SLOTS:
        if sl is None:
            xs.append(0)
            ylo.append(0)
            yhi.append(0)
            continue
        name, dy = sl
        c, r_, w_, h_ = B8_PARTS[name]
        xs.append(8 * (HULL8_COL + c))
        y = (stern - r_ + 1) * 16 - dy
        ylo.append(y & 255)
        yhi.append(y >> 8)
    top8 = (stern + 1) * 16
    # (stage8.bas: no asteroids in view from scroll position DP_END * 256 on)
    last = max(r for r in range(STAGE8_BODY) if any(int(t) in solid for t in m[r]))
    b8 = {"b8_stop": top8 - 208 + B8_TOP, "b8_gone": top8 + 8, "b8_row": bow, "b8_end": stern + 1,
          "b8_sway": B8_SWAY, "dp_end": ((last + 1) * 16 >> 8) + 1}
    lines = ["; Generated by tools/gen_assets.py. Do not edit.",
             "; HIVE MOTHERSHIP's parts (slots 0-9): x, and the world height of each one's",
             "; top (lo, hi). Its stop (a scroll position), where it has gone, its map rows",
             "; (from, to), its sway (pixels either side)."]
    lines.append("b8_x .byte " + ",".join(str(v) for v in xs))
    lines.append("b8_ylo .byte " + ",".join(str(v) for v in ylo))
    lines.append("b8_yhi .byte " + ",".join(str(v) for v in yhi))
    for name, v in b8.items():
        lines.append(f"{name.upper()} = {v}")
    (GEN / "boss8tab.asm").write_text("\n".join(lines) + "\n")

    gr = ground_cols([])
    w = wave_cols(meta["waves"])
    bossat = (bow * 16 - 208 - 144) >> 8
    return {"n": 8, "map": m, "t_slots": t_slots, "t_pals": t_pals,
            "blank": {0}, "col0": 0, "col1": 20, "loop": loop, "solid": solid,
            "charset": "charset8", "pals": [nearest(c) for p in STAGE8_PALETTES for c in p],
            "bg": nearest(STAGE8_BG), "song": "SONG_STAGE8", "bosssong": "SONG_BOSS8", "vec": boss_vec(8, "deep"),
            "bossat": bossat, "waves": spread_waves(w, gr), "ground": gr,
            "pal_codes": [[nearest(c) for c in p] for p in STAGE8_PALETTES]}


# Stage 9, CORONA: low over the Sun (its surface the background color),
# granulation, sunspots and faculae; and flares, solar loops and tongues
# of plasma in two groups (A in P0, B in P1, the same tiles: alias), lit
# in turn (stage9.bas): dark, a flicker of warning, then the eruption,
# which is fatal to fly through (by each map row's masks: stage_bank).
# Each group alone always leaves a way through. Then GAMMA PRIME, the
# Gamma Core's true form, a sunburst fortress of gold, its hull map rows
# (as HIVE MOTHERSHIP's), swaying in the fight; P0 and P1 hold its gold
# and its spine's gamma light then (the flares are behind).
STAGE9_BG = (204, 92, 10)
STAGE9_PALETTES = [
    [(96, 22, 0), (110, 28, 0), (124, 34, 0)],          # P0 flares A, dark (stage9.bas lights them)
    [(96, 22, 0), (110, 28, 0), (124, 34, 0)],          # P1 flares B
    [(46, 6, 0), (150, 52, 0), (255, 222, 120)],        # P2 the surface: umbra, lanes, faculae (and gunships)
]
# the flares' colors, dark, warning, erupting, fading (MegaGammaForce's bg.c)
FLARE9_COLORS = [[(96, 22, 0), (110, 28, 0), (124, 34, 0)],
                 [(200, 60, 0), (230, 100, 10), (250, 140, 30)],
                 [(230, 50, 10), (255, 190, 60), (255, 250, 210)],
                 [(200, 60, 0), (220, 100, 20), (240, 150, 60)]]
# the fight's: P0 GAMMA PRIME's gold, P1 its spine (gold, gamma light)
GAMMA9_COLORS = [[(90, 60, 20), (196, 150, 60), (255, 240, 190)],
                 [(196, 150, 60), (80, 255, 140), (230, 255, 230)]]
STAGE9_BODY = 176                    # rows before the gap
STAGE9_CHUNK = 20                    # a chunk of flares' rows
STAGE9_GAP = 14                      # bare surface before GAMMA PRIME
FLARE9_CLEAR = 18                    # no flares in the rows before it (P0 turns gold)
HULL9_COL = 5                        # the hull's left column (10 wide, centred)
B9_TOP = 0                           # the fight: the hull's top at line 0
B9_W, B9_H = 10, 7
# GAMMA PRIME's parts, repacked from MegaGammaForce's 9 rows to 7: tile
# column and row of each one's top left, size in tiles
B9_PARTS = {"CORE": (4, 2, 2, 2), "CANNON_L": (1, 2, 2, 2), "CANNON_R": (7, 2, 2, 2), "EMITTER": (4, 4, 2, 2),
            "TUR0": (2, 0, 1, 1), "TUR1": (7, 0, 1, 1), "TUR2": (2, 5, 1, 1), "TUR3": (7, 5, 1, 1)}
B9_SWAY = 13                         # its sway, pixels either side (MegaGammaForce's 16 of 192)
# slots: name, lines down (a prism: the core's, 8 down: the orbit's centre
# less half a prism). 5 is the core (the shared code's reactor slot)
B9_SLOTS = [("CANNON_L", 0), ("CANNON_R", 0), ("EMITTER", 0), ("CORE", 8), ("CORE", 8), ("CORE", 0),
            ("TUR0", 0), ("TUR1", 0), ("TUR2", 0), ("TUR3", 0), ("CORE", 8), ("CORE", 8)]


def _runs9(row, pals):
    """Display objects a row of map numbers takes (pals: each number's
    palette, None for the blank), cut at the split column."""
    n, prev = 0, None
    for c, t in enumerate(row):
        p = pals[int(t)]
        if p is not None and (p != prev or c == SPLIT_COL):
            n += 1
        prev = p
    return n


def stage9():
    import tiles7800 as t7
    meta = json.loads((MGF / "stage9.json").read_text())
    s_tiles, s_pals, patches, flecks, flares, lethal = t7.corona_tiles()
    h_tiles, h_pals, hull = t7.gamma_tiles(B9_W, B9_H, B9_PARTS)
    base = len(s_tiles)
    t_slots, t_pals = s_tiles + h_tiles, s_pals + h_pals
    # group B: the flares' tiles again, in P1
    flare_tiles = sorted({int(t) for g in flares for t in g.ravel() if t})
    alias = [(t, t7.FLARE9_B) for t in flare_tiles]
    to_b = {t: len(t_slots) + k for k, t in enumerate(flare_tiles)}
    print(f"stage 9: {len(s_tiles)} + {len(h_tiles)} tiles, {len(lethal)} lethal")
    assert len(t_slots) <= 64, f"stage 9: {len(t_slots)} tiles (64 fit beside its sprites)"
    vpals = [None] + t_pals[1:] + [p for _, p in alias]
    loop = 16
    rows = STAGE9_BODY + STAGE9_GAP + B9_H + loop
    assert rows <= MAX_ROWS, rows
    m = np.zeros((rows, 20), dtype=np.uint8)
    rng = np.random.default_rng(99)
    used = np.zeros((rows, 20), dtype=bool)
    assert rows >= STAGE9_CHUNK

    def put(g, r, c, mark=True, remap=None):
        """Grid g (top row first) with its bottom row at map row r."""
        h, w = g.shape
        for y in range(h):
            for x in range(w):
                if g[y, x]:
                    t = int(g[y, x])
                    m[r + h - 1 - y, c + x] = remap[t] if remap else t
        if mark:
            used[r:r + h, c:c + w] = True

    def fits(g, r, c, pad=1, cap=4):
        h, w = g.shape
        if r < 0 or r + h > rows or c < 0 or c + w > 20:
            return False
        if used[max(r - pad, 0):r + h + pad, max(c - pad, 0):c + w + pad].any():
            return False
        keep = m.copy()
        put(g, r, c, mark=False)
        ok = all(_runs9(m[y], vpals) <= cap for y in range(r, r + h))
        m[:] = keep
        return ok

    def surface(n, seed, cap=3):
        """n rows of surface (stage order): patches of granulation and
        sunspots (none across its ends, so it repeats), faculae."""
        g_rng = np.random.default_rng(seed)
        keep_m, keep_u = m.copy(), used.copy()
        m[:n], used[:n] = 0, False
        r = 0
        while r < n:
            g = patches[int(g_rng.choice(3, p=[0.55, 0.2, 0.25]))]
            if r + g.shape[0] <= n:
                for _ in range(6):
                    c = int(g_rng.integers(0, 20 - g.shape[1] + 1))
                    if fits(g, r, c, pad=2, cap=cap):
                        put(g, r, c)
                        break
            r += int(g_rng.integers(2, 6))
        for y in range(n):
            for _ in range(2):
                x = int(g_rng.integers(0, 20))
                if g_rng.random() < 0.35 and not used[max(y - 1, 0):y + 2, max(x - 1, 0):x + 2].any():
                    m[y, x] = flecks[int(g_rng.integers(0, 2))]
                    if _runs9(m[y], vpals) > cap:
                        m[y, x] = 0
                    else:
                        used[y, x] = True
        out = m[:n].copy(), used[:n].copy()
        m[:], used[:] = keep_m, keep_u
        return out

    # the flares (MegaGammaForce's stage9_sky): a group and a shape at a
    # time, up a chunk of rows, each group alone leaving a way through (a
    # run of 7 clear columns in every row). The bank has room for few
    # different rows: four chunks over the surface, used in turn.
    def passable(gu, r0, h):
        for y in range(r0, r0 + h):
            run = best = 0
            for c in range(20):
                run = 0 if gu[y, c] else run + 1
                best = max(best, run)
            if best < 7:
                return False
        return True

    def chunk(seed):
        c_rng = np.random.default_rng(seed)
        ground, _ = surface(STAGE9_CHUNK, seed + 50)
        keep_m, keep_u = m.copy(), used.copy()
        m[:STAGE9_CHUNK], used[:STAGE9_CHUNK] = ground, False
        gu = {"A": np.zeros((STAGE9_CHUNK, 20), dtype=bool), "B": np.zeros((STAGE9_CHUNK, 20), dtype=bool)}
        r = 0
        while r < STAGE9_CHUNK:
            grp = "AB"[int(c_rng.integers(0, 2))]
            g = flares[int(c_rng.integers(0, len(flares)))]
            if grp == "B":
                g = np.vectorize(lambda t: to_b[int(t)] if t else 0)(g)
            h, w = g.shape
            if r + h <= STAGE9_CHUNK:
                for _ in range(10):
                    c = int(c_rng.integers(0, 20 - w + 1))
                    if not fits(g, r, c, pad=0, cap=5):
                        continue
                    gu[grp][r:r + h, c:c + w] = True
                    if not passable(gu[grp], r, h):
                        gu[grp][r:r + h, c:c + w] = False
                        continue
                    put(g, r, c)
                    break
            r += int(c_rng.integers(1, 3))
        out = m[:STAGE9_CHUNK].copy()
        m[:], used[:] = keep_m, keep_u
        return out

    plain, _ = surface(16, 90)
    lull, _ = surface(4, 91)
    chunks = [chunk(92 + k) for k in range(4)]
    end = STAGE9_BODY + STAGE9_GAP - FLARE9_CLEAR
    m[0:16] = plain
    m[16:20] = lull
    # seven chunks, and lulls between to fill the rows to the end
    r = 20
    order = [0, 1, 2, 3, 1, 0, 2]
    lulls = (end - r - STAGE9_CHUNK * len(order)) // 4
    assert lulls >= 0
    for i, k in enumerate(order):
        m[r:r + STAGE9_CHUNK] = chunks[k]
        r += STAGE9_CHUNK
        if i < len(order) - 1 and i % 2 == 1 and lulls:
            m[r:r + 4] = lull
            r += 4
            lulls -= 1
    while r < rows:
        m[r:min(r + 16, rows)] = plain[:min(16, rows - r)]
        r += 16
    m[rows - loop:] = plain                         # (the loop: seamless)
    flare_numbers = set(lethal) | set(to_b.values()) | set(flare_tiles)
    last_flare = max(y for y in range(rows) if any(int(t) in flare_numbers for t in m[y]))

    # GAMMA PRIME: its tiles over clear rows
    bow = STAGE9_BODY + STAGE9_GAP                  # its lowest row
    stern = bow + B9_H - 1
    m[bow:stern + 1, :] = 0
    for hr in range(B9_H):                          # hull row hr (from the top) is map row stern - hr
        for hc in range(B9_W):
            if hull[hr, hc]:
                m[stern - hr, HULL9_COL + hc] = base + hull[hr, hc] - 1
    for y in range(rows):
        assert _runs9(m[y], vpals) <= MAX_RUNS, (y, _runs9(m[y], vpals))

    # GAMMA PRIME's numbers for its boss code: each part's x (with no
    # sway) and the world height of its top; where the scroll stops, where
    # it has gone; its rows (they sway: engine.asm); the flares' colors and
    # where they end (stage9.bas)
    xs, ylo, yhi = [], [], []
    for name, dy in B9_SLOTS:
        c, r_, w_, h_ = B9_PARTS[name]
        xs.append(8 * (HULL9_COL + c))
        y = (stern - r_ + 1) * 16 - dy
        ylo.append(y & 255)
        yhi.append(y >> 8)
    top9 = (stern + 1) * 16
    fl_end = (last_flare + 1) * 16
    assert fl_end + 240 < bow * 16, "a flare still in view as the hull comes"
    b9 = {"b9_stop": top9 - 208 + B9_TOP, "b9_gone": top9 + 8, "b9_row": bow, "b9_end": stern + 1,
          "b9_sway": B9_SWAY, "fl_end": fl_end,
          "fl_c0": 2 * NFONT + 2 * lethal.start, "fl_c1": 2 * NFONT + 2 * lethal.stop}
    lines = ["; Generated by tools/gen_assets.py. Do not edit.",
             "; GAMMA PRIME's parts (slots 0-11): x, and the world height of each one's",
             "; top (lo, hi). Its stop (a scroll position), where it has gone, its map rows",
             "; (from, to), its sway (pixels either side); where the flares end (a scroll",
             "; position: past it, none in view), the characters of the tiles that kill",
             "; (from, to); the flares' colors (dark, warning, erupting, fading), the",
             "; fight's (P0 gold, P1 the spine)."]
    lines.append("b9_x .byte " + ",".join(str(v) for v in xs))
    lines.append("b9_ylo .byte " + ",".join(str(v) for v in ylo))
    lines.append("b9_yhi .byte " + ",".join(str(v) for v in yhi))
    for name, v in b9.items():
        lines.append(f"{name.upper()} = {v}")
    lines.append("fl_cols .byte " + ",".join(f"${nearest(c):02X}" for p in FLARE9_COLORS for c in p))
    lines.append("b9_cols .byte " + ",".join(f"${nearest(c):02X}" for p in GAMMA9_COLORS for c in p))
    (GEN / "boss9tab.asm").write_text("\n".join(lines) + "\n")

    gr = ground_cols([])
    w = wave_cols(meta["waves"])
    bossat = (bow * 16 - 208 - 144) >> 8
    # (the last stage throws everything at once: the waves may crowd more
    # than elsewhere, so the last is over before the warning must come)
    waves = spread_waves(w, gr, cap=14, most=40, by=b9["b9_stop"] - BOSS_LEAD)
    view = [FLARE9_COLORS[2], FLARE9_COLORS[0], STAGE9_PALETTES[2]]
    return {"n": 9, "map": m, "t_slots": t_slots, "t_pals": t_pals, "alias": alias,
            "blank": {0}, "col0": 0, "col1": 20, "loop": loop,
            "charset": "charset9", "pals": [nearest(c) for p in STAGE9_PALETTES for c in p],
            "bg": nearest(STAGE9_BG), "song": "SONG_STAGE9", "bosssong": "SONG_BOSS9", "vec": boss_vec(9, "corona")[:7] + ["finale"],
            "bossat": bossat, "waves": waves, "ground": gr,
            "pal_codes": [[nearest(c) for c in p] for p in view]}


UNIT_WEIGHT = {"ET_TRAIN": 3, "ET_GUNSHIP": 3, "ET_GUNBOAT": 3, "ET_SAUCER": 2}


# A boss whose hull comes with the map can't wait: the shared code warns
# of it once the last wave has started, and the warning and the entry take
# about this much scroll, so the last wave must start this far before the
# scroll's stop (or the hull overshoots, down onto the ship).
BOSS_LEAD = 200


def spread_waves(w, gr, cap=11, life=260, step=20, most=300, weights=None, by=None):
    """Air waves moved later (never earlier, in order, at most `most`
    pixels, and none past scroll position `by`) where they would pile up: a rough load of the units on the
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
    prev, last_wasp = 0, -WASP_APART
    for at, n, t in zip(ats, w["wcount"], w["wtype"]):
        count = n * weight.get(t, 1)
        x0 = max(at, prev)
        if t == ENEMY_TYPES["ET_WASP"]:
            x0 = max(x0, last_wasp + WASP_APART)
        best = x0
        for x in range(x0, max(x0, at + most) + 1, step):
            if load(x, (x, count)) <= cap:
                best = x
                break
        else:
            best = min(range(x0, max(x0, at + most) + 1, step), key=lambda x: load(x, (x, count)))
        placed.append((best, count))
        prev = best
        if t == ENEMY_TYPES["ET_WASP"]:
            last_wasp = best
    if by is not None:
        # (the late ones brought back, still a step apart)
        for i in range(len(placed) - 1, -1, -1):
            placed[i] = (min(placed[i][0], by), placed[i][1])
            by = placed[i][0] - step
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
    stages = [stage1(), stage2(), stage3(), stage4(), stage5(), stage6(), stage7(), stage8(), stage9()]
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
            if n not in in_chars and n not in STAGE2_STRIPS | STAGE3_STRIPS | STAGE4_STRIPS | STAGE5_STRIPS
            | STAGE6_STRIPS | STAGE7_STRIPS | STAGE8_STRIPS | STAGE9_STRIPS]
    (GEN / "gfx.bas").write_text("\n".join(bas) + "\n")
    # gfxN.bas: stage N's graphics block, in its bank at $A000: the font
    # and the stage's tiles, then its own sprites.
    for n, strips in ((2, STAGE2_STRIPS), (3, STAGE3_STRIPS), (4, STAGE4_STRIPS), (5, STAGE5_STRIPS),
                          (6, STAGE6_STRIPS), (7, STAGE7_STRIPS), (8, STAGE8_STRIPS), (9, STAGE9_STRIPS)):
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
    t9 = ["; Generated by tools/gen_assets.py. Do not edit.",
          "; Playfield texts in stage 9's bank (TXT_ numbers: data.asm's tables)."]
    for i, (label, text) in enumerate(BANK9_TEXTS.items()):
        t9.append(f"txt_{label} .byte " + ",".join(str(char_index(ch, font_base)) for ch in text) + f" ; {text!r}")
        consts.append(f"  const TXT_{label.upper()} = {len(SCREEN_TEXTS) + len(SCREEN_RAM) + i}")
    (GEN / "texts9.asm").write_text("\n".join(t9) + "\n")
    asm.append("; the results lines' templates, copied into their RAM lines")
    asm.append("restmpl .byte " + ",".join(str(char_index(ch, font_base)) for ch in RESULT_LINES[0]))
    for line in RESULT_LINES[1:]:
        asm.append("  .byte " + ",".join(str(char_index(ch, font_base)) for ch in line))
    lens = {**{k: len(v) for k, v in SCREEN_TEXTS.items()}, **{k: SCREEN_RAM_LEN.get(k, RESULT_LEN) for k in SCREEN_RAM},
            **{k: len(v) for k, v in BANK9_TEXTS.items()}}
    names = list(SCREEN_TEXTS) + list(SCREEN_RAM) + list(BANK9_TEXTS)
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
    def rows_of(label, vals):
        # (dasm takes 32 operators a line)
        out = [label]
        for i in range(0, len(vals), 16):
            out.append("  .byte " + ",".join(vals[i:i + 16]))
        return out
    asm += rows_of("imglo", lo) + rows_of("imghi", hi) + rows_of("imglo2", lo2) + rows_of("imghi2", hi2)
    asm += rows_of("imgw", w) + rows_of("imgstrips", st) + rows_of("imgframes", fr)
    asm += ["; lines used in the image's last strip (the plotter skips the part",
            "; of a strip that would only be empty lines)"]
    asm += rows_of("imgh", hh)
    asm += ["; -width & 31, the width bits of a 4-byte header"]
    asm += rows_of("imgnegw", [str((-int(x)) & 31) for x in w]) + [""]
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
        map_preview(st["map"], *virtual_tiles(st), pals=st.get("pal_codes"),
                    bg=st["bg"] if st["n"] > 1 else None).save(PREVIEW / f"stage{st['n']}_map.png")
    print(f"BG ${BG_CODE:02X}; palettes " + " ".join("/".join(f"{c:02X}" for c in p) for p in PAL_CODES))
    print(f"{len(incs)} sprite strips; largest row background {max_bg} bytes")


if __name__ == "__main__":
    main()
