  rem ======================================================================
  rem  ATARI GAMMA FORCE
  rem  A demake of MegaGammaForce (RP6502) for the Atari 7800.
  rem  7800basic for the game; assembly for the display (asm/engine.asm),
  rem  the object loops (asm/objects.asm) and the music (asm/music.asm).
  rem ======================================================================

  rem 144K SuperGame: bank 1 fixed at $4000 (the game), banks 2-8 switched
  rem in at $8000 (one per stage), the last bank fixed at $C000 (graphics).
  set romsize 144k
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
  rem enemy slots: waves and ground units use the first 12 (NEW1); the
  rem 13th is for LEVIATHAN's darts, as its parts fill slots 0-10
  const NE = 13
  const NB = 16
  const NS = 6
  const NX = 4
  const NSP = 3
  rem 7800basic drops arithmetic in a for loop's limit ("to NE1" runs to
  rem NE), so loops use these.
  const NE1 = 12
  const NEW1 = 11
  const NB1 = 15
  const NS1 = 5
  const NX1 = 3
  const NSP1 = 2

  rem Uncomment to time the main loop's sections (tools/profile.py).
  rem const PROFILE = 1
  rem Uncomment to log each displayed frame's catch-up, draw and wait time
  rem (engine.asm il_*; RIOT timer, 1024-cycle ticks, at $25F0).
  rem const IDLELOG = 1
  rem Testing: start at the boss, and/or never get hit.
  rem const BOSSTEST = 1
  rem const CHEAT = 1
  rem Start at stage 2, 3, 4 or 5.
  rem const STAGE2TEST = 1
  rem const STAGE3TEST = 1
  rem const STAGE4TEST = 1
  rem const STAGE5TEST = 1
  rem const STAGE6TEST = 1
  rem Always 30 frames a second (each frame two game steps). Without it the
  rem display runs at 60 and drops to 30 only while a frame runs late.
  rem const FPS30 = 1

  rem ---- enemy types (as in MegaGammaForce's enemies.h) ----
  const ET_DART = 1
  const ET_SAUCER = 2
  const ET_DRONE = 3
  const ET_GUNSHIP = 4
  const ET_TURRET = 5
  const ET_WASP = 6
  const ET_TANK = 7
  rem an obstacle (stage 2's towers): rides the map, can't be shot, and
  rem destroys the ship that flies into it
  const ET_TOWER = 8
  const ET_GUNBOAT = 9
  rem stage 4's armored train cars, on the railway (eframe 0: the engine)
  const ET_TRAIN = 10
  rem the stages, round and round
  const NSTAGES = 6
  rem boss parts: types from ET_PART up are placed by the boss code
  const ET_PART = 11
  const ET_PCANNON = 11
  const ET_PWING = 12
  const ET_PARMOR = 13
  const ET_PCORE = 14
  const ET_PTURRET = 15
  rem a destroyed cannon or wing: drawn dark, no longer hit
  const ET_PWRECK = 16
  rem stage 2's boss: a pod orbiting the core
  const ET_PPOD = 17

  rem ---- bullet kinds: odd = pink (the sword absorbs them) ----
  const BK_PINK = 1
  const BK_BLUE = 2
  const BK_NEEDLE = 5

  rem pink bullets the sword must absorb to charge the Hyper Sword
  const GAUGE_MAX = 36

  rem ---- engine arguments (asm/engine.asm) ----
  dim pimg = $2300
  dim pframe = $2301
  dim px = $2302
  dim py = $2303
  dim ppal = $2304

  rem ---- engine state BASIC reads or writes ----
  dim spos_lo = $2231
  dim spos_hi = $2232
  dim pflate = $22C1
  dim pfnodraw = $22C2
  dim pfahead = $22C6
  dim pfowe = $22C7
  dim pfdraws = $22C3
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

  rem ---- enemies (NE slots; arrays 16 apart) ----
  dim etype = $2600
  dim ecol = $2610
  dim ehp = $2620
  dim exl = $2630
  dim exh = $2640
  dim eyl = $2650
  dim eyh = $2660
  dim evx = $2670
  dim evy = $2680
  dim etimer = $2690
  dim estate = $26A0
  dim eparam = $26B0
  dim ehit = $26C0
  dim eflash = $26D0
  dim ebase = $26E0
  dim eimg = $26F0
  dim ewamp = $2700
  dim ewstep = $2710
  dim ewang = $2720
  dim eframe = $2730

  rem ---- enemy bullets (NB) ----
  dim bkind = $2480
  dim bxl = $2490
  dim bxh = $24A0
  dim byl = $24B0
  dim byh = $24C0
  dim bvx = $24D0
  dim bvy = $24E0
  dim shcount = $233F
  dim swcd = $2354
  dim anyhit = $2356
  dim plfire = $2357
  dim plsword = $2358
  dim gn = $234D
  dim gcolor = $234E
  dim bstate = $2344
  dim btl = $2345
  dim bth = $2346
  dim bx = $2347
  dim by = $2348
  dim bcorehp = $2349
  dim bspin = $234A
  dim bparts = $234B
  dim bmsg = $234C
  dim bburst = $2359
  dim bsrc = $235A
  rem the stage being played (1-5)
  dim stage = $235B
  rem stage 2's boss: the pods' orbit angle, the cannon's sweep
  dim borbit = $235C
  dim bsweep = $235D
  dim bsdir = $235E
  rem "STAGE n" in the HUD while this counts down
  dim smsg = $235F
  rem stage 2's boss: bullets of the core's ring still to fire
  dim bring = $2380
  rem the stage chosen on the title
  dim selstage = $2390
  dim selcd = $2391
  rem the results: % of the boss destroyed, bonus (in hundreds) still to
  rem count, the boss got away, fire released, the longest chain
  dim bdestr = $2392
  dim bbonus = $2393
  dim bescape = $2394
  dim bready = $2395
  dim chmax = $2396
  rem Teddy Bear mode (chosen on the title): fewer enemy bullets
  rem (objects.asm bul_fire, bul_fan); bfalt alternates single shots
  dim easy = $2397
  rem Teddy Bear's armor: 1 while the ship can take a hit (player_hit)
  dim armor = $239D
  dim bfalt = $2398
  rem the next extra life's score, as the score's top two BCD bytes:
  rem millions; hundred and ten thousands
  dim nextx = $2399
  dim nextx0 = $239B
  rem the results: 1 for all of the boss destroyed (10,000 more)
  dim bperf = $239A
  rem a background color for userinterrupt to set off the screen (0: none;
  rem stage 5's blizzard gusts; engine.asm pf_palettes clears it)
  dim bgwant = $239C
  rem stage 6's fade: the background color and palette 1, for
  rem userinterrupt to set off the screen while fadeon (stage6.bas; engine.asm
  rem pf_palettes clears it)
  dim fadeon = $234F
  dim fadebg = $2350
  dim fadep1 = $2351
  rem the results' three lines of text (60 characters), each part's weight
  dim rtline = $23A0
  dim bwt = $23E0
  rem each boss part's offset from the boss centre (from the boss's tables)
  dim bdx = $2360
  dim bdy = $2370
  dim tzone = $2342
  dim tpal = $2343
  dim pfspeed = $2233
  dim pfstartrow = $223C
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

  characterset charset
  rem the difficulty starts at Normal
  easy = 1
  rem Switch stage 1's bank (bank 2) in at $8000 (engine.asm pf_stage;
  rem 7800basic only allows loadrombank in the last bank).
  asm
  lda #1
  jsr pf_stage
end
  asm
  jsr pf_init
end

  rem ======================================================================
  rem  Title screen: the sea stands still under the title
  rem ======================================================================
title
  asm
  ; the music first: it plays from the stage's bank, and once stage 1's
  ; bank is in, the song's old addresses hold other bytes (a game over
  ; comes here with the song still playing)
  jsr mus_stop
  lda #0
  sta pfspeed
  lda #1
  jsr pf_stage
  jsr pf_reset
