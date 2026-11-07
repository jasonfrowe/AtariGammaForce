#!/usr/bin/env python3
"""Cutscene pictures for the 7800: a 160 x 96 PNG (2:1 pixels) as a 160A
bitmap, one 4K graphics block.

The picture is 6 zones of 16 lines. Each zone line is 40 bytes (160
pixels, 4 to a byte), so the six zones' bytes sit side by side in the
block, 240 of its 256 bytes a line (MARIA reads a zone's line n at the
object's address + (15 - n) * 256). Each zone's display list draws its
row as objects that each take one palette, so the picture is cut into
cells, 8 pixels wide by 16 lines, and a run of cells sharing a palette is
one object.

The rules a picture keeps (storyboard/panels/README.md):
  - 7800 colors (the a7800 NTSC palette; anything else is snapped to the
    nearest)
  - one background color, shared by the whole picture
  - in each 8 x 16 cell, at most 3 colors besides the background
  - at most 6 palettes of 3 colors over the whole picture: every cell's
    colors must be within one of them
fit() keeps them: a cell with too many colors loses its rarest (each
pixel to its nearest kept color), and cells that no palette fits take the
closest one; check() says what it had to change.

    tools/cutscene7800.py check panel.png [--bg $00] [--out preview.png]
    tools/cutscene7800.py previews [storyboard/panels]

previews rewrites each picture's <name>_preview.png (4x, 2:1 pixels, as
the 7800 shows it) in the panels folder: the full pictures and the
portraits (32 x 48 ones).
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PAL7800 = np.array(json.loads((ROOT / "tools" / "a7800_ntsc_palette.json").read_text())["rgb"], dtype=float)

W, H = 160, 96
CELL_W, CELL_H = 8, 16
COLS, ROWS = W // CELL_W, H // CELL_H
NPAL = 6
WEIGHT = np.array([3.0, 4.0, 2.0])   # (as gen_assets.nearest: weighted for the eye)


def snap(rgb):
    """An H x W x 3 RGB array -> 7800 color bytes (nearest)."""
    flat = rgb.reshape(-1, 3).astype(float)
    d = (((flat[:, None, :] - PAL7800[None, :, :]) ** 2) * WEIGHT).sum(axis=2)
    return d.argmin(axis=1).reshape(rgb.shape[:2]).astype(int)


def cdist(a, b):
    """Distance between two 7800 colors."""
    return float((((PAL7800[a] - PAL7800[b]) ** 2) * WEIGHT).sum())


def load(path, size=(W, H)):
    """A picture (size: pixels across, lines; a portrait's is PORTRAIT) as
    7800 colors. Drawn with square pixels at twice the width, it is halved."""
    img = Image.open(path).convert("RGB")
    w, h = size
    if img.size != (w, h):
        if img.size == (2 * w, h):
            img = img.resize((w, h), Image.NEAREST)
        else:
            sys.exit(f"{path}: {img.size[0]} x {img.size[1]}, not {w} x {h} (or {2 * w} x {h})")
    return snap(np.asarray(img))


# a briefing's speaker: 32 pixels by 48 lines (4 x 3 cells), 2 palettes
PORTRAIT = (32, 48)
PORTRAIT_NPAL = 2


def cells(img):
    for r in range(img.shape[0] // CELL_H):
        for c in range(img.shape[1] // CELL_W):
            yield r, c, img[r * CELL_H:(r + 1) * CELL_H, c * CELL_W:(c + 1) * CELL_W]


def fit(img, bg=None, npal=NPAL):
    """Make a picture keep the rules. Returns (fitted picture of 7800 colors,
    bg, palettes: lists of 3 colors, cell palette numbers ROWS x COLS,
    notes: what had to change)."""
    img = img.copy()
    notes = []
    if bg is None:
        vals, counts = np.unique(img, return_counts=True)
        bg = int(vals[counts.argmax()])
    # each cell: at most 3 colors besides the background
    sets = {}
    for r, c, cell in cells(img):
        vals, counts = np.unique(cell[cell != bg], return_counts=True)
        order = [int(v) for _, v in sorted(zip(-counts, vals))]
        keep = order[:3]
        if len(order) > 3:
            notes.append(f"cell ({c}, {r}): {len(order)} colors besides the background, kept 3")
            for v in order[3:]:
                to = min(keep + [bg], key=lambda k: cdist(v, k))
                cell[cell == v] = to
        sets[r, c] = frozenset(keep)
    # palettes covering every cell's colors: the biggest sets first, each
    # into a palette it fits (or has room to grow into)
    pals = []
    order = sorted(sets, key=lambda k: -len(sets[k]))
    for k in order:
        s = sets[k]
        if not s or any(s <= set(p) for p in pals):
            continue
        grow = [p for p in pals if len(set(p) | s) <= 3]
        if grow:
            p = min(grow, key=lambda p: len(set(p) | s))
            p.extend(sorted(s - set(p)))
        elif len(pals) < npal:
            pals.append(sorted(s))
    for p in pals:
        while len(p) < 3:
            p.append(p[-1] if p else bg)
    if not pals:
        pals = [[bg, bg, bg]]
    # each cell to its palette (the best fit for the ones no palette holds)
    which = np.zeros((img.shape[0] // CELL_H, img.shape[1] // CELL_W), dtype=int)
    for r, c, cell in cells(img):
        s = sets[r, c]
        fits = [i for i, p in enumerate(pals) if s <= set(p)]
        if fits:
            which[r, c] = fits[0]
            continue

        def cost(i):
            return sum(min(cdist(v, k) for k in pals[i] + [bg]) * int((cell == v).sum()) for v in s)
        i = min(range(len(pals)), key=cost)
        which[r, c] = i
        notes.append(f"cell ({c}, {r}): colors {sorted(f'${v:02X}' for v in s)} in no palette, given palette {i}")
        for v in s:
            if v not in pals[i]:
                cell[cell == v] = min(pals[i] + [bg], key=lambda k: cdist(v, k))
    return img, bg, pals, which, notes


def slots(img, bg, pals, which):
    """Each pixel's 160A slot: 0 the background, 1-3 its cell's palette."""
    out = np.zeros(img.shape, dtype=np.uint8)
    for r, c, cell in cells(img):
        p = pals[which[r, c]]
        sl = out[r * CELL_H:(r + 1) * CELL_H, c * CELL_W:(c + 1) * CELL_W]
        for k in range(3):
            sl[cell == p[k]] = k + 1
        # (a palette padded with a repeat: its first match wins, as above)
    return out


def block(sl):
    """The 4K graphics block: zone z's line n at (15 - n) * 256 + z * 40."""
    out = bytearray(4096)
    for z in range(ROWS):
        for n in range(CELL_H):
            y = z * CELL_H + n
            for b in range(W // 4):
                px = sl[y, b * 4:b * 4 + 4]
                out[(15 - n) * 256 + z * 40 + b] = (px[0] << 6) | (px[1] << 4) | (px[2] << 2) | px[3]
    return bytes(out)


def objects(which):
    """Each zone's objects: (first byte in the zone's 40, width in bytes,
    palette, x) for each run of cells sharing a palette."""
    zones = []
    for r in range(which.shape[0]):
        runs = []
        for c in range(which.shape[1]):
            p = int(which[r, c])
            if runs and runs[-1][2] == p:
                runs[-1][1] += CELL_W // 4
            else:
                runs.append([c * CELL_W // 4, CELL_W // 4, p, c * CELL_W])
        zones.append([tuple(x) for x in runs])
    return zones


def preview(img, scale=3):
    rgb = PAL7800[img].astype(np.uint8)
    h, w = img.shape
    return Image.fromarray(rgb).resize((w * 2 * scale, h * scale), Image.NEAREST)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["check", "previews"])
    ap.add_argument("png", nargs="?", default=str(ROOT / "storyboard" / "panels"))
    ap.add_argument("--bg", help="the background color, a 7800 byte ($00); the commonest otherwise")
    ap.add_argument("--out", help="write the fitted picture's preview here")
    ap.add_argument("--portrait", action="store_true", help="a speaker's portrait (32 x 48, 2 palettes)")
    args = ap.parse_args()
    if args.cmd == "previews":
        folder = Path(args.png)
        for f in sorted(folder.glob("*.png")):
            if f.stem.endswith("_preview") or f.stem.startswith(("template", "grid", "atari7800")):
                continue
            size = Image.open(f).size
            portrait = size in (PORTRAIT, (2 * PORTRAIT[0], PORTRAIT[1]))
            img = load(f, PORTRAIT if portrait else (W, H))
            fitted, bg, pals, which, notes = fit(img, 0 if portrait else None,
                                                 PORTRAIT_NPAL if portrait else NPAL)
            preview(fitted, 4).save(folder / f"{f.stem}_preview.png")
            print(f"{f.name}: preview{'' if not notes else f' ({len(notes)} cells changed to fit)'}")
        return
    img = load(args.png, PORTRAIT if args.portrait else (W, H))
    bg = int(args.bg.lstrip("$"), 16) if args.bg else None
    fitted, bg, pals, which, notes = fit(img, bg, PORTRAIT_NPAL if args.portrait else NPAL)
    print(f"{args.png}: background ${bg:02X}; {len(pals)} palettes: "
          + "  ".join("/".join(f"${c:02X}" for c in p) for p in pals))
    nobj = max(len(z) for z in objects(which))
    print(f"  {nobj} objects in its busiest zone")
    changed = int((fitted != img).sum())
    if notes:
        print(f"  {len(notes)} changes ({changed} pixels):")
        for n in notes[:40]:
            print("   ", n)
    else:
        print("  keeps the rules: no changes")
    if args.out:
        preview(fitted).save(args.out)
        print(f"  preview: {args.out}")


if __name__ == "__main__":
    main()
