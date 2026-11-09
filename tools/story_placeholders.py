#!/usr/bin/env python3
"""Placeholder cutscene pictures, drawn here until the real ones are made:
the five full panels (160 x 96) and the briefings' three portraits
(32 x 48), each fitted to the 7800's rules (tools/cutscene7800.py) so it
is also a template of what they allow.

    .venv/bin/python tools/story_placeholders.py [--force]   -> storyboard/panels/

A picture already there (drawn by hand) is left alone; --force redraws
the placeholders over everything.
"""

import sys

import math
from pathlib import Path

import numpy as np
from PIL import Image

import cutscene7800 as cs

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "storyboard" / "panels"


class Pic:
    """An RGB picture; shapes in screen units (a pixel is 2 across, a line 1)."""

    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 3), dtype=float)
        self.a[:] = bg
        yy, xx = np.mgrid[0:h, 0:w]
        self.x, self.y = xx * 2 + 1.0, yy + 0.5

    def fill(self, mask, rgb):
        self.a[mask] = rgb

    def vgrad(self, y0, y1, c0, c1, mask=None, steps=3):
        """A gradient in a few flat bands (a cell holds only 3 colors)."""
        t = np.clip((self.y - y0) / (y1 - y0), 0, 0.999)
        t = (np.floor(t * steps) / max(steps - 1, 1))[..., None]
        g = np.array(c0) * (1 - t) + np.array(c1) * t
        m = (self.y >= y0) & (self.y < y1)
        if mask is not None:
            m &= mask
        self.a[m] = g[m]

    def disc(self, cx, cy, r):
        return np.hypot(self.x - cx, self.y - cy) < r

    def poly(self, pts):
        inside = np.zeros((self.h, self.w), dtype=bool)
        n = len(pts)
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            cond = (y0 > self.y) != (y1 > self.y)
            xi = (x1 - x0) * (self.y - y0) / (y1 - y0 + 1e-9) + x0
            inside ^= cond & (self.x < xi)
        return inside

    def stars(self, n, seed, rgb=(220, 220, 255), below=None):
        rng = np.random.default_rng(seed)
        for _ in range(n):
            px, py = int(rng.integers(0, self.w)), int(rng.integers(0, self.h if below is None else below))
            self.a[py, px] = rgb

    def rgb(self):
        return np.clip(self.a, 0, 255).astype(np.uint8)


def ship(p, cx, cy, s=1.0, hull=(170, 180, 205), dark=(60, 70, 110), glow=(120, 200, 255)):
    """The GF-01 from above, nose up: a dart with swept wings."""
    p.fill(p.poly([(cx, cy - 14 * s), (cx + 5 * s, cy + 2 * s), (cx + 16 * s, cy + 9 * s), (cx + 5 * s, cy + 8 * s),
                   (cx, cy + 11 * s), (cx - 5 * s, cy + 8 * s), (cx - 16 * s, cy + 9 * s), (cx - 5 * s, cy + 2 * s)]), hull)
    p.fill(p.poly([(cx, cy - 6 * s), (cx + 2.5 * s, cy + 1 * s), (cx - 2.5 * s, cy + 1 * s)]), dark)
    p.fill(p.disc(cx, cy + 12 * s, 2.5 * s), glow)


def prologue():
    """SCRAMBLE ORDER: CODE GAMMA. The launch tube under the ocean: rails
    running into the distance, steam, the ship in the spotlight."""
    p = Pic(160, 96, (0, 40, 60))
    # the tube's walls, converging on the far end
    p.fill(p.poly([(0, 0), (110, 34), (110, 62), (0, 96)]), (0, 70, 100))
    p.fill(p.poly([(320, 0), (210, 34), (210, 62), (320, 96)]), (0, 70, 100))
    p.fill(p.poly([(110, 34), (210, 34), (210, 62), (110, 62)]), (12, 20, 30))
    for k in range(4):                                     # wall lamps
        x = 30 + k * 22
        p.fill(p.disc(x, 12 + k * 6, 2.2), (255, 80, 60))
        p.fill(p.disc(320 - x, 12 + k * 6, 2.2), (255, 80, 60))
    # the rails
    for dx in (-36, 36):
        p.fill(p.poly([(160 + dx * 0.25, 62), (160 + dx * 0.3, 62), (160 + dx * 1.3, 96), (160 + dx * 1.1, 96)]),
               (150, 160, 170))
    # the spotlight and the steam
    cone = p.poly([(150, 0), (170, 0), (230, 96), (90, 96)])
    p.fill(cone, (40, 120, 150))
    for k, y in enumerate((70, 80, 90)):
        p.fill((np.abs(p.y - y) < 2.5) & (np.sin(p.x / 9 + k) > 0.2), (130, 150, 160))
    ship(p, 160, 66, 1.4)
    return p


