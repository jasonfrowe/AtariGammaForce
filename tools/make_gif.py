#!/usr/bin/env python3
"""Record docs/gameplay.gif: the title, then each stage and its boss.

Each clip is a run of the A7800 emulator (tools/play.sh) with an
invulnerable test build, the ship weaving and firing, a screenshot every
third frame (20 a second). The GIF is twice size with sharp pixels, in
the game's own colors (there are few: every one is kept).

    .venv/bin/python tools/make_gif.py
"""

import glob
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

# name, build defines, first and last frame, title (no game started)
CLIPS = [
    ("title", "CHEAT", 60, 240, True),
    ("stage1", "CHEAT", 1580, 1820, False),
    ("boss1", "CHEAT BOSSTEST", 1100, 1340, False),
    ("stage2", "CHEAT STAGE2TEST", 1500, 1740, False),
    ("boss2", "CHEAT BOSSTEST STAGE2TEST", 1200, 1440, False),
    ("stage3", "CHEAT STAGE3TEST", 1850, 2090, False),
    ("boss3", "CHEAT BOSSTEST STAGE3TEST", 3900, 4140, False),
    ("stage4", "CHEAT STAGE4TEST", 1150, 1390, False),
    ("boss4", "CHEAT BOSSTEST STAGE4TEST", 1800, 2040, False),
]


def record(tmp, name, defines, first, last, title):
    lines = []
    if not title:
        lines += ["300 press P1 Button 2", "310 release P1 Button 2", "320 press P1 Button 1"]
    for f in range(330, 6000, 200):  # weave
        lines += [f"{f} press P1 Left", f"{f + 45} release P1 Left",
                  f"{f + 100} press P1 Right", f"{f + 145} release P1 Right"]
    lines += [f"{f} snap" for f in range(first, last + 1, 3)]
    script = tmp / f"{name}.txt"
    script.write_text("\n".join(lines) + "\n")
    subprocess.run([str(ROOT / "tools" / "build.sh")], env={**os.environ, "GF_DEFINES": defines},
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run([str(ROOT / "tools" / "play.sh"), str(script), str(tmp / name)],
                   env={**os.environ, "ROM": str(ROOT / "build" / "gammaforce-test.a78")},
                   check=True, stdout=subprocess.DEVNULL)
    return sorted(glob.glob(str(tmp / name / "a7800" / "*.png")))


def main():
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        files = []
        for clip in CLIPS:
            files += record(tmp, *clip)
            print(clip[0], file=sys.stderr)
        arrs = [np.asarray(Image.open(f).convert("RGB")) for f in files]
    cols = sorted({tuple(int(v) for v in c) for a in arrs for c in np.unique(a.reshape(-1, 3), axis=0)})
    assert len(cols) <= 256, len(cols)
    flat = [v for c in cols for v in c]
    palette = flat + [0] * (768 - len(flat))
    key = {c: i for i, c in enumerate(cols)}
    frames = []
    for a in arrs:
        packed = (a[..., 0].astype(np.uint32) << 16) | (a[..., 1].astype(np.uint32) << 8) | a[..., 2]
        idx = np.zeros(a.shape[:2], dtype=np.uint8)
        for (r, g, b), i in key.items():
            idx[packed == ((r << 16) | (g << 8) | b)] = i
        im = Image.fromarray(idx, "P")
        im.putpalette(palette)
        frames.append(im.resize((im.size[0] * 2, im.size[1] * 2), Image.NEAREST))
    out = ROOT / "docs" / "gameplay.gif"
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=50, loop=0, optimize=True)
    print(f"{out}: {len(frames)} frames, {len(cols)} colors, {out.stat().st_size} bytes")


if __name__ == "__main__":
    main()
