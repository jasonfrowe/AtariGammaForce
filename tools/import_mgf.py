#!/usr/bin/env python3
"""Snapshot MegaGammaForce source art into assets/mgf/.

MegaGammaForce (the RP6502 original) draws its art procedurally. This script
runs its generators where we need something different (stage maps 20 tiles
wide instead of 12, to fill the 7800's 160 pixel screen) and copies the
sprite sheets as they are. The results are committed, so building the 7800
game never needs the MegaGammaForce checkout; rerun this only to pull fresh
art from it.

    .venv/bin/python tools/import_mgf.py [--mgf ../../rp6502/MegaGammaForce]
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "mgf"
COLS = 20  # 160 px screen / 8 px tiles
MGF_COLS = 12  # MegaGammaForce's playfield width in tiles
RAIL4 = 12  # stage 4's railway: its left column
ROCK4 = (0.74, 0.70, 0.70, 0.70)  # stage 4's rock level per chunk (MegaGammaForce: 0.62)
# Stage 5's chunks (32 rows each): their stretches of shelf (s) and floes (f),
# and the noise level above which a corner is ice, in each kind (MegaGammaForce:
# shelf 0.18, floes 0.62; here the ice is the background, so the floes are
# mostly ice too, cut by leads of open water)
CHUNKS5 = [([("f", 32)], 11), ([("s", 32)], 12), ([("s", 10), ("f", 14), ("s", 8)], 13),
           ([("f", 12), ("s", 20)], 14)]
SHELF5, FLOE5 = 0.16, 0.33

SPRITE_SHEETS = [
    "player.png", "enemy16.png", "enemy32.png", "bullet8.png", "bullet16.png",
    "shot8.png", "sword.png", "vulcan.png", "expl16.png", "expl32.png",
    "flame.png", "miniship.png", "gem.png", "digits.png", "icons.png",
]


def save_indexed(path, frames, palette):
    """frames: list of 2D uint8 arrays of palette indices, saved side by side."""
    h, w = frames[0].shape
    img = Image.new("P", (w * len(frames), h))
    flat = []
    for c in palette:
        flat += list(c) if c is not None else [255, 0, 255]
    img.putpalette(flat + [0] * (768 - len(flat)))
    for i, f in enumerate(frames):
        img.paste(Image.fromarray(f.astype(np.uint8), "P"), (i * w, 0))
    img.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mgf", default=str(ROOT.parent.parent / "rp6502" / "MegaGammaForce"))
    args = ap.parse_args()
    mgf = Path(args.mgf).resolve()
    if not (mgf / "tools" / "art" / "tiles.py").exists():
        sys.exit(f"MegaGammaForce not found at {mgf}")
    sys.path.insert(0, str(mgf / "tools" / "art"))
    import palettes  # noqa: E402  (MegaGammaForce's)
    import tiles  # noqa: E402

    OUT.mkdir(parents=True, exist_ok=True)

    # Stage 1 at 20 columns. tiles.stage1() returns the map top row first;
    # we store it in stage order (row 0 is where the stage starts, at the
    # bottom of the screen) because that is the order the 7800 reads it.
    # The fortress is generated at MegaGammaForce's own 12 columns and set in
    # the middle of a 20-column sea: it keeps its size next to the ship, and
    # the deck (a full row of characters costs MARIA ~190 DMA cycles a line,
    # which halts the CPU) covers 60% of a row at most.
    tiles.COLS = MGF_COLS
    tl, ids, top_first, hatches = tiles.stage1()
    narrow = top_first[::-1].copy()
    pad = (COLS - MGF_COLS) // 2
    stage_order = np.full((narrow.shape[0], COLS), ids["sea0"], dtype=np.uint8)
    stage_order[:, pad:pad + MGF_COLS] = narrow
    hatches = [(r, c + pad) for r, c in hatches]
    save_indexed(OUT / "stage1_tiles.png", tl, palettes.TILES)
    (OUT / "stage1_map.bin").write_bytes(stage_order.astype(np.uint8).tobytes())
    meta = {
        "cols": COLS,
        "rows": int(stage_order.shape[0]),
        "loop_rows": tiles.LOOP_ROWS,
        "tile_ids": {k: int(v) for k, v in ids.items()},
        # Ground turrets sit on the big hatches (stages.py): centre y in
        # pixels up from the bottom of the map, centre x in 16-px tiles.
        "ground": sorted([[(r + 1) * 16, (c + 1)] for r, c in hatches]),
        "note": "map is stage order: row 0 = start of stage (bottom of screen)",
    }
    (OUT / "stage1.json").write_text(json.dumps(meta, indent=1) + "\n")

    for name in SPRITE_SHEETS:
        src = mgf / "images" / name
        if src.exists():
            shutil.copy2(src, OUT / name)
    for name in ["boss_core.png", "boss_wing.png", "boss_cannon.png", "boss_turret.png", "logo.png"]:
        src = mgf / "images" / "stage1" / name
        if src.exists():
            shutil.copy2(src, OUT / f"stage1_{name}")

    # Stage 1's air waves (waves.py), as they are; gen_assets.py scales them.
    import waves  # noqa: E402  (MegaGammaForce's)
    (OUT / "stage1_waves.json").write_text(json.dumps(
        {"fields": ["at", "type", "color", "x", "dx", "count", "gap", "param"],
         "units": "MegaGammaForce: x in its 192 px playfield, y in its 240 lines, at in scroll pixels",
         "waves": waves.S1_WAVES}, indent=1) + "\n")

    # Stage 2, NEON SPIRES: the city's ground layer (12 columns). The 7800
    # version builds its stage from eight districts (8-row blocks, each a
    # road and a block of buildings) generated by MegaGammaForce's city.py,
    # repeated in a varied order (tools/gen_assets.py), so its bank holds
    # few different rows; plus city.py's 16-row loop for the boss. Saved in
    # stage order (row 0 first), with the gun pads' (row, col). The
    # parallax sky layer (towers, clouds) is left out: the 7800 version
    # has one background.
    import city  # noqa: E402
    import waves  # noqa: E402  (MegaGammaForce's)
    _, ids2 = city.ground_tileset()
    blocks, pads, roads = city.ground_map(8 * city.BLOCK, ids2, seed=3)
    loop, _, _ = city.ground_map(city.LOOP_ROWS, ids2, seed=11)
    (OUT / "stage2_blocks.bin").write_bytes(blocks.astype(np.uint8).tobytes())
    (OUT / "stage2_loop.bin").write_bytes(loop.astype(np.uint8).tobytes())
    (OUT / "stage2.json").write_text(json.dumps({
        "cols": city.COLS,
        "block_rows": city.BLOCK,
        "blocks": int(blocks.shape[0] // city.BLOCK),
        "loop_rows": city.LOOP_ROWS,
        "tile_ids": {k: int(v) for k, v in ids2.items()},
        "pads": sorted([int(r), int(c)] for r, c in pads),
        "waves": waves.S2_WAVES,
        "note": "stage order: row 0 = first seen (bottom of screen); pads are (row, col) of the pad's lower row",
    }, indent=1) + "\n")

    # Stage 3, IRON TIDE: open ocean with islands (20 columns), as four
    # 30-row chunks from MegaGammaForce's ocean.py (open sea at both ends
    # of each, so any can follow any; gen_assets.py strings them), with
    # their bunkers (turrets) and open water (gunboats); and LEVIATHAN, the
    # battleship: its hull map (ship.py, rows from the stern down) and
    # where its parts sit. The cloud layer is left out.
    import ocean  # noqa: E402
    import ship  # noqa: E402
    _, ids3 = ocean.ground_tileset()
    ocean.COLS = COLS  # the full 20-column width: the islands keep to the sides
    chunks, bunk3, water3 = [], [], []
    for k, seed in enumerate((7, 8, 9, 10)):
        m3, b3, w3 = ocean.ground_map(30, ids3, seed=seed)
        chunks.append(m3)
        bunk3 += [[k, int(r), int(c)] for r, c in b3]
        water3 += [[k, int(r), int(c)] for r, c in w3]
    (OUT / "stage3_chunks.bin").write_bytes(np.concatenate(chunks).astype(np.uint8).tobytes())
    _, hids = ship.hull_tileset()
    hull = ship.hull_map(hids)
    (OUT / "stage3_hull.bin").write_bytes(hull.astype(np.uint8).tobytes())
    (OUT / "stage3.json").write_text(json.dumps({
        "cols": int(chunks[0].shape[1]),
        "chunk_rows": 30,
        "chunks": len(chunks),
        "tile_ids": {k: int(v) for k, v in ids3.items()},
        "bunkers": bunk3,
        "water": water3,
        "hull_w": int(hull.shape[1]),
        "hull_h": int(hull.shape[0]),
        "hull_tile_ids": {k: int(v) for k, v in hids.items()},
        "hull_parts": {k: list(v) for k, v in ship.PARTS.items()},
        "waves": waves.S3_WAVES,
        "note": "chunks: stage order (row 0 first); bunkers/water: (chunk, row, col); "
                "hull: rows from the stern (top) down to the bow; parts: (col, row, w, h) in hull tiles",
    }, indent=1) + "\n")

    # Stage 4, SCORCHED SANDS: desert (20 columns) as four 32-row chunks
    # from MegaGammaForce's desert.py (plain sand and the railway at both
    # ends of each, so any can follow any), with their bunkers (turrets).
    # The railway runs up columns RAIL4..RAIL4+1, right of the middle as in
    # the original. The sand haze layer is left out.
    import desert  # noqa: E402
    import inspect
    _, ids4 = desert.ground_tileset()
    desert.COLS, desert.RAIL = COLS, RAIL4
    # Sparser rock than MegaGammaForce's (rock where its noise passes 0.62):
    # the plateaus are character objects MARIA must fetch on every line,
    # and wide ones slowed the stage. The same generator, with the level
    # raised (most of all in chunk 0, the stage's opening).
    src = inspect.getsource(desert.ground_map).replace("nr[r, c] > 0.62", "nr[r, c] > ROCK_LEVEL")
    assert "ROCK_LEVEL" in src
    ns = dict(vars(desert))
    exec(src, ns)
    chunks4, bunk4 = [], []
    for k, seed in enumerate((4, 5, 6, 7)):
        ns["ROCK_LEVEL"] = ROCK4[k]
        m4, b4 = ns["ground_map"](32, ids4, seed=seed)
        chunks4.append(m4)
        bunk4 += [[k, int(r), int(c)] for r, c in b4]
    (OUT / "stage4_chunks.bin").write_bytes(np.concatenate(chunks4).astype(np.uint8).tobytes())
    (OUT / "stage4.json").write_text(json.dumps({
        "cols": COLS,
        "chunk_rows": 32,
        "chunks": len(chunks4),
        "rail": RAIL4,
        "tile_ids": {k: int(v) for k, v in ids4.items()},
        "bunkers": bunk4,
        "waves": waves.S4_WAVES,
        "note": "chunks: stage order (row 0 first); bunkers: (chunk, row, col) of the bunker's lower row",
    }, indent=1) + "\n")

    # Stage 5, FROZEN STRAIT: pack ice (20 columns) as four 32-row chunks
    # from MegaGammaForce's arctic.py, solid ice at both ends of each so any
    # can follow any; roads half as often (every 16 rows); with bunkers
    # (turrets), roads (tanks) and open water (icebreakers). The iceberg
    # layer is left out (gen_assets places a few bergs as obstacles). And
    # GLACIER CRAWLER: its hull map (crawler.py, rows from the rear down to
    # the drill) and where its parts sit.
    import arctic  # noqa: E402
    import crawler  # noqa: E402
    _, ids5 = arctic.ground_tileset()
    arctic.COLS = COLS
    src = inspect.getsource(arctic.ground_map)
    for a, b in (("n[r, c] > 0.18", "n[r, c] > SHELF_LEVEL"), ("n[r, c] > 0.62", "n[r, c] > FLOE_LEVEL"),
                 ("corners[0:3, :] = 0  # open water to begin with",
                  "corners[0:2, :] = 1\n    corners[rows - 1:, :] = 1"),
                 ("r % 8 == 4", "r % 16 == 6")):
        assert a in src, a
        src = src.replace(a, b)
    ns = dict(vars(arctic))
    ns.update(SHELF_LEVEL=SHELF5, FLOE_LEVEL=FLOE5)
    chunks5, bunk5, roads5, water5 = [], [], [], []
    for k, (sections, seed) in enumerate(CHUNKS5):
        ns["SECTIONS"] = sections
        exec(src, ns)
        m5, b5, r5, w5 = ns["ground_map"](32, ids5, seed=seed)
        chunks5.append(m5)
        bunk5 += [[k, int(r), int(c)] for r, c in b5]
        roads5 += [[k, int(r)] for r in r5]
        water5 += [[k, int(r), int(c)] for r, c in w5]
    (OUT / "stage5_chunks.bin").write_bytes(np.concatenate(chunks5).astype(np.uint8).tobytes())
    _, hids5 = crawler.hull_tileset()
    hull5 = crawler.hull_map(hids5)
    (OUT / "stage5_hull.bin").write_bytes(hull5.astype(np.uint8).tobytes())
    (OUT / "stage5.json").write_text(json.dumps({
        "cols": COLS,
        "chunk_rows": 32,
        "chunks": len(chunks5),
        "tile_ids": {k: int(v) for k, v in ids5.items()},
        "bunkers": bunk5,
        "roads": roads5,
        "water": water5,
        "hull_w": int(hull5.shape[1]),
        "hull_h": int(hull5.shape[0]),
        "hull_tile_ids": {k: int(v) for k, v in hids5.items()},
        "hull_parts": {k: list(v) for k, v in crawler.PARTS.items()},
        "waves": waves.S5_WAVES,
        "note": "chunks: stage order (row 0 first); bunkers/water: (chunk, row, col); roads: (chunk, row); "
                "hull: rows from the rear (top) down to the drill; parts: (col, row, w, h) in hull tiles",
    }, indent=1) + "\n")

    # The palettes the sheets were drawn with, for the converters.
    pals = {k: v for k, v in vars(palettes).items() if k.isupper() and isinstance(v, list)}
    (OUT / "palettes.json").write_text(json.dumps(pals) + "\n")
    print(f"stage 1 map {stage_order.shape[1]}x{stage_order.shape[0]}, {len(tl)} tiles -> {OUT}")


if __name__ == "__main__":
    main()
