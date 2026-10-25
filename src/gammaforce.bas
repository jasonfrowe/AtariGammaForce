  rem ======================================================================
  rem  ATARI GAMMA FORCE
  rem  A demake of MegaGammaForce (RP6502) for the Atari 7800.
  rem  7800basic for the game, assembly (asm/engine.asm) for the display.
  rem ======================================================================

  set romsize 48k
  set zoneheight 16
  set screenheight 224
  displaymode 160A
  set doublewide on
  set 7800header 'name Atari Gamma Force'
  set pokeysupport $450

  rem The scroll engine owns the playfield zones; 7800basic only manages
  rem zone 0 (the HUD), which gets $1880-$18FF. See docs/ENGINE.md.
  const ZONECOUNT = 1
  const DLMEMEND = $18FF
  const PFDLI = 1

  incbasic gen/consts.bas

  rem ---- engine arguments (asm/engine.asm reads these) ----
  dim pimg = $2300
  dim pframe = $2301
  dim px = $2302
  dim py = $2303
  dim ppal = $2304

  rem ---- game state ----
  dim shipx = $2310
  dim shipy = $2311
  dim tick = $2312
  dim firecd = $2313
  dim shotx = $2320
  dim shoty = $2328
  dim enx = $2330
  dim eny = $2338
  dim enimg = $2340
  dim enpal = $2348

  const SHOTS = 6
  const ENEMIES = 4

  incbasic gen/gfx.bas

  characterset charset
  asm
  jsr pf_init
  lda #SONG_STAGE1
  jsr mus_play
end

  shipx = 74 : shipy = 200
  for i = 0 to SHOTS - 1 : shoty[i] = 0 : next
  enx[0] = 30 : eny[0] = 40 : enimg[0] = IMG_DART : enpal[0] = 4
  enx[1] = 70 : eny[1] = 80 : enimg[1] = IMG_SAUCER : enpal[1] = 5
  enx[2] = 110 : eny[2] = 120 : enimg[2] = IMG_DRONE : enpal[2] = 6
  enx[3] = 140 : eny[3] = 60 : enimg[3] = IMG_DART : enpal[3] = 4

main
  asm
  jsr pf_frame
end
  tick = tick + 1

  rem ---- ship ----
  if joy0left && shipx > 2 then shipx = shipx - 1
  if joy0right && shipx < 145 then shipx = shipx + 1
  if joy0up && shipy > 40 then shipy = shipy - 2
  if joy0down && shipy < 216 then shipy = shipy + 2

  rem ---- Vulcan ----
  if firecd > 0 then firecd = firecd - 1
  if joy0fire0 && firecd = 0 then gosub fire_vulcan
  for i = 0 to SHOTS - 1
    if shoty[i] > 0 then shoty[i] = shoty[i] - 6 : if shoty[i] < 20 then shoty[i] = 0
  next

  rem ---- test enemies drift down and wrap ----
  for i = 0 to ENEMIES - 1
    eny[i] = eny[i] + 1
    if eny[i] > 250 then eny[i] = 8
  next

  rem ---- draw: enemies, shots, then the ship on top ----
  for i = 0 to ENEMIES - 1
    pimg = enimg[i] : pframe = (tick / 8) & 1 : px = enx[i] : py = eny[i] : ppal = enpal[i]
    asm
    jsr pf_drawimg
end
  next
  pimg = IMG_VULCAN : pframe = 0 : ppal = 3
  for i = 0 to SHOTS - 1
    if shoty[i] = 0 then goto skipshot
    px = shotx[i] : py = shoty[i]
    asm
    jsr pf_drawimg
end
skipshot
  next
  pimg = IMG_SHIP : pframe = 0 : px = shipx : py = shipy : ppal = 3
  if joy0left then pframe = 1
  if joy0right then pframe = 2
  asm
  jsr pf_drawimg
end

  asm
  jsr pf_drawscreen
end
  goto main

fire_vulcan
  for i = 0 to SHOTS - 1
    if shoty[i] = 0 then shotx[i] = shipx + 4 : shoty[i] = shipy - 8 : firecd = 4 : return
  next
  return

  rem Runs every frame from 7800basic's NMI, off screen.
userinterrupt
  asm
  jmp mus_tick
end

  rem Assembly files are copied flat into the build directory (tools/build.sh).
  inline engine.asm
  inline data.asm
  inline music.asm
  inline musicdata.asm
