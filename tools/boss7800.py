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


def parts3():
    br = bridge3()[0]
    return {"b3bridget": [br[:32]], "b3bridgeb": [br[32:]], "b3reactor": reactor3(), "b3gun": gun3(),
            "gunboat": gunboat()}
