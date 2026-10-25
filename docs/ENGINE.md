# The display engine

`src/asm/engine.asm` gives a 7800basic game a smoothly scrolling vertical
playfield. 7800basic still runs the game, the interrupts, the HUD zone and
the sound; the engine takes over the playfield's display lists.

## Why 7800basic needs help

MARIA draws the screen as a stack of *zones*, each 16 lines tall here, and
each zone has a display list (DL) of objects: sprites and runs of
characters. The display list list (DLL) says which DL each zone uses and
how tall the zone is. 7800basic builds a fixed DLL: 12-14 zones of 16
lines, each with its own DL in RAM. Moving something down one line is easy
for a sprite, but moving the whole background means every character object
in every zone moving with it, a line at a time, across zone boundaries.

## Screen layout

```
 zone 0      HUD                         16 lines, fixed
 zone 1      playfield, top partial      16-s lines
 zones 2-13  playfield                   16 lines each
 zone 14     playfield, bottom partial   1+s lines
```

`s` is the fine scroll, 0-15. The playfield is always 16-s + 192 + 1+s =
209 lines. One line is taken off the top border so the frame keeps the
length 7800basic expects.

Fine scrolling is just zone heights: as the map moves down a line, zone 1
grows by one line at its top and zone 14 shrinks by one. MARIA always
draws a zone's lines from its height down to 0, which for zone 1 shows the
*bottom* of its map row, exactly what is wanted. Zone 14 needs the *top* of
its row, so its graphics are read 15-s pages higher:

- the background: an interrupt (DLI) on zone 14's DLL entry moves
  CHARBASE up by 15-s pages just before the zone starts. The DLI fires as
  MARIA reaches the entry, so the flag goes on zone 14 itself.
- sprites: `pf_object` adds 15-s to the high byte of every sprite object it
  puts in zone 14.

Coarse scrolling (every 16 pixels) moves the zones down one DL. The 14
playfield zones use 14 of 15 *ring buffers*; each buffer holds one map row
(its background objects at the start, then that frame's sprites). The 15th,
the *spare*, is filled with the next map row a frame after it frees up.
When the scroll crosses a 16-pixel boundary, zone 1 takes the spare, every
other zone takes the buffer above it, and the buffer leaving the bottom
becomes the spare. Only pointers change, so a coarse step costs about the
same as a fine one, and the background is never rewritten while MARIA
might be showing it.

## Frame order

```
pf_frame        fill the spare if needed, advance the scroll, rotate on a
                16-pixel boundary, empty last frame's sprites
...game logic, pf_drawimg / pf_plot for every sprite...
pf_drawscreen   (instead of drawscreen) wait for the visible screen to end,
                terminate the DLs, write the zone layout into the DLL
```

The engine keeps a *shadow* layout (`zonelo`/`zonehi`: which buffer each
zone uses) that changes at the start of the frame, and writes it into the
real DLL only in vblank. Sprites are plotted against the shadow, so on a
coarse step they land in the buffers the next frame will show.

## Sprites

`pf_drawimg` draws image `pimg`, frame `pframe`, at `px`, `py` with palette
`ppal`. `py` is the playfield line plus 32, so a sprite can sit partly
above the top. Images are 16-line strips (two strips for tall ones); the
tables come from `tools/gen_assets.py`. Strips that overlap the HUD or fall
below the playfield are clipped. Each ring buffer holds about 20 sprite
objects besides its background; past that, objects are dropped.

## Memory

| Where | What |
|---|---|
| `$1800-$1844` | DLL: 3 blank entries, HUD, 14 playfield entries, 5 non-visible |
| `$1880-$18FF` | Zone 0 (HUD) DL, managed by 7800basic (`DLMEMEND = $18FF`) |
| `$1900-$1F8F` | 15 ring buffers of 112 bytes |
| `$2200-$22FF` | Engine variables (`zonelo` etc., `hudtext` at `$2240`) |
| `$A5-$B4` | Engine zero page (7800basic's tracker block; we don't use `playsong`) |
| `$2300-` | Game variables (BASIC `dim`s) |

## Changes to 7800basic

7800basic is vendored in `tools/7800basic` (v0.41). Only
`includes/std_routines.asm` is changed, and only inside `ifconst PFDLI`
blocks: the NMI handler checks `pfdliflag` first and, when it is set,
handles the zone 14 DLI (one store to CHARBASE) without touching
7800basic's own interrupt counting. NMI 1 (top of the screen) sets the
flag. Games that don't define `PFDLI` get stock 7800basic.

The engine also relies on these 7800basic settings in the game source:

```
set zoneheight 16
set screenheight 224
set doublewide on
const ZONECOUNT = 1      7800basic manages only zone 0
const DLMEMEND = $18FF   ...in $1880-$18FF
const PFDLI = 1
```

## Testing

`tools/test_scroll.sh` runs the ROM headless in the a7800 emulator, takes
screenshots across every fine scroll value, several coarse steps and the
boss loop, and `tools/check_scroll.py` compares every playfield line with
the map. It should report 0 bad lines.

## Known limits

- Single-buffered, like stock 7800basic: sprites are plotted while MARIA
  shows the previous frame, so a zone not yet drawn can briefly show a
  mix. Plotting in a consistent order keeps this invisible. Double
  buffering in cart RAM is the fix if it ever shows.
- Map rows are indexed with a byte, so a stage map is at most 255 rows
  (4,080 pixels). Stage 1 is 208.
- NTSC timing only so far; PAL needs the top border adjusted.
