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
 (HUD)      3 empty lines, zone 0 (the HUD: 7 lines), 6 empty lines
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
drawing), then the usual one, and `pf_frame` scrolls two steps' worth (a
frame that took three gets two catch-up steps). `pf_drawscreen` counts the
frames a frame took after its wait for vblank, by the overscan NMIs
(`pfvbl`, counted in `userinterrupt`), which come just before each vblank.
It used to count top-of-screen NMIs before the wait; those come some 25
lines after vblank begins, and a frame that ended between the two waited a
whole extra frame without its catch-up step, so the game did slow down
when the load was high. So the game never slows down; the display drops to 30 frames a second while
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

## Stages

Each stage has a 16K ROM bank of its own, switched in at $8000 for the
whole stage (`pf_stage`; `pf_newstage` mid-game blanks the screen for a
frame while the old display lists still point into the old bank). The
bank starts with a header of the same layout in every stage
(`tools/gen_assets.py` `stg_layout`, BASIC `dim`s `stg_*`, `watl`...,
`gtl`...): row count, boss-loop rows, character block, the first
non-background character, wave and ground-unit counts, background color,
palettes 0-2, songs, the map's used columns; then fixed-size tables:
waves, ground units, each character's palette, and each map row's
pointers. The engine and the BASIC read whichever stage is in through the
same addresses, so stage code has no stage numbers in it. Code for one
stage only (its boss) goes in its bank too, called from the shared code
by `if stage = n`: the fixed bank has room only for what every stage uses.
From stage 5 on, a stage's own code is reached through vectors in its
header (`stg_vec`, after the row tables): its boss's build, enter, fight,
place, attack and sinking routines, its main loop hook, and a spare
(stage 9's: the ending's texts). The shared code jumps through them
(`jmp (STGV_FIGHT)`...), so a new stage costs the fixed bank nothing.
Texts shown only with one bank in can live there too (stage 9's ending:
`gen/texts9.asm`; only their entries in the text tables are in the fixed
bank).