end
  for i = 0 to NE1 : etype[i] = 0 : next
  for i = 0 to NB1 : bkind[i] = 0 : next
  for i = 0 to NS1 : shy[i] = 0 : next
  for i = 0 to NX1 : xt[i] = 0 : next
  temp9 = 30
  if selstage = 0 then selstage = 1
  asm
  jsr hud_hide
end
  asm
  lda #SONG_TITLE
  jsr mus_play
end
title_loop
  asm
  jsr pf_frame
end
  tick = tick + 1
  rem the logo, GAMMA over FORCE, in palette 4
  pframe = 0 : ppal = 4 : px = 34
  pimg = IMG_LOGO_GAMMA : py = 70
  asm
  jsr pf_drawimg
end
  pimg = IMG_LOGO_FORCE : py = 104
  asm
  jsr pf_drawimg
end
  tpal = 3
  tzone = 2 : temp1 = TXT_ATARI : gosub text
  rem the starting stage: left and right choose
  tpal = 6
  tzone = 9 : temp1 = TXT_SEL1 + selstage - 1 : gosub text
  tpal = 3
  tzone = 10 : temp1 = TXT_NAME1 + selstage - 1 : gosub text
  rem the difficulty: up and down choose
  rem (Expert in yellow, Normal in blue, Teddy Bear in the logo's colors)
  tpal = 6
  if easy = 1 then tpal = 5
  if easy = 2 then tpal = 4
  tzone = 11 : temp1 = TXT_MODE0 + easy : gosub text
  rem PRESS FIRE and the buttons, by turns
  tpal = 7 : temp1 = TXT_PUSH
  temp2 = tick & 64
  if temp2 then tpal = 3 : temp1 = TXT_B1
  tzone = 12 : gosub text
  tpal = 6
  tzone = 13 : temp1 = TXT_CREDIT : gosub text
  asm
  jsr pf_drawscreen
end
  rem Astrowing's rotating palette: each of the logo's colors steps
  rem through the 16 hues (a step every 4 frames) at its own brightness:
  rem a dark rim, the body, and the lit bevel a couple of hues ahead
  temp4 = tick / 4
  temp5 = temp4 & 15 : P4C1 = temp5 * 16 + 2
  P4C2 = temp5 * 16 + 7
  temp5 = (temp4 + 2) & 15 : P4C3 = temp5 * 16 + 13
  if selcd > 0 then selcd = selcd - 1 : goto title_fire
  if joy0left && selstage > 1 then selstage = selstage - 1 : selcd = 15
  if joy0right && selstage < NSTAGES then selstage = selstage + 1 : selcd = 15
  if joy0up && easy > 0 then easy = easy - 1 : selcd = 15
  if joy0down && easy < 2 then easy = easy + 1 : selcd = 15
title_fire
  rem Start on a fresh press of either button (released first)
  temp3 = 0
  if joy0fire0 then temp3 = 1
  if joy0fire1 then temp3 = 1
  if temp3 = 0 && temp9 > 0 then temp9 = temp9 - 1
  if temp3 = 0 then goto title_loop
  if temp9 > 0 then goto title_loop
  stage = selstage : smsg = 180
  asm
  ifconst STAGE2TEST
  lda #2
  sta stage
  endif
  ifconst STAGE3TEST
  lda #3
  sta stage
  endif
  ifconst STAGE4TEST
  lda #4
  sta stage
  endif
  ifconst STAGE5TEST
  lda #5
  sta stage
  endif
  ifconst STAGE6TEST
  lda #6
  sta stage
  endif
  lda #160
  sta pfspeed
  lda stage
  jsr pf_stage
  ifconst BOSSTEST
  lda stg_bossat          ; a little before the boss: row bossat * 16 - 6
  asl
  asl
  asl
  asl
  sec
  sbc #6
  sta pfstartrow
  endif
  jsr pf_reset
  lda stg_song
  jsr mus_play
end

  rem ======================================================================
newgame
  for i = 0 to 3 : score_bcd[i] = 0 : next
  lives = 3 : if easy = 2 then lives = 5
  gauge = 0 : hyper = 0 : nextx0 = 0 : nextx = $05
  chlevel = 0 : chcount = 0 : chcolor = 255 : chmax = 0
  vdmg = 3 : wn = 0 : overt = 0 : bstate = 0 : bmsg = 0 : gn = 0 : gcolor = 0
  swcd = 0 : pfahead = 0
  for i = 0 to NE1 : etype[i] = 0 : next
  for i = 0 to NB1 : bkind[i] = 0 : next
  for i = 0 to NS1 : shy[i] = 0 : next
  for i = 0 to NX1 : xt[i] = 0 : next
  for i = 0 to NSP1 : spcount[i] = 0 : next
  phit = 0 : absorbed = 0
  asm
  ifconst BOSSTEST
  lda stg_nwaves
  sta wn
  endif
end
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
  rem After a late frame (the last one showed for two or three), a
  rem catch-up step for each extra frame, drawing nothing, so the game
  rem keeps its speed (engine.asm pf_drawscreen); less those already run
  rem early, while waiting for the frame to show (below).
  pfowe = 0 : if pflate > pfahead then pfowe = pflate - pfahead
  pfahead = 0
  asm
  ifconst IDLELOG
  lda #0
  sta il_c
  lda pfowe
  sta il_n
  jsr il_go
  endif
end
  if pfowe = 0 then goto main_step
  pfnodraw = 1 : gosub step
  if pfowe >= 2 then gosub step
  pfnodraw = 0
  asm
  ifconst IDLELOG
  jsr il_take
  sta il_c
  jsr il_go
  endif
end
main_step
  gosub step
  rem Text after the sprites, on top of them (engine.asm pf_text)
  if overt > 0 then tpal = 4 : tzone = 6 : temp1 = TXT_OVER : gosub text
  if bstate = 5 then gosub results_text
  asm
  ifconst IDLELOG
  jsr il_take
  sta il_d
  lda #0
  sta il_e
  jsr il_go
  endif
end
  rem Late already (the logic ran past a vblank)? Rather than wait for the
  rem next one idle, run the catch-up steps it will owe now, each only if
  rem it fits before that vblank (engine.asm pf_early). Otherwise a frame
  rem that showed for three left two steps for the next, and with them it
  rem took three again: slow spots stuck at 20 frames a second.
main_early
  asm
  jsr pf_early
  beq .main_wait
end
  pfnodraw = 1 : gosub step : pfnodraw = 0
  pfahead = pfahead + 1
  goto main_early
main_wait
  asm
  ifconst IDLELOG
  jsr il_take
  sta il_e
  lda pfahead
  sta il_a
  endif
  jsr pf_drawscreen
end
  if overt = 1 then goto title
  goto main

  rem One game step: 1/60 second of play, drawn unless pfnodraw
step
  tick = tick + 1

  if overt > 0 then gosub gameover_tick
  gosub extra_life
  gosub player
  asm
  ifconst PROFILE
  lda #11
  jsr prof_mark
  endif
end
  rem The boss moves first, so its wrecks can be drawn under the ship
  gosub boss
  asm
  ifconst PROFILE
  lda #12
  jsr prof_mark
  endif
  jsr en_draw_wrecks
  ifconst PROFILE
  lda #13
  jsr prof_mark
  endif
end
  rem The ship and sword are plotted early in the frame, before MARIA
  rem reaches the bottom of the screen where they usually are.
  if pfnodraw = 0 then gosub draw_player
  asm
  ifconst PROFILE
  lda #1
  jsr prof_mark
  endif
end
  gosub waves
  gosub ground
  gosub spawners
  asm
  ifconst PROFILE
  lda #2
  jsr prof_mark
  endif
end
  asm
  jsr en_think
end
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
  if anyhit then anyhit = 0 : gosub damage
  asm
  ifconst PROFILE
  lda #5
  jsr prof_mark
  endif
end

  rem ---- draw, back to front (the moving objects move as they draw) ----
  asm
  lda pfnodraw
  bne skip_en_draw
  jsr en_draw
skip_en_draw
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
  rem stage 5's blizzards (stage5.bas, in its bank)
  if stage = 5 then gosub blizzard
  rem stage 6's fade (stage6.bas, in its bank)
  if stage = 6 then gosub ascent
  asm
  ifconst PROFILE
  lda #8
  jsr prof_mark
  endif
end
  asm
  ifconst PROFILE
  lda #9
  jsr prof_mark
  endif
end
  if pfnodraw = 0 then gosub hud
  asm
  ifconst PROFILE
  lda #10
  jsr prof_mark
  endif
end
  return

  rem Show text temp1 in zone tzone, palette tpal (asm/engine.asm pf_text)
text
  asm
  lda temp1
  jsr pf_text
end
  return

  rem ======================================================================
  rem  Player
  rem ======================================================================
respawn
  plx = 74 : ply = 200 : pdead = 0 : inv = 120 : firecd = 0
  hyper = 0 : swon = 0
  rem Teddy Bear: armor again with each ship
  armor = 0 : if easy = 2 then armor = 1
  return

player
  swon = 0 : swdmg = 0 : plvuln = 0
  if pdead > 0 then goto player_dead
  if inv > 0 then inv = inv - 1

  rem temp1 = Vulcan (button 1), temp2 = Sword (button 2)
  temp1 = 0 : temp2 = 0
  if joy0fire1 then temp1 = 1
  if joy0fire0 then temp2 = 1
  rem the results: the buttons only go on to the next stage
  if bstate = 5 then temp1 = 0 : temp2 = 0

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

  rem Movement, the Vulcan and the sword's box: asm/objects.asm pl_update
  plfire = temp1 : plsword = temp2
  asm
  jsr pl_update
end

  rem Bullets the sword absorbed last frame: 10 points and gauge each
  if absorbed = 0 then goto player_noabsorb
  temp6 = gauge + absorbed
  if temp6 > GAUGE_MAX then temp6 = GAUGE_MAX
  rem (temp7: the gauge has just filled)
  temp7 = 0
  if gauge < GAUGE_MAX && temp6 >= GAUGE_MAX then temp7 = 1
  gauge = temp6
  sadd0 = absorbed * 16
  asm
  jsr score_add
  lda #SFX_ABSORB
  jsr sfx_play
end
  rem the Hyper Sword is ready: a chime (it outranks the absorb's sound)
  if temp7 then gosub hyper_ready
  absorbed = 0
player_noabsorb

  if inv = 0 && hyper = 0 then plvuln = 1
  asm
  ifconst CHEAT
  lda #0
  sta phit
  endif
end
  if phit then phit = 0 : gosub player_hit
  return

  rem Hit: in Teddy Bear the armor takes it (a burst, and the ship blinks,
  rem invulnerable, for a second and a half); else the ship is lost
player_hit
  if armor = 0 then goto player_die
  armor = 0 : inv = 90
  temp7 = plx + 2 : temp8 = ply + 4 : gosub spawn_fx
  asm
  lda #SFX_HIT
  jsr sfx_play
end
  return

player_dead
  phit = 0
  if overt > 0 then return
  pdead = pdead - 1
  if pdead > 0 then return
  if lives = 0 then overt = 240 : pfspeed = 0 : pdead = 255 : return
  gosub respawn
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

hyper_ready
  asm
  lda #SFX_READY
  jsr sfx_play
end
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

  rem An extra life at 50,000 points and 100,000, then every 100,000
  rem (MegaGammaForce's): the score's top two BCD bytes against nextx0,
  rem nextx, which then go up (BCD)
extra_life
  if score_bcd[0] < nextx0 then return
  if score_bcd[0] = nextx0 && score_bcd[1] < nextx then return
  if nextx0 = $09 && nextx = $90 then nextx0 = $99 : goto extra_life_1up
  asm
  sed
  lda nextx
  cmp #$05
  bne extra_life_100k
  lda #$05                ; 50,000 -> 100,000
  .byte $2C               ; (bit abs: skip the next 2 bytes)
extra_life_100k
  lda #$10                ; then 100,000 more
  clc
  adc nextx
  sta nextx
  lda nextx0
  adc #0
  sta nextx0
  cld
end
extra_life_1up
  if lives < 9 then lives = lives + 1
  asm
  lda #SFX_1UP
  jsr sfx_play
end
  return

  rem (stops at 1, which the main loop takes back to the title)
gameover_tick
  if overt > 1 then overt = overt - 1
  return

  rem ======================================================================
  rem  Waves: start a spawner when the scroll reaches a wave's position
  rem ======================================================================
waves
  if wn >= stg_nwaves then return
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
  for k = 0 to NEW1
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
  rem wasps weave faster (MegaGammaForce: base + sin(4t) * w)
  if temp1 = ET_WASP then ewamp[k] = spparam[j] : ewstep[k] = 4
  rem stage 5's falling shelves: towers that fall (objects.asm en_update),
  rem param the speed (128ths of a line a frame faster than the scroll); a
  rem tower's line is the scroll plus eparam, so it starts above the screen
  if temp1 <> ET_TOWER then return
  eimg[k] = IMG_SLAB : ewamp[k] = spparam[j] : eparam[k] = 16 - spos_lo
  exh[k] = spx[j] & 127
  return

  rem Enemy behavior is in asm/objects.asm (en_think).

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
    if etype[i] >= ET_PART then gosub part_damage : goto damage_next
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
  if temp1 = ET_GUNBOAT then goto destroy_big
  if temp1 = ET_TRAIN then goto destroy_big
  if temp1 <> ET_GUNSHIP then goto destroy_small
destroy_big
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
  if chlevel > chmax then chmax = chlevel
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
  rem armored (Teddy Bear): bluer (palette 5)
  if armor then ppal = 5
  rem the Hyper Sword is ready: the ship glows gold (palette 6) by turns
  temp6 = tick & 8
  if gauge >= GAUGE_MAX && temp6 then ppal = 6
  asm
  jsr pf_drawimg
end
  return



  rem ======================================================================
  rem  Ground units (the stage's ground table): turrets on the fortress's
  rem  hatches or the city's rooftop pads, tanks on its roads. Each spawns
  rem  as its row scrolls in (at most 4 at a time) and rides the map.
  rem ======================================================================
ground
  if gn >= stg_nground then return
  temp1 = gn
  if spos_hi < gth[temp1] then return
  if spos_hi > gth[temp1] then goto ground_go
  if spos_lo < gtl[temp1] then return
ground_go
  gn = gn + 1
  rem at most 4 turrets and tanks at once (a train's cars always come)
  if gtype[temp1] = ET_TRAIN then goto ground_find
  temp2 = 0
  for k = 0 to NEW1
    if etype[k] = ET_TURRET then temp2 = temp2 + 1
    if etype[k] = ET_TANK then temp2 = temp2 + 1
  next
  if temp2 >= 4 then return
ground_find
  for k = 0 to NEW1
    if etype[k] = 0 then goto ground_slot
  next
  rem no free slot: try again next step (ground units' lines follow the
  rem scroll, so a late one is still in its place)
  gn = gn - 1
  return
ground_slot
  temp2 = gtype[temp1]
  etype[k] = temp2 : eimg[k] = enemy_img[temp2] : ehp[k] = enemy_hp[temp2]
  rem (stage 5's obstacles are icebergs)
  if temp2 = ET_TOWER && stage = 5 then eimg[k] = IMG_BERG
  if temp2 = ET_TOWER && stage = 6 then eimg[k] = IMG_SAT
  exh[k] = gtx[temp1] : eparam[k] = gtbase[temp1] : ewamp[k] = gparam[temp1]
  eyh[k] = spos_lo + gtbase[temp1]
  ecol[k] = gpal[temp1]
  etimer[k] = k * 26 : estate[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  evx[k] = 0 : evy[k] = 0 : eframe[k] = 0
  rem a train car's param: its picture (0 the engine, 1 a gun car)
  if temp2 = ET_TRAIN then eframe[k] = gparam[temp1] : return
  rem a tank's param: its speed, bit 6 for a veteran (stage 5's: objects.asm
  rem think_tank, noted in estate), and bit 7 for driving left
  if temp2 <> ET_TANK then return
  temp3 = gparam[temp1] & 63
  evx[k] = temp3
  estate[k] = gparam[temp1] & 64
  temp4 = gparam[temp1] & 128
  if temp4 then evx[k] = 0 - temp3
  return


  rem ======================================================================
  rem  GAMMA CORE, the stage 1 boss (MegaGammaForce's boss1.c, thinned).
  rem  Eleven enemy slots: cannon, two wings (a top half and a bottom
  rem  half, ET_PARMOR, that passes its hits to the top), the core (two
  rem  halves sharing bcorehp), and four turrets on the wings. While a wing
  rem  has turrets, shots pass through the wing's middle column to reach
  rem  them (eparam, objects.asm en_hits). A destroyed cannon or wing stays
  rem  as a dark wreck. bstate: 0 none, 1 warning, 2 entering, 3 fighting,
  rem  4 exploding, 5 stage clear.
  rem ======================================================================
boss
  if bstate = 0 then goto boss_wait
  if bstate = 1 then goto boss_warning
  if bstate = 2 then goto boss_enter
  if bstate = 3 then goto boss_fight
  if bstate = 4 then goto boss_dying
  goto boss_clear

  rem After the last wave, once the sky is clear and the fortress is behind
boss_wait
  if wn < stg_nwaves then return
  if spos_hi < stg_bossat then return
  rem (stage 3's ship and stage 5's crawler come in with the map: they
  rem can't wait for a clear sky)
  if stage = 3 then goto boss_go
  if stage = 5 then goto boss_go
  if stage = 6 then goto boss_go
  for k = 0 to NE1
    if etype[k] then return
  next
boss_go
  bstate = 1 : btl = 0 : bth = 0
  asm
  lda stg_bosssong
  jsr mus_play
end
  return

boss_warning
  btl = btl + 1
  bmsg = 1
  if btl < 180 then return
  bmsg = 0
  rem build the boss above the screen
  bx = 80 : by = 0 : bspin = 0 : bcorehp = 225 : bparts = 0 : bburst = 0
  bescape = 0
  for k = 0 to 10
    ecol[k] = 0 : eflash[k] = 0 : ehit[k] = 0 : eframe[k] = 0
    evx[k] = 0 : evy[k] = 0 : ewamp[k] = 0
  next
  rem the stage's boss: its parts from its tables (stage 2's are in its bank)
  if stage = 1 then gosub boss1_build
  if stage = 2 then gosub boss2_build
  if stage = 3 then gosub boss3_build
  if stage = 4 then gosub boss4_build
  if stage = 5 then gosub boss5_build
  if stage = 6 then gosub boss6_build
  gosub boss_place
  bstate = 2 : btl = 0 : bth = 0
  return

boss_enter
  if stage = 3 then goto boss3_enter
  if stage = 4 then goto boss4_enter
  if stage = 5 then goto boss5_enter
  if stage = 6 then goto boss6_enter
  by = by + 1
  gosub boss_place
  if by < 89 then return
  bstate = 3
  return

boss_fight
  if stage = 3 then goto boss3_fight
  if stage = 4 then goto boss4_fight
  if stage = 5 then goto boss5_fight
  if stage = 6 then goto boss6_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  rem sway: x = 80 + 17 sin(t/2), y = 89 + 6 sin(t/4) (stage 2: 12, 7)
  wang = btl / 2 + 192 : wamp = 17
  if stage = 2 then wamp = 12
  asm
  jsr weave
end
  bx = 80 + woff
  wang = btl / 4 + 192 : wamp = 6
  if stage = 2 then wamp = 7
  asm
  jsr weave
end
  by = 89 + woff
  rem every third spell of 256 steps (about 4 seconds) it swoops down at
  rem the player and back up: 0-72 lines lower, (1 - cos) shaped
  temp1 = bth
boss_mod3
  if temp1 >= 3 then temp1 = temp1 - 3 : goto boss_mod3
  if temp1 <> 2 then goto boss_nodive
  temp6 = by
  wang = btl : wamp = 36
  asm
  jsr weave
end
  by = temp6 + 36 - woff
boss_nodive
  if stage = 2 then gosub boss2_orbit
  gosub boss_place
  rem 90 seconds and it escapes
  if bth >= 21 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 200 : return
  if plvuln = 0 then return
  gosub boss_attack
  return

  rem Part k's position from the boss centre (bx, by): bdx, bdy (copied
  rem from the boss's tables: MegaGammaForce pixels halved across, as
  rem sprites are half width here; stage 2's pods move theirs).
  rem A part above the centre whose y would go below 0 (the boss still
  rem coming in from the top) is parked at 0, wholly above the screen,
  rem rather than wrapping round to the bottom.
boss_place
  if stage = 3 then goto boss3_place
  if stage = 4 then goto boss4_place
  if stage = 5 then goto boss5_place
  if stage = 6 then goto boss6_place
  asm
  ldx #10
boss_place_loop
  lda etype,x
  beq boss_place_next
  lda bx
  clc
  adc bdx,x
  sta exh,x
  lda bdy,x
  bpl boss_place_down
  clc
  adc by
  bcs boss_place_y
  lda #0
  beq boss_place_y
boss_place_down
  clc
  adc by
boss_place_y
  sta eyh,x
boss_place_next
  dex
  bpl boss_place_loop
end
  if stage = 1 then gosub boss1_frames
  if stage = 2 then gosub boss2_frames
boss_turrets
  rem turrets turn to face the player (8 directions), one a step
  k = (btl & 3) + 7
  if stage = 2 then k = (btl & 1) + 1
  if etype[k] <> ET_PTURRET then return
  fx = exh[k] + 4 : fy = eyh[k] + 8
  gosub aim
  eframe[k] = (fang - 48) / 32 & 7
  return

boss_attack
  if stage = 2 then goto boss2_attack
  if stage = 3 then goto boss3_attack
  if stage = 4 then goto boss4_attack
  if stage = 5 then goto boss5_attack
  if stage = 6 then goto boss6_attack
  goto boss1_attack

  rem Damage temp1 to boss part i. A wing's bottom half passes its hits
  rem to the top half, the slot before it.
part_damage
  if bstate <> 3 then return
  if etype[i] <> ET_PARMOR then goto part_hit
  i = i - 1 : gosub part_hit : i = i + 1
  return
part_hit
  temp2 = etype[i]
  if temp2 = ET_PWRECK then return
  if temp2 = ET_PCORE then goto part_core
  eflash[i] = 3
  temp5 = i + 1
  if temp2 = ET_PWING then eflash[temp5] = 3
  if ehp[i] > temp1 then ehp[i] = ehp[i] - temp1 : return
  rem a part is destroyed: 2,000 points
  temp7 = exh[i] : temp8 = eyh[i]
  if temp2 = ET_PTURRET then gosub spawn_fx : etype[i] = 0 : goto part_score
  if temp2 <> ET_PPOD then goto part_notpod
  temp7 = temp7 + 4 : temp8 = temp8 + 8 : gosub spawn_fx : etype[i] = 0
  rem (stage 6's satellites fall as debris)
  if stage = 6 then gosub b6_debris
  goto part_score
part_notpod
  rem stage 5's guns, drill and bridge blow apart, leaving their wells bare
  rem (its hatches leave craters, as LEVIATHAN's bays)
  if stage = 5 && eimg[i] <> IMG_B3BAY then goto part_blast
  rem explosions down the part, and it stays as a wreck
  temp7 = temp7 + 4 : temp8 = temp8 + 4 : gosub spawn_fx
  temp8 = eyh[i] + 20 : gosub spawn_fx
  etype[i] = ET_PWRECK : ecol[i] = 1 : eframe[i] = 0
  if temp2 <> ET_PWING then goto part_score
  temp8 = eyh[i] + 40 : gosub spawn_fx
  etype[temp5] = ET_PWRECK : ecol[temp5] = 1
  rem and a wing takes its turrets with it
  if i = 1 then etype[7] = 0 : etype[8] = 0
  if i = 3 then etype[9] = 0 : etype[10] = 0
  goto part_score
part_blast
  temp8 = temp8 + 4 : gosub spawn_fx
  temp7 = temp7 + 6 : temp8 = temp8 + 12 : gosub spawn_fx
  temp7 = temp7 - 8 : temp8 = temp8 + 6 : gosub spawn_fx
  etype[i] = 0
part_score
  bparts = bparts + 1
  sadd2 = 0 : sadd1 = $20 : sadd0 = 0
  asm
  jsr score_add
  lda #SFX_BIGBOOM
  jsr sfx_play
end
  return
part_core
  rem stage 4's head is shut while its tail or any segment is whole
  if stage <> 4 then goto part_core_2
  for k = 0 to 8
    if etype[k] = ET_PCANNON then return
  next
part_core_2
  rem stage 2's core is shut while any of its pods orbits, stage 6's
  rem while any of its satellites does
  if stage <> 6 then goto part_core_6
  for k = 0 to 3
    if etype[k] = ET_PPOD then return
  next
part_core_6
  if stage <> 2 then goto part_core_open
  temp6 = etype[8] | etype[9] | etype[10]
  if temp6 then return
part_core_open
  rem (stage 4's core, the wyrm's head, is slots 9 and 10; stage 3's and
  rem 5's reactor is slot 5 alone, a hatch beside it)
  temp5 = 5
  if stage = 4 then temp5 = 9
  eflash[temp5] = 3 : temp5 = temp5 + 1
  if stage = 3 || stage >= 5 then goto part_core_hit
  eflash[temp5] = 3
part_core_hit
  rem the core is armored: half damage
  temp1 = temp1 / 2 + 1
  if bcorehp > temp1 then bcorehp = bcorehp - temp1 : return
  bcorehp = 0
  gosub boss_tally
  bdestr = bdestr + 30
  rem the core: 10,000, and 20,000 more for taking every other part first
  sadd2 = $01 : sadd1 = 0 : sadd0 = 0
  asm
  jsr score_add
end
  temp3 = 0
  for k = 0 to 10
    if etype[k] = ET_PCANNON || etype[k] = ET_PWING then temp3 = 1
    if etype[k] = ET_PPOD then temp3 = 1
  next
  if temp3 = 0 then sadd2 = $02 : sadd1 = 0 : sadd0 = 0 : gosub boss_bonus
  bstate = 4 : btl = 0
  rem stage 3's ship sinks, stage 5's crawler breaks through the ice: the
  rem scroll carries it away
  if stage = 3 then pfspeed = 250
  if stage >= 5 then pfspeed = 250
  return
boss_bonus
  asm
  jsr score_add
end
  return

  rem Explosions all over it, then gone
boss_dying
  btl = btl + 1
  temp1 = btl & 7
  if temp1 = 0 then gosub boss_boom
  if stage = 3 then gosub boss3_sinking
  if stage = 4 then gosub boss4_sinking
  if stage = 5 then gosub boss5_sinking
  if stage = 6 then gosub boss6_sinking
  if btl < 240 then gosub boss_place : return
  for k = 0 to 10 : etype[k] = 0 : next
  bstate = 5 : btl = 0
  gosub results_start
  return
boss_boom
  temp7 = bx - 20 + (rand & 31) : temp8 = by - 24 + (rand & 31)
  gosub spawn_fx
  asm
  lda #SFX_BIGBOOM
  jsr sfx_play
end
  return

  rem How much of the boss was destroyed (%): the weights of the parts
  rem that are gone (the core's 30 is added when it falls). A part's slot
  rem is empty, a wreck, or holds something else once the part is gone:
  rem a dart, an escort or a falling slab can take a freed slot (a live
  rem part never gives up its own).
boss_tally
  bdestr = 0
  for k = 0 to 10
    temp1 = etype[k]
    if temp1 < ET_PART then bdestr = bdestr + bwt[k]
    if temp1 = ET_PWRECK then bdestr = bdestr + bwt[k]
  next
  return

  rem ======================================================================
  rem  The results (MegaGammaForce's): the stage, how much of the boss was
  rem  destroyed, the longest chain, and a bonus (100 a percent, 10,000
  rem  more for all of it) counted into the score. Then fire starts the
  rem  next stage. The scroll stands still meanwhile, for the text.
  rem ======================================================================
results_start
  bmsg = 0 : bready = 0 : bth = 0
  rem the bonus, in hundreds: 100 a percent destroyed, 100 a link of the
  rem longest chain (8: 800), and 10,000 more for all of it; added to the
  rem score at once (the BONUS line flashes)
  bbonus = bdestr + chmax
  bperf = 0
  if bdestr >= 100 then bperf = 1
  for k = 0 to 59 : rtline[k] = restmpl[k] : next
  temp1 = bdestr : temp5 = 12 : gosub put3
  temp1 = chmax : temp5 = 33 : gosub put3
  gosub results_bonus
  temp1 = bbonus : temp2 = bperf : temp3 = 0
  if temp1 >= 100 then temp1 = temp1 - 100 : temp2 = temp2 + 1
results_bcd
  if temp1 >= 10 then temp1 = temp1 - 10 : temp3 = temp3 + 1 : goto results_bcd
  sadd2 = temp2 : sadd1 = temp3 * 16 + temp1 : sadd0 = 0
  asm
  jsr score_add
end
  pfspeed = 0
  asm
  jsr mus_stop
  lda #SFX_HYPER
  jsr sfx_play
end
  return

  rem the bonus, in hundreds: "xxx00" (the perfect 100 on the first digit)
results_bonus
  temp1 = bbonus : temp5 = 51
  gosub put3
  rtline[51] = rtline[51] + bperf * 2
  rtline[54] = CH_0 : rtline[55] = CH_0
  return
  rem 3 digits of temp1 into rtline from temp5
put3
  temp2 = 0 : temp3 = 0
put3_h
  if temp1 >= 100 then temp1 = temp1 - 100 : temp2 = temp2 + 1 : goto put3_h
put3_t
  if temp1 >= 10 then temp1 = temp1 - 10 : temp3 = temp3 + 1 : goto put3_t
  rtline[temp5] = CH_0 + temp2 * 2 : temp5 = temp5 + 1
  rtline[temp5] = CH_0 + temp3 * 2 : temp5 = temp5 + 1
  rtline[temp5] = CH_0 + temp1 * 2
  return

boss_clear
  btl = btl + 1
  if btl = 0 then bth = bth + 1
boss_clear_wait
  rem (a second first, so a press meant for the fight doesn't skip it)
  if btl < 60 && bth = 0 then return
  rem a fresh press of fire (released first) goes on
  temp3 = 0
  if joy0fire0 then temp3 = 1
  if joy0fire1 then temp3 = 1
  if temp3 = 0 then bready = 1 : return
  if bready = 0 then return
  rem on to the next stage (after the last, round again)
  bstate = 0 : wn = 0 : gn = 0 : chmax = 0
  stage = stage + 1 : smsg = 180
  if stage > NSTAGES then stage = 1
  asm
  lda #160
  sta pfspeed
  lda #0
  sta pfstartrow
  lda stage
  jsr pf_newstage
  lda stg_song
  jsr mus_play
end
  return

results_text
  tpal = 3 : tzone = 3 : temp1 = TXT_NAME1 + stage - 1 : gosub text
  tpal = 6 : temp1 = TXT_CLEAR
  if bescape then temp1 = TXT_ESCAPED : tpal = 4
  tzone = 4 : gosub text
  tpal = 3 : tzone = 6 : temp1 = TXT_RESA : gosub text
  tzone = 7 : temp1 = TXT_RESB : gosub text
  rem the bonus's figure flashes: spaces every other 8 frames (the line is
  rem RAM; hiding the whole line off the screen needs 12 characters or
  rem fewer)
  temp2 = tick & 8
  if temp2 then for k = 51 to 55 : rtline[k] = CH_SPACE : next
  if temp2 = 0 then gosub results_bonus
  tpal = 6 : tzone = 8 : temp1 = TXT_RESC : gosub text
  if bdestr >= 100 then tpal = 7 : tzone = 10 : temp1 = TXT_PERFECT : gosub text
  rem PRESS FIRE blinks after a second. Hidden (tpal + 128: off the
  rem screen), not left out, so the zone's display list keeps its shape.
  tpal = 7 + 128
  temp2 = tick & 32
  if temp2 then tpal = 7
  if btl < 60 && bth = 0 then tpal = 7 + 128
  tzone = 12 : temp1 = TXT_PUSH : gosub text
  return

  rem ======================================================================
  rem  HUD: score (0-6), the chain's gems (sprites, x 58-78) and level
  rem  (10-11), the sword gauge (sprites, x 100-139), lives (a fighter
  rem  sprite at x 144, the count at 19). The sprites: asm/objects.asm
  rem  hud_sprites. Messages (WARNING, STAGE n, GAMEOVER) take 12-19.
  rem ======================================================================
  rem One part of the HUD text a frame, so no frame pays for all of it.
hud
  temp1 = pfdraws & 3
  if temp1 = 1 then goto hud_chain
  if temp1 = 2 then goto hud_middle
  if temp1 = 3 then goto hud_lives
  asm
  jsr hud_score
end
  return
hud_chain
  hudtext[7] = CH_SPACE : hudtext[8] = CH_SPACE : hudtext[9] = CH_SPACE
  temp1 = chlevel : temp2 = 0
hud_tens
  if temp1 >= 10 then temp1 = temp1 - 10 : temp2 = temp2 + 1 : goto hud_tens
  if temp2 > 9 then temp2 = 9
  hudtext[10] = FONTBASE + temp2 * 2
  hudtext[11] = FONTBASE + temp1 * 2
  rem (GAMEOVER takes 12-19: a space before it)
  if overt > 0 then hudtext[10] = CH_SPACE : hudtext[11] = CH_SPACE
  return
hud_middle
  if overt > 0 then goto hud_over
  if bmsg = 1 then goto hud_warning
  if smsg > 0 then goto hud_stage
  rem (under the gauge's sprites)
  for k = 12 to 17 : hudtext[k] = CH_SPACE : next
  return
  rem (the sprites, every fourth frame too: they stay in the DL between)
hud_lives
  asm
  jsr hud_sprites
end
  if overt > 0 then return
  if bmsg > 0 then return
  if smsg > 0 then return
  hudtext[18] = CH_SPACE
  hudtext[19] = FONTBASE + lives * 2
  return
  rem (WARNING and STAGE n at 13-19, a space after the chain's level)
hud_warning
  temp6 = tick & 16
  for k = 0 to 6
    temp5 = 13 + k
    temp4 = hudwarn[k]
    if temp6 then temp4 = CH_SPACE
    hudtext[temp5] = temp4
  next
  hudtext[12] = CH_SPACE
  return
hud_stage
  if smsg > 4 then smsg = smsg - 4 else smsg = 0
  for k = 0 to 5
    temp5 = 13 + k
    hudtext[temp5] = hudstage[k]
  next
  hudtext[12] = CH_SPACE
  hudtext[19] = FONTBASE + stage * 2
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
  inc pfvbl
  lda fadeon              ; stage 6's fade (stage6.bas)
  beq ui_nofade
  lda fadebg
  sta BACKGRND
  lda fadep1
  sta P1C1
  lda fadep1+1
  sta P1C2
  lda fadep1+2
  sta P1C3
ui_nofade
  ifnconst PROFILE
  lda #255                ; the RIOT timer: time since this NMI (pf_early)
  sta T1024T
  endif
  lda bgwant
  beq ui_bg
  sta BACKGRND
ui_bg
  jmp mus_tick
end

  rem ---- per enemy type: hit points, score (hundreds, BCD), image ----
  rem hit points: the Vulcan does 3 a bolt pair, the sword 4 a strike
  data enemy_hp
  0, 2, 8, 10, 60, 16, 9, 20, 255, 30, 60
end
  data enemy_score1
  0, $01, $02, $03, $20, $03, $01, $04, 0, $15, $08
end
  data enemy_img
  0, IMG_DART, IMG_SAUCER, IMG_DRONE, IMG_GUNSHIP, IMG_TURRET, IMG_WASP, IMG_TANK, IMG_TOWER, IMG_GUNBOAT, IMG_TRAIN
end

  rem Assembly files are copied flat into the build directory (tools/build.sh).
  inline engine.asm
  inline objects.asm
  inline data.asm
  inline music.asm
  inline musiccommon.asm
  inline sfx.asm

  rem ======================================================================
  rem  Bank 2: stage 1 (map, waves, music, the GAMMA CORE's code; and the
  rem  title's song: the title shows with stage 1's bank in).
  rem  Switched in for the whole stage.
  rem ======================================================================
  bank 2
  rem the stage header must come first: it is read at $8000
  inline stage1.asm
  inline musicdata.asm
  incbasic boss1.bas

  rem ======================================================================
  rem  Bank 3: stage 2 (map, waves, music, and its graphics block at $A000)
  rem ======================================================================
  bank 3
  rem the stage header must come first: it is read at $8000
  inline stage2.asm
  inline musicdata2b.asm
  incbasic boss2.bas
  incbasic gen/gfx2.bas
  dmahole 0
  inline musicdata2.asm

  rem ======================================================================
  rem  Bank 4: stage 3 (map, waves, music, LEVIATHAN's code, its graphics
  rem  block at $A000)
  rem ======================================================================
  bank 4
  rem the stage header must come first: it is read at $8000
  inline stage3.asm
  inline musicdata3b.asm
  incbasic boss3.bas
  incbasic gen/gfx3.bas
  dmahole 0
  inline musicdata3.asm
  incbasic boss3data.bas

  rem ======================================================================
  rem  Bank 5: stage 4 (map, waves, the boss's song and path; its graphics
  rem  block at $A000; the stage's song and DUNE WYRM's code after it)
  rem ======================================================================
  bank 5
  rem the stage header must come first: it is read at $8000
  inline stage4.asm
  inline musicdata4b.asm
  inline boss4tab.asm
  incbasic boss4b.bas
  incbasic gen/gfx4.bas
  dmahole 0
  inline musicdata4.asm
  incbasic boss4.bas

  rem ======================================================================
  rem  Bank 6: stage 5 (map, the stage song's drums, the boss's song,
  rem  GLACIER CRAWLER's code and tables; its graphics block at $A000; the
  rem  rest of the stage's song after it)
  rem ======================================================================
  bank 6
  rem the stage header must come first: it is read at $8000
  inline stage5.asm
  inline musicdata5c.asm
  inline musicdata5b.asm
  incbasic stage5.bas
  incbasic gen/gfx5.bas
  dmahole 0
  inline musicdata5.asm
  inline boss5tab.asm
  incbasic boss5.bas

  rem ======================================================================
  rem  Bank 7: stage 6 (map, waves, the fade, HALO STATION's code and
  rem  tables, its graphics block at $A000, music)
  rem ======================================================================
  bank 7
  rem the stage header must come first: it is read at $8000
  inline stage6.asm
  inline boss6tab.asm
  incbasic stage6.bas
  incbasic boss6.bas
  incbasic gen/gfx6.bas
  inline musicdata6b.asm
  dmahole 0
  inline musicdata6.asm

  rem ======================================================================
  rem  The last bank: graphics (MARIA reads them from here at any time)
  rem ======================================================================
  bank 9
  incbasic gen/gfx.bas
