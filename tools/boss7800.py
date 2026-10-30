"""GAMMA CORE, the stage 1 boss, drawn for the 7800.

Shapes are described in screen units (a 160A pixel is 2 units wide, a line
1 unit tall), so circles come out round, then sampled into 160A pixels.
Palette (P0): 1 dark steel, 2 light steel, 3 red. No dithering: flat
plates, dark outlines and panel lines, a red eye.

    parts() -> dict name -> list of frames (uint8 slot arrays)
"""

import math

import numpy as np


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h            # in 160A pixels and lines
        self.a = np.zeros((h, w), dtype=np.uint8)

    def fill(self, inside, c):
        """Set every pixel whose centre (screen units) satisfies inside(x, y)."""
        for py in range(self.h):
            for px in range(self.w):
                x, y = px * 2 + 1.0, py + 0.5
                if inside(x, y):
                    self.a[py, px] = c

    def outline(self, c=1):
        """Dark outline: filled pixels that touch transparency."""
        a = self.a
        out = a.copy()
        for y in range(self.h):
            for x in range(self.w):
                if a[y, x] == 0:
                    continue
                n = [a[y + dy, x + dx] if 0 <= y + dy < self.h and 0 <= x + dx < self.w else 0
                     for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))]
                if 0 in n:
                    out[y, x] = c
        self.a = out


