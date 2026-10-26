"""The title logo, GAMMA over FORCE, drawn for the 7800.

Chunky beveled letters after MegaGammaForce's logo: a 5x7 letter grid,
each cell 3 pixels by 4 lines (about square on screen), in three colors:
1 dark rim and shadow, 2 body, 3 the lit bevel. The title
cycles the palette's hues (gammaforce.bas title_hues), as Astrowing does.

    words() -> {"logo_gamma": frame, "logo_force": frame}, 92 x 32 each
"""

import numpy as np

CW, CH = 3, 4          # cell size: pixels, lines
GAP = 1                # cells between letters
W, H = 92, 32          # image size (a multiple of 4 pixels; two strips)

FONT = {
    "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
}


def word(text):
    cells_w = len(text) * 5 + (len(text) - 1) * GAP
    mask = np.zeros((7 * CH, cells_w * CW), dtype=bool)
    for i, ch in enumerate(text):
        for r, row in enumerate(FONT[ch]):
            for c, v in enumerate(row):
                if v == "#":
                    x = (i * (5 + GAP) + c) * CW
                    mask[r * CH:(r + 1) * CH, x:x + CW] = True
    # Into the image, centred, with room for the rim.
    a = np.zeros((H, W), dtype=np.uint8)
    m = np.zeros((H, W), dtype=bool)
    oy = (H - mask.shape[0]) // 2
    ox = (W - mask.shape[1]) // 2
    m[oy:oy + mask.shape[0], ox:ox + mask.shape[1]] = mask

    def at(dy, dx):
        s = np.zeros_like(m)
        ys = slice(max(dy, 0), H + min(dy, 0))
        yd = slice(max(-dy, 0), H + min(-dy, 0))
        xs = slice(max(dx, 0), W + min(dx, 0))
        xd = slice(max(-dx, 0), W + min(-dx, 0))
        s[yd, xd] = m[ys, xs]
        return s       # s[y, x] = m[y + dy, x + dx]

    a[m] = 2
    # bevel: lit where the stroke faces up or left, dark where it faces
    # down or right (the light comes from the top left)
    a[m & (~at(-1, 0) | ~at(0, -1))] = 3
    a[m & (~at(1, 0) | ~at(0, 1))] = 1
    # dark rim around the letters, a line deeper below (a drop shadow)
    rim = (at(-1, 0) | at(1, 0) | at(0, -1) | at(0, 1) | at(-2, 0) | at(-1, -1)) & ~m
    a[rim] = 1
    return a


def words():
    return {"logo_gamma": word("GAMMA"), "logo_force": word("FORCE")}


if __name__ == "__main__":
    for name, a in words().items():
        print(name)
        for row in a:
            print("".join(".123"[v] for v in row))
