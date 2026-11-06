#!/usr/bin/env python3
"""Snapshot MegaGammaForce's stage 7 (SEA OF TRANQUILITY) into assets/mgf/.

MegaGammaForce removed its art generators from git (its commit 35d274c);
they live on, untracked, in its gtools/art (or extract them with
`git archive 35d274c^ tools/art`). This runs them for stage 7 only, so
the other stages' snapshots stay as they were:

  stage7_ground.bin  the moon (luna.py) at 20 columns, stage order (row 0
                     first seen), the body only: gen_assets adds the gap,
                     MASS DRIVER's hull and the loop
  stage7_hull.bin    MASS DRIVER's hull (driver.py), rows from the breech
                     (top) down to the muzzle
  stage7.json        tile names, bunkers, roads, the hull's parts, waves

    .venv/bin/python tools/import_mgf7.py [--art ../../rp6502/MegaGammaForce/gtools/art]
"""

import argparse
import inspect
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "mgf"
COLS = 20
BODY_ROWS = 176        # MegaGammaForce's: 208 rows less its two 16-row loops
# The bases' plazas: MegaGammaForce's run nearly the whole width (in from
# each side 0-2 tiles); here 3-5, so a plaza is at most 14 of the 20
# columns (MARIA fetches every drawn tile on every line)
PLAZA_IN = (3, 6)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--art", default=str(ROOT.parent.parent / "rp6502" / "MegaGammaForce" / "gtools" / "art"))
    args = ap.parse_args()
    art = Path(args.art).resolve()
    if not (art / "luna.py").exists():
        sys.exit(f"MegaGammaForce's art generators not found at {art}")
    sys.path.insert(0, str(art))
    import driver  # noqa: E402
    import luna  # noqa: E402
    import waves  # noqa: E402

    _, ids = luna.ground_tileset()
    src = inspect.getsource(luna.ground_map)
    for a, b in (("c0 = int(rng.integers(0, 3))", f"c0 = int(rng.integers{PLAZA_IN})"),
                 ("c1 = COLS - int(rng.integers(0, 3))", f"c1 = COLS - int(rng.integers{PLAZA_IN})")):
        assert a in src, a
        src = src.replace(a, b)
    ns = dict(vars(luna))
    ns["COLS"] = COLS
    exec(src, ns)
    ground, bunkers, roads = ns["ground_map"](BODY_ROWS, ids)
    (OUT / "stage7_ground.bin").write_bytes(ground.astype(np.uint8).tobytes())

    _, hids, hull = driver.hull()
    (OUT / "stage7_hull.bin").write_bytes(hull.astype(np.uint8).tobytes())
    (OUT / "stage7.json").write_text(json.dumps({
        "cols": COLS,
        "rows": BODY_ROWS,
        "tile_ids": {k: int(v) for k, v in ids.items()},
        "bunkers": sorted([int(r), int(c)] for r, c in bunkers),
        "roads": sorted(int(r) for r in roads),
        "hull_w": int(hull.shape[1]),
        "hull_h": int(hull.shape[0]),
        "hull_tile_ids": {k: int(v) for k, v in hids.items()},
        "hull_parts": {k: list(v) for k, v in driver.PARTS.items()},
        "fields": ["at", "type", "color", "x", "dx", "count", "gap", "param"],
        "waves": waves.S7_WAVES,
        "source": "MegaGammaForce gtools/art (luna.py, driver.py, waves.py S7_WAVES), "
                  "as its commit 35d274c^ tools/art",
        "note": "ground: stage order (row 0 first), 20 columns; bunkers: (row, col) of the bunker's "
                "lower row; roads: rows; hull: rows from the breech (top) down to the muzzle; "
                "parts: (col, row, w, h) in hull tiles",
    }, indent=1) + "\n")
    print(f"stage 7: {ground.shape[0]} x {ground.shape[1]}, {len(bunkers)} bunkers, {len(roads)} roads; "
          f"hull {hull.shape[1]} x {hull.shape[0]}; {len(waves.S7_WAVES)} waves")


if __name__ == "__main__":
    main()
