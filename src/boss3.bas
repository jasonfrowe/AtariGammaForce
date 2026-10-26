  rem ======================================================================
  rem  LEVIATHAN, the stage 3 boss (MegaGammaForce's boss3.c): a battleship
  rem  sailing bow first down the screen. Its hull is part of the map (map
  rem  rows after the stage's last open sea), so it costs no sprites: the
  rem  boss moves it by the scroll (the open sea is the background color and
  rem  shows no movement): in at the stage's speed, then a crawl while the
  rem  fight goes on, a stop once the reactor at its stern is in reach, and
  rem  on again to carry it away as it sinks. Its parts are sprites pinned
  rem  to map rows, as ground units are (gen/boss3tab.asm).
  rem  Slots: 0-1 the main guns, 2-3 the bridge (top; bottom, which passes
  rem  its hits to the top), 5 the reactor (the core), 7-10 deck turrets.
  rem  It lives in stage 3's bank; the shared boss code calls it.
  rem ======================================================================

boss3_build
  for k = 0 to 10
    etype[k] = boss3_type[k] : eimg[k] = boss3_img[k] : ehp[k] = boss3_hp[k]
    bwt[k] = boss3_wt[k] : eparam[k] = 0
  next
  rem (bx, by: where it burns as it sinks)
  bcorehp = 250 : bx = 80 : by = 120
  return

  rem Each part's line from the scroll: spos + 240 - its top's world height
  rem (16 bits); off the screen, it waits off to the right
boss3_place
  asm
  ldx #10
b3p_loop
  lda etype,x
  cmp #ET_PART
  bcc b3p_next            ; (not a part: a dart from the bays)
  clc
  lda spos_lo
  adc #240
  sta temp1
  lda spos_hi
  adc #0
  sta temp2
  sec
  lda temp1
  sbc b3_ylo,x
  sta temp1
  lda temp2
  sbc b3_yhi,x
  bne b3p_off
  lda temp1
  cmp #250
  bcs b3p_off
  sta eyh,x
  lda b3_x,x
  sta exh,x
  jmp b3p_next
b3p_off
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b3p_next
  dex
  bpl b3p_loop
end
  rem the reactor pulses
  eframe[5] = (tick / 8) & 1
  return

  rem In at the stage's speed until the hull's middle is near the top
boss3_enter
  gosub boss3_place
  asm
  lda spos_lo
  cmp #<B3_FIGHT
  lda spos_hi
  sbc #>B3_FIGHT
  bcc b3e_wait
  lda #3
  sta bstate
  lda #14                 ; the crawl: 14/256 of a line a frame
  sta pfspeed
b3e_wait
end
  return

boss3_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  rem it stops with the reactor in reach
  asm
  lda spos_lo
  cmp #<B3_FINAL
  lda spos_hi
  sbc #>B3_FINAL
  bcc b3f_crawl
  lda #0
  sta pfspeed
b3f_crawl
end
  gosub boss3_place
  rem two minutes, and it sails away
  if bth >= 30 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 0 : pfspeed = 250 : return
  if plvuln = 0 then return
  gosub boss3_attack
  return

boss3_attack
  rem main guns: turn to the player, and slow fans of four blue
  for k = 0 to 1
    if etype[k] <> ET_PCANNON then goto b3_gun_next
    if eyh[k] = 0 then goto b3_gun_next
    fx = exh[k] + 6 : fy = eyh[k] + 8
    gosub aim
    eframe[k] = (fang - 48) / 32 & 7
    temp1 = (btl + k * 64) & 127
    if temp1 then goto b3_gun_next
    fkind = BK_BLUE : fspd = 42 : fcount = 4 : fstep = 14
    asm
    jsr bul_fan
end
b3_gun_next
  next
  rem deck turrets (aimed by the shared code): aimed blue, staggered
  for k = 7 to 10
    if etype[k] = 0 then goto b3_tur_next
    if eyh[k] = 0 then goto b3_tur_next
    temp1 = (btl + k * 17) & 127
    if temp1 then goto b3_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 8
    gosub aim
    fkind = BK_BLUE : fspd = 50
    asm
    jsr bul_fire
end
b3_tur_next
  next
  rem bridge: wide pink sprays, there for the sword
  temp1 = btl & 127
  if temp1 <> 62 then goto b3_bays
  if etype[2] <> ET_PWING then goto b3_bays
  if eyh[3] = 0 then goto b3_bays
  fx = exh[3] + 14 : fy = eyh[3] + 24 : fang = 64
  fkind = BK_PINK : fspd = 44 : fcount = 5 : fstep = 12
  asm
  jsr bul_fan
end
b3_bays
  rem the missile bays: a pair of darts from each, by turns
  if btl = 100 then temp2 = 0 : gosub b3_bay
  if btl = 112 then temp2 = 0 : gosub b3_bay
  if btl = 228 then temp2 = 1 : gosub b3_bay
  if btl = 240 then temp2 = 1 : gosub b3_bay
  rem reactor: spirals once the bridge falls, time drags on, or it is hurt
  temp3 = 0
  if etype[2] <> ET_PWING then temp3 = 1
  if bth >= 12 then temp3 = 1
  if bcorehp < 125 then temp3 = 1
  if temp3 = 0 then return
  if eyh[5] = 0 then return
  temp1 = btl & 7
  if bcorehp < 125 then temp1 = btl & 3
  if temp1 then return
  fx = exh[5] + 6 : fy = eyh[5] + 14 : fang = bspin : fspd = 38 : fkind = BK_PINK
  temp1 = btl & 16
  if temp1 then fkind = BK_BLUE
  asm
  jsr bul_fire
end
  fang = bspin + 128 : fkind = BK_BLUE
  asm
  jsr bul_fire
end
  bspin = bspin + 11
  return

  rem A dart from bay temp2, if the bay is on the screen (its line as in
  rem boss3_place), into a free enemy slot
b3_bay
  asm
  ldx temp2
  clc
  lda spos_lo
  adc #240
  sta temp6
  lda spos_hi
  adc #0
  sta temp5
  sec
  lda temp6
  sbc b3_bayylo,x
  sta temp6
  lda temp5
  sbc b3_bayyhi,x
  sta temp5
end
  if temp5 then return
  if temp6 < 40 then return
  if temp6 > 180 then return
  for k = 0 to NE1
    if etype[k] = 0 then goto b3_bay_slot
  next
  return
b3_bay_slot
  etype[k] = ET_DART : ecol[k] = 4 + temp2 : eimg[k] = IMG_DART : ehp[k] = 2
  temp1 = b3_bayx[temp2]
  exh[k] = temp1 : ebase[k] = temp1 : exl[k] = 128 : eyh[k] = temp6 : eyl[k] = 0
  rem it dives to a line below the bay, then turns on the player
  eparam[k] = temp6 + 30
  evx[k] = 0 : evy[k] = 0 : estate[k] = 0 : etimer[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  ewamp[k] = 0 : ewang[k] = 0 : ewstep[k] = 3 : eframe[k] = 0
  return


  rem It burns on until its stern has sunk away below the screen
boss3_sinking
  if btl < 230 then return
  asm
  lda spos_lo
  cmp #<B3_GONE
  lda spos_hi
  sbc #>B3_GONE
  bcs b3s_gone
  lda #230
  sta btl
b3s_gone
end
  return
