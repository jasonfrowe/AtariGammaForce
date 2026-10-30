  rem ======================================================================
  rem  GLACIER CRAWLER, the stage 5 boss (MegaGammaForce's boss5.c): a
  rem  tracked fortress grinding up the ice. Its hull is part of the map, as
  rem  LEVIATHAN's is (map rows after the stage's last bare ice), so it costs
  rem  no sprites, and the boss moves it by the scroll (the bare ice shows
  rem  no movement); its treads run (two colors of palette 2 swapped to and
  rem  fro). Its parts are sprites pinned to map rows (gen/boss5tab.asm).
  rem  The fight, as LEVIATHAN's: it stops with its front half in view (the
  rem  drill, two turrets, the hatches and guns, the command bridge at the
  rem  top). Once the bridge falls it drives on, its front off the bottom of
  rem  the screen, spraying bullets while shelves of ice fall; then it stops
  rem  with the cryo reactor at its rear in reach, and shelves keep falling.
  rem  Slots: 0-1 the guns, 2 the ice drill, 3 the bridge, 4 and 6 the
  rem  launch hatches (LEVIATHAN's bays: shut, open, a crater), 5 the
  rem  reactor (the core), 7-8 the rear turrets, 9-10 the front ones (the
  rem  ground turret, red). The drill, the hatches, the bridge and the
  rem  reactor are one behind the other up its middle: shots stop at the
  rem  first. Beaten, it breaks through the ice: the scroll carries it away.
  rem  It lives in stage 5's bank; the shared boss code calls it.
  rem ======================================================================

  rem the fight's phase: 0 its front half, 1 driving on, 2 the reactor
  rem (stage 2's orbit variable: free here)
  dim b5phase = $235C

boss5_build
  for k = 0 to 10
    etype[k] = boss5_type[k] : eimg[k] = boss5_img[k] : ehp[k] = boss5_hp[k]
    bwt[k] = boss5_wt[k] : eparam[k] = 0
  next
  for k = 7 to 10 : ecol[k] = 4 : next
  b5phase = 0
  rem (bx, by: where it burns as it sinks)
  bcorehp = 250 : bx = 80 : by = 100
  return

  rem Each part's line from the scroll: spos + 240 - its top's world height
  rem (16 bits); off the screen, it waits off to the right
boss5_place
  asm
  ldx #10
b5p_loop
  lda etype,x
  cmp #ET_PART
  bcc b5p_next            ; (not a part: a dart from the hatches)
  clc
  lda spos_lo
  adc #240
  sta temp1
  lda spos_hi
  adc #0
  sta temp2
  sec
  lda temp1
  sbc b5_ylo,x
  sta temp1
  lda temp2
  sbc b5_yhi,x
  bne b5p_off
  lda temp1
  cmp #250
  bcs b5p_off
  sta eyh,x
  lda b5_x,x
  sta exh,x
  jmp b5p_next
b5p_off
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b5p_next
  dex
  bpl b5p_loop
end
  rem the reactor pulses; the drill shudders as it turns
  eframe[5] = (tick / 8) & 1
  temp1 = (tick / 2) & 1
  if etype[2] = ET_PCANNON && eyh[2] > 0 then exh[2] = exh[2] + temp1
  rem the hatches: open while they launch (btl 88-127 the left, 216-255
  rem the right), a crater once destroyed
  temp1 = btl & 127
  temp2 = 0
  if temp1 >= 88 then temp2 = 1
  temp3 = btl & 128
  temp4 = 0 : temp5 = 0
  if temp3 then temp5 = temp2 else temp4 = temp2
  if etype[4] = ET_PWRECK then temp4 = 2
  if etype[6] = ET_PWRECK then temp5 = 2
  eframe[4] = temp4 : eframe[6] = temp5
  rem the treads run: palette 2's first two colors swapped every 4 frames
  rem (the stage's colors are in its header, stg_pal); still once it burns
  if bstate >= 4 && btl >= 8 then return
  temp1 = tick & 4
  if temp1 then P2C1 = stg_pal[7] : P2C2 = stg_pal[6] : return
  P2C1 = stg_pal[6] : P2C2 = stg_pal[7]
  return

  rem In at the stage's speed, slowing, until its front half is in view
boss5_enter
  gosub boss5_place
  asm
  lda spos_lo
  cmp #<(B5_STOP-48)
  lda spos_hi
  sbc #>(B5_STOP-48)
  bcc b5e_wait
  lda #48                 ; the last 3 rows: slower
  sta pfspeed
  lda spos_lo
  cmp #<B5_STOP
  lda spos_hi
  sbc #>B5_STOP
  bcc b5e_wait
  lda #3
  sta bstate
  lda #0
  sta pfspeed
b5e_wait
end
  return

boss5_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  rem the bridge is down: it drives on (a quarter of a line a frame), and
  rem a shelf of ice breaks away behind it: six slabs falling
  if b5phase = 0 && etype[3] <> ET_PCANNON then b5phase = 1 : pfspeed = 64 : temp3 = 6 : gosub b5_shelves
  if b5phase = 1 then gosub b5_drive
  rem at the reactor, more slabs every 4 seconds or so
  if b5phase = 2 && btl = 0 then temp3 = 3 : gosub b5_shelves
  gosub boss5_place
  rem 100 seconds, and it grinds on past the ship
  if bth >= 23 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 0 : pfspeed = 250 : return
  if plvuln = 0 then return
  gosub boss5_attack
  return

  rem Driving on until the reactor is in reach
b5_drive
  asm
  lda spos_lo
  cmp #<B5_FINAL
  lda spos_hi
  sbc #>B5_FINAL
  bcc b5d_on
  lda #0
  sta pfspeed
  lda #2
  sta b5phase
b5d_on
end
  return

  rem temp3 slabs of shelf ice falling, one every 36 frames, x by 88s from
  rem 16 (wrapping within 0-127): a spawner, as the stage's waves use
  rem (gammaforce.bas spawn_slot)
b5_shelves
  for j = 0 to NSP1
    if spcount[j] = 0 then goto b5_shelves_go
  next
  return
b5_shelves_go
  sptype[j] = ET_TOWER : sppal[j] = 1 : spx[j] = 16 + (btl & 32) : spdx[j] = 88
  spcount[j] = temp3 : spgap[j] = 36 : spparam[j] = 200 : sptimer[j] = 0
  return

boss5_attack
  rem as it drives on, its guns and turrets fire four times as often
  temp9 = 127
  if b5phase = 1 then temp9 = 31
  rem guns: turn to the player, and fans of five blue by turns
  for k = 0 to 1
    if etype[k] <> ET_PCANNON then goto b5_gun_next
    if eyh[k] = 0 then goto b5_gun_next
    fx = exh[k] + 6 : fy = eyh[k] + 8
    gosub aim
    eframe[k] = (fang - 48) / 32 & 7
    temp1 = (btl + k * 16) & temp9
    if temp1 then goto b5_gun_next
    fkind = BK_BLUE : fspd = 36 : fcount = 5 : fstep = 12
    asm
    jsr bul_fan
end
b5_gun_next
  next
  rem turrets (aimed by the shared code): aimed blue, staggered
  for k = 7 to 10
    if etype[k] = 0 then goto b5_tur_next
    if eyh[k] = 0 then goto b5_tur_next
    temp1 = (btl + k * 22) & temp9
    if temp1 then goto b5_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 8
    gosub aim
    fkind = BK_BLUE : fspd = 44
    asm
    jsr bul_fire
end
b5_tur_next
  next
  rem the drill: a spray of seven pink straight down, there for the sword
  temp1 = btl & 127
  if temp1 <> 50 then goto b5_hatches
  if etype[2] <> ET_PCANNON then goto b5_hatches
  if eyh[2] = 0 then goto b5_hatches
  fx = exh[2] + 6 : fy = eyh[2] + 30 : fang = 64
  fkind = BK_PINK : fspd = 34 : fcount = 7 : fstep = 10
  asm
  jsr bul_fan
end
b5_hatches
  rem the hatches: a pair of darts from each, by turns
  if btl = 100 then temp2 = 0 : gosub b5_hatch
  if btl = 112 then temp2 = 0 : gosub b5_hatch
  if btl = 228 then temp2 = 1 : gosub b5_hatch
  if btl = 240 then temp2 = 1 : gosub b5_hatch
  rem the bridge: an aimed blue three now and then
  temp1 = btl & 63
  if temp1 <> 24 then goto b5_reactor
  if etype[3] <> ET_PCANNON then goto b5_reactor
  if eyh[3] = 0 then goto b5_reactor
  fx = exh[3] + 6 : fy = eyh[3] + 28
  gosub aim
  fkind = BK_BLUE : fspd = 40 : fcount = 3 : fstep = 16 : gosub b5_fan
b5_reactor
  rem the reactor, once in view: a pink ring, a blue one late in the
  rem fight, and a two-armed spiral once it is hurt
  if eyh[5] = 0 then return
  temp1 = btl & 127
  fx = exh[5] + 6 : fy = eyh[5] + 14
  if temp1 = 20 then fang = bspin : fkind = BK_PINK : fspd = 30 : fcount = 8 : fstep = 32 : gosub b5_fan
  if temp1 = 84 && bth >= 12 then fang = bspin + 16 : fkind = BK_BLUE : fspd = 30 : fcount = 8 : fstep = 32 : gosub b5_fan
  if bcorehp >= 125 then return
  temp1 = btl & 7
  if temp1 then return
  fang = bspin : fspd = 36 : fkind = BK_PINK
  asm
  jsr bul_fire
end
  fang = bspin + 128 : fkind = BK_BLUE
  asm
  jsr bul_fire
end
  bspin = bspin + 11
  return

b5_fan
  asm
  jsr bul_fan
end
  return

  rem A dart from hatch temp2 (slot 4 or 6, while it stands and is in view)
  rem into a free enemy slot; it dives to a line below the hatch, then
  rem turns on the ship
b5_hatch
  temp1 = temp2 * 2 + 4
  if etype[temp1] <> ET_PCANNON then return
  if eyh[temp1] = 0 then return
  if eyh[temp1] > 180 then return
  for k = 0 to NE1
    if etype[k] = 0 then goto b5_hatch_slot
  next
  return
b5_hatch_slot
  etype[k] = ET_DART : ecol[k] = 4 + temp2 : eimg[k] = IMG_DART : ehp[k] = 2
  temp6 = eyh[temp1] + 8
  exh[k] = exh[temp1] : ebase[k] = exh[temp1] : exl[k] = 128 : eyh[k] = temp6 : eyl[k] = 0
  eparam[k] = temp6 + 40
  evx[k] = 0 : evy[k] = 0 : estate[k] = 0 : etimer[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  ewamp[k] = 0 : ewang[k] = 0 : ewstep[k] = 3 : eframe[k] = 0
  return

  rem It burns on until it has gone below the screen
boss5_sinking
  if btl < 230 then return
  asm
  lda spos_lo
  cmp #<B5_GONE
  lda spos_hi
  sbc #>B5_GONE
  bcs b5s_gone
  lda #230
  sta btl
b5s_gone
end
  return

  rem ---- parts: type, image, hit points, share of the boss (%) ----
  rem (the reactor's 30 is counted apart; positions in gen/boss5tab.asm)
  data boss5_type
  ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCORE, ET_PCANNON, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET
end
  data boss5_img
  IMG_B5GUN, IMG_B5GUN, IMG_B5DRILL, IMG_B5BRIDGE, IMG_B3BAY, IMG_B5REACTOR, IMG_B3BAY, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET
end
  data boss5_hp
  150, 150, 180, 240, 110, 255, 110, 60, 60, 60, 60
end
  data boss5_wt
  8, 8, 12, 16, 4, 0, 4, 5, 5, 4, 4
end
