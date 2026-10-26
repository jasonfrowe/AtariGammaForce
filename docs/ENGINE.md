# The display engine

`src/asm/engine.asm` gives a 7800basic game a smoothly scrolling vertical
playfield. 7800basic still runs the game, the interrupts, the HUD zone and
the sound; the engine takes over the playfield's display lists.

## Why 7800basic needs help

MARIA draws the screen as a stack of *zones*, each 16 lines tall here, and
each zone has a display list (DL) of objects: sprites and runs of
characters. The display list list (DLL) says which DL each zone uses and
how tall the zone is. 7800basic builds a fixed DLL: 12-14 zones of 16
lines, each with its own DL in RAM. Moving a sprite down a line is easy,
but moving the whole background means every character object in every
zone moving with it, a line at a time, across zone boundaries.

## Screen layout

```
 zone 0      HUD                         16 lines, fixed (7800basic's zone)
 zone 1      playfield, top partial      16-s lines   ring buffer
 zones 2-13  playfield                   16 lines     ring buffers
 zone 14     playfield, bottom partial   1+s lines    its own pair of DLs
```

`s` is the fine scroll, 0-15. The playfield is always 16-s + 192 + 1+s =
209 lines. One line is taken off the top border so the frame keeps the
length 7800basic expects.

**Fine scrolling** is just zone heights: as the map moves down a line,
zone 1 grows by a line at its top and zone 14 shrinks by one. MARIA always
draws a zone's lines from its height down to 0, which for zone 1 shows the
*bottom* of its map row, as wanted. Zone 14 needs the *top* of its row, so
everything in it points its graphics 15-s pages higher. Character objects
can't do that (they all read from CHARBASE), so zone 14 draws its row as
one direct-mode object per tile, each with its own graphics address, and
the sprite plotter adds 15-s to the high byte of sprites it puts there.

**Coarse scrolling** (every 16 pixels) moves the rows down one zone.
Zones 1-13 use 13 of 14 *ring buffers*; each holds one map row's
background objects at the start, then that frame's sprites. The 14th, the
*spare*, is filled with the next map row a frame after it frees up. When
the scroll crosses a 16-pixel boundary, zone 1 takes the spare, every other
zone takes the buffer above it, zone 13's buffer becomes the spare, and
zone 14 rebuilds its tiles for the row that just left zone 13. Only
pointers change for zones 1-13, and the background is never rewritten
while MARIA might be showing it.

Zone 14 alternates between two DLs, one shown while the other is built,
so its per-frame tile pointers and sprites never race the display.

Open sea is the background color: runs of sea tiles get no objects at
all (sea tiles are blank in the character set and have a palette of their
own, so they never join a deck run). That keeps MARIA's DMA, which halts
the CPU, low wherever the map is water.

## Frame order

```
pf_frame        fill the spare if needed, advance the scroll, rotate on a
                16-pixel boundary, ready zone 14, empty last frame's sprites
...game logic, pf_drawimg / pf_plot for every sprite...
pf_drawscreen   (instead of drawscreen) wait for MARIA's vblank, terminate
                the DLs, write the zone layout into the DLL
```

**Game speed vs. frame rate.** The game runs in steps of 1/60 second.
When a frame's logic runs past its frame, that frame shows for two and
`pflate` is set; the next frame then runs two steps: a catch-up step with
`pfnodraw` set (`pf_plot` draws nothing, and the game skips its other
drawing), then the usual one, and `pf_frame` scrolls two steps' worth. So
the game never slows down; the display drops to 30 frames a second while
the load is high and comes back to 60 when it eases. `const FPS30 = 1`
locks it at 30 (two steps every frame). Anything that should alternate as
*shown* (the HUD's four parts, the boss's hit flash) counts `pfdraws`, the
frames drawn, rather than `tick`, the game steps, since at 30 frames a
second only every other step is drawn.

The engine keeps a *shadow* layout (`zonelo`/`zonehi`: which DL each zone
uses) that changes at the start of the frame, and writes it into the real
DLL only in vblank. Sprites are plotted against the shadow, so on a coarse
step they land in the buffers the next frame will show.

`pf_drawscreen` syncs to MARIA's vblank flag (`MSTAT`), not to 7800basic's
`visibleover`, and resets 7800basic's NMI count (`interruptindex = 3`,
`visibleover = 0`) every vblank. 7800basic tells its three NMIs apart by
counting them; if the count ever slips, `visibleover` is only set for a few
lines that its long top-of-screen handler covers, and a wait on it never
ends. Resetting the count heals a slip within a frame. When the game logic
runs past the end of a frame, `pf_drawscreen` waits for the next vblank, so
that frame takes two (the game slows down rather than tearing).

