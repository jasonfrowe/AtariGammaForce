  rem ======================================================================
  rem  HIVE MOTHERSHIP, the stage 8 boss (MegaGammaForce's boss8.c): an
  rem  alien ship grown, not built, a carapace of honeycomb round a great
  rem  eye, its core. Its hull is part of the map (as MASS DRIVER's: map rows
  rem  after the drifts), and the scroll brings it in and stops with it at
  rem  the top of the screen; in the fight it sways from side to side as if
  rem  swimming (engine.asm pfsway, a pixel at a time: b8_sway). Two spore
  rem  pods launch saucers, two mandibles fire pink fans at the ship, four
  rem  turrets aimed blue; the eye glares before each blue ring. The eye is
  rem  shut, armored, while both mandibles stand; with one gone it opens,
  rem  and the maw spits needles; hurt, the eye sprays at the ship; late in
  rem  the fight, pink rings too.
  rem  Slots: 0-1 the pods, 2-3 the mandibles, 4 the shut eye's armor (off
  rem  the screen), 5 the eye (the core), 6-9 the turrets; 10 is free (a
  rem  saucer may take it).
  rem  Beaten (or gone), it sinks away below: the scroll carries it off.
  rem  It lives in stage 8's bank; the shared boss code calls it.
  rem ======================================================================

  rem its clocks: the turrets (0-89), the mandibles (0-109), the pods
  rem (0-199), the eye's ring (0-139)
  dim b8tur = $22E0
  dim b8claw = $22E1
  dim b8pod = $22E2
  dim b8ring = $22E3
  rem (engine.asm's)
  dim pfsway = $22C8
  dim pfswayrow = $22C9
  dim pfswayend = $22CA

boss8_build
  for k = 0 to 10
    etype[k] = boss8_type[k] : eimg[k] = boss8_img[k] : ehp[k] = boss8_hp[k]
    bwt[k] = boss8_wt[k] : eparam[k] = 0 : ecol[k] = boss8_col[k]
  next
  rem (bx, by: where it burns, round its middle)
  bcorehp = 250 : bx = 80 : by = 56
  b8tur = 0 : b8claw = 0 : b8pod = 0 : b8ring = 0
  rem its rows sway from here on (still, for now)
  pfsway = 0
  asm
  lda #B8_ROW
  sta pfswayrow
  lda #B8_END
  sta pfswayend
end
  return

  rem Each part's line from the scroll: spos + 240 - its top's world
  rem height (16 bits), its x the table's plus the sway; off the screen,
  rem it waits off to the right
boss8_place
  asm
  ldx #9
b8p_loop
  lda etype,x
  cmp #ET_PART
  bcc b8p_next            ; (not a part: a saucer)
  clc
  lda spos_lo
  adc #240
  sta temp1
  lda spos_hi
  adc #0
  sta temp2
  sec
  lda temp1
  sbc b8_ylo,x
  sta temp1
  lda temp2
  sbc b8_yhi,x
  bne b8p_off
  lda temp1
  cmp #250
  bcs b8p_off
  sta eyh,x
  lda b8_x,x
  clc
  adc pfsway
  sta exh,x
  jmp b8p_next
b8p_off
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b8p_next
  dex
  bpl b8p_loop
end
  rem the eye is shut while both mandibles stand: dark, armored (shots stop
  rem on it, to no effect: as armor, ET_PARMOR, it passes its hits to the
  rem slot before it, 4, a part kept off the screen); with one gone it
  rem opens, red
  if etype[5] = ET_PCORE || etype[5] = ET_PARMOR then gosub b8_lid
  rem the eye glares as its ring comes (its last 30 frames); the pods
  rem pulse; the mandibles work
  temp2 = 0
  if b8ring >= 110 then temp2 = 1
  eframe[5] = temp2
  temp1 = tick / 16
  eframe[0] = temp1 & 1
  eframe[1] = (temp1 + 1) & 1
  temp1 = tick / 8
  eframe[2] = temp1 & 1
  eframe[3] = (temp1 + 1) & 1
  rem the turrets turn to the ship, one a step
  temp1 = tick & 3
  k = temp1 + 6
  if etype[k] <> ET_PTURRET then return
  if eyh[k] = 0 then return
  fx = exh[k] + 4 : fy = eyh[k] + 8
  gosub aim
  eframe[k] = (fang - 48) / 32 & 7
  return

b8_lid
  if etype[2] = ET_PCANNON && etype[3] = ET_PCANNON then goto b8_shut
  etype[5] = ET_PCORE : ecol[5] = 4
  if etype[4] = ET_PCANNON then etype[4] = 0
  return
b8_shut
  etype[5] = ET_PARMOR : ecol[5] = 0
  etype[4] = ET_PCANNON : ehp[4] = 255 : eimg[4] = IMG_B8POD
  return

  rem In at the stage's speed, slowing, until the hull is in view
boss8_enter
  gosub boss8_place
  asm
  lda spos_lo
  cmp #<(B8_STOP-48)
  lda spos_hi
  sbc #>(B8_STOP-48)
  bcc b8e_wait
  lda #48                 ; the last 3 rows: slower
  sta pfspeed
  lda spos_lo
  cmp #<B8_STOP
  lda spos_hi
  sbc #>B8_STOP
  bcc b8e_wait
  lda #3
  sta bstate
  lda #0
  sta pfspeed
b8e_wait
end
  return

boss8_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  rem the sway: B8_SWAY sin(t / 2), about 8 seconds a sweep there and back
  wang = bth * 128 + btl / 2 + 192
  asm
  lda #B8_SWAY
  sta wamp
  jsr weave
  lda woff
  jsr .b8_sway
end
  gosub boss8_place
  rem its clocks
  b8tur = b8tur + 1
  if b8tur >= 90 then b8tur = 0
  b8claw = b8claw + 1
  if b8claw >= 110 then b8claw = 0
  b8pod = b8pod + 1
  if b8pod >= 200 then b8pod = 0
  b8ring = b8ring + 1
  if b8ring >= 140 then b8ring = 0
  rem 100 seconds, and it drifts away
  if bth >= 23 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 0 : pfspeed = 250 : return
  if plvuln = 0 then return
  gosub boss8_attack
  return

  rem Move the sway (pfsway) a pixel toward A (signed), and the rows already
  rem built with it: the ring buffers' background objects (x, each one's
  rem fifth byte) and zone 14's tiles (x, each one's fourth) of the rows
  rem from pfswayrow up to pfswayend (MASS DRIVER's b7_sway, with the end)
b8_sway
  asm
  sec
  sbc pfsway
  beq b8s_done
  bmi b8s_left
  lda #1
  bne b8s_go
b8s_left
  lda #$FF
b8s_go
  sta temp1
  clc
  adc pfsway
  sta pfsway
  ldx #RINGN-1
b8s_ring
  lda ringrow,x
  cmp pfswayrow
  bcc b8s_ringnext
  cmp pfswayend
  bcs b8s_ringnext
  lda ringlo,x
  sta pfq
  lda ringhi,x
  sta pfq+1
  ldy #4
b8s_obj
  tya
  cmp bgsize,x
  bcs b8s_ringnext
  lda (pfq),y
  clc
  adc temp1
  sta (pfq),y
  tya
  clc
  adc #5
  tay
  bne b8s_obj
b8s_ringnext
  dex
  bpl b8s_ring
  ldx #1
b8s_z14
  lda pfz14row,x
  cmp pfswayrow
  bcc b8s_z14next
  cmp pfswayend
  bcs b8s_z14next         ; (or it holds no row: $FF)
  lda z14lo,x
  sta pfq
  lda z14hi,x
  sta pfq+1
  ldy #3
b8s_tile
  tya
  cmp pfz14bg,x
  bcs b8s_z14next
  lda (pfq),y
  clc
  adc temp1
  sta (pfq),y
  iny
  iny
  iny
  iny
  bne b8s_tile
b8s_z14next
  dex
  bpl b8s_z14
b8s_done
end
  return

boss8_attack
  rem turrets: aimed blue, each every 90 frames, by turns
  for k = 6 to 9
    if etype[k] <> ET_PTURRET then goto b8_tur_next
    if eyh[k] = 0 then goto b8_tur_next
    if b8tur <> boss8_tph[k] then goto b8_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 8
    gosub aim
    fkind = BK_BLUE : fspd = 44
    asm
    jsr bul_fire
end
b8_tur_next
  next
  rem the mandibles: an aimed pink five, each every 110 frames
  for k = 2 to 3
    if etype[k] <> ET_PCANNON then goto b8_claw_next
    if eyh[k] = 0 then goto b8_claw_next
    if b8claw <> boss8_cph[k] then goto b8_claw_next
    fx = exh[k] + 6 : fy = eyh[k] + 28
    gosub aim
    fkind = BK_PINK : fspd = 36 : fcount = 5 : fstep = 12 : gosub b8_fan
b8_claw_next
  next
  rem the pods: a saucer from each, every 200 frames, by turns
  if b8pod = 40 then temp2 = 0 : gosub b8_spore
  if b8pod = 140 then temp2 = 1 : gosub b8_spore
  rem the eye: a blue ring every 140 frames; hurt, a two-armed spray at the
  rem ship (as MASS DRIVER's breech: aimed, the arms swinging through 30
  rem degrees); late in the fight, a pink ring now and then
  if eyh[5] = 0 then return
  fx = exh[5] + 6 : fy = eyh[5] + 14
  if b8ring = 0 then fang = bspin : fkind = BK_BLUE : fspd = 28 : fcount = 12 : fstep = 21 : gosub b8_fan : bspin = bspin + 9
  temp1 = btl & 63
  if temp1 = 32 && bth >= 12 then fang = bspin + 10 : fkind = BK_PINK : fspd = 34 : fcount = 12 : fstep = 21 : gosub b8_fan
  rem with a mandible gone, needles from the maw: five straight down,
  rem every 45 frames
  temp3 = 0
  if etype[2] <> ET_PCANNON then temp3 = 1
  if etype[3] <> ET_PCANNON then temp3 = 1
  if temp3 = 0 then goto b8_spray
  if b8tur <> 25 && b8tur <> 70 then goto b8_spray
  temp6 = fy
  fy = fy + 18 : fang = 64 : fkind = BK_NEEDLE : fspd = 60 : fcount = 5 : fstep = 10 : gosub b8_fan
  fy = temp6
b8_spray
  if bcorehp >= 125 then return
  temp1 = btl & 7
  if temp1 then return
  gosub aim
  wang = bspin : wamp = 11
  asm
  jsr weave
end
  fang = aimang + woff : fspd = 34 : fkind = BK_PINK
  asm
  jsr bul_fire
end
  fang = aimang - woff : fkind = BK_BLUE
  asm
  jsr bul_fire
end
  bspin = bspin + 16
  return

b8_fan
  asm
  jsr bul_fan
end
  return

  rem A saucer from pod temp2 (slot 0 or 1, while it stands and is in
  rem view) into a free enemy slot (not a part's: its slot is the
  rem part's, gone or not): red from the left, blue from the right
b8_spore
  if etype[temp2] <> ET_PCANNON then return
  if eyh[temp2] = 0 then return
  for k = 0 to NE1
    if boss8_free[k] = 0 then goto b8_spore_next
    if etype[k] = 0 then goto b8_spore_slot
b8_spore_next
  next
  return
b8_spore_slot
  etype[k] = ET_SAUCER : ecol[k] = 4 + temp2 : eimg[k] = IMG_SAUCER : ehp[k] = enemy_hp[ET_SAUCER]
  temp6 = eyh[temp2] + 8
  exh[k] = exh[temp2] : ebase[k] = exh[temp2] : exl[k] = 128 : eyh[k] = temp6 : eyl[k] = 0
  eparam[k] = 24 : ewamp[k] = 24
  evx[k] = 0 : evy[k] = 0 : estate[k] = 0 : etimer[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  ewang[k] = 0 : ewstep[k] = 3 : eframe[k] = 0
  return

  rem It burns on, settling back to the middle, until it has gone below
  rem the screen
boss8_sinking
  temp1 = 0
  asm
  lda temp1
  jsr .b8_sway
end
  if btl < 230 then return
  asm
  lda spos_lo
  cmp #<B8_GONE
  lda spos_hi
  sbc #>B8_GONE
  bcs b8s_gone
  lda #230
  sta btl
b8s_gone
end
  return

  rem each turret's (slots 6-9) and each mandible's (2-3) moment in its
  rem clock, so they fire by turns
  data boss8_tph
  0, 0, 0, 0, 0, 0, 0, 45, 22, 67
end
  data boss8_cph
  0, 0, 30, 85
end
  rem the slots a saucer may take
  data boss8_free
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1
end

  rem ---- parts: type, image, hit points, share of the boss (%), palette
  rem (the eye's 30 is counted apart; positions in gen/boss8tab.asm)
  data boss8_type
  ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, 0, ET_PCORE, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET, 0
end
  data boss8_img
  IMG_B8POD, IMG_B8POD, IMG_B8CLAWL, IMG_B8CLAWR, 0, IMG_B8EYE, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET, 0
end
  data boss8_hp
  170, 170, 190, 190, 0, 255, 70, 70, 70, 70, 0
end
  data boss8_wt
  10, 10, 13, 13, 0, 0, 6, 6, 6, 6, 0
end
  data boss8_col
  0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 0
end