def act1():
    """ATMOSPHERIC BREAKOUT: the ship climbing out of the air, the Earth's
    curve below, HALO STATION's ring above among dead satellites."""
    p = Pic(160, 96, (0, 0, 10))
    p.vgrad(0, 96, (0, 0, 12), (70, 40, 130), steps=2)
    p.stars(40, 1, below=60)
    earth = p.disc(160, 400, 330)
    p.fill(earth, (30, 90, 200))
    p.fill(earth & (np.sin(p.x / 13) * np.sin(p.y / 3) > 0.45), (230, 240, 250))
    p.fill(~earth & p.disc(160, 400, 334), (150, 200, 255))      # the air's thin rim
    # HALO STATION, a ring
    ring = (np.hypot((p.x - 250) / 1.0, (p.y - 20) / 0.55) < 34) & (np.hypot((p.x - 250), (p.y - 20) / 0.55) > 26)
    p.fill(ring, (150, 150, 160))
    p.fill(p.disc(250, 20, 7), (90, 90, 110))
    p.fill(p.disc(250, 20, 3), (255, 60, 60))
    for k in range(5):                                     # debris
        p.fill(p.disc(40 + k * 50, 12 + (k * 23) % 40, 2.5), (110, 110, 120))
    # the ship, its exhaust trail
    p.fill(p.poly([(156, 64), (164, 64), (172, 96), (148, 96)]), (60, 120, 255))
    p.fill(p.poly([(158, 64), (162, 64), (165, 96), (155, 96)]), (190, 230, 255))
    ship(p, 160, 52, 1.2)
    return p


def act2():
    """INTO THE DEEP FIELD: the Moon falling behind, the asteroid drift
    ahead, the hive deep inside it."""
    p = Pic(160, 96, (0, 0, 8))
    p.stars(55, 2)
    moon = p.disc(40, 90, 46)
    p.fill(moon, (150, 150, 150))
    p.fill(moon & ~p.disc(55, 80, 46), (90, 90, 95))      # its shadowed side
    for cx, cy, r in ((30, 70, 6), (52, 84, 5), (22, 92, 4)):
        p.fill(moon & p.disc(cx, cy, r), (110, 110, 112))
    rng = np.random.default_rng(8)
    for _ in range(9):                                     # the asteroids
        cx, cy, r = rng.uniform(110, 300), rng.uniform(10, 85), rng.uniform(5, 13)
        rock = p.disc(cx, cy, r)
        p.fill(rock, (120, 100, 86))
        p.fill(rock & ~p.disc(cx - r * 0.35, cy - r * 0.35, r), (60, 50, 46))
    hive = (np.hypot((p.x - 255) / 1.3, (p.y - 40) / 1.0) < 22)
    p.fill(hive, (100, 30, 100))
    p.fill(hive & (np.sin(p.x / 4) * np.sin(p.y / 3) > 0.5), (160, 80, 160))
    p.fill(p.disc(255, 40, 5), (255, 60, 40))
    ship(p, 150, 70, 1.0)
    return p


def act3():
    """THE SOLAR CORONA: the Sun filling the sky, its prominences, and
    GAMMA PRIME, a golden sunburst at its heart."""
    p = Pic(160, 96, (70, 0, 0))
    sun = p.disc(160, 220, 170)
    p.fill(sun, (230, 110, 20))
    p.fill(sun & (np.sin(p.x / 7) * np.sin(p.y / 2.5) > 0.55), (150, 50, 0))
    for cx in (60, 250):                                   # prominences
        d = np.abs(np.hypot((p.x - cx) / 1.0, (p.y - 62) / 1.2) - 26)
        p.fill((d < 3.5) & (p.y < 62), (255, 200, 80))
    # GAMMA PRIME: eight rays round a collar, its light
    a = np.arctan2(p.y - 40, (p.x - 160) / 1.0)
    r = np.hypot(p.x - 160, p.y - 40)
    rays = (r < 30) & (np.cos(a * 8) > 0.55)
    p.fill(rays | (r < 18), (230, 180, 40))
    p.fill(r < 11, (120, 70, 0))
    p.fill(r < 7, (255, 250, 200))
    ship(p, 160, 84, 0.8, hull=(220, 220, 240))
    return p