## Sprites

`pf_drawimg` draws image `pimg`, frame `pframe`, at `px`, `py` with palette
`ppal`. `py` is the playfield line plus 32, so a sprite can sit partly
above the top. Images are 16-line strips (two strips for tall ones); the
tables come from `tools/gen_assets.py`, including how many lines of its
last strip each image uses, so a short sprite (a bullet) skips the zone
below when it ends above it. Strips that overlap the HUD or fall below the
playfield are clipped. A ring buffer holds about 19 sprite objects besides
its background; zone 14 about 14. Past that, objects are dropped.

MARIA rereads a zone's DL on every line, and the frame is built while the
last one is showing, so `pf_object` keeps every DL valid after each single
store. A new object past last frame's end gets a terminator after it first
and its palette|width byte (which makes it exist) last. An object over one
of last frame's: if it is the same image (low byte and width), as for
anything that stays put or moves a little, palette, high byte and x are
rewritten one byte at a time, and a line drawn in between is at worst a
line or a pixel off. A different image is hidden first (x = 160) and shown
last, which drops it from a line drawn in between: on a big sprite that
shows as a one-line gap. So the draw order is kept stable: a full 16-line
strip always takes two objects, even lined up with a zone (the lower one
then reads only DMA holes and costs just its header), and the boss's parts
all count as full strips. That way the objects after it keep their slots
from frame to frame.

## Memory

| Where | What |
|---|---|
| `$1800-$1844` | DLL: 3 blank entries, HUD, 14 playfield entries, 5 non-visible |
| `$1880-$18FF` | Zone 0 (HUD) DL, managed by 7800basic (`DLMEMEND = $18FF`) |
| `$1900-$1EE7` | 14 ring buffers of 108 bytes |
| `$1EE8-$1FFF` | Zone 14's two DLs, 140 bytes each |
| `$2200-$223F` | Engine variables (`zonelo` etc.) |
| `$2240-$2253` | `hudtext`: the HUD's 20 characters, shown live |
| `$2260-$2278` | Music player |
| `$A5-$BA`, `$C4` | Engine and music zero page (7800basic's tracker block; we don't use `playsong`) |
| `$BB-$C3` | Object routines' zero page scratch |
| `$2300-` | Game variables (BASIC `dim`s) |

## 7800basic settings and gotchas

The engine needs these in the game source:

```
set zoneheight 16
set screenheight 224
set doublewide on
const ZONECOUNT = 1      7800basic manages only zone 0...
const DLMEMEND = $18FF   ...in $1880-$18FF
```

7800basic itself is stock (v0.41, vendored in `tools/7800basic`).

Things that bit us:

- `for i = 0 to N - 1` compiles as `for i = 0 to N`: 7800basic drops
  arithmetic in a loop limit. Use a constant (`const NE1 = 7`).
- An `inline` file's path becomes a symbol name, so it can't contain a
  `/`; `tools/build.sh` copies the assembly files flat into the build.
- dasm allows 32 operators on a line (long `.byte <a,<b,...` tables have to
  be split) and groups with `[ ]`, not `( )`, before `,x`.

## Testing

`tools/test_scroll.sh` builds an invulnerable test ROM, starts a game in
the a7800 emulator headless, takes
screenshots across every fine scroll value, several coarse steps and the
boss loop, and `tools/check_scroll.py` compares every playfield line with
the map. It should report 0 bad lines.

## Performance

MARIA's DMA halts the CPU: a full row of background characters costs
about 9 DMA cycles per 8 pixels (of ~430 per line), and every sprite object
costs at least 11 cycles on each line of its zone, drawn or not. With no
background at all the game holds 60 fps under full load, so the map is
kept light: open sea is the background color (no objects), and the
fortress is MegaGammaForce's own 12-column map in the middle of the sea.

CPU side: each sprite object costs ~100 cycles of 6502 work (a 16-line
strip that crosses a zone boundary is two objects), so the hot loops are
assembly (objects.asm: enemy AI, movement, bullets, hits, the ship), the
game keeps 16 enemy bullets and 4 explosions at most, and late frames are
caught up rather than slowing the game (above). `tools/fps_test.sh`
measures stage 1 with an invulnerable ship (`tests/boss_fps.txt`, run the
same way with a BOSSTEST build, measures the boss); `tools/fps.py` reports
the game speed and the frames drawn. Stage 1: game speed 59/s, display
about 56 fps. The boss: 59/s, display about 40 fps (its parts are ~36
objects).

Tools: `const PROFILE = 1` times each part of the main loop (wall time,
so MARIA and the NMIs count; `tools/profile.py`), and the `a7800dev`
machine draws each line's DMA use at the left edge.
