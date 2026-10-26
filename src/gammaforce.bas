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
  const NE = 12
  const NB = 12
  const NS = 6
  const NX = 4
  const NSP = 3
  rem 7800basic drops arithmetic in a for loop's limit ("to NE1" runs to
  rem NE), so loops use these.
  const NE1 = 11
  const NB1 = 11
  const NS1 = 5
  const NX1 = 3
  const NSP1 = 2

  rem Uncomment to time the main loop's sections (tools/profile.py).
  rem const PROFILE = 1
  rem Testing: start at the boss, and/or never get hit.
  rem const BOSSTEST = 1
  rem const CHEAT = 1

  rem ---- enemy types (as in MegaGammaForce's enemies.h) ----
  const ET_DART = 1
  const ET_SAUCER = 2
  const ET_DRONE = 3
  const ET_GUNSHIP = 4
  const ET_TURRET = 5
  rem boss parts: types from ET_PART up are placed by the boss code
  const ET_PART = 10
  const ET_PCANNON = 10
  const ET_PWING = 11
  const ET_PARMOR = 12
  const ET_PCORE = 13
  const ET_PTURRET = 14

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
  dim vxp = $2350
  dim sxp = $2351
  dim vlv = $2352
  dim slv = $2353
  dim swcd = $2354
  dim lvmsg = $2355
  dim anyhit = $2356
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
  rem Switch stage 1's bank (bank 2) in at $8000. 7800basic only allows
  rem loadrombank in the last bank; the hotspot value is the bank - 2.
  asm
  lda #0
  sta $8000
end
  asm
  jsr pf_init
end

  rem ======================================================================
  rem  Title screen: the sea stands still under the title
  rem ======================================================================
title
  asm
  lda #0
  sta pfspeed
  jsr pf_reset
end
  for i = 0 to NE1 : etype[i] = 0 : next
  for i = 0 to NB1 : bkind[i] = 0 : next
  for i = 0 to NS1 : shy[i] = 0 : next
  for i = 0 to NX1 : xt[i] = 0 : next
  temp9 = 30
  asm
  lda #SONG_TITLE
  jsr mus_play
end
title_loop
  asm
  jsr pf_frame
end
  tick = tick + 1
  tpal = 3
  tzone = 3 : temp1 = TXT_ATARI : gosub text
  tzone = 4 : temp1 = TXT_GAMMA : gosub text
  tpal = 7
  temp2 = tick & 32
  if temp2 then tzone = 7 : temp1 = TXT_PUSH : gosub text
  tpal = 3
  tzone = 9 : temp1 = TXT_B1 : gosub text
  tzone = 10 : temp1 = TXT_B2 : gosub text
  tpal = 6
  tzone = 12 : temp1 = TXT_DEMAKE : gosub text
  tzone = 13 : temp1 = TXT_CREDIT : gosub text
  asm
  jsr pf_drawscreen
end
  rem Start on a fresh press of either button (released first)
  temp3 = 0
  if joy0fire0 then temp3 = 1
  if joy0fire1 then temp3 = 1
  if temp3 = 0 && temp9 > 0 then temp9 = temp9 - 1
  if temp3 = 0 then goto title_loop
  if temp9 > 0 then goto title_loop
  asm
  lda #160
  sta pfspeed
  ifconst BOSSTEST
  lda #186
  sta pfstartrow
  endif
  jsr pf_reset
  lda #SONG_STAGE1
  jsr mus_play
end

  rem ======================================================================
newgame
  for i = 0 to 3 : score_bcd[i] = 0 : next
  lives = 3 : gauge = 0 : hyper = 0
  chlevel = 0 : chcount = 0 : chcolor = 255
  vdmg = 3 : wn = 0 : overt = 0 : bstate = 0 : bmsg = 0 : gn = 0 : gcolor = 0
  vxp = 0 : sxp = 0 : vlv = 0 : slv = 0 : swcd = 0 : lvmsg = 0
  for i = 0 to NE1 : etype[i] = 0 : next
  for i = 0 to NB1 : bkind[i] = 0 : next
  for i = 0 to NS1 : shy[i] = 0 : next
  for i = 0 to NX1 : xt[i] = 0 : next
  for i = 0 to NSP1 : spcount[i] = 0 : next
  phit = 0 : absorbed = 0
  asm
  ifconst BOSSTEST
  lda #WAVES
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
  tick = tick + 1

  if overt > 0 then gosub gameover_tick
  gosub player
  rem The ship and sword are plotted first, early in the frame, before
  rem MARIA reaches the bottom of the screen where they usually are.
  gosub draw_player
  asm
  ifconst PROFILE
  lda #1
  jsr prof_mark
  endif
end
  gosub waves
  gosub ground
  gosub boss
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

  if overt > 0 then tpal = 4 : tzone = 6 : temp1 = TXT_OVER : gosub text
  asm
  jsr pf_drawscreen
end
  if overt = 1 then goto title
  goto main

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
  if joy0right && plx < 143 then plx = plx + temp4
  if joy0up && ply > 40 then ply = ply - temp5
  if joy0down && ply < 214 then ply = ply + temp5
  bank = 0
  if joy0left then bank = 1
  if joy0right then bank = 2
  pcx = plx + 8 : pcy = ply + 12

  rem Vulcan (not while the sword is out)
  if firecd > 0 then firecd = firecd - 1
  if temp2 = 0 && temp1 = 1 then gosub fire_vulcan

  rem Radiant Sword: an arc above the ship that cuts and absorbs pink
  if temp2 = 0 then goto player_nosword
  swon = 1
  swx0 = pcx - 12 : swx1 = pcx + 12
  swy0 = pcy - 30 : swy1 = pcy - 4
  rem it strikes every 8 frames at level 1, every 4 at level 5, and harder
  if swcd > 0 then swcd = swcd - 1
  if swcd = 0 then swdmg = 3 + slv / 2 : swcd = 8 - slv
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
  asm
  ifconst CHEAT
  lda #0
  sta phit
  endif
end
  if phit then phit = 0 : gosub player_die
  return

player_dead
  phit = 0
  if overt > 0 then return
  pdead = pdead - 1
  if pdead > 0 then return
  if lives = 0 then overt = 240 : pfspeed = 0 : pdead = 255 : return
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
  shx[i] = plx + 6 : shy[i] = ply - 6 : firecd = 4
  rem the Vulcan, already the strongest, only speeds up at level 4
  if vlv >= 3 then firecd = 3
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
  temp3 = enemy_hp[temp1] / 4 + 1 : gosub weapon_xp
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

  rem Experience temp3 for the weapon that made the kill: the sword if it
  rem is out, else the Vulcan (which learns at half the rate). Levels at
  rem 25, 75, 150, 250 (MegaGammaForce's 50/150/300/500, halved to fit a byte).
weapon_xp
  if swon then goto weapon_xp_sword
  if vlv >= 4 then return
  temp3 = temp3 / 2 + 1
  temp4 = vxp + temp3
  if temp4 < vxp then temp4 = 255
  vxp = temp4
  if vxp < level_xp[vlv] then return
  vlv = vlv + 1 : goto weapon_xp_up
weapon_xp_sword
  if slv >= 4 then return
  temp4 = sxp + temp3
  if temp4 < sxp then temp4 = 255
  sxp = temp4
  if sxp < level_xp[slv] then return
  slv = slv + 1
weapon_xp_up
  lvmsg = 90
  asm
  lda #SFX_HYPER
  jsr sfx_play
end
  return

  data level_xp
  25, 75, 150, 250
end

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
  rem  Ground turrets: one on each big hatch of the fortress deck, spawned
  rem  as its row scrolls in (at most 4 at a time), riding the map
  rem ======================================================================
ground
  if gn >= GROUNDS then return
  temp1 = gn
  if spos_hi < gth[temp1] then return
  if spos_hi > gth[temp1] then goto ground_go
  if spos_lo < gtl[temp1] then return
ground_go
  gn = gn + 1
  temp2 = 0
  for k = 0 to NE1
    if etype[k] = ET_TURRET then temp2 = temp2 + 1
  next
  if temp2 >= 4 then return
  for k = 0 to NE1
    if etype[k] = 0 then goto ground_slot
  next
  return
ground_slot
  etype[k] = ET_TURRET : eimg[k] = IMG_TURRET : ehp[k] = 8
  exh[k] = gtx[temp1] : eparam[k] = gtbase[temp1]
  eyh[k] = spos_lo + gtbase[temp1]
  ecol[k] = 4 + gcolor : gcolor = gcolor + 1
  if gcolor > 2 then gcolor = 0
  etimer[k] = k * 26 : estate[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  evx[k] = 0 : evy[k] = 0 : ewamp[k] = 0 : eframe[k] = 0
  return


  rem ======================================================================
  rem  GAMMA CORE, the stage 1 boss (MegaGammaForce's boss1.c, thinned).
  rem  Eleven enemy slots: cannon, two wings (a hittable top half and an
  rem  armor bottom half each), the core (two halves sharing bcorehp), and
  rem  four turrets on the wings. bstate: 0 none, 1 warning, 2 entering,
  rem  3 fighting, 4 exploding, 5 stage clear.
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
  if wn < WAVES then return
  if spos_hi < 12 then return
  for k = 0 to NE1
    if etype[k] then return
  next
  bstate = 1 : btl = 0 : bth = 0
  asm
  lda #SONG_BOSS
  jsr mus_play
end
  return

boss_warning
  btl = btl + 1
  bmsg = 1
  if btl < 180 then return
  bmsg = 0
  rem build the boss above the screen
  bx = 80 : by = 0 : bspin = 0 : bcorehp = 225 : bparts = 0
  for k = 0 to 10
    etype[k] = boss_type[k] : eimg[k] = boss_img[k] : ehp[k] = boss_hp[k]
    ecol[k] = 0 : eflash[k] = 0 : ehit[k] = 0 : eframe[k] = 0
    evx[k] = 0 : evy[k] = 0 : ewamp[k] = 0
  next
  gosub boss_place
  bstate = 2 : btl = 0 : bth = 0
  return

boss_enter
  by = by + 1
  gosub boss_place
  if by < 89 then return
  bstate = 3
  return

boss_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  rem sway: x = 80 + 17 sin(t/2), y = 89 + 6 sin(t/4)
  wang = btl / 2 + 192 : wamp = 17
  asm
  jsr weave
end
  bx = 80 + woff
  wang = btl / 4 + 192 : wamp = 6
  asm
  jsr weave
end
  by = 89 + woff
  gosub boss_place
  rem 90 seconds and it escapes
  if bth >= 21 then bstate = 4 : btl = 200 : return
  if plvuln = 0 then return
  gosub boss_attack
  return

  rem Part k's position from the boss centre (bx, by): offset tables in
  rem MegaGammaForce pixels halved across (sprites are half width here)
boss_place
  for k = 0 to 10
    if etype[k] = 0 then goto boss_place_next
    exh[k] = bx + boss_dx[k]
    eyh[k] = by + boss_dy[k]
boss_place_next
  next
  rem the cannon glows before it fires
  eframe[0] = 0
  temp1 = btl & 255
  if temp1 >= 96 && temp1 < 128 then eframe[0] = (tick / 4) & 1
  rem turrets turn to face the player (8 directions)
  for k = 7 to 10
    if etype[k] = 0 then goto boss_turret_next
    fx = exh[k] + 4 : fy = eyh[k] + 8
    gosub aim
    eframe[k] = (fang - 48) / 32 & 7
boss_turret_next
  next
  return

boss_attack
  rem turrets: aimed blue shots, staggered
  for k = 7 to 10
    if etype[k] = 0 then goto boss_att_next
    temp1 = (btl + k * 17) & 63
    if temp1 then goto boss_att_next
    fx = exh[k] + 4 : fy = eyh[k] + 12
    gosub aim
    fkind = BK_BLUE : fspd = 52
    asm
    jsr bul_fire
end
boss_att_next
  next
  rem wings: pink fans, alternating sides
  temp1 = btl & 127
  if temp1 = 0 && etype[1] then fx = exh[1] + 8 : fy = eyh[1] + 56 : fang = 72 : gosub boss_fan
  if temp1 = 64 && etype[3] then fx = exh[3] + 8 : fy = eyh[3] + 56 : fang = 56 : gosub boss_fan
  rem cannon: three big pink orbs at the player. Absorb them!
  temp1 = btl & 255
  if temp1 = 128 && etype[0] then gosub boss_cannon
  rem core: spirals once a wing is gone, time drags on, or it is hurt
  temp2 = 0
  if etype[1] = 0 then temp2 = 1
  if etype[3] = 0 then temp2 = temp2 + 1
  temp3 = 0
  if bcorehp < 112 then temp3 = 1
  if temp2 = 0 && temp3 = 0 && bth < 6 then return
  temp1 = btl & 7
  if temp3 then temp1 = btl & 3
  if temp1 then return
  fx = bx + 2 : fy = by + 4 : fang = bspin : fspd = 42
  fkind = BK_PINK
  temp1 = btl & 16
  if temp1 then fkind = BK_BLUE
  asm
  jsr bul_fire
end
  if temp2 = 2 then fang = bspin + 128 : asm
  jsr bul_fire
end
  bspin = bspin + 11
  return

boss_fan
  fkind = BK_PINK : fspd = 49 : fcount = 3 : fstep = 12
  asm
  jsr bul_fan
end
  return

boss_cannon
  fx = exh[0] + 8 : fy = eyh[0] + 28
  gosub aim
  fkind = 3 : fspd = 38 : fcount = 3 : fstep = 18
  asm
  jsr bul_fan
  lda #SFX_HIT
  jsr sfx_play
end
  return

  rem Damage temp1 to boss part i
part_damage
  temp2 = etype[i]
  if temp2 = ET_PARMOR then return
  if bstate <> 3 then return
  eflash[i] = 3
  if temp2 = ET_PCORE then goto part_core
  if ehp[i] > temp1 then ehp[i] = ehp[i] - temp1 : return
  rem a part is destroyed: 2,000 points
  temp3 = boss_hp[i] / 4 + 1 : gosub weapon_xp
  temp7 = exh[i] : temp8 = eyh[i] : gosub spawn_fx
  etype[i] = 0 : bparts = bparts + 1
  sadd2 = 0 : sadd1 = $20 : sadd0 = 0
  asm
  jsr score_add
  lda #SFX_BIGBOOM
  jsr sfx_play
end
  rem a wing takes its armor and its turrets with it
  if i = 1 then etype[2] = 0 : etype[7] = 0 : etype[8] = 0
  if i = 3 then etype[4] = 0 : etype[9] = 0 : etype[10] = 0
  return
part_core
  eflash[5] = 3 : eflash[6] = 3
  rem the core is armored: half damage
  temp1 = temp1 / 2 + 1
  if bcorehp > temp1 then bcorehp = bcorehp - temp1 : return
  bcorehp = 0
  rem the core: 10,000, and 20,000 more for taking every other part first
  sadd2 = $01 : sadd1 = 0 : sadd0 = 0
  asm
  jsr score_add
end
  temp3 = 0
  for k = 0 to 4
    if etype[k] = ET_PCANNON || etype[k] = ET_PWING then temp3 = 1
  next
  if temp3 = 0 then sadd2 = $02 : sadd1 = 0 : sadd0 = 0 : gosub boss_bonus
  bstate = 4 : btl = 0
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
  if btl < 240 then gosub boss_place : return
  for k = 0 to 10 : etype[k] = 0 : next
  bstate = 5 : btl = 0
  return
boss_boom
  temp7 = bx - 20 + (rand & 31) : temp8 = by - 24 + (rand & 31)
  gosub spawn_fx
  asm
  lda #SFX_BIGBOOM
  jsr sfx_play
end
  return

  rem STAGE CLEAR in the HUD, then round again from the start
boss_clear
  btl = btl + 1
  bmsg = 2
  if btl < 240 then return
  bmsg = 0 : bstate = 0 : wn = 0 : gn = 0
  asm
  lda #0
  sta pfstartrow
  jsr pf_reset
  lda #SONG_STAGE1
  jsr mus_play
end
  return

  rem ---- boss parts: type, image, hit points, offset from the centre ----
  data boss_type
  ET_PCANNON, ET_PWING, ET_PARMOR, ET_PWING, ET_PARMOR, ET_PCORE, ET_PCORE, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET
end
  data boss_img
  IMG_BCANNON, IMG_BWINGLT, IMG_BWINGLB, IMG_BWINGRT, IMG_BWINGRB, IMG_BCORET, IMG_BCOREB, IMG_BTURRET, IMG_BTURRET, IMG_BTURRET, IMG_BTURRET
end
  data boss_hp
  150, 180, 255, 180, 255, 255, 255, 60, 60, 60, 60
end
  rem top-left x and y of each part relative to (bx, by), two's complement
  data boss_dx
  248, 224, 224, 16, 16, 240, 240, 228, 228, 20, 20
end
  data boss_dy
  28, 220, 252, 220, 252, 224, 0, 232, 254, 232, 254
end

  rem ======================================================================
  rem  HUD: score (0-6), chain (8-10), sword gauge (12-16), lives (18-19)
  rem ======================================================================
  rem One part of the HUD a frame, so no frame pays for all of it.
hud
  temp1 = tick & 3
  if temp1 = 1 then goto hud_chain
  if temp1 = 2 then goto hud_middle
  if temp1 = 3 then goto hud_lives
  asm
  jsr hud_score
end
  return
hud_chain
  hudtext[7] = CH_SPACE
  hudtext[8] = CH_X
  temp1 = chlevel : temp2 = 0
hud_tens
  if temp1 >= 10 then temp1 = temp1 - 10 : temp2 = temp2 + 1 : goto hud_tens
  if temp2 > 9 then temp2 = 9
  hudtext[9] = FONTBASE + temp2 * 2
  hudtext[10] = FONTBASE + temp1 * 2
  hudtext[11] = CH_SPACE
  return
hud_middle
  if overt > 0 then goto hud_over
  if bmsg = 1 then goto hud_warning
  if bmsg = 2 then goto hud_clear
  if lvmsg > 0 then goto hud_level
  if gauge >= GAUGE_MAX then goto hud_hyper
  temp3 = gauge / 8
  for k = 0 to 4
    temp4 = CH_SPACE
    if k < temp3 then temp4 = CH_I
    temp5 = 12 + k
    hudtext[temp5] = temp4
  next
  return
hud_hyper
  hudtext[12] = CH_H : hudtext[13] = CH_Y : hudtext[14] = CH_P
  hudtext[15] = CH_E : hudtext[16] = CH_R
  temp6 = tick & 8
  if temp6 = 0 then return
  for k = 12 to 16 : hudtext[k] = CH_SPACE : next
  return
hud_lives
  if overt > 0 then return
  if bmsg > 0 then return
  if lvmsg > 0 then return
  hudtext[17] = CH_SPACE
  hudtext[18] = CH_X
  hudtext[19] = FONTBASE + lives * 2
  return
hud_warning
  temp6 = tick & 16
  for k = 0 to 6
    temp5 = 12 + k
    temp4 = hudwarn[k]
    if temp6 then temp4 = CH_SPACE
    hudtext[temp5] = temp4
  next
  hudtext[19] = CH_SPACE
  return
hud_level
  if lvmsg > 4 then lvmsg = lvmsg - 4 else lvmsg = 0
  for k = 0 to 7
    temp5 = 12 + k
    hudtext[temp5] = hudlevel[k]
  next
  return
hud_clear
  for k = 0 to 7
    temp5 = 12 + k
    hudtext[temp5] = hudclear[k]
  next
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
  0, 2, 4, 10, 60, 8
end
  data enemy_score1
  0, $01, $02, $03, $20, $03
end
  data enemy_img
  0, IMG_DART, IMG_SAUCER, IMG_DRONE, IMG_GUNSHIP, IMG_TURRET
end

  rem Assembly files are copied flat into the build directory (tools/build.sh).
  inline engine.asm
  inline objects.asm
  inline data.asm
  inline music.asm
  inline musiccommon.asm
  inline sfx.asm

  rem ======================================================================
  rem  Bank 2: stage 1 (map, waves, music). Switched in for the whole stage.
  rem ======================================================================
  bank 2
  inline stage1.asm
  inline musicdata.asm

  rem ======================================================================
  rem  The last bank: graphics (MARIA reads them from here at any time)
  rem ======================================================================
  bank 9
  incbasic gen/gfx.bas
