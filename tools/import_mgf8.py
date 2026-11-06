#!/usr/bin/env python3
"""Snapshot MegaGammaForce's stage 8 (DEEP FIELD) into assets/mgf/.

MegaGammaForce removed its art generators from git (its commit 35d274c);
they live on, untracked, in its gtools/art. Stage 8's map here is our own
(gen_assets.stage8: asteroid drifts in repeated chunks, as the bank has
room for few different rows), so this keeps only what we take as it is:

  stage8.json   the waves, HIVE MOTHERSHIP's parts (for reference: our
                hull is repacked into 7 rows)

    .venv/bin/python tools/import_mgf8.py [--art ../../rp6502/MegaGammaForce/gtools/art]
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
    if not (art / "hive.py").exists():
        sys.exit(f"MegaGammaForce's art generators not found at {art}")
    sys.path.insert(0, str(art))
    import hive  # noqa: E402
    import waves  # noqa: E402

    (OUT / "stage8.json").write_text(json.dumps({
        "hull_w": hive.W,
        "hull_h": hive.H,
        "hull_parts": {k: list(v) for k, v in hive.PARTS.items()},
        "fields": ["at", "type", "color", "x", "dx", "count", "gap", "param"],
        "waves": waves.S8_WAVES,
        "source": "MegaGammaForce gtools/art (hive.py, waves.py S8_WAVES), as its commit 35d274c^ tools/art",
        "note": "parts: (col, row, w, h) in hull tiles, MegaGammaForce's 10 x 9 hull",
    }, indent=1) + "\n")
    print(f"stage 8: {len(waves.S8_WAVES)} waves; hull {hive.W} x {hive.H}, {len(hive.PARTS)} parts")


if __name__ == "__main__":
    main()