A map row stores its ready-made background objects (one per run of drawn
tiles sharing a palette; background tiles, like open sea, aren't drawn)
and those runs' characters, packed together; rows that are the same are
stored once. Zone 14 builds its one-object-a-tile list from the same
objects (`pf_zone14`). Each row also has a shift
byte (`stg_rowshift`): a whole-row shift in tiles, and a gap opened at x 80
that moves everything right of it on (`pf_rowshift`, applied as a row is
copied into its zone and to zone 14's tiles). Stage 2's city winds and
splits with these, while storing each district once.

Every character block starts with the font, so text keeps its character
numbers in every stage. Stage 1's block is in the last bank; stage 2's
bank holds its own graphics block at $A000 (its tiles, its enemies and
its boss): the data goes first, at $8000, so the block lands at $A000,
where sprites' lower parts read DMA holes, and the song after it in the
hole at $B000.

| Bank | |
|---|---|
| 1 ($4000, fixed) | the game, the engine, the shared boss code and results |
| 2 | stage 1: header, map, songs, the GAMMA CORE's code (`src/boss1.bas`), the title song (the title shows with stage 1's bank in) |
| 3 | stage 2: header, map, boss tune copy, SPIRE WARDEN's code (`src/boss2.bas`), graphics ($A000), song ($B000) |
| 4 | stage 3: header, map, boss tune, LEVIATHAN's code (`src/boss3.bas`), graphics ($A000), song and LEVIATHAN's tables ($B000) |
| 5 | stage 4: header, map, boss tune, DUNE WYRM's path, graphics ($A000), song and DUNE WYRM's code (`src/boss4.bas`, $B000) |
| 6 | stage 5: header, map, the stage song's voices 0 and 2, boss tune (less its voice 1), graphics ($A000), the stage song's voice 1, the boss tune's voice 1, GLACIER CRAWLER's code and tables ($B000) |
| 7 | stage 6: header, map, HALO STATION's tables and the fade, the fade's code (`src/stage6.bas`), HALO STATION's code (`src/boss6.bas`), the stage song's voices 1 and 2, graphics ($A000), the boss tune and the stage song's voice 0 ($B000) |
| 8 | stage 7: header, map, MASS DRIVER's tables, graphics ($A000), the stage song and the boss tune's voice 0; the rest of the boss tune and MASS DRIVER's code (`src/boss7.bas`, $B000) |
| 9 | stage 8: header, map (each row's solid columns after its objects), HIVE MOTHERSHIP's tables, the asteroids' code (`src/stage8.bas`), graphics ($A000), the stage song; the boss tune and HIVE MOTHERSHIP's code (`src/boss8.bas`, $B000) |
| 10 | stage 9: header, map, the flares' tables, the ending's texts, the flares' code (`src/stage9.bas`), graphics ($A000), the boss tune (MegaGammaForce's Final) and the stage song's voice 0; the rest of the stage song and GAMMA PRIME's code (`src/boss9.bas`, $B000) |
| 11-16 | the cutscenes (`tools/gen_cutscenes.py`): 11 the prologue, 12 the five briefings and the high score table (with hiscore.asm in its DMA hole), 13-15 the act breaks, 16 the epilogue. Each: the 40-column font ($8000), the entry ($8800), its song, its player, script and display lists; its pictures ($A000) |
| 17 ($C000, fixed) | graphics: stage 1's tiles and the font, the logo and LEVIATHAN's bays (in the character block's spare room), the shared sprites |

## Cutscenes

A cutscene takes the screen over between stages: in vblank it points
MARIA's DPPH/DPPL at its own display list list, in its bank's ROM, and
puts 7800basic's DLLMEM back as it ends (DMA off: the caller rebuilds the
screen, as a new stage does). The list keeps 7800basic's frame: its 9-line
top border, 224 visible lines, its non-visible entries with their NMIs.
7800basic counts three NMIs a frame; the cutscene's list puts the first
(the top-of-screen one) under the hazard stripe, and 7800basic calls
`topscreenroutine` there, which jumps through `cutvec` to the cutscene's
handler: from the next line, 320A (CTRL $43: 1-byte characters), CHARBASE
at its font, a black background, palette 7 white. The end-of-screen NMI
(`bottomscreenroutine`, `cutvec2`) puts the game's mode and font back for
the next frame's top; the picture's background comes back off the screen
(`bgwant`). The picture is 160A, six zones of direct objects, a run of
cells sharing a palette each (tools/cutscene7800.py); the text, 36 columns
in RAM ($1900, the engine's idle ring buffers), two 18-character indirect
objects a row in 8-line zones, its font one byte a glyph line (8 pages,
glyph line 7 - p in page p). A briefing's portrait zones' lists are in RAM
($1C00): its portrait, and its header lines in the game's font. The fixed
bank holds only the hooks, `cutscene` (a bank switch and `jsr $8800`) and
the song table's entries: the three act breaks hold the same song at the
same address, so one entry serves them.

The high score table is bank 12's too (its entry at $8803): 7800basic's
hiscore.asm, inlined in that bank's DMA hole without its high score font,
leaves out its own display and keeps the device code (High Score Cart,
AtariVox/SaveKey: `loaddifficultytable`, `savedifficultytable`, a table
of five a difficulty in `HSRAMInitials`/`HSRAMScores`), and the bank's
player draws the table on a briefing's screen. A score is stored as the
six BCD digits after its first (its last, always 0, left off).

## Wrecks under the ship

A later object in a zone's DL is drawn over an earlier one. The ship is
plotted early in the frame (before MARIA reaches it), so every enemy went
over it, the bosses' wrecks too, and the ship vanished under a big one.
The boss now moves before the ship is plotted, and its wrecks are drawn
first, in a pass of their own (`en_draw_wrecks`; `en_draw` leaves them
out): everything else shows over them.

## Text in the playfield

Screen text (the title, GAME OVER, the results) is a character object
in a playfield zone's DL (`pf_text`), drawn after the zone's sprites so it
shows on top of them. The frame is built in the DLs while MARIA shows
them, so every store must leave a valid list, and `pf_object` saves time
by rewriting last frame's 4-byte sprite objects in place. If the 5-byte
text header moved whenever a sprite entered or left its zone, those
rewrites would land on half of it: a line of garbage. So the text keeps
its place: with fewer sprites in the zone than last frame, the slots
before it are hidden (x = 160) rather than the text moving up; with more,
the sprites from its old place on are appended anew (`pf_frame` stops
`zoneold` at the old text: `txtold`, per buffer), each with the list ended
at its slot first, and the text goes on after them. A text that is
already there, the same, is left alone; a new one is written with the
list ended at its slot until its header is whole. Blinking text isn't
left out when it blinks off but moved off the screen (`tpal` + 128),
so the zone's list keeps its shape.

## A boss that is part of the map

Stage 3's battleship, LEVIATHAN, is longer than the screen. Its hull is
map rows (after the stage's last open sea), so it costs no sprites, and
the boss moves it by the scroll: the open sea is the background color, so
a change of scroll speed shows nowhere but on the ship. It comes in at the
stage's speed, crawls while any of its parts is on the screen above the
player to fight (and comes on faster while none is), stops once the
reactor is in reach (waves of escorts defend it as it is hurt), and the scroll runs on to carry it away as it sinks. Its guns,
bridge, reactor, missile bays and turrets are sprites pinned to map rows
like ground units (a shut bay is drawn the same as its hull tiles, so it
shows only as it flashes, opens, or lies wrecked): each part's line is `spos + 240 -` the world height of its top
(16 bits; off the screen it is parked off to the right).

Stage 5's GLACIER CRAWLER works the same way, LEVIATHAN's fight in
short: it stops with its front half in view over bare ice (the background
color, so nothing shows the stop); once its command bridge falls it drives
on, its front off the bottom of the screen, while slabs of shelf ice fall,
and stops with the cryo reactor at its rear in reach. Its treads are drawn
in bands of palette 2's first two colors, which the boss code swaps every
4 frames, so they run (palette 2 is the water's, and there is no water in
the arena). The falling slabs are towers that slip down the map
(`en_update`: `ewamp` their speed), spawned by the waves (and the boss)
like any enemy: they shove the ship like any tower, and crush it against
the bottom of the screen.

Stage 6's HALO STATION too: its ring (an octagon a tile thick, every
diagonal step the same two tiles, `tiles7800.station6`) is map rows over
the stars, and the scroll stops with it near the top of the screen. Its
turrets and core are pinned to map rows; its four gun satellites orbit
the hub (`b6_ox`/`b6_oy`, a step a frame and one more for each one gone),
and the core is shut while any of them orbits.

Stage 7's MASS DRIVER is map rows too, and it sways from side to side:
the engine adds `pfsway` (pixels, signed) to the x of every row from
`pfswayrow` on as it builds them (`pf_rowshift`), and the boss moves the
sway a pixel at a time, patching the rows already built: each ring
buffer's background objects and zone 14's tiles (`b7_sway`; `ringrow`
says which map row each ring buffer holds). Rows from `pfswayend` on
don't sway (stage 7 sets it to $FF; stage 8's HIVE MOTHERSHIP to the row
past its hull, so the stars above it stay still). The rail's coils are drawn
in palette 2's three colors, turned round every 4 frames (palette 2 is
the bases', and there are none near the boss). `pf_stage` turns the sway
off (`pfswayrow` $FF).

Stage 8's HIVE MOTHERSHIP is map rows and sways the same way (its own
copy of the patch, `b8_sway`, which stops at `pfswayend`).

