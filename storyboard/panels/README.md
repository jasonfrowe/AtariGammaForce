# Cutscene panels: how to draw them for the 7800

Five full pictures (the prologue, the three act breaks, the epilogue) and
three portraits for the briefings. The PNGs here are placeholders drawn by
`tools/story_placeholders.py`; draw over them and keep the file names.
Only `<name>.png` is read: the `_preview.png` files are just enlarged
previews (`.venv/bin/python tools/cutscene7800.py previews` remakes them all).
Then `.venv/bin/python tools/gen_cutscenes.py` and `tools/build.sh` put
them in the game. (`story_placeholders.py` leaves a picture that is
already here alone, unless given `--force`.)

| File | Size | Scene |
|---|---|---|
| `prologue.png` | 160 x 96 | Scramble Order: Code Gamma (before stage 1) |
| `act1.png` | 160 x 96 | Atmospheric Breakout (before stage 6) |
| `act2.png` | 160 x 96 | Into the Deep Field (before stage 8) |
| `act3.png` | 160 x 96 | The Solar Corona (before stage 9) |
| `epilogue.png` | 160 x 96 | The Sun Burns Clean (after GAMMA PRIME) |
| `maya.png`, `thorne.png`, `gamma.png` | 32 x 48 | the briefings' speakers |

## The rules

The 7800 draws a picture in rows of 16 lines, each row as a few objects,
and each object has one palette of 3 colors plus the background. So:

1. **Size:** 160 x 96 (portraits 32 x 48). Pixels are 2:1, twice as wide
   as tall: view at 2x across, or draw at 320 x 96 with every pixel
   doubled across (the tool halves a 320-wide picture).
2. **Colors:** the 7800's own, `atari7800.gpl` (load it in GIMP or
   Aseprite; `atari7800_palette.png` shows each with its byte). Anything
   else is snapped to the nearest.
3. **One background color** for the whole picture (the color most used,
   unless you say otherwise). It is free in every cell.
4. **Cells:** the picture is a grid of 8 x 16 cells, 20 across and 6
   down (`grid_guide_panel_4x.png`, a guide to lay over the 4x preview).
   **In each cell, at most 3 colors besides the background.**
5. **Palettes:** at most **6 groups of 3 colors** across the whole
   picture (portraits: 2). Every cell's colors must all be in one group.
   So in all: up to 18 colors plus the background, but a cell picks its
   3 from one group.

Thinking of it like the NES helps: choose the 6 color groups first (a
sky group, a metal group, a skin group...), then paint each cell from
one group.

## Checking a picture

    .venv/bin/python tools/cutscene7800.py check storyboard/panels/act3.png --out /tmp/act3.png
    .venv/bin/python tools/cutscene7800.py check storyboard/panels/maya.png --portrait

It lists the background, the 6 groups it found, and every cell it had to
change (too many colors, or colors in no one group), and writes a
preview of the picture as the 7800 will show it. A picture that keeps the
rules comes through unchanged.