def poly(points):
    """Point-in-polygon test for a list of (x, y) in screen units."""
    def inside(x, y):
        n, hit = len(points), False
        j = n - 1
        for i in range(n):
            xi, yi = points[i]
            xj, yj = points[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                hit = not hit
            j = i
        return hit
    return inside


def circle(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 < r * r


def ring(cx, cy, r0, r1):
    return lambda x, y: r0 * r0 <= (x - cx) ** 2 + (y - cy) ** 2 < r1 * r1


def core():
    """The core: 32 px (64 units) by 64 lines, an armored pod with the eye."""
    c = Canvas(32, 64)
    body = poly([(10, 4), (54, 4), (63, 18), (63, 46), (48, 62), (16, 62), (1, 46), (1, 18)])
    c.fill(body, 2)
    c.outline(1)
    # shading: the flanks and the lower chevron in dark steel (lit from the top left)
    c.fill(lambda x, y: body(x, y) and (x > 50 or (y > 46 and abs(x - 32) > 62 - y)), 1)
    c.fill(lambda x, y: body(x, y) and x < 12 and 18 < y < 46 and (int(y) % 4 == 0), 1)
    # panel lines and vents
    c.fill(lambda x, y: body(x, y) and (abs(y - 14) < 0.6 or abs(y - 52) < 0.6), 1)
    c.fill(lambda x, y: body(x, y) and 6 < y < 14 and abs(x - 32) < 1.5, 1)
    c.fill(lambda x, y: body(x, y) and (abs(x - 8) < 1.5 or abs(x - 56) < 1.5) and 20 < y < 44, 1)
    # the eye: dark ring, red disc, a light glint
    c.fill(circle(32, 32, 17), 1)
    c.fill(circle(32, 32, 14), 3)
    c.fill(ring(32, 32, 7, 9), 1)
    c.fill(circle(27, 27, 3), 2)
    return [c.a]


def wing(mirror=False):
    """A wing: 16 px (32 units) by 64 lines, with two turret sockets."""
    c = Canvas(16, 64)
    body = poly([(4, 2), (30, 10), (30, 54), (4, 62), (2, 58), (2, 6)])
    c.fill(body, 2)
    c.outline(1)
    c.fill(lambda x, y: body(x, y) and abs(y - 32) < 0.6, 1)
    c.fill(lambda x, y: body(x, y) and x > 24, 1)            # the shaded outer band
    c.fill(lambda x, y: body(x, y) and x > 24 and int(y) % 6 == 0, 2)
    for sy in (16, 38):  # turret sockets (the turrets sit over them)
        c.fill(circle(14, sy + 8, 7), 1)
    a = c.a[:, ::-1] if mirror else c.a
    return [a.copy()]


def cannon():
    """The belly cannon: 16 px by 32 lines; frame 2 glows before it fires."""
    frames = []
    for glow in (False, True):
        c = Canvas(16, 32)
        c.fill(poly([(2, 0), (30, 0), (30, 12), (22, 18), (10, 18), (2, 12)]), 2)
        c.fill(poly([(11, 16), (21, 16), (21, 30), (11, 30)]), 2)
        c.outline(1)
        c.fill(lambda x, y: abs(y - 6) < 0.6 and 4 < x < 28, 1)
        c.fill(circle(16, 9, 4), 3 if glow else 1)
        if glow:
            c.fill(poly([(13, 26), (19, 26), (19, 31), (13, 31)]), 3)
        frames.append(c.a)
    return frames


def turret():
    """A wing turret: 8 px by 16 lines, eight directions (frame 0 = down,
    then turning clockwise as the aim angle grows)."""
    frames = []
    for k in range(8):
        c = Canvas(8, 16)
        ang = math.pi / 2 + k * math.pi / 4      # 0 = down (+y), increasing
        dx, dy = math.cos(ang), math.sin(ang)
        # barrel: a thick line from the centre outwards
        def barrel(x, y, dx=dx, dy=dy):
            px, py = x - 8, y - 8
            t = px * dx + py * dy
            d = abs(px * dy - py * dx)
            return 2 <= t <= 8 and d < 1.6
        c.fill(barrel, 2)
        c.fill(circle(8, 8, 5.5), 2)
        c.outline(1)
        c.fill(circle(8, 8, 2.2), 3)
        frames.append(c.a)
    return frames


def parts():
    co = core()[0]
    wl, wr = wing()[0], wing(True)[0]
    return {
        "bcoret": [co[:32]], "bcoreb": [co[32:]],
        "bwinglt": [wl[:32]], "bwinglb": [wl[32:]],
        "bwingrt": [wr[:32]], "bwingrb": [wr[32:]],
        "bcannon": cannon(),
        "bturret": turret(),
    }


# ---------------------------------------------------------------------------
# SPIRE WARDEN, the stage 2 boss. Palette P0 in stage 2 (neon): 1 dark
# violet, 2 violet, 3 magenta.

def core2(open_eye=True):
    """The defence core: 32 px by 64 lines, an armored spire with a ringed
    eye, fins top and bottom. Closed, armored shutters cover the eye."""
    c = Canvas(32, 64)
    body = poly([(32, 0), (52, 10), (60, 28), (60, 40), (50, 56), (32, 63), (14, 56), (4, 40), (4, 28), (12, 10)])
    c.fill(body, 2)
    c.outline(1)
    # facets: the right side in shadow, ridges down the middle
    c.fill(lambda x, y: body(x, y) and x > 44 and 12 < y < 52, 1)
    c.fill(lambda x, y: body(x, y) and abs(x - 32) < 1.5 and (y < 16 or y > 48), 1)
    c.fill(lambda x, y: body(x, y) and (abs(y - 14) < 0.6 or abs(y - 50) < 0.6) and 14 < x < 50, 1)
    # the eye
    c.fill(circle(32, 32, 15), 1)
    if open_eye:
        c.fill(ring(32, 32, 9, 13), 3)
        c.fill(circle(32, 32, 6), 3)
        c.fill(circle(29, 29, 2), 2)
    else:
        # two shutters meeting in a dark seam, a glint of the eye between
        c.fill(lambda x, y: (x - 32) ** 2 + (y - 32) ** 2 < 13 * 13 and abs(y - 32) > 1.2, 2)
        c.fill(lambda x, y: (x - 32) ** 2 + (y - 32) ** 2 < 13 * 13 and abs(y - 32) > 1.2
               and int(x) % 8 == 0, 1)
        c.fill(lambda x, y: abs(y - 32) <= 1.2 and abs(x - 32) < 4, 3)
    return [c.a]


def pod():
    """An orbiting pod: 16 px by 32 lines (a 32 x 32 ball on screen), two
    frames: its band of lights turns."""
    frames = []
    for f in range(2):
        c = Canvas(16, 32)
        c.fill(circle(16, 16, 15), 2)
        c.outline(1)
        c.fill(lambda x, y: (x - 16) ** 2 + (y - 16) ** 2 < 225 and x + y > 38, 1)   # shadow, lower right
        c.fill(lambda x, y: abs(y - 16) < 2.2 and (x - 16) ** 2 < 196, 1)              # the band
        for k in range(4):
            cx = 4 + k * 8 + (4 if f else 0)
            c.fill(circle(cx, 16, 1.6), 3 if k % 2 == f else 2)
        c.fill(circle(11, 9, 3), 3)                                                   # glint
        frames.append(c.a)
    return frames


def cannon2():
    """The twin cannon slung beneath: 16 px by 32 lines; frame 2 glows
    before a sweep."""
    frames = []
    for glow in (False, True):
        c = Canvas(16, 32)
        c.fill(poly([(4, 0), (28, 0), (30, 10), (22, 16), (10, 16), (2, 10)]), 2)
        c.fill(poly([(8, 14), (13, 14), (13, 31), (8, 31)]), 2)
        c.fill(poly([(19, 14), (24, 14), (24, 31), (19, 31)]), 2)
        c.outline(1)
        c.fill(circle(16, 7, 3.5), 3 if glow else 1)
        if glow:
            c.fill(lambda x, y: y > 27 and (8 < x < 13 or 19 < x < 24), 3)
        frames.append(c.a)
    return frames


def parts2():
    """Frames: the core closed (0) and open (1)."""
    shut, op = core2(False)[0], core2(True)[0]
    return {"b2coret": [shut[:32], op[:32]], "b2coreb": [shut[32:], op[32:]],
            "b2pod": pod(), "b2cannon": cannon2()}


# ---------------------------------------------------------------------------
# LEVIATHAN, the stage 3 battleship: the parts that ride its hull (the hull
# itself is map tiles). Palette P0 in stage 3: 1 dark steel, 2 steel, 3 red.

def bridge3():
    """The bridge: 32 px by 64 lines, stepped decks, a radar dish, a mast,
    lit windows."""
    c = Canvas(32, 64)
    outer = poly([(8, 60), (8, 18), (16, 6), (48, 6), (56, 18), (56, 60)])
    c.fill(outer, 2)
    c.outline(1)
    c.fill(lambda x, y: outer(x, y) and x > 48, 1)                      # the shaded side
    c.fill(lambda x, y: 14 <= x < 50 and 22 <= y < 56 and (abs(x - 14) < 1.5 or abs(y - 22) < 1), 1)
    c.fill(lambda x, y: 20 <= x < 44 and 28 <= y < 50 and (abs(x - 43) < 1.5 or abs(y - 49) < 1), 1)
    c.fill(lambda x, y: 22 <= x < 42 and 44 <= y < 47 and int(x) % 4 < 2, 3)  # windows
    c.fill(ring(32, 15, 5, 8), 1)                                        # the radar dish
    c.fill(lambda x, y: abs(x - 32) < 1.5 and 2 <= y < 15, 1)            # the mast
    c.fill(circle(32, 3, 2), 3)
    c.fill(lambda x, y: 10 <= x < 54 and 56 <= y < 59, 1)
    return [c.a]


def reactor3():
    """The reactor: 16 px by 32 lines, a red core under an armored ring;
    frames: it pulses."""
    frames = []
    for hot in (False, True):
        c = Canvas(16, 32)
        c.fill(circle(16, 16, 15), 2)
        c.outline(1)
        for a in range(0, 360, 60):
            x, y = 16 + math.cos(math.radians(a)) * 11, 16 + math.sin(math.radians(a)) * 11
            c.fill(circle(x, y, 2.5), 1)
        c.fill(circle(16, 16, 8), 1)
        c.fill(circle(16, 16, 7 if hot else 5), 3)
        frames.append(c.a)
    return frames


def gun3():
    """A main gun: 12 px by 16 lines, twin barrels aimed in 8 directions
    (frame 0 down, turning clockwise as the aim angle grows)."""
    frames = []
    for k in range(8):
        a = math.pi / 2 + k * math.pi / 4
        dx, dy = math.cos(a), math.sin(a)
        c = Canvas(12, 16)
        for side in (-2.5, 2.5):
            ox, oy = -dy * side, dx * side
            def barrel(x, y, ox=ox, oy=oy):
                px, py = x - 12 - ox, y - 8 - oy
                t = px * dx + py * dy
                return 0 <= t <= 10 and abs(px * dy - py * dx) < 1.4
            c.fill(barrel, 2)
        c.fill(circle(12, 8, 6.5), 2)
        c.outline(1)
        c.fill(circle(12, 8, 2.5), 3)
        frames.append(c.a)
    return frames


def gunboat():
    """A gunboat (stage 3): 16 px by 32 lines, sailing up the screen: a
    pointed hull, a deck gun, a wake that churns (two frames)."""
    frames = []
    for f in range(2):
        c = Canvas(16, 32)
        hull = poly([(16, 1), (26, 10), (26, 26), (22, 30), (10, 30), (6, 26), (6, 10)])
        c.fill(hull, 2)
        c.outline(1)
        c.fill(lambda x, y: hull(x, y) and x > 21, 1)
        c.fill(circle(16, 12, 4.5), 1)                                    # the gun
        c.fill(circle(16, 12, 2.5), 3)
        c.fill(lambda x, y: abs(x - 16) < 1.2 and 3 <= y < 9, 3)
        c.fill(lambda x, y: 11 <= x < 21 and 19 <= y < 25, 1)             # the wheelhouse
        c.fill(lambda x, y: 13 <= x < 19 and 20 <= y < 22, 3)
        for k in range(3):                                                # wake
            y = 30 + (k + f) % 2
            c.fill(lambda x, yy, y=y, k=k: int(yy) == y and abs(x - 16) > 6 + k * 2 and abs(x - 16) < 9 + k * 2, 3)
        frames.append(c.a)
    return frames


def bay3():
    """A missile bay, 8 px by 32 lines, over its two hull tiles: frame 0
    shut (the tiles' hazard doors, so it shows only when it flashes), 1
    open (a dark pit, two missiles, red rims), 2 a crater, drawn when it is
    a wreck (in P1, the hull's steel: 1 dark, 2 steel, 3 light)."""
    import tiles7800
    W, H = tiles7800.W, tiles7800.H
    door = np.full((H, W), 1, dtype=np.uint8)
    for y in range(1, H):
        for x in range(1, W - 1):
            door[y, x] = 3 if ((x + y) // 3) % 2 == 0 else 1
    shut = np.concatenate([door, door[::-1]])
    pit = np.full((2 * H, W), 1, dtype=np.uint8)
    pit[0, :] = 3
    pit[-1, :] = 3
    pit[:, 0] = 3
    pit[:, W - 1] = 3
    for x0 in (2, 5):                       # two missiles, noses up
        pit[5:27, x0] = 2
        pit[4:7, x0] = 3
        pit[24:27, x0] = 1
    crater = np.zeros((2 * H, W), dtype=np.uint8)
    rng = np.random.default_rng(3)
    for y in range(2 * H):
        for x in range(W):
            d = ((x - 3.5) / 4.2) ** 2 + ((y - 15.5) / 15.5) ** 2 + rng.uniform(-0.15, 0.15)
            if d < 0.45:
                crater[y, x] = 1 if rng.uniform() < 0.8 else 0      # scorched, holed through
            elif d < 0.75:
                crater[y, x] = 1
            elif d < 1.0:
                crater[y, x] = 3 if rng.uniform() < 0.5 else 2      # torn plate
    return [shut, pit, crater]


def parts3():
    br = bridge3()[0]
    return {"b3bridget": [br[:32]], "b3bridgeb": [br[32:]], "b3reactor": reactor3(), "b3gun": gun3(),
            "gunboat": gunboat(), "b3bay": bay3()}


# ---------------------------------------------------------------------------
# Stage 4: the armored train (an enemy, in the chain colors: 1 dark, 2 the
# color, 3 glow) and DUNE WYRM, the sandworm (P0 in stage 4: 1 dark, 2
# bone shell, 3 the glowing maw).

def train():
    """32-line train cars on the rails, heading up the screen, 16 px wide:
    frame 0 the locomotive, frame 1 a gun car."""
    frames = []
    for loco in (True, False):
        c = Canvas(16, 32)
        for y in (5, 22):                                                 # bogies
            c.fill(lambda x, yy, y=y: 6 <= x < 26 and y <= yy < y + 6, 1)
        if loco:
            body = poly([(16, 0), (25, 8), (25, 31), (7, 31), (7, 8)])
        else:
            body = poly([(7, 2), (25, 2), (25, 31), (7, 31)])
        c.fill(body, 2)
        c.outline(1)
        if loco:
            c.fill(lambda x, y: 11 <= x < 21 and 12 <= y < 15, 3)            # the cab's windows
            c.fill(lambda x, y: 11 <= x < 21 and 18 <= y < 29 and int(y) % 3 == 0, 1)  # grille
            c.fill(circle(13, 4, 1.6), 3)                                   # lamps
            c.fill(circle(19, 4, 1.6), 3)
        else:
            c.fill(circle(16, 16, 6.5), 1)                                  # the turret
            c.fill(circle(16, 16, 4.5), 2)
            c.fill(lambda x, y: abs(x - 16) < 1.5 and 3 <= y < 14, 1)       # its barrel, forward
            c.fill(circle(16, 16, 1.6), 3)
            c.fill(lambda x, y: 9 <= x < 23 and (int(y) in (4, 28)), 1)
        frames.append(c.a)
    return frames


def wyrm_head():
    """The head: 24 px by 48 lines, an armored skull over a round maw that
    opens toward the bottom of the screen; frames: the maw glows."""
    frames = []
    for hot in (False, True):
        c = Canvas(24, 48)
        skull = poly([(24, 1), (38, 6), (46, 20), (44, 36), (36, 47), (12, 47), (4, 36), (2, 20), (10, 6)])
        c.fill(skull, 2)
        c.outline(1)
        c.fill(poly([(24, 5), (34, 10), (37, 19), (24, 23), (11, 19), (14, 10)]), 1)   # the brow plate
        c.fill(poly([(24, 8), (31, 11), (33, 17), (24, 20), (15, 17), (17, 11)]), 2)
        c.fill(circle(12, 15, 2.5), 3)                                      # eyes
        c.fill(circle(36, 15, 2.5), 3)
        c.fill(circle(24, 35, 11), 1)                                       # the maw
        c.fill(circle(24, 35, 8 if hot else 7), 3)
        c.fill(circle(24, 35, 3.5 if hot else 4.5), 1)                      # the throat
        for k in range(8):                                                  # teeth round it
            a = math.radians(k * 45 + 22)
            x, y = 24 + math.cos(a) * 9.5, 35 + math.sin(a) * 9.5
            c.fill(circle(x, y, 1.7), 2)
        frames.append(c.a)
    return frames


def wyrm_segment():
    """A body ring: 16 px by 32 lines, a bone shell with a dark band and
    spines; frame 1 has a glowing vent, so neighbors differ."""
    frames = []
    for k in range(2):
        c = Canvas(16, 32)
        c.fill(lambda x, y: ((x - 16) / 14.5) ** 2 + ((y - 17) / 13.5) ** 2 < 1, 2)
        for x in (9, 16, 23):
            c.fill(poly([(x - 2.5, 7), (x, 0), (x + 2.5, 7)]), 2)            # spines
        c.outline(1)
        c.fill(lambda x, y: ((x - 16) / 9.5) ** 2 + ((y - 17) / 8.5) ** 2 < 1
               and not ((x - 16) / 7.5) ** 2 + ((y - 17) / 6.5) ** 2 < 1, 1)   # the plate's rim
        c.fill(lambda x, y: 6 <= x < 26 and 16 <= y < 19, 3 if k else 1)    # the band
        frames.append(c.a)
    return frames


def wyrm_tail():
    """The tail: 16 px by 32 lines, a tapering shell and a glowing sting."""
    c = Canvas(16, 32)
    c.fill(poly([(5, 1), (27, 1), (23, 17), (16, 31), (9, 17)]), 2)
    c.outline(1)
    c.fill(poly([(10, 4), (22, 4), (19, 13), (13, 13)]), 1)
    c.fill(poly([(14, 17), (16, 30), (18, 17)]), 3)
    return [c.a]


def parts4():
    head = wyrm_head()
    return {"b4headt": [f[:32] for f in head], "b4headb": [f[32:] for f in head],
            "b4seg": wyrm_segment(), "b4tail": wyrm_tail(), "train": train()}


# ---------------------------------------------------------------------------
# Stage 5: GLACIER CRAWLER's parts (P0 in stage 5: 1 dark steel, 2 steel,
# 3 frost and the cryo glow), and the icebergs (P1, snow: 1 shadow, 2
# grey-blue ice, 3 snow).

def reactor5():
    """The cryo reactor: 16 px by 32 lines, a frosted dome ringed with
    vents over a glowing core; frames: it pulses."""
    frames = []
    for hot in (False, True):
        c = Canvas(16, 32)
        c.fill(circle(16, 16, 15), 2)
        c.outline(1)
        for a in range(0, 360, 45):
            x, y = 16 + math.cos(math.radians(a)) * 11.5, 16 + math.sin(math.radians(a)) * 11.5
            c.fill(circle(x, y, 2), 1)
        c.fill(circle(16, 16, 8.5), 1)
        c.fill(circle(16, 16, 7 if hot else 5), 3)
        if hot:
            c.fill(lambda x, y: abs(x - 16) < 1.2 and abs(y - 16) < 5, 2)  # the core's rods
        frames.append(c.a)
    return frames


def drill5():
    """The ice drill: 16 px by 32 lines, its housing at the top, the bit
    pointing down; frames: its spiral turns."""
    frames = []
    for k in range(2):
        c = Canvas(16, 32)
        c.fill(lambda x, y: 6 <= x < 26 and 0 <= y < 8, 2)
        bit = poly([(5, 7), (27, 7), (16, 31)])
        c.fill(bit, 2)
        c.outline(1)
        c.fill(lambda x, y: bit(x, y) and x > 18, 1)                     # the shaded side
        for j in range(4):
            y0 = 10 + j * 5 + k * 2.5
            c.fill(lambda x, y, y0=y0: bit(x, y) and 0 <= y - y0 - (x - 5) * 0.12 < 1.2, 3)
        c.fill(circle(16, 3.5, 2.5), 3)
        frames.append(c.a)
    return frames


def berg():
    """An iceberg: 32 px by 32 lines, a snowy top with ridges, its cliff
    face dark below it (the south side, toward the ship)."""
    c = Canvas(32, 32)
    rng = np.random.default_rng(5)
    pts = []
    for k in range(14):
        a = 2 * math.pi * k / 14
        r = 1 + rng.uniform(-0.18, 0.12)
        pts.append((32 + math.cos(a) * 29 * r, 13 + math.sin(a) * 11 * r))
    top = poly(pts)
    face = lambda x, y: any(top(x, y - d) for d in (3, 6, 9))           # noqa: E731
    c.fill(lambda x, y: face(x, y) and not top(x, y), 1)
    c.fill(top, 3)                                                       # snow
    c.fill(lambda x, y: top(x, y) and not top(x + 4, y + 2), 2)          # its shaded edge
    c.fill(lambda x, y: top(x, y) and abs((x - 2 * y) % 22 - 11) < 1.2 and 6 < y < 20, 2)  # ridges
    c.fill(lambda x, y: face(x, y) and not top(x, y) and int(x) % 7 == 0, 2)  # streaks in the cliff
    return [c.a]


def bridge5():
    """The command bridge: 16 px by 32 lines, an armored cabin with a lit
    window band, a mast and a lamp. The key part: once it falls, the
    crawler drives on."""
    c = Canvas(16, 32)
    cab = poly([(4, 30), (4, 10), (10, 4), (22, 4), (28, 10), (28, 30)])
    c.fill(cab, 2)
    c.outline(1)
    c.fill(lambda x, y: cab(x, y) and x > 23, 1)                       # the shaded side
    c.fill(lambda x, y: 8 <= x < 24 and 13 <= y < 17, 1)
    c.fill(lambda x, y: 9 <= x < 23 and 14 <= y < 16 and int(x) % 4 < 3, 3)  # the windows
    c.fill(lambda x, y: 8 <= x < 24 and 21 <= y < 27 and (abs(x - 8) < 1.5 or abs(y - 21) < 1), 1)
    c.fill(lambda x, y: abs(x - 16) < 1.2 and 0 <= y < 6, 1)            # the mast
    c.fill(circle(16, 1.5, 1.6), 3)
    return [c.a]


def slab():
    """A slab of shelf ice breaking away and falling: 32 px by 16 lines,
    snow on top, a jagged edge, the dark break under it."""
    c = Canvas(32, 16)
    rng = np.random.default_rng(8)
    top = [(2, 3)] + [(x, 1 + rng.uniform(0, 3)) for x in range(8, 60, 8)] + [(62, 3), (62, 10)] + \
          [(x, 10 + rng.uniform(-2, 2)) for x in range(56, 2, -7)] + [(2, 10)]
    slabp = poly(top)
    c.fill(lambda x, y: any(slabp(x, y - d) for d in (2, 4)) and not slabp(x, y), 1)  # the break
    c.fill(slabp, 3)
    c.fill(lambda x, y: slabp(x, y) and not slabp(x + 3, y + 2), 2)
    c.fill(lambda x, y: slabp(x, y) and abs((x + 3 * y) % 19 - 9) < 1, 2)  # cracks
    return [c.a]


def flake():
    """Blowing snow for the blizzard: 8 px by 8 lines, a long streak
    driving down and to the left and a short one, white (P1)."""
    a = np.zeros((8, 8), dtype=np.uint8)
    for k in range(8):
        a[k, 7 - k] = 3                                 # the long streak
    for k in range(3):
        a[5 + k // 2, 2 - k] = 3 if k else 2            # a short one
    a[1, 3] = 2
    return [a]


def parts5():
    return {"b5reactor": reactor5(), "b5drill": drill5()[:1], "b5gun": gun3(), "berg": berg(),
            "b5bridge": bridge5(), "slab": slab(), "flake": flake()}