Stage 9's GAMMA PRIME is sprites, built on SPIRE WARDEN (a hull's tiles
were most of a fight's MARIA load): a sunburst core in two halves, a
cannon, two turrets, three orbiting prisms, and two nodes atop it of a
type (`ET_PNODE`) that Vulcan shots stop on without harm
(`objects.asm en_hits_take`), so only the Hyper Sword's beam breaks one.
Shut, the core keeps its health (`boss9.bas` restores `bcorehp` each
step); a node broken opens it, half its health shuts it again (the prisms
grow back), the other node opens it for good. The shared boss code counts
slots 0-11.

## Solid tiles

Stage 8's asteroids are map tiles that stop the player's shots and the
enemies' bullets, and the ship crashes on them (MegaGammaForce's solid
sky). A tile is solid if it is mostly rock. Each stored row has its solid
columns right after its background objects: 3 bytes, a bit a column
(`gen_assets.stage_bank`, for a stage with `solid` tiles), so the row
pointers the engine already has find them. A point at playfield y + 32
(`py`) is in map row (spos + 239 - py) / 16; `src/stage8.bas` tests each
shot's tip, half the bullets each step, and the ship's middle and nose.
The asteroid drifts are a few chunks of 18 rows, each used more than
once: stage 8's bank has room for few different rows.

## Flares

