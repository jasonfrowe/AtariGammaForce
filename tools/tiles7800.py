"""Stage 1's background tiles, drawn for the 7800.

The map (from MegaGammaForce's generator) names its tiles; these are new
pictures for the same names, 8 pixels by 16 lines each (square on screen),
in three flat colors: 1 dark, 2 plate, 3 light. Open sea is the background
color, so sea tiles are blank and deck edges are cut out against it.

    tiles(ids) -> (list of 8x16 slot arrays, list of palette numbers)
"""

import math

import numpy as np

W, H = 8, 16
DECK, DETAIL = 1, 2  # palettes (gen_assets.PALETTES)


def plate(light=3):
    """A deck plate: flat, lit from the top left, seams at its edges.
    Detail tiles pass light=2: their palette's third color is amber."""
    t = np.full((H, W), 2, dtype=np.uint8)
    t[0, :] = light
    t[:, 0] = light
    t[H - 1, :] = 1
    t[:, W - 1] = 1
    t[0, W - 1] = 2
    t[H - 1, 0] = 2
    return t


def edge(corners):
    """Marching-squares edge: corners (tl, tr, br, bl), 1 = deck."""
    tl, tr, br, bl = corners
    t = np.zeros((H, W), dtype=np.uint8)
    p = plate()
    f = np.zeros((H, W))
    for y in range(H):
        for x in range(W):
            u, v = (x + 0.5) / W, (y + 0.5) / H
            f[y, x] = tl * (1 - u) * (1 - v) + tr * u * (1 - v) + br * u * v + bl * (1 - u) * v
    deck = f >= 0.5
    t[deck] = p[deck]
    # A rim along the cut: light where the deck faces up or left, dark
    # where it faces down or right (the light comes from the top left).
    for y in range(H):
        for x in range(W):
            if not deck[y, x]:
                continue
            up = y == 0 or not deck[y - 1, x]
            left = x == 0 or not deck[y, x - 1]
            down = y == H - 1 or not deck[y + 1, x]
            right = x == W - 1 or not deck[y, x + 1]
            # only real cuts, not the tile's own border
            up &= y > 0
            left &= x > 0
            down &= y < H - 1
            right &= x < W - 1
            if down or right:
                t[y, x] = 1
            elif up or left:
                t[y, x] = 3
    return t


