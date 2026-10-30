  rem ======================================================================
  rem  HALO STATION, the stage 6 boss (MegaGammaForce's boss6.c): an
  rem  orbital ring station. Its ring is part of the map, as LEVIATHAN's and
  rem  the crawler's hulls are (map rows after the stage's open space), so
  rem  it costs no sprites, and the scroll brings it in and stops with it
  rem  near the top of the screen. Six turrets on the ring and the core in
  rem  the hub are sprites pinned to map rows (gen/boss6tab.asm); four gun
  rem  satellites orbit outside the ring, faster as they fall; the core
  rem  is shut while any of them orbits (gammaforce.bas part_core).
  rem  Slots: 0-3 the satellites, 5 the core, 4 and 6-10 the turrets.
  rem  Beaten (or gone), it drifts away below: the scroll carries it off.
  rem  It lives in stage 6's bank; the shared boss code calls it.
  rem ======================================================================

boss6_build
  for k = 0 to 10
    etype[k] = boss6_type[k] : eimg[k] = boss6_img[k] : ehp[k] = boss6_hp[k]
    bwt[k] = boss6_wt[k] : eparam[k] = 0 : ecol[k] = boss6_col[k]
  next
  rem (bx, by: where it burns, round the hub; boss6_place moves by)
  bcorehp = 250 : bx = 80 : by = 100 : borbit = 0
  return

  rem Each part's line from the scroll: spos + 240 - its top's world
  rem height (16 bits); off the screen, it waits off to the right. Then
  rem the satellites, round the orbit's centre (slots 0-3 hold it), a
  rem quarter turn apart, and turned a step further each frame for each
  rem one gone.
boss6_place
  asm
  ldx #10
b6p_loop
  lda etype,x
  cmp #ET_PART
  bcc b6p_next            ; (not a part)
  clc
  lda spos_lo
  adc #240
  sta temp1
  lda spos_hi
  adc #0
  sta temp2
  sec
  lda temp1
  sbc b6_ylo,x
  sta temp1
  lda temp2
  sbc b6_yhi,x
  bne b6p_off
  lda temp1
  cmp #250
  bcs b6p_off
  sta eyh,x
  lda b6_x,x
  sta exh,x
  jmp b6p_next
b6p_off
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b6p_next
  dex
  bpl b6p_loop
  ; the orbit: a step a frame, and one more for each satellite gone
  ldy #1
  ldx #3
b6p_dead
  lda etype,x
  bne b6p_alive
  iny
b6p_alive
  dex
  bpl b6p_dead
  lda bstate
  cmp #3
  bne b6p_still           ; (it turns only in the fight)
  tya
  clc
  adc borbit
  sta borbit
b6p_still
  ldx #3
b6p_sat
  lda etype,x
  cmp #ET_PPOD
  bne b6p_satnext
  lda eyh,x
  beq b6p_satnext         ; (the centre is off the screen: so is it)
  txa                     ; angle / 4: borbit / 4 + a quarter turn a slot
  asl
  asl
  asl
  asl
  sta temp1
  lda borbit
  lsr
  lsr
  clc
  adc temp1
  and #63
  tay
  lda exh,x
  clc
  adc b6_ox,y
  sta exh,x
  lda b6_oy,y
  bmi b6p_up
  clc
  adc eyh,x
  bcs b6p_satoff
  cmp #250
  bcs b6p_satoff
  sta eyh,x
  jmp b6p_satnext
b6p_up
  clc
  adc eyh,x
  bcc b6p_satoff          ; (above the top: off)
  sta eyh,x
  jmp b6p_satnext
b6p_satoff
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b6p_satnext
  dex
  bpl b6p_sat
