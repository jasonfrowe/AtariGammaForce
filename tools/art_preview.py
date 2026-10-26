#!/usr/bin/env python3
"""Preview assets/art7800.txt in 7800 colors, pixels 2:1 like a TV.

    .venv/bin/python tools/art_preview.py [out.png] [sprite ...]
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import art7800  # noqa: E402
import gen_assets as ga  # noqa: E402

SCALE = 4


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ga.PREVIEW / "art7800.png"
    pick = set(sys.argv[2:])
    sprites = art7800.load()
    rows = []
    for name, frames in sprites.items():
        if pick and name not in pick:
            continue
        pal = ga.SPRITE_PAL.get(name, 3)
        imgs = [ga.preview(f, ga.PAL_CODES[pal], scale=SCALE) for f in frames]
        w = sum(i.size[0] + 8 for i in imgs)
        h = max(i.size[1] for i in imgs)
        row = Image.new("RGB", (w, h), ga.rgb_of(ga.BG_CODE))
        x = 0
        for i in imgs:
            row.paste(i, (x, 0))
            x += i.size[0] + 8
        rows.append(row)
    W = max(r.size[0] for r in rows)
    H = sum(r.size[1] + 8 for r in rows)
    sheet = Image.new("RGB", (W, H), (40, 0, 40))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.size[1] + 8
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