def epilogue():
    """A QUIET SUN: the ship turning for home, the Earth's crescent
    ahead, the Sun quiet and warm behind."""
    p = Pic(160, 96, (0, 0, 20))
    p.stars(50, 5)
    glow = p.disc(0, 96, 120)
    p.fill(glow, (200, 120, 20))
    p.fill(p.disc(0, 96, 60), (255, 230, 150))
    earth = p.disc(260, 40, 40)
    p.fill(earth, (20, 50, 140))
    p.fill(earth & ~p.disc(275, 34, 40), (90, 160, 255))   # its sunlit edge
    p.fill(earth & ~p.disc(275, 34, 40) & (np.sin(p.y / 2) > 0.6), (230, 240, 255))
    ship(p, 170, 62, 1.0)
    return p


def maya():
    """Captain Maya Kestrel: an orange helmet, its gold visor up, her face."""
    p = Pic(32, 48, (10, 10, 30))
    p.fill(p.disc(32, 22, 21), (230, 90, 20))              # the helmet
    p.fill(p.disc(32, 22, 21) & (p.y < 12), (250, 210, 40))   # the visor, raised
    p.fill(p.disc(32, 22, 21) & (np.abs(p.x - 32) < 3) & (p.y > 12), (245, 245, 245))  # its stripe
    p.fill(p.disc(32, 26, 13), (240, 180, 140))            # her face
    p.fill(p.disc(26, 24, 1.6) | p.disc(38, 24, 1.6), (40, 40, 70))
    p.fill(p.poly([(10, 48), (54, 48), (46, 38), (18, 38)]), (70, 80, 120))   # the flight suit
    return p


def thorne():
    """Dr. Nathan Thorne: dark hair, glasses, a headset; his jacket."""
    p = Pic(32, 48, (20, 30, 20))
    p.fill(p.disc(32, 24, 14), (220, 170, 130))            # his face
    p.fill(p.disc(32, 16, 14) & (p.y < 17), (30, 25, 25))  # hair
    p.fill((np.abs(p.y - 24) < 1.6) & (np.abs(p.x - 32) < 13), (30, 25, 25))  # glasses
    p.fill(p.disc(26, 24, 3) | p.disc(38, 24, 3), (130, 200, 130))
    p.fill(p.disc(17, 25, 3.5), (30, 25, 25))              # the headset
    p.fill(p.poly([(8, 48), (56, 48), (48, 39), (16, 39)]), (40, 50, 90))     # the jacket
    return p


def gamma():
    """GAMMA PRIME's voice: its sunburst eye."""
    p = Pic(32, 48, (30, 0, 0))
    a = np.arctan2(p.y - 24, p.x - 32)
    r = np.hypot(p.x - 32, p.y - 24)
    p.fill((r < 22) & (np.cos(a * 8) > 0.5) | (r < 13), (230, 180, 40))
    p.fill(r < 9, (150, 20, 20))
    p.fill(r < 4, (255, 240, 200))
    return p


PANELS = {"prologue": prologue, "act1": act1, "act2": act2, "act3": act3, "epilogue": epilogue}
PORTRAITS = {"maya": maya, "thorne": thorne, "gamma": gamma}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, table, npal in (("panel", PANELS, cs.NPAL), ("portrait", PORTRAITS, cs.PORTRAIT_NPAL)):
        for name, draw in table.items():
            if (OUT / f"{name}.png").exists() and "--force" not in sys.argv:
                print(f"{kind} {name}: there already (left alone; --force to redraw)")
                continue
            img = cs.snap(draw().rgb())
            fitted, bg, pals, which, notes = cs.fit(img, npal=npal)
            rgb = cs.PAL7800[fitted].astype(np.uint8)
            Image.fromarray(rgb).save(OUT / f"{name}.png")
            cs.preview(fitted, 4).save(OUT / f"{name}_preview.png")
            print(f"{kind} {name}: background ${bg:02X}, {len(pals)} palettes, {len(notes)} fixes")


if __name__ == "__main__":
    main()