Stage 9's solar flares are map tiles in two groups that share their
characters: a map number from the tile count on is an alias, a tile's
characters in another palette (`stage_bank`'s `alias`), so group A is
drawn in palette 0 and group B in palette 1. `src/stage9.bas` writes the
two palettes each step from a 512-frame clock (dark, a flicker of
warning, the eruption, a fade; B half a cycle behind A, so they take
turns). An erupting flare kills the ship: the test finds the tile under
the ship's middle, and 3 pixels either side, among its map row's
background objects (their x, width and palette say which run it is in;
the run's characters, which tile), and the tiles that kill are numbered
together, so a range of characters says (no masks: the bank had no room).
The map's last 16 rows, which loop through GAMMA PRIME's fight, are a
chunk of flares of their own, so they keep coming. Like the asteroids,
the stage's flares are a few chunks of rows used in turn.

Stage 6 also fades: as the ship climbs, the ocean (the background color)
and its clouds (palette 1) darken to black by the scroll position
(`src/stage6.bas`, tables from `gen_assets.stage6`). The colors are
written in the overscan NMI (`fadeon`, `fadebg`, `fadep1`), off the
screen, so no line shows two. And every bank switch (`pf_stage`) stops
the music first: a song plays from its own stage's bank, and with another
bank in, its bytes can keep the NMI past vblank, where the main loop,
waiting for vblank, would wait for ever.

## A boss that follows its own path

Stage 4's sandworm, DUNE WYRM, is eleven sprites: a tail, eight body
segments and the head (two slots, top and bottom). MegaGammaForce keeps a
trail of the head's past positions for the body to follow; here the path
is a closed curve worked out from a clock (x by `t`, the line by `t / 2`
from two 256-entry tables: a figure of eight), so each part is simply the
path at `t` less its lag. No trail is kept, and a part costs two table
reads. It rises into view by an offset that counts down, and sinks by one
that counts up as it dies (`src/boss4.bas`, tables in
`src/gen/boss4tab.asm`).

The body follows a trail of the head's positions (64 entries, one every 2
frames, at `$2740`/`$2780`), each part its lag back (`b4lagt`), the frames
between taking the middle of two entries. On the path the trail just
records the path; as 3, then 6, of its tail and segments fall the head
leaves it for a 4-second chase (it steers for the ship, a little slower
than the ship flies, holding its heading when close so it lunges past
rather than coiling round it), then flies straight back to where its path
has got to. The body follows the trail through all of it, so nothing
jumps. The head can't be hurt until the tail and every segment are down.

## Memory

| Where | What |
|---|---|
| `$1800-$184A` | DLL: 3 blank entries, the HUD's 3, 14 playfield entries, 5 non-visible |
| `$1880-$18FF` | Zone 0 (HUD) DL, managed by 7800basic (`DLMEMEND = $18FF`) |
| `$1900-$1EE7` | 14 ring buffers of 108 bytes |
| `$1EE8-$1FFF` | Zone 14's two DLs, 140 bytes each |
| `$2200-$223F` | Engine variables (`zonelo` etc.) |
| `$2240-$2253` | `hudtext`: the HUD's 20 characters, shown live |
| `$1885-$18AC` | The HUD's ten sprites (gems, gauge, lives), after its text in zone 0's DL (`objects.asm hud_sprites`) |
| `$2560-$257F` | `txtold`, `txtnow`: where each buffer's and zone's text is (`pf_text`) |
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

The HUD: 7800basic's 16-line zone 0 is split (`pf_init`) into 3 empty
lines, a 7-line zone 0 and 6 empty lines, and the font's glyphs (and the
HUD's sprites) sit on the last 7 lines of their 16, which a 7-line zone
shows: MARIA reads the HUD's 20 characters and 10 sprites 7 lines a frame,
not 16. (Text in the playfield sits on the same lines of its zone.)

`tools/bench.sh` is the speed benchmark: an invulnerable ship that holds
fire and never moves, so every build plays the same game (input pressed by
emulator frame would land on different game steps in builds of different
speed) and the figures compare. With MARIA's DMA switched off the game
holds 60 frames a second: what the CPU loses to DMA (the background most of
all, then the sprites, then the HUD) is what makes frames late.

CPU side: each sprite object costs ~100 cycles of 6502 work (a 16-line
strip that crosses a zone boundary is two objects), so the hot loops are
assembly (objects.asm: enemy AI, movement, bullets, hits, the ship), the
game keeps 16 enemy bullets and 4 explosions at most, and late frames are
caught up rather than slowing the game (above). `tools/fps_test.sh`
measures stage 1 with an invulnerable ship (`tests/boss_fps.txt`, run the
same way with a BOSSTEST build, measures the boss); `tools/fps.py` reports
the game speed and the frames drawn. Stage 1 (its fortress now runs most of
the way to the boss): game speed 59/s, display
about 48 fps; its boss 59/s, about 42 fps (its parts are ~36 objects).
Stage 2 (the city covers the whole stage): 58/s, about 48 fps; its boss
fights over a mostly dark plaza (a city block under it cost most of the
frame rate): 58/s, about 34 fps.

Tools: `const PROFILE = 1` times each part of the main loop (wall time,
so MARIA and the NMIs count; `tools/profile.py`), and the `a7800dev`
machine draws each line's DMA use at the left edge.
