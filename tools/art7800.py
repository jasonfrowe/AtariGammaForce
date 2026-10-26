"""Read assets/art7800.txt: sprites drawn as text for the 7800.

Each sprite is a list of frames; a frame is a 2D uint8 array of 160A
slots (0 = transparent, 1-3 = palette colors). Frames are padded at the
bottom to the tallest frame of their sprite, and on the right to a whole
byte (4 pixels).
"""

from pathlib import Path

import numpy as np

ART = Path(__file__).resolve().parent.parent / "assets" / "art7800.txt"


def load(path=ART):
    sprites = {}
    name, frames, cur = None, [], []

    def end_frame():
        nonlocal cur
        if cur:
            frames.append(cur)
        cur = []

    def end_sprite():
        nonlocal frames
        end_frame()
        if name is not None:
            sprites[name] = to_arrays(name, frames)
        frames = []

    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            end_sprite()
            name = line[1:-1]
        elif line == "frame":
            end_frame()
        else:
            cur.append(line)
    end_sprite()
    return sprites


def to_arrays(name, frames):
    h = max(len(f) for f in frames)
    w = max(len(r) for f in frames for r in f)
    w = (w + 3) // 4 * 4
    out = []
    for f in frames:
        a = np.zeros((h, w), dtype=np.uint8)
        for y, row in enumerate(f):
            for x, ch in enumerate(row):
                if ch not in ".123":
                    raise ValueError(f"[{name}] bad character {ch!r} in {row!r}")
                a[y, x] = ".123".index(ch)
        out.append(a)
    return out
