  rem ======================================================================
  rem  GLACIER CRAWLER, the stage 5 boss (MegaGammaForce's boss5.c): a
  rem  tracked fortress grinding up the ice. Its hull is part of the map, as
  rem  LEVIATHAN's is (map rows after the stage's last bare ice), so it costs
  rem  no sprites: the scroll brings it in and stops with it at the top of
  rem  the screen (the bare ice shows no movement), and its treads run (two
  rem  colors of palette 2 swapped to and fro). Its parts are sprites pinned
  rem  to map rows (gen/boss5tab.asm). Slots: 0-1 the guns, 2 the ice drill
  rem  at its front, 4 and 6 the launch hatches (LEVIATHAN's bays: shut,
  rem  open, a crater), 5 the cryo reactor (the core), 7-10 turrets (the
  rem  ground turret, red). The drill, the hatches and the reactor are one
  rem  behind the other up its middle: shots stop at the first. Beaten, it
  rem  breaks through the ice: the scroll carries it away.
  rem  It lives in stage 5's bank; the shared boss code calls it.
  rem ======================================================================

boss5_build
  for k = 0 to 10
    etype[k] = boss5_type[k] : eimg[k] = boss5_img[k] : ehp[k] = boss5_hp[k]
    bwt[k] = boss5_wt[k] : eparam[k] = 0
  next
  for k = 7 to 10 : ecol[k] = 4 : next
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
  rem the reactor pulses, the drill turns
  eframe[5] = (tick / 8) & 1
  if etype[2] = ET_PCANNON then eframe[2] = (tick / 4) & 1
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
  rem the treads run while it moves: palette 2's first two colors swapped
  rem every 4 frames (the stage's colors are in its header, stg_pal)
  if bstate >= 4 && btl >= 8 then return
  temp1 = tick & 4
  if temp1 then P2C1 = stg_pal[7] : P2C2 = stg_pal[6] : return
  P2C1 = stg_pal[6] : P2C2 = stg_pal[7]
  return

  rem In at the stage's speed, slowing, until its top is at line 6
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
  gosub boss5_place
  rem 100 seconds, and it grinds on past the ship
  if bth >= 23 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 0 : pfspeed = 250 : return
  if plvuln = 0 then return
  gosub boss5_attack
  return

boss5_attack
  rem guns: turn to the player, and fans of five blue by turns
  for k = 0 to 1
    if etype[k] <> ET_PCANNON then goto b5_gun_next
    fx = exh[k] + 6 : fy = eyh[k] + 8
    gosub aim
    eframe[k] = (fang - 48) / 32 & 7
    temp1 = (btl + k * 64) & 127
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
    temp1 = (btl + k * 22) & 127
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
  rem the reactor: a pink ring once the drill is gone, a blue one late in
  rem the fight, and a two-armed spiral once it is hurt
  temp1 = btl & 127
  fx = exh[5] + 6 : fy = eyh[5] + 14
  if temp1 = 20 && etype[2] <> ET_PCANNON then fang = bspin : fkind = BK_PINK : fspd = 30 : fcount = 8 : fstep = 32 : gosub b5_fan
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

  rem A dart from hatch temp2 (slot 4 or 6, while it stands) into a free
  rem enemy slot; it dives to a line below the hatch, then turns on the ship
b5_hatch
  temp1 = temp2 * 2 + 4
  if etype[temp1] <> ET_PCANNON then return
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
  ET_PCANNON, ET_PCANNON, ET_PCANNON, 0, ET_PCANNON, ET_PCORE, ET_PCANNON, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET
end
  data boss5_img
  IMG_B5GUN, IMG_B5GUN, IMG_B5DRILL, 0, IMG_B3BAY, IMG_B5REACTOR, IMG_B3BAY, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET
end
  data boss5_hp
  150, 150, 200, 0, 110, 255, 110, 60, 60, 60, 60
end
  data boss5_wt
  10, 10, 18, 0, 4, 0, 4, 6, 6, 6, 6
end
