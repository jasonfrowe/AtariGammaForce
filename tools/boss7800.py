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
