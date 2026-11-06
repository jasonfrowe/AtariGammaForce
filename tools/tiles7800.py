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


# ---------------------------------------------------------------------------
# Stage 3, IRON TIDE: islands in the open ocean (the sea is the background
# color), and LEVIATHAN's hull, which is part of the map. Palettes: P2
# islands (1 dark green, 2 jungle, 3 sand), P1 steel (1 dark, 2 steel,
# 3 light: the hull, the bunkers' concrete), P0 the boss's (1 dark steel,
# 2 light steel, 3 naval red: lamps, the engines, the bays).

ISLAND, STEEL, BOSSPAL = 2, 1, 0


def _jungle(seed):
    t = np.full((H, W), 2, dtype=np.uint8)
    rng = np.random.default_rng(seed)
    for _ in range(9):
        x, y = int(rng.integers(0, W)), int(rng.integers(0, H - 1))
        t[y:y + 2, x] = 1                   # shade between the trees
    return t


def _island_edge(corners, seed):
    """Marching-squares shore: corners (tl, tr, br, bl), 1 = land. A sand
    rim along the water, jungle inside, a dark lip where it faces down or
    right."""
    tl, tr, br, bl = corners
    t = np.zeros((H, W), dtype=np.uint8)
    inner = _jungle(seed)
    for y in range(H):
        for x in range(W):
            u, v = (x + 0.5) / W, (y + 0.5) / H
            f = tl * (1 - u) * (1 - v) + tr * u * (1 - v) + br * u * v + bl * (1 - u) * v
            if f >= 0.62:
                t[y, x] = inner[y, x]
            elif f >= 0.5:
                t[y, x] = 3
    return t


def _bunker():
    """A 2x2 concrete bunker (16 px by 32 lines) for a turret."""
    big = np.full((32, 16), 2, dtype=np.uint8)
    big[0:2, :] = 3
    big[:, 0] = 3
    big[30:32, :] = 1
    big[:, 15] = 1
    for y in range(32):
        for x in range(16):
            d = math.hypot((x + 0.5 - 8) * 2, y + 0.5 - 16)
            if d < 10:
                big[y, x] = 1
            if d < 7:
                big[y, x] = 2
    return big


def island_tiles(ids):
    """Tiles for MegaGammaForce's ocean names (ocean.py). Returns (tiles,
    palettes, lut); tile 0 is blank (open sea)."""
    tiles, pals, lut = [np.zeros((H, W), dtype=np.uint8)], [ISLAND], {}
    bunker = _quarters(_bunker())
    for name, i in ids.items():
        if name.startswith("sea"):
            lut[i] = 0
            continue
        lut[i] = len(tiles)
        if name.startswith("edge"):
            cfg = int(name[4:])
            tiles.append(_island_edge(((cfg >> 3) & 1, (cfg >> 2) & 1, (cfg >> 1) & 1, cfg & 1), cfg))
            pals.append(ISLAND)
        elif name.startswith("land"):
            tiles.append(_jungle(40 + int(name[4:])))
            pals.append(ISLAND)
        elif name.startswith("bunker"):
            tiles.append(bunker[int(name[6:])])
            pals.append(STEEL)
    return tiles, pals, lut


def _plate(seed):
    t = np.full((H, W), 2, dtype=np.uint8)
    t[0, :] = 3
    t[H - 1, :] = 1
    t[7 + seed, 1:W - 1:3] = 1                # rivets
    return t


