#!/usr/bin/env python3
"""Snapshot MegaGammaForce's stage 9 (CORONA) into assets/mgf/.

MegaGammaForce removed its art generators from git (its commit 35d274c);
they live on, untracked, in its gtools/art. Stage 9's map here is our own
(gen_assets.stage9: the Sun's surface and its flares, laid out as
MegaGammaForce's are, in our tiles), so this keeps only what we take as
it is:

  stage9.json   the waves, GAMMA PRIME's parts (for reference: our hull
                is repacked into 7 rows)

    .venv/bin/python tools/import_mgf9.py [--art ../../rp6502/MegaGammaForce/gtools/art]
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "mgf"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--art", default=str(ROOT.parent.parent / "rp6502" / "MegaGammaForce" / "gtools" / "art"))
    args = ap.parse_args()
    art = Path(args.art).resolve()
    if not (art / "gamma.py").exists():
        sys.exit(f"MegaGammaForce's art generators not found at {art}")
    sys.path.insert(0, str(art))
    import gamma  # noqa: E402
    import waves  # noqa: E402

    (OUT / "stage9.json").write_text(json.dumps({
        "hull_w": gamma.W,
        "hull_h": gamma.H,
        "hull_parts": {k: list(v) for k, v in gamma.PARTS.items()},
        "fields": ["at", "type", "color", "x", "dx", "count", "gap", "param"],
        "waves": waves.S9_WAVES,
        "source": "MegaGammaForce gtools/art (gamma.py, waves.py S9_WAVES), as its commit 35d274c^ tools/art",
        "note": "parts: (col, row, w, h) in hull tiles, MegaGammaForce's 10 x 9 hull",
    }, indent=1) + "\n")
    print(f"stage 9: {len(waves.S9_WAVES)} waves; hull {gamma.W} x {gamma.H}, {len(gamma.PARTS)} parts")


if __name__ == "__main__":
    main()
