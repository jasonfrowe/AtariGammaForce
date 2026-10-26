#!/usr/bin/env python3
"""Check the scroll engine against the map.

For each screenshot taken by tools/emu/probe.lua, render what the
playfield background should look like at the logged scroll position and
compare it line by line with the emulator's picture. Sprites cover a few
pixels, so a line counts as wrong only when most of it differs.

    check_scroll.py <probe dir>    (holds probe.txt and a7800/NNNN.png)
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gen_assets as ga  # noqa: E402


def expected_lines(spos, tiles, pals, m):
    """The 209 playfield lines as (209, 160, 3) RGB, one 160A pixel each."""
    rows = m.shape[0]
    C, s = spos >> 4, 15 - (spos & 15)
    out = np.zeros((209, 160, 3), dtype=np.uint8)
    for L in range(209):
        v = L + 16 + s
        k, line = v >> 4, v & 15
        r = C + 14 - k
        while r >= rows:
            r -= 16  # the boss loop
        for c in range(20):
            t = int(m[r, c])
            cols = [ga.rgb_of(ga.BG_CODE)] + [ga.rgb_of(x) for x in ga.PAL_CODES[pals[t]]]
            for x in range(8):
                out[L, c * 8 + x] = cols[tiles[t][line, x]]
    return out


TOP = 26  # screenshot line where the playfield starts (HUD is the 16 above)


def main():
    d = Path(sys.argv[1])
    st = ga.stage1()
    m, tiles, pals = st["map"], st["t_slots"], st["t_pals"]
    ok = True
    # play.sh log: "<frame> 2231 <lo> <hi>" per screenshot, in order
    probes = [l.split() for l in (d / "play.txt").read_text().split("\n") if l.split()[1:2] == ["2231"]]
    for i, p in enumerate(probes):
        frame, spos = int(p[0]), int(p[2], 16) + 256 * int(p[3], 16)
        shot = np.array(Image.open(d / "a7800" / f"{i:04d}.png").convert("RGB"))[:, ::2, :]  # 160 wide
        # The probe reads the engine at the end of a frame, when the game has
        # already advanced the scroll for the next one, so the picture shows
        # this position or an earlier one (more than one when frames lag).
        results = []
        for pos in (spos, spos - 1, spos - 2, spos - 3):
            exp = expected_lines(pos, tiles, pals, m)
            bad = [L for L in range(209) if np.any(shot[TOP + L] != exp[L], axis=1).mean() > 0.5]
            results.append((len(bad), pos, bad))
        nbad, pos, bad = min(results)
        zones = sorted(set((L + 16 + 15 - (pos & 15)) >> 4 for L in bad))
        print(f"frame {frame} scroll {pos} (s={15 - (pos & 15)}): "
              f"{len(bad)} bad lines" + (f" in zones {zones}: {bad[:12]}" if bad else ""))
        ok &= not bad
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
