  rem ======================================================================
  rem  ATARI GAMMA FORCE
  rem  A demake of MegaGammaForce (RP6502) for the Atari 7800.
  rem  7800basic for the game; assembly for the display (asm/engine.asm),
  rem  the object loops (asm/objects.asm) and the music (asm/music.asm).
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

  incbasic gen/consts.bas

  rem ---- sizes ----
  const NE = 8
  const NB = 16
  const NS = 6
  const NX = 6
  const NSP = 3
  rem 7800basic drops arithmetic in a for loop's limit ("to NE1" runs to
  rem NE), so loops use these.
  const NE1 = 7
  const NB1 = 15
  const NS1 = 5
  const NX1 = 5
  const NSP1 = 2

  rem Uncomment to time the main loop's sections (tools/profile.py).
  rem const PROFILE = 1

  rem ---- enemy types (as in MegaGammaForce's enemies.h) ----
  const ET_DART = 1
  const ET_SAUCER = 2
  const ET_DRONE = 3
  const ET_GUNSHIP = 4

  rem ---- bullet kinds: odd = pink (the sword absorbs them) ----
  const BK_PINK = 1
  const BK_BLUE = 2
  const BK_NEEDLE = 5

  const GAUGE_MAX = 48

  rem ---- engine arguments (asm/engine.asm) ----
  dim pimg = $2300
  dim pframe = $2301
  dim px = $2302
  dim py = $2303
  dim ppal = $2304

  rem ---- engine state BASIC reads or writes ----
  dim spos_lo = $2231
  dim spos_hi = $2232
  dim hudtext = $2240

  rem ---- object arguments and results (asm/objects.asm) ----
  dim fx = $2305
  dim fy = $2306
  dim fang = $2307
  dim fspd = $2308
  dim fkind = $2309
  dim fcount = $230A
  dim fstep = $230B
  dim aimang = $230C
  dim velx = $230D
  dim vely = $230E
  dim wang = $230F
  dim wamp = $2310
  dim woff = $2311
  dim tick = $2312
  dim pcx = $2313
  dim pcy = $2314
  dim plvuln = $2315
  dim phit = $2316
  dim swon = $2317
  dim swx0 = $2318
  dim swx1 = $2319
  dim swy0 = $231A
  dim swy1 = $231B
  dim absorbed = $231C
  dim swdmg = $231D
  dim vdmg = $231E
  dim sadd0 = $231F
  dim sadd1 = $2320
  dim sadd2 = $2321
  dim score_bcd = $2322

  rem ---- player ----
  dim plx = $2330
  dim ply = $2331
  dim lives = $2332
  dim pdead = $2333
  dim inv = $2334
  dim firecd = $2335
  dim gauge = $2336
  dim hyper = $2337
  dim bank = $2338
  dim chlevel = $2339
  dim chcolor = $233A
  dim chcount = $233B
  dim wn = $233C
  dim overt = $233D
  dim bothheld = $233E

  rem ---- enemies (NE) ----
  dim etype = $2400
  dim ecol = $2408
  dim ehp = $2410
  dim exl = $2418
  dim exh = $2420
  dim eyl = $2428
  dim eyh = $2430
  dim evx = $2438
  dim evy = $2440
  dim etimer = $2448
  dim estate = $2450
  dim eparam = $2458
  dim ehit = $2460
  dim eflash = $2468
  dim ebase = $2470
  dim eimg = $2478

  rem ---- enemy bullets (NB) ----
  dim bkind = $2480
  dim bxl = $2490
  dim bxh = $24A0
  dim byl = $24B0
  dim byh = $24C0
  dim bvx = $24D0
  dim bvy = $24E0
  dim shcount = $233F
  dim ewamp = $2560
  dim ewstep = $2568
  dim ewang = $2570
  dim bvxh = $2540
  dim bvyh = $2550

  rem ---- player shots (NS), explosions (NX), wave spawners (NSP) ----
  dim shx = $24F0
  dim shy = $24F6
  dim xx = $2500
  dim xy = $2506
  dim xt = $250C
  dim sptype = $2512
  dim sppal = $2515
  dim spx = $2518
  dim spdx = $251B
  dim spcount = $251E
  dim spgap = $2521
  dim sptimer = $2524
  dim spparam = $2527

  incbasic gen/gfx.bas

  characterset charset
  asm
  jsr pf_init
  lda #SONG_STAGE1
  jsr mus_play
end

  rem ======================================================================
newgame
  for i = 0 to 3 : score_bcd[i] = 0 : next
  lives = 3 : gauge = 0 : hyper = 0
  chlevel = 0 : chcount = 0 : chcolor = 255
  vdmg = 3 : wn = 0 : overt = 0
  for i = 0 to NE1 : etype[i] = 0 : next
  for i = 0 to NB1 : bkind[i] = 0 : next
  for i = 0 to NS1 : shy[i] = 0 : next
  for i = 0 to NX1 : xt[i] = 0 : next
  for i = 0 to NSP1 : spcount[i] = 0 : next
  phit = 0 : absorbed = 0
  gosub respawn

  rem ======================================================================
main
  asm
  ifconst PROFILE
  jsr prof_start
  endif
  jsr pf_frame
  ifconst PROFILE
  lda #0
  jsr prof_mark
  endif
end
  tick = tick + 1

  if overt > 0 then gosub gameover_tick
  gosub player
  asm
  ifconst PROFILE
  lda #1
  jsr prof_mark
  endif
end
  gosub waves
  gosub spawners
  asm
  ifconst PROFILE
  lda #2
  jsr prof_mark
  endif
end
  gosub think
  asm
  ifconst PROFILE
  lda #3
  jsr prof_mark
  endif
end
  asm
  jsr en_update
  jsr en_hits
end
  asm
  ifconst PROFILE
  lda #4
  jsr prof_mark
  endif
end
  gosub damage
  asm
  ifconst PROFILE
  lda #5
  jsr prof_mark
  endif
end

  rem ---- draw, back to front ----
  asm
  jsr en_draw
end
  asm
  ifconst PROFILE
  lda #6
  jsr prof_mark
  endif
end
  asm
  jsr fx_update
  jsr sh_update
end
  asm
  ifconst PROFILE
  lda #7
  jsr prof_mark
  endif
end
  asm
  jsr bul_update
end
  asm
  ifconst PROFILE
  lda #8
  jsr prof_mark
  endif
end
  gosub draw_player
  asm
  ifconst PROFILE
  lda #9
  jsr prof_mark
  endif
end
  gosub hud
  asm
  ifconst PROFILE
  lda #10
  jsr prof_mark
  endif
end

  asm
  jsr pf_drawscreen
end
  if overt = 1 then goto newgame
  goto main

  rem ======================================================================
  rem  Player
  rem ======================================================================
respawn
  plx = 74 : ply = 200 : pdead = 0 : inv = 120 : firecd = 0
  hyper = 0 : swon = 0
  return

player
  swon = 0 : swdmg = 0 : plvuln = 0
  if pdead > 0 then goto player_dead
  if inv > 0 then inv = inv - 1

  rem temp1 = Vulcan (button 1), temp2 = Sword (button 2)
  temp1 = 0 : temp2 = 0
  if joy0fire1 then temp1 = 1
  if joy0fire0 then temp2 = 1

  rem Hyper Sword: press both together with a full gauge
  temp3 = temp1 & temp2
  if temp3 = 0 then bothheld = 0
  if temp3 = 0 then goto player_nohyper
  if bothheld then goto player_nohyper
  bothheld = 1
  if gauge < GAUGE_MAX then goto player_nohyper
  if hyper > 0 then goto player_nohyper
  gosub start_hyper
player_nohyper
  if hyper > 0 then hyper = hyper - 1 : temp2 = 1

  rem Movement: slower firing, slower still with the sword out.
  rem temp4 = horizontal step, temp5 = vertical step
  temp4 = 1 : temp5 = 2
  if temp1 then temp5 = 1 + (tick & 1)
  temp6 = tick & 3
  if temp1 && temp6 = 0 then temp4 = 0
  if temp2 then temp5 = 1 : temp4 = tick & 1
  if joy0left && plx > 2 then plx = plx - temp4
  if joy0right && plx < 145 then plx = plx + temp4
  if joy0up && ply > 40 then ply = ply - temp5
  if joy0down && ply < 214 then ply = ply + temp5
  bank = 0
  if joy0left then bank = 1
  if joy0right then bank = 2
  pcx = plx + 6 : pcy = ply + 12

  rem Vulcan (not while the sword is out)
  if firecd > 0 then firecd = firecd - 1
  if temp2 = 0 && temp1 = 1 then gosub fire_vulcan

  rem Radiant Sword: an arc above the ship that cuts and absorbs pink
  if temp2 = 0 then goto player_nosword
  swon = 1
  swx0 = pcx - 12 : swx1 = pcx + 12
  swy0 = pcy - 30 : swy1 = pcy - 4
  temp6 = tick & 7
  if temp6 = 0 then swdmg = 3
  temp6 = tick & 15
  if temp6 = 0 then gosub sword_hum
  if hyper = 0 then goto player_nosword
  rem Hyper: a wider blade and a beam up the whole screen
  swx0 = pcx - 20 : swx1 = pcx + 20 : swy0 = 24
  swdmg = 0
  temp6 = tick & 3
  if temp6 = 0 then swdmg = 3
player_nosword

  rem Bullets the sword absorbed last frame: 10 points and gauge each
  if absorbed = 0 then goto player_noabsorb
  temp6 = gauge + absorbed
  if temp6 > GAUGE_MAX then temp6 = GAUGE_MAX
  gauge = temp6
  sadd0 = absorbed * 16
  asm
  jsr score_add
  lda #SFX_ABSORB
  jsr sfx_play
end
  absorbed = 0
player_noabsorb

  if inv = 0 && hyper = 0 then plvuln = 1
  if phit then phit = 0 : gosub player_die
  return

player_dead
  phit = 0
  pdead = pdead - 1
  if pdead > 0 then return
  if lives = 0 then overt = 240 : return
  gosub respawn
  return

sword_hum
  asm
  lda #SFX_SWORD
  jsr sfx_play
end
  return

player_die
  asm
  lda #SFX_DIE
  jsr sfx_play
end
  temp7 = plx : temp8 = ply : gosub spawn_fx
  temp7 = plx + 4 : temp8 = ply + 8 : gosub spawn_fx
  pdead = 90
  if lives > 0 then lives = lives - 1
  gauge = 0
  chlevel = 0 : chcount = 0
  return

start_hyper
  hyper = 150 : gauge = 0
  asm
  lda #SFX_HYPER
  jsr sfx_play
end

  asm
  jsr bul_cancel
  sta temp6
end
  rem 20 points a bullet: BCD $20 each (up to 16 bullets = 320)
  temp7 = temp6 / 5
  temp8 = temp6 - temp7 * 5
  sadd1 = temp7
  sadd0 = temp8 * 32
  asm
  jsr score_add
end
  return

fire_vulcan
  if firecd > 0 then return
  for i = 0 to NS1
    if shy[i] = 0 then goto fire_slot
  next
  return
fire_slot
  shx[i] = plx + 4 : shy[i] = ply - 6 : firecd = 4
  asm
  lda #SFX_VULCAN
  jsr sfx_play
end
  return

gameover_tick
  overt = overt - 1
  return

  rem ======================================================================
  rem  Waves: start a spawner when the scroll reaches a wave's position
  rem ======================================================================
waves
  if wn >= WAVES then return
  temp1 = wn
  if spos_hi < wath[temp1] then return
  if spos_hi > wath[temp1] then goto waves_go
  if spos_lo < watl[temp1] then return
waves_go
  for j = 0 to NSP1
    if spcount[j] = 0 then goto waves_slot
  next
  return
waves_slot
  sptype[j] = wtype[temp1] : sppal[j] = wpal[temp1] : spx[j] = wx[temp1]
  spdx[j] = wdx[temp1] : spcount[j] = wcount[temp1] : spgap[j] = wgap[temp1]
  spparam[j] = wparam[temp1] : sptimer[j] = 0
  wn = wn + 1
  return

spawners
  for j = 0 to NSP1
    if spcount[j] = 0 then goto spawners_next
    if sptimer[j] > 0 then sptimer[j] = sptimer[j] - 1 : goto spawners_next
    gosub spawn_enemy
    spx[j] = spx[j] + spdx[j]
    sptimer[j] = spgap[j]
    spcount[j] = spcount[j] - 1
spawners_next
  next
  return

  rem Spawn spawner j's enemy just above the screen.
spawn_enemy
  for k = 0 to NE1
    if etype[k] = 0 then goto spawn_slot
  next
  return
spawn_slot
  temp1 = sptype[j]
  etype[k] = temp1 : ecol[k] = sppal[j] : eparam[k] = spparam[j]
  exh[k] = spx[j] : ebase[k] = spx[j] : exl[k] = 128
  eyh[k] = 16 : eyl[k] = 0
  evx[k] = 0 : evy[k] = 0
  estate[k] = 0 : etimer[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  ewamp[k] = 0 : ewang[k] = 0 : ewstep[k] = 3
  ehp[k] = enemy_hp[temp1] : eimg[k] = enemy_img[temp1]
  if temp1 = ET_GUNSHIP then eyh[k] = 5
  rem saucers weave from the start (MegaGammaForce: x = base + cos(3t) * w)
  if temp1 = ET_SAUCER then ewamp[k] = spparam[j]
  return

  rem ======================================================================
  rem  Enemy behavior (MegaGammaForce's enemies.c think(), scaled: speeds
  rem  are 1/32 pixel per frame, so its 1/16 values are roughly x1.75).
  rem  Each enemy thinks every other frame (its timer counts in twos, so
  rem  timer tests use even numbers); movement and weaving run every frame
  rem  in asm (en_update).
  rem ======================================================================
think
  for i = 0 to NE1
    temp1 = etype[i]
    if temp1 = 0 then goto think_next
    temp2 = (i ^ tick) & 1
    if temp2 then goto think_next
    etimer[i] = etimer[i] + 2
    fx = exh[i] + 4 : fy = eyh[i] + 8
    if temp1 = ET_DART then gosub think_dart
    if temp1 = ET_SAUCER then gosub think_saucer
    if temp1 = ET_DRONE then gosub think_drone
    if temp1 = ET_GUNSHIP then gosub think_gunship
think_next
  next
  return

  rem Dives to its line, then turns on the player and fires once.
think_dart
  if estate[i] then return
  evy[i] = 70
  if eyh[i] < eparam[i] then return
  estate[i] = 1
  gosub aim
  fspd = 77
  asm
  jsr ang_vel
end
  evx[i] = velx : evy[i] = vely
  if plvuln = 0 then return
  fkind = BK_PINK : fspd = 63
  asm
  jsr bul_fire
end
  return

  rem Weaves down; every so often a 3-way pink fan at the player.
think_saucer
  evy[i] = 24
  temp2 = etimer[i] & 63
  if temp2 <> 40 then return
  if eyh[i] > 200 then return
  if plvuln = 0 then return
  gosub aim
  fkind = BK_PINK : fspd = 52 : fcount = 3 : fstep = 14
  asm
  jsr bul_fan
end
  return

  rem Stops, fires a blue ring then a pink ring, and leaves.
think_drone
  if estate[i] = 0 then goto drone_in
  if estate[i] = 1 then goto drone_hold
  evy[i] = 214
  return
drone_in
  evy[i] = 49
  if eyh[i] < eparam[i] then return
  estate[i] = 1 : etimer[i] = 0 : evy[i] = 0
  return
drone_hold
  temp2 = etimer[i]
  if temp2 = 20 then fkind = BK_BLUE : fang = 112 : goto drone_ring
  if temp2 = 70 then fkind = BK_PINK : fang = 128 : goto drone_ring
  if temp2 > 120 then estate[i] = 2
  return
drone_ring
  if plvuln = 0 then return
  fspd = 45 : fcount = 8 : fstep = 32
  asm
  jsr bul_fan
end
  return

  rem Big, strafes, drops needles and aimed blue fans; leaves after a while.
think_gunship
  fx = exh[i] + 8 : fy = eyh[i] + 24
  if estate[i] = 0 then goto gunship_in
  if estate[i] = 3 then evy[i] = 228 : return
  evy[i] = 0
  if etimer[i] = 254 then estate[i] = estate[i] + 1
  if plvuln = 0 then return
  temp2 = etimer[i] & 63
  if temp2 = 24 then gosub gunship_needles
  temp2 = etimer[i] & 127
  if temp2 <> 60 then return
  gosub aim
  fkind = BK_BLUE : fspd = 42 : fcount = 3 : fstep = 20
  asm
  jsr bul_fan
end
  return
gunship_in
  evy[i] = 21
  if eyh[i] < eparam[i] then return
  rem start strafing: x = base + sin(t) * 40 (sin = cos 64 steps behind)
  estate[i] = 1 : etimer[i] = 0 : ewamp[i] = 33 : ewang[i] = 192 : ewstep[i] = 1
  return
gunship_needles
  fang = 64 : fspd = 70 : fkind = BK_NEEDLE
  fx = fx - 7
  asm
  jsr bul_fire
end
  fx = fx + 7
  asm
  jsr bul_fire
end
  fx = fx + 7
  asm
  jsr bul_fire
end
  return

  rem fang = angle from (fx, fy) to the player
aim
  asm
  jsr aim_player
end
  fang = aimang
  return

  rem ======================================================================
  rem  Damage, destruction, score and the chain
  rem ======================================================================
damage
  for i = 0 to NE1
    temp1 = ehit[i]
    if temp1 = 0 then goto damage_next
    ehit[i] = 0
    eflash[i] = 3
    asm
    lda #SFX_HIT
    jsr sfx_play
end
    if ehp[i] <= temp1 then gosub destroy : goto damage_next
    ehp[i] = ehp[i] - temp1
damage_next
  next
  return

destroy
  temp1 = etype[i]
  temp7 = exh[i] : temp8 = eyh[i] : gosub spawn_fx
  if temp1 <> ET_GUNSHIP then goto destroy_small
  asm
  lda #SFX_BIGBOOM
  jsr sfx_play
end

  temp7 = exh[i] + 8 : temp8 = eyh[i] + 14 : gosub spawn_fx
  temp7 = exh[i] + 2 : temp8 = eyh[i] + 18 : gosub spawn_fx
  goto destroy_score
destroy_small
  asm
  lda #SFX_EXPLODE
  jsr sfx_play
end
destroy_score
  etype[i] = 0
  sadd2 = 0 : sadd1 = enemy_score1[temp1] : sadd0 = 0
  asm
  jsr score_add
end
  rem the chain: red, blue, yellow are palettes 4, 5, 6; gray never chains
  temp2 = ecol[i]
  if temp2 < 4 then return
  gosub chain_kill
  return

  rem MegaGammaForce's chain_kill(): three of a color complete a set.
chain_kill
  if chcount = 0 then goto chain_new
  if temp2 <> chcolor then goto chain_switch
  if chcount < 3 then chcount = chcount + 1
  goto chain_check
chain_switch
  if chcount < 3 then chlevel = 0
chain_new
  chcolor = temp2 : chcount = 1
chain_check
  if chcount < 3 then return
  if chlevel < 99 then chlevel = chlevel + 1
  temp3 = chlevel
  if temp3 > 41 then temp3 = 41
  sadd2 = chainb2[temp3] : sadd1 = chainb1[temp3] : sadd0 = chainb0[temp3]
  asm
  jsr score_add
end
  return

  rem ---- explosions ----
spawn_fx
  for k = 0 to NX1
    if xt[k] = 0 then xx[k] = temp7 : xy[k] = temp8 : xt[k] = 1 : return
  next
  return

draw_player
  if pdead > 0 then return
  rem blink while invulnerable
  temp6 = tick & 4
  if inv > 0 && temp6 then return
  if swon = 0 then goto draw_ship
  pimg = IMG_SWORD : pframe = (tick / 4) & 3 : ppal = 7
  temp6 = tick & 2
  if hyper > 0 && temp6 then ppal = 3
  px = pcx - 12 : py = pcy - 32
  asm
  jsr pf_drawimg
end
  if hyper = 0 then goto draw_ship
  rem the Hyper beam: bolts stacked up the screen
  pimg = IMG_VULCAN : pframe = 0 : ppal = 3 : px = pcx - 2
  py = ply - 32
draw_beam
  if py < 30 then goto draw_ship
  asm
  jsr pf_drawimg
end
  py = py - 16
  goto draw_beam
draw_ship
  pimg = IMG_SHIP : pframe = bank : px = plx : py = ply : ppal = 3
  asm
  jsr pf_drawimg
end
  return

  rem ======================================================================
  rem  HUD: score (0-6), chain (8-10), sword gauge (12-16), lives (18-19)
  rem ======================================================================
hud
  temp1 = tick & 3
  if temp1 then return
  asm
  jsr hud_score
end
  hudtext[7] = CH_SPACE
  hudtext[8] = CH_X
  temp1 = chlevel : temp2 = 0
hud_tens
  if temp1 >= 10 then temp1 = temp1 - 10 : temp2 = temp2 + 1 : goto hud_tens
  if temp2 > 9 then temp2 = 9
  hudtext[9] = FONTBASE + temp2 * 2
  hudtext[10] = FONTBASE + temp1 * 2
  hudtext[11] = CH_SPACE
  if overt > 0 then goto hud_over
  if gauge >= GAUGE_MAX then goto hud_hyper
  temp3 = gauge / 8
  for k = 0 to 4
    temp4 = CH_SPACE
    if k < temp3 then temp4 = CH_I
    temp5 = 12 + k
    hudtext[temp5] = temp4
  next
  goto hud_lives
hud_hyper
  hudtext[12] = CH_H : hudtext[13] = CH_Y : hudtext[14] = CH_P
  hudtext[15] = CH_E : hudtext[16] = CH_R
  temp6 = tick & 8
  if temp6 = 0 then goto hud_lives
  for k = 12 to 16 : hudtext[k] = CH_SPACE : next
hud_lives
  hudtext[17] = CH_SPACE
  hudtext[18] = CH_X
  hudtext[19] = FONTBASE + lives * 2
  return
hud_over
  for k = 0 to 7
    temp5 = 12 + k
    hudtext[temp5] = hudover[k]
  next
  return

  rem ======================================================================
  rem Runs every frame from 7800basic's NMI, off screen.
userinterrupt
  asm
  jmp mus_tick
end

  rem ---- per enemy type: hit points, score (hundreds, BCD), image ----
  data enemy_hp
  0, 2, 4, 10, 60
end
  data enemy_score1
  0, $01, $02, $03, $20
end
  data enemy_img
  0, IMG_DART, IMG_SAUCER, IMG_DRONE, IMG_GUNSHIP
end

  rem Assembly files are copied flat into the build directory (tools/build.sh).
  inline engine.asm
  inline objects.asm
  inline data.asm
  inline music.asm
  inline sfx.asm
  inline musicdata.asm