def hull_tiles(ids):
    """LEVIATHAN's hull, for MegaGammaForce's hull names (ship.py). Returns
    (tiles, palettes, lut). The sockets under its guns are left plain
    (the guns sit over them), and the craters are not used (the map is
    ROM: destroyed parts leave wrecks)."""
    tiles, pals, lut = [], [], {}

    def add(key, t, pal):
        if key not in lut:
            lut[key] = len(tiles)
            tiles.append(t)
            pals.append(pal)
        return lut[key]

    deck0, deck1 = _plate(0), _plate(4)
    walk = np.full((H, W), 1, dtype=np.uint8)
    walk[:, 1:W - 1] = 2
    walk[::3, 1:W - 1] = 1                      # grating
    vent = _plate(0)
    vent[3:13, 1:7] = 1
    vent[4:12:2, 2:6] = 2
    lamp = _plate(0)
    lamp[6:10, 2:6] = 1
    lamp[7:9, 3:5] = 3                          # red (the boss palette)
    port = _plate(2)
    port[:, 0] = 1
    port[:, 1] = 3
    stbd = _plate(2)
    stbd[:, W - 1] = 1
    stbd[:, W - 2] = 1
    stern = np.full((H, W), 2, dtype=np.uint8)
    stern[0:4, :] = 0
    stern[4, :] = 1
    stern[5, :] = 3
    engine = stern.copy()
    engine[8:14, 1:7] = 1
    engine[9:13, 2:6] = 3                       # glow (red)
    stern_l = stern.copy()
    for y in range(H):
        for x in range(W):
            if x + y < 6:
                stern_l[y, x] = 0
        stern_l[y, max(0, 6 - y):max(0, 6 - y) + 1] = 1 if y >= 4 else 0
    stern_l[6:, 0] = 1
    stern_r = stern_l[:, ::-1].copy()
    bow_l = np.zeros((H, W), dtype=np.uint8)    # the hull narrows a tile a row
    bow_r = np.zeros((H, W), dtype=np.uint8)
    for y in range(H):
        e = y * W // H                          # the cut goes down and inward
        bow_l[y, e:] = 2
        bow_l[y, e] = 1
        bow_l[y, min(W - 1, e + 1)] = 3
        bow_r[y, :W - e] = 2
        bow_r[y, W - 1 - e] = 1
    mark = _plate(0)
    for y in range(2, 14):
        mark[y, max(0, 3 - (y - 2) // 4):min(W, 5 + (y - 2) // 4)] = 3
    socket = _plate(0)
    socket[2:14, 1:7] = 1
    bay0 = np.full((H, W), 1, dtype=np.uint8)
    for y in range(1, H):
        for x in range(1, W - 1):
            bay0[y, x] = 3 if ((x + y) // 3) % 2 == 0 else 1   # hazard (red)
    bay1 = bay0[::-1].copy()
    out = {}
    for name, i in ids.items():
        if name == "clear":
            continue
        if name.startswith("deck"):
            out[i] = add("deck" + str(int(name[4:]) % 2), deck0 if int(name[4:]) % 2 == 0 else deck1, STEEL)
        elif name in ("walk", "vent", "port", "stbd", "stern", "stern_l", "stern_r", "bow_l", "bow_r"):
            out[i] = add(name, locals()[name], STEEL)
        elif name == "engine":
            out[i] = add(name, engine, BOSSPAL)
        elif name == "lamp":
            # in the hull's steel: in the boss's palette its plate was a
            # light box with a red edge, which read as a gun turret
            out[i] = add(name, lamp, STEEL)
        elif name == "bow_mark":
            out[i] = add(name, mark, STEEL)
        elif name.startswith("big") or name == "small":
            out[i] = add("socket", socket, STEEL)
        elif name in ("bay0", "bay1"):
            out[i] = add(name, bay0 if name == "bay0" else bay1, BOSSPAL)
    return tiles, pals, out, ids.get("clear")


# ---------------------------------------------------------------------------
# Stage 4, SCORCHED SANDS: the desert (the sand is the background color, so
# open dunes cost nothing), rock plateaus, oases and the railway.
# Palettes: P1 rock (1 shadow, 2 rock, 3 sunlit sand: the plateaus, the
# railway, the bunkers), P2 oasis (1 palm green, 2 water, 3 glint).

ROCK, OASIS = 1, 2


def _rock(seed):
    """Rock: plate color with shadow cracks and a few sunlit grains."""
    t = np.full((H, W), 2, dtype=np.uint8)
    rng = np.random.default_rng(seed)
    for _ in range(4):
        x, y = int(rng.integers(0, W - 2)), int(rng.integers(1, H - 1))
        t[y, x:x + int(rng.integers(2, 4))] = 1     # a crack
    for _ in range(3):
        x, y = int(rng.integers(0, W)), int(rng.integers(0, H))
        if t[y, x] == 2:
            t[y, x] = 3
    return t


def _water(seed):
    t = np.full((H, W), 2, dtype=np.uint8)
    rng = np.random.default_rng(seed)
    for _ in range(3):
        x, y = int(rng.integers(0, W - 2)), int(rng.integers(0, H))
        t[y, x:x + 2] = 3                           # glints
    return t


def _blend(corners, inner, rim_up, rim_down, cut=0.5, band=0.0, band_c=0):
    """Marching squares (corners tl, tr, br, bl; 1 = inside): inner where
    the field says so, the background outside. Along the cut, rim_up
    where the inside faces up or left (lit), rim_down where it faces down
    or right. band > 0: a band of band_c just inside the cut (a shore)."""
    tl, tr, br, bl = corners
    f = np.zeros((H, W))
    for y in range(H):
        for x in range(W):
            u, v = (x + 0.5) / W, (y + 0.5) / H
            f[y, x] = tl * (1 - u) * (1 - v) + tr * u * (1 - v) + br * u * v + bl * (1 - u) * v
    ins = f >= cut
    t = np.where(ins, inner, 0).astype(np.uint8)
    if band:
        t[ins & (f < cut + band)] = band_c
    for y in range(H):
        for x in range(W):
            if not ins[y, x]:
                continue
            up = y > 0 and not ins[y - 1, x]
            left = x > 0 and not ins[y, x - 1]
            down = y < H - 1 and not ins[y + 1, x]
            right = x < W - 1 and not ins[y, x + 1]
            if (down or right) and rim_down:
                t[y, x] = rim_down
            elif (up or left) and rim_up:
                t[y, x] = rim_up
    return t


def _rail(side):
    """Half of the track (side 0 left, 1 right): a gravel bed, sleepers
    across it every 4 lines, one bright steel rail."""
    t = np.full((H, W), 2, dtype=np.uint8)
    for y in range(0, H, 4):
        t[y:y + 2, :] = 1                           # sleepers
    rx = 5 if side == 0 else 1
    t[:, rx:rx + 2] = 3                             # the rail
    t[:, rx + 2 if side == 0 else rx - 1] = 1       # its shadow
    return t


def _bunker4():
    """A 2x2 gun pit dug into the rock (16 px by 32 lines) for a turret:
    a berm, lit on its upper left, round a dark pit."""
    big = np.concatenate([np.concatenate([_rock(70 + y * 2 + x) for x in range(2)], axis=1) for y in range(2)])
    for y in range(32):
        for x in range(16):
            d = math.hypot((x + 0.5 - 8) * 2, y + 0.5 - 16)
            if d < 12.5:
                big[y, x] = 3 if (x - 8) * 2 + (y - 16) < 0 else 1
            if d < 10.5:
                big[y, x] = 2
            if d < 8:
                big[y, x] = 1
    return big


def _palm():
    """A palm seen from above: six fronds round a dark crown."""
    t = np.zeros((H, W), dtype=np.uint8)
    for a in range(0, 360, 60):
        r = math.radians(a + 15)
        for s in np.linspace(0, 7, 15):
            x, y = int(4 + math.cos(r) * s / 2), int(8 + math.sin(r) * s)
            if 0 <= x < W and 0 <= y < H:
                t[y, x] = 1
    t[7:9, 3:5] = 2
    return t


def desert_tiles(ids):
    """Our desert tileset for MegaGammaForce's desert names (desert.py).
    Returns (tiles, palettes, lut); tile 0 is blank (open sand)."""
    tiles, pals, lut = [np.zeros((H, W), dtype=np.uint8)], [ROCK], {}
    bunker = _quarters(_bunker4())
    for name, i in ids.items():
        if name.startswith("dune"):
            lut[i] = 0
            continue
        lut[i] = len(tiles)
        if name.startswith("rock"):
            cfg = int(name[4:])
            c = ((cfg >> 3) & 1, (cfg >> 2) & 1, (cfg >> 1) & 1, cfg & 1)
            tiles.append(_blend(c, _rock(cfg), 3, 1))
            pals.append(ROCK)
        elif name.startswith("oasis"):
            cfg = int(name[5:])
            c = ((cfg >> 3) & 1, (cfg >> 2) & 1, (cfg >> 1) & 1, cfg & 1)
            tiles.append(_blend(c, _water(cfg + 20), 0, 0, band=0.1, band_c=1))
            pals.append(OASIS)
        elif name.startswith("rail"):
            tiles.append(_rail(int(name[4:])))
            pals.append(ROCK)
        elif name.startswith("bunker"):
            tiles.append(bunker[int(name[6:])])     # (0/1 the top row)
            pals.append(ROCK)
        elif name == "palm":
            tiles.append(_palm())
            pals.append(OASIS)
    return tiles, pals, lut


# ---------------------------------------------------------------------------
# Stage 5, FROZEN STRAIT: pack ice (the ice is the background color, so the
# open shelf costs nothing), leads of open water, plowed roads, bunkers.
# Palettes: P0 the crawler (1 dark steel, 2 steel, 3 frost), P1 snow (1
# shadow, 2 concrete, 3 snow white: roads, cracks, bunkers), P2 water (1
# deep, 2 water, 3 white rim). During the boss fight the game swaps P2's
# first two colors to and fro, which runs the crawler's treads (drawn in
# P2's bands); there is no water on the screen by then.

CRAWLER, SNOW, WATER = 0, 1, 2


def _water5(seed):
    t = np.full((H, W), 2, dtype=np.uint8)
    rng = np.random.default_rng(seed)
    for _ in range(3):
        x, y = int(rng.integers(0, W - 3)), int(rng.integers(0, H))
        t[y, x:x + 3] = 1                           # ripples
    return t


def _crack():
    """Snow with a crack across it: a dark line, a bright edge under it."""
    t = np.zeros((H, W), dtype=np.uint8)
    for x in range(W):
        y = int(7 + 3 * math.sin(x * 0.9))
        t[y, x] = 1
        t[min(H - 1, y + 1), x] = 3
    return t


def _road5(variant):
    """A plowed track: two pairs of ruts, snow banks on both sides; the
    packed snow between is the ice itself (background)."""
    t = np.zeros((H, W), dtype=np.uint8)
    t[1, :] = 3
    t[14, :] = 1
    for y in (5, 10):
        t[y, :] = 1
        t[y, (variant * 3)::4] = 2
    return t


def _bunker5():
    """A 2x2 concrete pillbox (16 px by 32 lines) for a turret: a snowy rim
    lit on its upper left round a dark gun well."""
    big = np.zeros((32, 16), dtype=np.uint8)
    for y in range(32):
        for x in range(16):
            sq = max(abs(x + 0.5 - 8) * 2, abs(y + 0.5 - 16))
            d = math.hypot((x + 0.5 - 8) * 2, y + 0.5 - 16)
            if sq < 14:
                big[y, x] = 2
                if sq >= 12:
                    big[y, x] = 3 if (x - 8) * 2 < (y - 16) * -1 + 0 and (x - 8) * 2 + (y - 16) < 0 else 1
            if d < 10:
                big[y, x] = 1
            if d < 8:
                big[y, x] = 2 if (x + y) % 3 == 0 else 1
    return big


def _beacon5():
    t = np.zeros((H, W), dtype=np.uint8)
    for y in range(H):
        for x in range(W):
            d = math.hypot((x + 0.5 - 4) * 2, y + 0.5 - 8)
            if d < 5:
                t[y, x] = 1
            if d < 3:
                t[y, x] = 3                         # the lamp (frost, P0)
    return t


def arctic_tiles(ids):
    """Our tiles for MegaGammaForce's arctic names (arctic.py). Returns
    (tiles, palettes, lut); tile 0 is blank (open ice)."""
    tiles, pals, lut = [np.zeros((H, W), dtype=np.uint8)], [SNOW], {}
    bunker = _quarters(_bunker5())
    for name, i in ids.items():
        # (the beacons are bare ice: stage 5's graphics block is full)
        if (name.startswith("snow") and name != "snow3") or name == "beacon":
            lut[i] = 0
            continue
        lut[i] = len(tiles)
        if name.startswith("edge"):
            # water where the corners are not ice: the lead's far bank (ice
            # above it, facing down the screen) in shadow, the near bank lit
            cfg = int(name[4:])
            c = tuple(1 - b for b in ((cfg >> 3) & 1, (cfg >> 2) & 1, (cfg >> 1) & 1, cfg & 1))
            tiles.append(_blend(c, _water5(cfg + 30), 1, 3))
            pals.append(WATER)
        elif name.startswith("water"):
            # (one open water tile for all four)
            if "water" not in lut:
                lut["water"] = len(tiles)
                tiles.append(_water5(50))
                pals.append(WATER)
            lut[i] = lut["water"]
        elif name == "snow3":
            tiles.append(_crack())
            pals.append(SNOW)
        elif name.startswith("road"):
            if "road" not in lut:
                lut["road"] = len(tiles)
                tiles.append(_road5(0))
                pals.append(SNOW)
            lut[i] = lut["road"]
        elif name.startswith("bunker"):
            tiles.append(bunker[int(name[6:])])
            pals.append(SNOW)
        elif name == "beacon":
            tiles.append(_beacon5())
            pals.append(CRAWLER)
    return tiles, pals, lut


def crawler_tiles(ids):
    """GLACIER CRAWLER's hull, for MegaGammaForce's names (crawler.py), 10
    tiles by 9 rows. Returns (tiles, palettes, lut, the clear tile). The
    treads are bands of P2's first two colors, so swapping them runs the
    treads; the sockets and hatches are left plain (parts cover them)."""
    tiles, pals, lut = [], [], {}

    def add(key, t, pal):
        # (the same picture is stored once, whatever its name)
        key = (t.tobytes(), pal)
        if key not in lut:
            lut[key] = len(tiles)
            tiles.append(t)
            pals.append(pal)
        return lut[key]

    deck0, deck1 = _plate(0), _plate(5)

    def tread(inner, end):
        t = np.zeros((H, W), dtype=np.uint8)
        for y in range(H):
            t[y, :] = 1 + (y // 2) % 2              # cleats
        if inner:
            t[2::4, 5:7] = 3                        # road wheels through the cleats
        else:
            t[:, 0] = 3                             # the outer edge, frosted
        if end and not inner:
            # the outer corner rounded off: a quarter ellipse round the
            # tile's inner corner at that end
            for y in range(H):
                for x in range(W):
                    u = (W - 0.5 - x) / W
                    v = (H - 0.5 - y) / H if end == "top" else (y + 0.5) / H
                    if u * u + v * v > 1:
                        t[y, x] = 0
        return t

    vent = _plate(0)
    vent[3:13, 1:7] = 1
    vent[4:12:2, 2:6] = 2
    lamp = _plate(0)
    lamp[6:10, 2:6] = 1
    lamp[7:9, 3:5] = 3
    stripe = _plate(0)
    for y in range(1, H - 1):
        for x in range(W):
            if ((x + y) // 3) % 2 == 0:
                stripe[y, x] = 3                    # hazard stripes, in frost
    stripe[0, :] = 1
    paint = _plate(0)
    paint[4:12, :] = 1
    paint[5:11, :] = 3                              # a frost-white band
    rear = np.full((H, W), 2, dtype=np.uint8)
    rear[0, :] = 1
    rear[1, :] = 3
    rear[4:11, 1:4] = 1
    rear[5:10, 2:3] = 3                             # exhaust stacks
    rear[4:11, 5:8] = 1
    rear[5:10, 6:7] = 3
    socket = _plate(0)
    socket[2:14, 1:7] = 1
    # the big sockets (2 x 2 tiles: guns, the reactor, the drill): a
    # round well with a frosted rim, so a gun shows mounted in it
    big = np.concatenate([np.concatenate([_plate(0), _plate(5)], axis=1)] * 2)
    for y in range(2 * H):
        for x in range(2 * W):
            d = math.hypot((x + 0.5 - W) * 2, y + 0.5 - H)
            if d < 14:
                big[y, x] = 3
            if d < 12:
                big[y, x] = 1
    bigq = _quarters(big)
    plow_l = np.zeros((H, W), dtype=np.uint8)
    for y in range(H):
        e = (H - 1 - y) * W // H                    # the blade sweeps back
        plow_l[y, e:] = 2
        plow_l[y, e] = 3
    plow_r = plow_l[:, ::-1].copy()
    out = {}
    for name, i in ids.items():
        if name == "clear" or name.startswith("crater"):
            continue
        if name.startswith("deck"):
            out[i] = add("deck" + str(int(name[4:]) % 2), deck0 if int(name[4:]) % 2 == 0 else deck1, CRAWLER)
        elif name.startswith("tread"):
            mirror = name.startswith("treadr")
            rest = name[6:] if mirror else name[5:]
            inner = rest[0] == "1"
            end = rest[1:] or None
            t = tread(inner, end)
            if mirror:
                t = t[:, ::-1].copy()
            out[i] = add(name, t, WATER)
        elif name == "lamp":
            out[i] = add("vent", vent, CRAWLER)        # (no room for a lamp of its own)
        elif name in ("vent", "stripe", "paint", "rear", "plow_l", "plow_r"):
            out[i] = add(name, locals()[name], CRAWLER)
        elif name.startswith("big"):
            out[i] = add(name, bigq[int(name[3:])], CRAWLER)
        elif name == "small":
            out[i] = add("socket", socket, CRAWLER)
        elif name in ("hatch0", "hatch1"):
            # the doors of LEVIATHAN's bays (boss7800.bay3's shut frame,
            # the same colors in P0), so the shut hatch's sprite needn't
            # be drawn
            door = np.full((H, W), 1, dtype=np.uint8)
            for y in range(1, H):
                for x in range(1, W - 1):
                    door[y, x] = 3 if ((x + y) // 3) % 2 == 0 else 1
            out[i] = add(name, door if name == "hatch0" else door[::-1].copy(), CRAWLER)
    return tiles, pals, out, ids.get("clear")


# ---------------------------------------------------------------------------
# Stage 6, ASCENT: the ocean far below (the background color), clouds over
# it, the Earth's limb, then space and stars; and HALO STATION's hull.
# Palettes: P0 the station and the satellites (1 solar blue, 2 steel, 3
# gold), P1 the clouds (1 shadow, 2 cloud, 3 sunlit: they fade toward
# black with the ocean as the ship climbs), P2 the sky (1 atmosphere blue,
# 2 its bright rim, 3 white: the limb and the stars).

STATION6, CLOUD6, SKY6 = 0, 1, 2


def cloud6(corners, seed):
    """A cloud's edge over the ocean (marching squares, corners tl, tr, br,
    bl, 1 = cloud; all four: the cloud's body): billowed white, sunlit
    along its top and left, shadowed along its bottom and right."""
    t = _blend(corners, 2, 3, 1, cut=0.45)
    # a soft edge: every other one of the outermost pixels (the ocean shows
    # through), so the clouds look like vapor, not land
    edge = np.zeros(t.shape, dtype=bool)
    for y in range(H):
        for x in range(W):
            if t[y, x] and any(0 <= y + dy < H and 0 <= x + dx < W and t[y + dy, x + dx] == 0
                               for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                edge[y, x] = True
    t[edge & (np.add.outer(np.arange(H), np.arange(W)) % 2 == 1)] = 0
    rng = np.random.default_rng(seed)
    body = t == 2
    for _ in range(5):                               # billows: bright tufts
        x, y = int(rng.integers(0, W - 1)), int(rng.integers(0, H - 1))
        if body[y, x] and body[y, x + 1] and body[y + 1, x]:
            t[y, x] = t[y, x + 1] = 3
            t[y + 1, x] = 1 if y + 2 < H and not body[y + 2, x] else 2
    return t


def star6(kind):
    """Space: one star (a dim blue one, a bright one, a white one), or a
    bright white star with arms."""
    t = np.zeros((H, W), dtype=np.uint8)
    rng = np.random.default_rng(60 + kind)
    x, y = int(rng.integers(1, W - 1)), int(rng.integers(2, H - 2))
    if kind < 3:
        t[y, x] = 1 + kind
    else:
        t[y, x] = 3
        t[y - 1, x] = t[y + 1, x] = t[y, x - 1] = t[y, x + 1] = 2
    if kind == 0:
        t[(y + 7) % H, (x + 4) % W] = 1
    return t


def station6():
    """HALO STATION's hull, 8 tiles by 8 rows (64 px by 128 lines): an
    octagonal ring round a hub on four spokes. Drawn whole in screen units
    (a 160A pixel is 2 units wide, a line 1 tall; the tile is 16 x 16),
    then cut into tiles: the straight sides are a tile thick, and each
    diagonal runs corner to corner through its tiles, so every step of it
    is the same two pictures. The hub (the middle 2 x 2) is left clear:
    the core's sprite covers it. Returns the 8 x 8 grid of tiles."""
    n = 128
    img = np.zeros((n, n // 2), dtype=np.uint8)

    def section(s, along):
        """The ring's cross-section, s from its outer edge (0) in (1): an
        outer rim, a dark seam, a band of gold windows, steel, the inner
        shadow."""
        if s < 0.1:
            return 1
        if s < 0.26:
            return 2
        if s < 0.34:
            return 1
        if s < 0.66:
            return 3 if (0.42 < s < 0.58 and int(along) % 8 < 3) else 2
        if s < 0.86:
            return 2
        return 1

    for py in range(n):
        for px in range(n // 2):
            x, y = px * 2 + 1.0 - 64, py + 0.5 - 64
            ax, ay = abs(x), abs(y)
            s_st = (64 - max(ax, ay)) / 16
            s_dg = (80 - ax - ay) / 16
            if s_st <= s_dg:
                s = s_st
                along = x if ay >= ax else y
            else:
                s = s_dg
                along = (x - y) if x * y > 0 else (x + y)
            if 0 <= s < 1:
                img[py, px] = section(s, along % 8 + 8)
                continue
            # the spokes, on the diagonals from the hub to the ring
            if 16 < ax < 32 and 16 < ay < 32 and abs(ax - ay) < 4.5:
                img[py, px] = 1 if abs(ax - ay) > 3 else (3 if int(ax + ay) % 12 < 2 else 2)
    tiles = [[img[r * H:(r + 1) * H, c * W:(c + 1) * W].copy() for c in range(8)] for r in range(8)]
    for r in (3, 4):
        for c in (3, 4):
            tiles[r][c][:] = 0
    return tiles


# ---------------------------------------------------------------------------
# Stage 7, SEA OF TRANQUILITY: the Moon. The regolith is the background
# color (gray), so open ground costs nothing; craters, the bases and the
# roads are drawn. Palettes: P0 MASS DRIVER's hull (1 shadow, 2 gunmetal,
# 3 light), P1 the regolith's shades (1 deep shadow, 2 dark dust, 3 sunlit
# rim), P2 the bases (1 dark metal, 2 dome glass, 3 white markings; in the
# boss fight the rail's coils, its three colors turned round).

HULL7, MOON7, BASE7 = 0, 1, 2


def _crater7(size, seed):
    """A crater size tiles across (size x size tiles): its rim lit on the
    upper left, the bowl's near (upper-left) wall in deep shadow, its far
    wall catching the light, the floor dark dust; bright flecks of ejecta
    round it. Returns its tiles, top row first, left to right."""
    n = size * H                                    # screen units across and down
    img = np.zeros((n, size * W), dtype=np.uint8)
    rng = np.random.default_rng(700 + seed)
    c = n / 2
    r = n / 2 - 1.5 - size * 0.4
    bump = rng.uniform(-0.05, 0.05, 8)
    for py in range(n):
        for px in range(size * W):
            x, y = px * 2 + 1.0 - c, py + 0.5 - c
            a = math.atan2(y, x)
            d = math.hypot(x, y) / (r * (1 + bump[int((a + math.pi) / (2 * math.pi) * 8) % 8]))
            lit = -(x + y) / (math.sqrt(2) * max(1.0, math.hypot(x, y)))  # + toward the upper left
            if 0.8 < d < 1.08:
                if lit > 0.25:
                    img[py, px] = 3
                elif lit < -0.3:
                    img[py, px] = 2
            elif d <= 0.8:
                img[py, px] = 2
                if lit > 0.05:
                    img[py, px] = 1
                if lit < -0.45 and d > 0.45:
                    img[py, px] = 0                 # the far wall, as lit as the plain
            elif d < 1.45 and size > 1 and rng.random() < 0.06:
                img[py, px] = 3                     # ejecta
    return [img[ty * H:(ty + 1) * H, tx * W:(tx + 1) * W].copy() for ty in range(size) for tx in range(size)]


def _floor7(edges):
    """A base's floor plate (the plain's own gray, dark seams), a 9-slice:
    edges (n, e, s, w) get a curb, bright where it faces up or left."""
    t = np.zeros((H, W), dtype=np.uint8)
    t[H - 1, :] = 1
    t[:, W - 1] = 1
    t[7, 2:W - 1:4] = 1                             # rivets
    n_, e_, s_, w_ = edges
    if n_:
        t[0, :] = 3
        t[1, :] = 1
    if w_:
        t[:, 0] = 3
        t[:, 1] = 1
    if s_:
        t[H - 2, :] = 1
        t[H - 1, :] = 1
    if e_:
        t[:, W - 2] = 1
    return t


def _dome7():
    """A glass dome on the floor, 2 x 2 tiles: dark frame, glass ribbed,
    a white glint on its upper left."""
    big = np.zeros((2 * H, 2 * W), dtype=np.uint8)
    for py in range(2 * H):
        for px in range(2 * W):
            x, y = px * 2 + 1.0 - 16, py + 0.5 - 16
            d = math.hypot(x, y)
            if d < 14:
                big[py, px] = 1
            if d < 12.5:
                big[py, px] = 2
                if px in (3, 5, 10, 12) or (x + y > 9 and (px + py) % 2 == 0):
                    big[py, px] = 1                 # ribs, the shaded side
            if abs(d - 8) < 0.9 and x + y < -4:
                big[py, px] = 3
            if math.hypot(x + 5, y + 5) < 2.2:
                big[py, px] = 3
    return _quarters(big)


def _pad7():
    """A landing pad: a dark disc with a white ring and H, glass-blue
    lights round its edge."""
    big = np.zeros((2 * H, 2 * W), dtype=np.uint8)
    for py in range(2 * H):
        for px in range(2 * W):
            x, y = px * 2 + 1.0 - 16, py + 0.5 - 16
            d = math.hypot(x, y)
            ang = math.degrees(math.atan2(y, x)) % 360
            if d < 14:
                big[py, px] = 1
            if abs(d - 13) < 1.0 and int(ang // 30) % 2 == 0:
                big[py, px] = 2
            if abs(d - 10) < 0.8:
                big[py, px] = 3
    big[10:22, 5:6] = 3
    big[10:22, 10:11] = 3
    big[15:17, 5:11] = 3
    return _quarters(big)


def _bunker7():
    """A turret bunker: a square concrete rim (P1: lit on its upper left)
    round a dark gun well."""
    big = np.zeros((2 * H, 2 * W), dtype=np.uint8)
    for py in range(2 * H):
        for px in range(2 * W):
            x, y = px * 2 + 1.0 - 16, py + 0.5 - 16
            sq = max(abs(x), abs(y))
            if sq < 14:
                big[py, px] = 2
                if sq >= 12:
                    big[py, px] = 3 if x + y < 0 else 1
            d = math.hypot(x, y)
            if d < 9.5:
                big[py, px] = 1
            if d < 7.5:
                big[py, px] = 1 if (px + py) % 2 else 2
    return _quarters(big)


def _road7(plaza):
    """A rover road: dark ruts in packed dust between rows of guide
    lights (bright dots); across a plaza, a dark roadway."""
    t = np.zeros((H, W), dtype=np.uint8)
    t[1, :] = 3 if not plaza else 1
    t[14, :] = 1
    if plaza:
        t[2:14, :] = 1
        t[7:9, 1:7:3] = 3                           # a dashed centre line
    else:
        for y in (5, 10):
            t[y, :] = 2
        t[1, 0::4] = 1
    return t


def luna_tiles(ids, used):
    """Our tiles for MegaGammaForce's lunar names (luna.py), those of them
    in used (the map's tile numbers). Returns (tiles, palettes, lut); tile
    0 is blank (the plain: regolith)."""
    tiles, pals, lut = [np.zeros((H, W), dtype=np.uint8)], [MOON7], {}

    def add(key, t, pal):
        if key not in lut:
            lut[key] = len(tiles)
            tiles.append(t)
            pals.append(pal)
        return lut[key]

    craters = {}
    dome, pad, bunker = _dome7(), _pad7(), _bunker7()
    out = {}
    for name, i in ids.items():
        if i not in used:
            continue
        if name.startswith("reg"):
            out[i] = 0
        elif name.startswith("crater"):
            # crater{size}_{variant}_{k}: k counts from its top row, left
            # to right. One picture per size (the bank's graphics are few).
            size, _, k = (int(v) for v in name[6:].split("_"))
            if size not in craters:
                craters[size] = _crater7(size, size)
            out[i] = add(f"crater{size}_{k}", craters[size][k], MOON7)
        elif name.startswith("floor"):
            e = int(name[5:])
            edges = ((e >> 3) & 1, (e >> 2) & 1, (e >> 1) & 1, e & 1)
            # (luna's floor edges: bit 3 the plaza's last row, its top as
            # the map scrolls; bit 1 its first, the bottom)
            n_, e_, s_, w_ = edges
            out[i] = add(f"floor{e}", _floor7((n_, e_, s_, w_)), BASE7)
        elif name.startswith(("dome", "pad", "bunker")):
            kind = name.rstrip("0123")
            q = {"dome": dome, "pad": pad, "bunker": bunker}[kind][int(name[len(kind):])]
            out[i] = add(name, q, MOON7 if kind == "bunker" else BASE7)
        elif name.startswith("roadp"):
            out[i] = add("roadp", _road7(True), BASE7)
        elif name.startswith("road"):
            out[i] = add("road", _road7(False), MOON7)
    return tiles, pals, out


def driver_tiles(ids):
    """MASS DRIVER's hull, for MegaGammaForce's names (driver.py), 10 tiles
    by 9 rows: gunmetal deck (P0), hover nacelles down both sides, and the
    rail cannon up its middle, its coil rings in P2's three colors (turned
    round in the fight, so charge seems to run down the barrel). The
    sockets and hatches are left plain (parts cover them). Returns (tiles,
    palettes, lut, the clear tile)."""
    tiles, pals, lut = [], [], {}

    def add(t, pal):
        key = (t.tobytes(), pal)
        if key not in lut:
            lut[key] = len(tiles)
            tiles.append(t)
            pals.append(pal)
        return lut[key]

    def rail(side):
        t = np.zeros((H, W), dtype=np.uint8)
        for y in range(H):
            t[y, :] = 1 + (y // 3) % 3 if y % 3 != 2 else 1
        if side == 0:
            t[:, 0] = 1
            t[:, 6:] = 1                            # the bore's shadow
        else:
            t[:, W - 1] = 1
            t[:, :2] = 1
        return t

    def nacelle(end, side):
        t = _plate(1)
        t[:, 0 if side == 0 else W - 1] = 1
        t[:, 1 if side == 0 else W - 2] = 3 if side == 0 else 1
        for y in range(3, H, 5):
            t[y:y + 2, 2:6] = 1                     # vents
        if end:
            for y in range(H):
                for x in range(W):
                    u = (W - 0.5 - x) / W if side == 0 else (x + 0.5) / W
                    v = (H - 0.5 - y) / H if end == "top" else (y + 0.5) / H
                    if u * u + v * v > 1:
                        t[y, x] = 0
        return t

    deck0, deck1 = _plate(0), _plate(5)
    stripe = _plate(0)
    for y in range(1, H - 1):
        for x in range(W):
            if ((x + y) // 3) % 2 == 0:
                stripe[y, x] = 1                    # hazard stripes
    lamp = _plate(0)
    lamp[6:10, 2:6] = 1
    lamp[7:9, 3:5] = 3
    socket = _plate(0)
    socket[2:14, 1:7] = 1
    big = np.concatenate([np.concatenate([_plate(0), _plate(5)], axis=1)] * 2)
    for y in range(2 * H):
        for x in range(2 * W):
            d = math.hypot((x + 0.5 - W) * 2, y + 0.5 - H)
            if d < 14:
                big[y, x] = 3
            if d < 12:
                big[y, x] = 1
    bigq = _quarters(big)
    door = np.full((H, W), 1, dtype=np.uint8)
    for y in range(1, H):
        for x in range(1, W - 1):
            door[y, x] = 3 if ((x + y) // 3) % 2 == 0 else 1
    out = {}
    for name, i in ids.items():
        if name == "clear" or name.startswith("crater"):
            continue
        if name.startswith("deck"):
            out[i] = add(deck0 if int(name[4:]) % 2 == 0 else deck1, HULL7)
        elif name.startswith("rail"):
            out[i] = add(rail(int(name[4:])), BASE7)
        elif name.startswith("nac"):
            side, end = int(name[3]), name[4:] or None
            out[i] = add(nacelle(end, side), HULL7)
        elif name == "stripe":
            out[i] = add(stripe, HULL7)
        elif name == "lamp":
            out[i] = add(lamp, HULL7)
        elif name.startswith("big"):
            out[i] = add(bigq[int(name[3:])], HULL7)
        elif name == "small":
            out[i] = add(socket, HULL7)
        elif name in ("hatch0", "hatch1"):
            out[i] = add(door if name == "hatch0" else door[::-1].copy(), HULL7)
    return tiles, pals, out, ids.get("clear")


# ---------------------------------------------------------------------------
# Stage 8, DEEP FIELD: open space past the Moon, through drifts of
# asteroids. Space is the background color (black), so it costs nothing.
# Palettes: P0 HIVE MOTHERSHIP's carapace (1 shadow, 2 chitin, 3 its glow:
# vein green), P1 the asteroids (1 shadow, 2 rock, 3 sunlit), P2 the stars
# (1 dim, 2 pale, 3 white; the gunships' gray too).

HIVE8, ROCK8, STAR8 = 0, 1, 2
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5


def star8(kind):
    """A star: a dim one, a pale one, a white one, or a white one with
    arms."""
    t = np.zeros((H, W), dtype=np.uint8)
    rng = np.random.default_rng(80 + kind)
    x, y = int(rng.integers(1, W - 1)), int(rng.integers(2, H - 2))
    if kind < 3:
        t[y, x] = 1 + kind
    else:
        t[y, x] = 3
        t[y - 1, x] = t[y + 1, x] = 1
    return t


def asteroid8(w, h, seed):
    """An asteroid filling w x h tiles: a lumpy sphere lit from the upper
    left, its shadow side fading into space, a few craters (bowls, their
    far rims lit). Returns its image (h * 16 lines by w * 8 pixels)."""
    rng = np.random.default_rng(800 + seed)
    n, m = h * H, w * W
    img = np.zeros((n, m), dtype=np.uint8)
    cx, cy = w * W, h * H / 2                         # screen units
    rx, ry = w * W - 1.5, h * H / 2 - 1.5
    lump = [(k, rng.uniform(0.05, 0.11) * 3 / k, rng.uniform(0, 2 * math.pi)) for k in (2, 3, 5)]
    pits = []
    for _ in range(int(rng.integers(2, 2 + (w + h) // 2))):
        pr = rng.uniform(3.0, 2.5 + min(w, h) * 2.5)
        a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0, 0.55)
        pits.append((cx + math.cos(a) * d * rx, cy + math.sin(a) * d * ry, pr))
    for py in range(n):
        for px in range(m):
            x, y = px * 2 + 1.0, py + 0.5
            u, v = (x - cx) / rx, (y - cy) / ry
            ang = math.atan2(v, u)
            r = 0.88 * (1 + sum(amp * math.cos(k * ang + ph) for k, amp, ph in lump))
            d = math.hypot(u, v) / r
            if d >= 1:
                continue
            # the sphere's normal, lit from the upper left and in front
            z = math.sqrt(max(0.0, 1 - d * d))
            lit = (-u * 0.55 - v * 0.6 + z * 0.75) / r
            for qx, qy, pr in pits:
                dc = math.hypot(x - qx, y - qy) / pr
                if dc < 1:
                    # a bowl: its near (upper left) wall in shadow, its far
                    # wall catching the light
                    lit += ((x - qx) + (y - qy)) / pr * 0.55 - 0.15
                elif dc < 1.3:
                    lit += 0.12 * -((x - qx) + (y - qy)) / pr
            lit += BAYER4[py % 4, px % 4] * 0.35
            img[py, px] = 3 if lit > 0.72 else 2 if lit > 0.22 else 1
    return img


# the asteroids drawn (w, h in tiles); each drawn once and reused
ROCKS8 = [(2, 2), (2, 2), (3, 2), (2, 3), (3, 3)]


def deep_tiles():
    """Stage 8's sky: tile 0 blank (space), the stars, the asteroids cut
    into tiles. Returns (tiles, palettes, stars: their tile numbers,
    rocks: for each asteroid its h x w grid of tile numbers (0 where
    empty), debris: a lone rock's tile, solid: the tiles mostly rock
    (shots, bullets and the ship stop at them))."""
    tiles, pals = [np.zeros((H, W), dtype=np.uint8)], [STAR8]
    stars = []
    for k in range(4):
        stars.append(len(tiles))
        tiles.append(star8(k))
        pals.append(STAR8)
    rocks, solid = [], set()
    for i, (w, h) in enumerate(ROCKS8):
        img = asteroid8(w, h, i)
        g = np.zeros((h, w), dtype=int)
        for r in range(h):
            for c in range(w):
                t = img[r * H:(r + 1) * H, c * W:(c + 1) * W].copy()
                if not t.any():
                    continue
                g[r, c] = len(tiles)
                if (t > 0).mean() >= 0.5:
                    solid.add(len(tiles))
                tiles.append(t)
                pals.append(ROCK8)
        rocks.append(g)
    # debris: a small rock, not solid (MegaGammaForce's 1 x 1s)
    deb = np.zeros((H, W), dtype=np.uint8)
    small = asteroid8(1, 1, 9)
    deb[3:13, 1:7] = small[3:13, 1:7]
    debris = len(tiles)
    tiles.append(deb)
    pals.append(ROCK8)
    return tiles, pals, stars, rocks, debris, solid


def _comb8():
    """Honeycomb across a tile (16 x 16 screen units, seamless): for each
    pixel, how far it is from its cell's wall (screen units), and which
    way from its cell's middle it lies (dx + dy: + toward the lower right)."""
    centres = [(x + (8 if (y // 8) % 2 else 0), y) for y in range(-16, 33, 8) for x in range(-32, 49, 16)]
    wall, side, cell = np.zeros((H, W)), np.zeros((H, W)), np.zeros((H, W), dtype=int)
    for py in range(H):
        for px in range(W):
            x, y = px * 2 + 1.0, py + 0.5
            ds = sorted((math.hypot(x - cx, (y - cy) * 1.7), k) for k, (cx, cy) in enumerate(centres))
            wall[py, px] = ds[1][0] - ds[0][0]
            cx, cy = centres[ds[0][1]]
            side[py, px] = (x - cx) + (y - cy)
            cell[py, px] = ds[0][1]
    return wall, side, cell


COMB8 = None


def _carapace8(variant):
    """The hull's honeycomb: chitin cells with dark walls, each cell's
    lower right shaded; variant 1 has a cell glowing green."""
    global COMB8
    if COMB8 is None:
        COMB8 = _comb8()
    wall, side, cell = COMB8
    t = np.full((H, W), 2, dtype=np.uint8)
    yy, xx = np.mgrid[0:H, 0:W]
    t[(side > 2.5) & (wall < 3.5) & ((xx + yy) % 2 == 0)] = 1
    t[wall < 1.6] = 1
    if variant == 1:
        k = cell[8, 4]
        t[(cell == k) & (wall >= 1.6)] = 3
    return t


def hive_shape(w, h):
    """HIVE MOTHERSHIP's hull corners, (h + 1) x (w + 1): an oval, and two
    mandibles reaching down past it (MegaGammaForce's, in 7 rows)."""
    g = np.zeros((h + 1, w + 1), dtype=np.uint8)
    for y in range(h + 1):
        for x in range(w + 1):
            if ((x - 5) / 5.3) ** 2 + ((y - 2.7) / 3.1) ** 2 < 1:
                g[y, x] = 1
    for x0 in (2, 6):
        g[4:7, x0:x0 + 3] = 1
    g[7, 3], g[7, 7] = 1, 1
    return g


def hive_tiles(w, h, parts):
    """HIVE MOTHERSHIP's hull: its map (h x w tile numbers into the
    returned tiles, 0 clear) in honeycomb chitin (P0), its rim in marching
    squares (one tile for each shape of corner), veins glowing out from
    the eye, a maw below it; the parts' sockets plain (their sprites cover
    them). Returns (tiles, palettes, map) - tile numbers from 1."""
    tiles, pals, ids = [None], [HIVE8], {}

    def add(t):
        key = t.tobytes()
        if key not in ids:
            ids[key] = len(tiles)
            tiles.append(t)
            pals.append(HIVE8)
        return ids[key]

    g = hive_shape(w, h)
    base = _carapace8(0)
    m = np.zeros((h, w), dtype=np.uint8)
    rng = np.random.default_rng(8)
    for r in range(h):
        for c in range(w):
            cfg = (int(g[r, c]), int(g[r, c + 1]), int(g[r + 1, c + 1]), int(g[r + 1, c]))
            if cfg == (1, 1, 1, 1):
                m[r, c] = add(_carapace8(1 if rng.random() < 0.2 else 0))
            elif any(cfg):
                t = _blend(cfg, 2, 3, 1, cut=0.5)
                t[(t == 2) & (base == 1)] = 1           # the honeycomb shows to the rim
                m[r, c] = add(t)
    # veins: up the eye's columns above it, and across its row to the turrets
    def vein(horizontal):
        t = base.copy()
        for py in range(H):
            for px in range(W):
                a = (py + 0.5 - H / 2) if horizontal else (px * 2 + 1.0 - W)
                along = px * 2 if horizontal else py
                wob = math.sin(along / 16 * 2 * math.pi) * 1.5
                d = abs(a - wob)
                if d < 2.6:
                    t[py, px] = 3 if d < 1.4 else 1
        return t
    ex, ey = parts["EYE"][:2]
    for r in range(0, ey):
        for c in (ex, ex + 1):
            if m[r, c] and all(g[r + a, c + b] for a in (0, 1) for b in (0, 1)):
                m[r, c] = add(vein(False))
    for c in range(w):
        r = ey + 1
        if c in (ex, ex + 1):
            continue
        if m[r, c] and all(g[r + a, c + b] for a in (0, 1) for b in (0, 1)):
            m[r, c] = add(vein(True))
    # the maw below the eye: a dark throat ringed with bone teeth
    maw = np.concatenate([base, base], axis=1)
    for py in range(H):
        for px in range(2 * W):
            x, y = px * 2 + 1.0 - 2 * W, py + 0.5 - 6
            d = math.hypot(x / 13, y / 8)
            if d < 1:
                maw[py, px] = 1
            if 0.7 <= d < 1 and y > -2 and (px // 2) % 2 == 0:
                maw[py, px] = 3
    m[ey + 2, ex], m[ey + 2, ex + 1] = add(maw[:, :W].copy()), add(maw[:, W:].copy())
    # the sockets: plain chitin, dark (the parts cover them)
    sock = base.copy()
    sock[1:H - 1, 1:W - 1] = 1
    for name, (c, r, pw, ph) in parts.items():
        for y in range(ph):
            for x in range(pw):
                m[r + y, c + x] = add(sock)
    return tiles[1:], pals[1:], m


# ---- stage 9, CORONA -------------------------------------------------------
# Low over the Sun: its surface is the background color; patches of
# granulation (the lanes between the boiling cells), sunspots and faculae
# are P2. The flares (MegaGammaForce's sky) are tiles too, in two groups:
# A in P0, B in P1, drawn once and used by both (gen_assets: a tile number
# for each group, the same characters). stage9.bas lights each group's
# palette in turn. In the fight P0 and P1 hold GAMMA PRIME's gold and the
# gamma light of its spine.
FLARE9_A, FLARE9_B, SUN9 = 0, 1, 2
GOLD9, SPINE9 = 0, 1


def _noise9(w, h, cell, seed):
    """Smooth value noise, 0-1, w x h pixels, cells `cell` pixels wide."""
    rng = np.random.default_rng(seed)
    gw, gh = w // cell + 2, h // cell + 2
    g = rng.random((gh, gw))
    yy, xx = np.mgrid[0:h, 0:w]
    u, v = xx / cell, yy / cell
    x0, y0 = u.astype(int), v.astype(int)
    fx, fy = u - x0, v - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = g[y0, x0] * (1 - fx) + g[y0, x0 + 1] * fx
    b = g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def granules9(w, h, seed):
    """A patch of granulation w x h tiles: the dark lanes between the
    cells (2) where a lumpy blob says so, a bright fleck (3) in a cell
    now and then. Its edge fades out, lanes breaking up."""
    rng = np.random.default_rng(900 + seed)
    n, m = h * H, w * W
    pts = [(rng.uniform(-6, m * 2 + 6), rng.uniform(-6, n + 6)) for _ in range(w * h * 5)]
    noise = _noise9(m, n, 4, 910 + seed)
    img = np.zeros((n, m), dtype=np.uint8)
    cx, cy = m, n / 2
    for py in range(n):
        for px in range(m):
            x, y = px * 2 + 1.0, py + 0.5
            ds = sorted(math.hypot(x - qx, y - qy) for qx, qy in pts)
            d = math.hypot((x - cx) / (m - 2), (y - cy) / (n / 2 - 1)) + (noise[py, px] - 0.5) * 0.5
            if d >= 1:
                continue
            gap = ds[1] - ds[0]
            if gap < (1.4 if d < 0.7 else 0.9):
                img[py, px] = 2
            elif ds[0] < 1.2 and d < 0.8 and BAYER4[py % 4, px % 4] < 0:
                img[py, px] = 3
    return img


def sunspot9(w, h, seed):
    """A sunspot filling w x h tiles: a dark umbra (1), a penumbra of
    radial filaments (2, lanes between), bright faculae flecked round it
    (3)."""
    n, m = h * H, w * W
    noise = _noise9(m, n, 4, 920 + seed)
    img = np.zeros((n, m), dtype=np.uint8)
    cx, cy = m, n / 2
    for py in range(n):
        for px in range(m):
            x, y = px * 2 + 1.0, py + 0.5
            u, v = (x - cx) / (m - 1), (y - cy) / (n / 2 - 1)
            a = math.atan2(v, u)
            d = math.hypot(u, v) + (noise[py, px] - 0.5) * 0.3
            bay = BAYER4[py % 4, px % 4]
            if d < 0.42:
                img[py, px] = 1
            elif d < 0.82:
                # filaments: radial stripes of penumbra, the gaps between
                # them showing the surface
                img[py, px] = 2 if math.cos(a * (8 + 2 * w) + noise[py, px] * 5) > -0.35 or d < 0.5 else 0
            elif d < 1.0 and noise[py, px] > 0.5 and bay < 0.1:
                img[py, px] = 3
    return img


def faculae9(kind):
    """A bright fleck or two on the surface."""
    t = np.zeros((H, W), dtype=np.uint8)
    rng = np.random.default_rng(930 + kind)
    for _ in range(1 + kind):
        x, y = int(rng.integers(1, W - 2)), int(rng.integers(2, H - 3))
        t[y, x] = 3
        t[y + 1, x] = 2
        if kind:
            t[y, x + 1] = 2
    return t


def flare9(kind, w, h, seed):
    """A flare w x h tiles, its feet at the bottom: a prominence loop (an
    arch of plasma) or a tongue licking up from its root (MegaGammaForce's
    sun.py). Shades 1-3 by strength."""
    n, m = h * H, w * W
    noise = _noise9(m, n, 4, 940 + seed)
    img = np.zeros((n, m), dtype=np.uint8)
    for py in range(n):
        for px in range(m):
            x, y = px * 2 + 1.0, py + 0.5
            bay = BAYER4[py % 4, px % 4]
            nz = noise[py, px] - 0.5
            if kind == "loop":
                cx, rx, ry = m, m - 5, n - 4
                d = abs(math.hypot((x - cx) / rx, (y - n) / ry) - 1) * min(rx, ry) + nz * 3
                thick = 3.4 + 1.6 * math.sin(math.atan2(n - y, x - cx) * 3 + seed)
                if d >= thick:
                    continue
                f = 1 - d / thick + nz * 0.4
            else:
                t = (n - y) / n
                cx = m + math.sin(t * math.pi * 2 + seed) * m * 0.22
                half = (m - 3) * (1 - t ** 1.5) + 1.5
                d = abs(x - cx) / half + nz * 0.5
                if d >= 1:
                    continue
                f = (1 - d) * 0.85 + (1 - t) * 0.25 + nz * 0.3
            img[py, px] = 1 + int(np.clip(math.floor(f * 3 + bay * 0.6), 0, 2))
    return img


# the flares drawn (kind, w, h in tiles), each used by both groups
FLARES9 = [("loop", 4, 2), ("tongue", 2, 3), ("tongue", 2, 4)]


def _cut9(img, w, h, tiles, pals, pal, keep=0.0):
    """Cut an image into tiles (appended): its h x w grid of tile numbers,
    0 where a tile would be (nearly) empty."""
    g = np.zeros((h, w), dtype=int)
    for r in range(h):
        for c in range(w):
            t = img[r * H:(r + 1) * H, c * W:(c + 1) * W].copy()
            if (t > 0).mean() <= keep:
                continue
            g[r, c] = len(tiles)
            tiles.append(t)
            pals.append(pal)
    return g


def corona_tiles():
    """Stage 9's ground and flares: tile 0 blank (the surface), granulation
    patches, sunspots, faculae (P2); the flares (P0, group A's). Returns
    (tiles, palettes, patches: h x w grids of tile numbers (granulation,
    then sunspots), flecks: faculae tile numbers, flares: grids,
    lethal: the flare tiles that kill (a quarter of them plasma or more))."""
    tiles, pals = [np.zeros((H, W), dtype=np.uint8)], [SUN9]
    patches = [_cut9(granules9(3, 2, 0), 3, 2, tiles, pals, SUN9, keep=0.04),
               _cut9(sunspot9(4, 3, 0), 4, 3, tiles, pals, SUN9, keep=0.04),
               _cut9(sunspot9(2, 2, 1), 2, 2, tiles, pals, SUN9, keep=0.04)]
    flecks = []
    for k in range(2):
        flecks.append(len(tiles))
        tiles.append(faculae9(k))
        pals.append(SUN9)
    # the flares: their lethal tiles (a quarter of them plasma or more)
    # numbered together, first, so a range says which kill (stage9.bas)
    cut, flares = [], []
    for i, (kind, w, h) in enumerate(FLARES9):
        img = flare9(kind, w, h, i)
        g = np.zeros((h, w), dtype=int)
        for r in range(h):
            for c in range(w):
                t = img[r * H:(r + 1) * H, c * W:(c + 1) * W].copy()
                if (t > 0).mean() > 0.03:
                    g[r, c] = len(cut) + 1
                    cut.append(t)
        flares.append(g)
    order = sorted(range(len(cut)), key=lambda k: (cut[k] > 0).mean() < 0.25)
    first = len(tiles)
    number = {}
    for k in order:
        number[k + 1] = len(tiles)
        tiles.append(cut[k])
        pals.append(FLARE9_A)
    flares = [np.vectorize(lambda t: number[int(t)] if t else 0)(g) for g in flares]
    lethal = range(first, first + sum((t > 0).mean() >= 0.25 for t in cut))
    return tiles, pals, patches, flecks, flares, lethal


def gamma_shape(w, h):
    """GAMMA PRIME's hull corners, (h + 1) x (w + 1): a disc and eight
    rays (MegaGammaForce's gamma.py, in 7 rows)."""
    g = np.zeros((h + 1, w + 1), dtype=np.uint8)
    for y in range(h + 1):
        for x in range(w + 1):
            dx, dy = x - w / 2, (y - h / 2) * 1.05
            r = math.hypot(dx, dy)
            a = math.degrees(math.atan2(dy, dx)) % 45
            ray = min(a, 45 - a)
            if r < 3.1 or (r < 6.2 and ray < 30 - r * 3.6):
                g[y, x] = 1
    return g


def _gold9(variant):
    """Gold plating (2), lit from the upper left: long plates, a seam (1,
    its lit lip 3) along the tile's top; variant 1 riveted, 2 a vent, 3 a
    seam down its left too."""
    t = np.full((H, W), 2, dtype=np.uint8)
    t[0, :] = 1
    t[1, :] = 3
    t[H - 1, :] = 1
    if variant == 1:
        for y, x in ((5, 1), (5, 6), (12, 1), (12, 6)):
            t[y, x] = 1
    elif variant == 2:
        t[6:13:2, 2:6] = 1
        t[7:14:2, 2:6] = 3
    elif variant == 3:
        t[:, 0] = 1
        t[1:, 1] = 3
    return t


def _spine9():
    """The spine (P1): gold at its edges (P1's first color matches the
    plating), a channel of gamma light down the middle in bands of its
    other two, which stage9.bas swaps so the light runs."""
    t = np.ones((H, W), dtype=np.uint8)
    for y in range(H):
        t[y, 2:6] = 2 if (y // 4) % 2 == 0 else 3
    return t


def gamma_tiles(w, h, parts):
    """GAMMA PRIME's hull: its map (h x w tile numbers into the returned
    tiles, 0 clear) in gold plate (P0), its rim in marching squares, the
    spine's light (P1) above the core and below the emitter, the parts'
    sockets plain (their sprites cover them). Returns (tiles, palettes,
    map) - tile numbers from 1."""
    tiles, pals, ids = [None], [GOLD9], {}

    def add(t, pal=GOLD9):
        key = (t.tobytes(), pal)
        if key not in ids:
            ids[key] = len(tiles)
            tiles.append(t)
            pals.append(pal)
        return ids[key]

    g = gamma_shape(w, h)
    m = np.zeros((h, w), dtype=np.uint8)
    rng = np.random.default_rng(9)
    for r in range(h):
        for c in range(w):
            cfg = (int(g[r, c]), int(g[r, c + 1]), int(g[r + 1, c + 1]), int(g[r + 1, c]))
            if cfg == (1, 1, 1, 1):
                m[r, c] = add(_gold9(int(rng.choice(4, p=[0.4, 0.25, 0.2, 0.15]))))
            elif any(cfg):
                m[r, c] = add(_blend(cfg, 2, 3, 1, cut=0.5))
    spine = add(_spine9(), SPINE9)
    cx, cy = parts["CORE"][:2]
    ey = parts["EMITTER"][1] + parts["EMITTER"][3]
    for r in list(range(0, cy)) + list(range(ey, h)):
        for c in (cx, cx + 1):
            if all(g[r + a, c + b] for a in (0, 1) for b in (0, 1)):
                m[r, c] = spine
    sock = _gold9(0)
    sock[1:H - 1, 1:W - 1] = 1
    for name, (c, r, pw, ph) in parts.items():
        for y in range(ph):
            for x in range(pw):
                m[r + y, c + x] = add(sock)
    return tiles[1:], pals[1:], m
