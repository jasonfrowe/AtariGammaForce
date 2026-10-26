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