end
  rem it burns round the hub (bx, by: the core's middle)
  if eyh[5] > 0 then by = eyh[5] - 16
  rem the core pulses; the satellites spin
  eframe[5] = (tick / 8) & 1
  temp1 = tick / 8
  for k = 0 to 3 : eframe[k] = (temp1 + k) & 1 : next
  rem the turrets turn to the ship, one a step
  temp1 = tick & 7
  if temp1 >= 6 then return
  k = boss6_tur[temp1]
  if etype[k] <> ET_PTURRET then return
  if eyh[k] = 0 then return
  fx = exh[k] + 4 : fy = eyh[k] + 8
  gosub aim
  eframe[k] = (fang - 48) / 32 & 7
  return

  rem In at the stage's speed, slowing, until the station is in view
boss6_enter
  gosub boss6_place
  asm
  lda spos_lo
  cmp #<(B6_STOP-48)
  lda spos_hi
  sbc #>(B6_STOP-48)
  bcc b6e_wait
  lda #48                 ; the last 3 rows: slower
  sta pfspeed
  lda spos_lo
  cmp #<B6_STOP
  lda spos_hi
  sbc #>B6_STOP
  bcc b6e_wait
  lda #3
  sta bstate
  lda #0
  sta pfspeed
b6e_wait
end
  return

boss6_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  gosub boss6_place
  rem 100 seconds, and it drifts away
  if bth >= 23 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 0 : pfspeed = 250 : return
  if plvuln = 0 then return
  gosub boss6_attack
  return

boss6_attack
  rem turrets: aimed blue, by turns (each every 128 frames)
  for k = 4 to 10
    if etype[k] <> ET_PTURRET then goto b6_tur_next
    if eyh[k] = 0 then goto b6_tur_next
    temp1 = (btl + boss6_tph[k]) & 127
    if temp1 then goto b6_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 8
    gosub aim
    fkind = BK_BLUE : fspd = 44
    asm
    jsr bul_fire
end
b6_tur_next
  next
  rem satellites: an aimed pink three, by turns (each every 128 frames)
  for k = 0 to 3
    if etype[k] <> ET_PPOD then goto b6_sat_next
    if eyh[k] = 0 then goto b6_sat_next
    temp1 = (btl + k * 32) & 127
    if temp1 <> 16 then goto b6_sat_next
    fx = exh[k] + 6 : fy = eyh[k] + 16
    gosub aim
    fkind = BK_PINK : fspd = 40 : fcount = 3 : fstep = 14 : gosub b6_fan
b6_sat_next
  next
  rem the core: a blue ring now and then, a pink one late in the fight,
  rem and once it is hurt a two-armed spray at the ship (as GLACIER
  rem CRAWLER's reactor: aimed, the arms swinging through 30 degrees)
  if eyh[5] = 0 then return
  fx = exh[5] + 6 : fy = eyh[5] + 14
  temp1 = btl & 127
  if temp1 = 72 then fang = bspin : fkind = BK_BLUE : fspd = 28 : fcount = 8 : fstep = 32 : gosub b6_fan : bspin = bspin + 16
  if temp1 = 8 && bth >= 12 then fang = bspin + 16 : fkind = BK_PINK : fspd = 34 : fcount = 8 : fstep = 32 : gosub b6_fan
  if bcorehp >= 125 then return
  temp1 = btl & 7
  if temp1 then return
  gosub aim
  wang = bspin : wamp = 11
  asm
  jsr weave
end
  fang = aimang + woff : fspd = 36 : fkind = BK_PINK
  asm
  jsr bul_fire
end
  fang = aimang - woff : fkind = BK_BLUE
  asm
  jsr bul_fire
end
  bspin = bspin + 16
  return

b6_fan
  asm
  jsr bul_fan
end
  return

  rem It burns on until it has drifted below the screen
boss6_sinking
  if btl < 230 then return
  asm
  lda spos_lo
  cmp #<B6_GONE
  lda spos_hi
  sbc #>B6_GONE
  bcs b6s_gone
  lda #230
  sta btl
b6s_gone
end
  return

  rem the turrets' slots, turned to the ship by turns; and each one's
  rem phase, so they fire by turns
  data boss6_tur
  4, 6, 7, 8, 9, 10
end
  data boss6_tph
  0, 0, 0, 0, 0, 0, 21, 42, 64, 85, 106
end

  rem ---- parts: type, image, hit points, share of the boss (%), palette
  rem (the core's 30 is counted apart; positions in gen/boss6tab.asm)
  data boss6_type
  ET_PPOD, ET_PPOD, ET_PPOD, ET_PPOD, ET_PTURRET, ET_PCORE, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET
end
  data boss6_img
  IMG_B6POD, IMG_B6POD, IMG_B6POD, IMG_B6POD, IMG_TURRET, IMG_B6CORE, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET
end
  data boss6_hp
  90, 90, 90, 90, 70, 255, 70, 70, 70, 70, 70
end
  data boss6_wt
  10, 10, 10, 10, 5, 0, 5, 5, 5, 5, 5
end
  data boss6_col
  0, 0, 0, 0, 4, 4, 4, 4, 4, 4, 4
end