def variant(kind):
    t = plate(2 if kind in (3, 4, 7) else 3)
    if kind == 1:  # rivets
        for x, y in ((2, 3), (5, 3), (2, 12), (5, 12)):
            t[y, x] = 1
            t[y - 1, x] = 3
    elif kind == 2:  # vent
        t[3:13, 2:6] = 1
        for y in (5, 8, 11):
            t[y, 2:6] = 2
    elif kind == 3:  # lamp (detail palette: 3 = amber)
        t[5:11, 2:6] = 1
        t[6:10, 3:5] = 3
    elif kind == 4:  # hazard stripes (detail palette)
        t[2:14, :] = 1
        for y in range(2, 14):
            for x in range(W):
                if ((x * 2 + y) // 4) % 2 == 0:
                    t[y, x] = 3
    elif kind == 5:  # horizontal pipe
        t[5, :] = 3
        t[6:10, :] = 2
        t[10, :] = 1
    elif kind == 6:  # vertical pipe
        t[:, 2] = 3
        t[:, 3:5] = 2
        t[:, 5] = 1
    elif kind == 7:  # status lights strip (detail palette)
        t[6:10, :] = 1
        for x in (1, 4, 7):
            if x < W:
                t[7:9, x] = 3
    return t


def hatch():
    """A round hatch two tiles across: 16 pixels by 32 lines (32 x 32 on
    screen), four tiles TL, TR, BL, BR. Detail palette."""
    big = np.zeros((32, 16), dtype=np.uint8)
    for ty in range(2):
        for tx in range(2):
            big[ty * H:(ty + 1) * H, tx * W:(tx + 1) * W] = plate(2)
    for y in range(32):
        for x in range(16):
            dx, dy = (x + 0.5 - 8) * 2, y + 0.5 - 16
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            if d < 13:
                big[y, x] = 3 if math.cos(a + 2.3) > 0.2 else 1   # the rim, lit top left
            if d < 11:
                big[y, x] = 2
            if 4 < d < 9 and (int((a + math.pi) / (math.pi / 4)) % 2 == 0):
                big[y, x] = 1                                       # shutter blades
            if d < 3:
                big[y, x] = 3                                       # centre light
    return [big[0:16, 0:8], big[0:16, 8:16], big[16:32, 0:8], big[16:32, 8:16]]


def tiles(ids):
    n = len(ids)
    out = [None] * n
    pals = [DECK] * n
    for name, i in ids.items():
        if name.startswith("sea"):
            out[i] = np.zeros((H, W), dtype=np.uint8)
            pals[i] = 0  # a palette of their own, so sea never joins a deck run
        elif name.startswith("edge"):
            cfg = int(name[4:])
            out[i] = edge(((cfg >> 3) & 1, (cfg >> 2) & 1, (cfg >> 1) & 1, cfg & 1))
        elif name.startswith("deck"):
            k = int(name[4:])
            out[i] = variant(k)
            if k in (3, 4, 7):
                pals[i] = DETAIL
        elif name.startswith("hatch"):
            out[i] = hatch()[int(name[5:])]
            pals[i] = DETAIL
    return out, pals


# ---------------------------------------------------------------------------
# Stage 2, NEON SPIRES: a city at night. Palettes: P1 roofs (1 dark, 2 roof,
# 3 lit edge), P2 the same with 3 amber (lights, signs, lane dashes), P0
# neon (1 dark violet, 2 violet, 3 magenta; the boss's too). The asphalt is
# the background color, so roads draw only their markings.

ROOF, LIGHTS, NEON = 1, 2, 0


def _roof(edges):
    """A plain rooftop tile; edges (n, e, s, w): the building's edge on that
    side. Lit from the top left: a light parapet north and west, dark
    south and east. A south edge (the street side) carries amber signs,
    so it is drawn in the lights palette."""
    n, e, s, w = edges
    t = np.full((H, W), 2, dtype=np.uint8)
    t[7, 2:6:3] = 1                     # panel seam rivets
    if n:
        t[0, :] = 3
        t[1, :] = 3
    if w:
        t[:, 0] = 3
    if s:
        t[H - 1, :] = 1
        t[H - 2, :] = 1
        t[H - 4, 1:W - 1:3] = 3         # signs (amber in the lights palette)
    if e:
        t[:, W - 1] = 1
    if n and w:
        t[3:5, 2:4] = 1                 # a vent in the corner
    return t


def _glass():
    """A glass roof: dark panes in a frame, some lit (amber)."""
    t = np.full((H, W), 2, dtype=np.uint8)
    lit = {(0, 1), (1, 0), (2, 1)}
    for py in range(3):
        for px in range(2):
            t[1 + py * 5:5 + py * 5, 1 + px * 4:4 + px * 4] = 3 if (py, px) in lit else 1
    return t


def _machinery():
    """Rooftop plant: an AC unit with a fan, and a vent."""
    t = np.full((H, W), 2, dtype=np.uint8)
    t[2:9, 1:7] = 3
    t[3:8, 2:6] = 1
    t[5, 2:6] = 2
    t[8, 1:7] = 1
    t[11:14, 2:6] = 1
    t[12, 2:6] = 2
    return t


def _road_h():
    t = np.zeros((H, W), dtype=np.uint8)
    t[0, :] = 1                         # curbs
    t[H - 1, :] = 1
    t[7, 0:3] = 3                       # lane dashes
    t[8, 0:3] = 3
    t[7, 5:7] = 2
    return t


def _road_v():
    t = np.zeros((H, W), dtype=np.uint8)
    t[:, 0] = 1
    t[:, W - 1] = 1
    t[2:7, 3:5] = 3
    t[10:15, 3:5] = 3
    return t


def _cross():
    t = np.zeros((H, W), dtype=np.uint8)
    for k in range(1, W - 1, 2):        # crosswalk stripes top and bottom
        t[1:3, k] = 2
        t[H - 3:H - 1, k] = 2
    t[6:10, 3:5] = 3                    # the signal lamp
    t[7:9, 2:6] = 3
    return t


def _pad():
    """A 2x2 rooftop gun pad (16 px by 32 lines): an amber ring on the roof."""
    big = np.full((32, 16), 2, dtype=np.uint8)
    for y in range(32):
        for x in range(16):
            dx, dy = (x + 0.5 - 8) * 2, y + 0.5 - 16
            d = math.hypot(dx, dy)
            if d < 14:
                big[y, x] = 1
            if 11 < d < 14 and (int(math.atan2(dy, dx) * 4 / math.pi + 8) % 2 == 0):
                big[y, x] = 3
            if d < 6:
                big[y, x] = 2
            if d < 2.5:
                big[y, x] = 3
    big[0, :] = 3
    big[:, 0] = 3
    return big


def _heli():
    """A 2x2 helipad: a magenta ring and H on violet (the neon palette)."""
    big = np.full((32, 16), 1, dtype=np.uint8)
    for y in range(32):
        for x in range(16):
            dx, dy = (x + 0.5 - 8) * 2, y + 0.5 - 16
            d = math.hypot(dx, dy)
            if d < 13:
                big[y, x] = 2
            if 10.5 < d < 13:
                big[y, x] = 3
    big[9:23, 4:6] = 3                  # the H
    big[9:23, 10:12] = 3
    big[15:17, 4:12] = 3
    return big


def _lamp():
    """A street lamp on the dark plaza: a post's shadow and an amber light."""
    t = np.zeros((H, W), dtype=np.uint8)
    t[6:10, 3:5] = 3
    t[5, 3:5] = 2
    t[10, 3:5] = 2
    t[11:14, 4] = 1
    return t


def _quarters(big):
    """TL, TR, BL, BR tiles of a 16 x 32 picture (MegaGammaForce's pad
    order: pad0/1 the top row, pad2/3 the bottom)."""
    return [big[0:16, 0:8], big[0:16, 8:16], big[16:32, 0:8], big[16:32, 8:16]]


def city_tiles(ids):
    """Our city tileset for MegaGammaForce's city tile names (city.py).
    Returns (tiles, palettes, lut): lut[mgf tile id] = our tile number.
    Tile 0 is blank (the background), for the columns outside the city."""
    tiles, pals, by_key = [np.zeros((H, W), dtype=np.uint8)], [ROOF], {}

    def add(key, t, pal):
        if key not in by_key:
            by_key[key] = len(tiles)
            tiles.append(t)
            pals.append(pal)
        return by_key[key]

    lut = {}
    pad, heli = _quarters(_pad()), _quarters(_heli())
    for name, i in ids.items():
        if name.startswith("rh"):
            lut[i] = add("rh", _road_h(), LIGHTS)
        elif name.startswith("rv"):
            lut[i] = add("rv", _road_v(), LIGHTS)
        elif name == "cross":
            lut[i] = add("cross", _cross(), LIGHTS)
        elif name.startswith("roof"):
            style, e = name[4:].split("_")
            e = int(e)
            edges = ((e >> 3) & 1, (e >> 2) & 1, (e >> 1) & 1, e & 1)
            if e == 0 and style == "1":
                lut[i] = add("glass", _glass(), LIGHTS)
            elif e == 0 and style == "2":
                lut[i] = add("plant", _machinery(), ROOF)
            else:
                lut[i] = add(f"roof{e}", _roof(edges), LIGHTS if edges[2] else ROOF)
        elif name.startswith("pad"):
            k = int(name[3:])
            lut[i] = add(name, pad[k], LIGHTS)
        elif name.startswith("heli"):
            k = int(name[4:])
            lut[i] = add(name, heli[k], NEON)
    # tiles of our own (no MegaGammaForce name): the boss plaza's lamps
    lut["lamp"] = add("lamp", _lamp(), LIGHTS)
    return tiles, pals, lut
