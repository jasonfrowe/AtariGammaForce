  rem ======================================================================
  rem  GAMMA PRIME, the stage 9 boss, the last (MegaGammaForce's boss9.c):
  rem  the Gamma Core's true form, a sunburst fortress of gold feeding on the
  rem  Sun. Its hull is part of the map (as HIVE MOTHERSHIP's: map rows after
  rem  the flares), and the scroll brings it in and stops with it at the top
  rem  of the screen. It holds still: the battlefield's flares under it
  rem  (stage9.bas) keep the ship from camping under the core. Two prisms
  rem  orbit it (as HALO STATION's satellites) firing pink threes at the
  rem  ship, two ring cannons fire pink rings, four turrets aimed blue; the
  rem  beam emitter below the core glows, then pours three fans of needles
  rem  straight down; the core fires blue rings. The core is shut (gold)
  rem  while any prism orbits, then burns red.
  rem  With the emitter gone the core sprays at the ship; hurt, it fires
  rem  blue threes too; late in the fight, pink rings.
  rem  Slots: 0-1 the cannons, 2 the emitter, 3-4 the prisms (two, not
  rem  MegaGammaForce's four: for speed), 5 the core, 6-9 the turrets.
  rem  Beaten (or gone), it sinks away below: the scroll carries it off.
  rem  It lives in stage 9's bank; the shared boss code calls it.
  rem ======================================================================

  rem its clocks: the turrets (0-83), the prisms (0-79), the cannons
  rem (0-129), the beam (0-149), the core's ring (0-169)
  dim b9tur = $22E0
  dim b9pr = $22E1
  dim b9can = $22E2
  dim b9beam = $22E3
  dim b9ring = $22E4

boss9_build
  for k = 0 to 11
    etype[k] = boss9_type[k] : eimg[k] = boss9_img[k] : ehp[k] = boss9_hp[k]
    bwt[k] = boss9_wt[k] : eparam[k] = 0 : ecol[k] = boss9_col[k]
  next
  rem (the shared code readies slots 0-10)
  eflash[11] = 0 : ehit[11] = 0 : eframe[11] = 0 : evx[11] = 0 : evy[11] = 0 : ewamp[11] = 0
  rem (bx, by: where it burns, round its middle)
  bcorehp = 250 : bx = 80 : by = 56 : borbit = 0
  b9tur = 0 : b9pr = 0 : b9can = 0 : b9beam = 0 : b9ring = 0
  return

  rem Each part's line from the scroll: spos + 240 - its top's world
  rem height (16 bits), its x the table's; off the screen,
  rem it waits off to the right. Then the prisms, round the core (their
  rem table's place), half a turn apart, turning a step a frame in the
  rem fight.
boss9_place
  asm
  ldx #11
b9p_loop
  lda etype,x
  cmp #ET_PART
  bcc b9p_next            ; (not a part)
  clc
  lda spos_lo
  adc #240
  sta temp1
  lda spos_hi
  adc #0
  sta temp2
  sec
  lda temp1
  sbc b9_ylo,x
  sta temp1
  lda temp2
  sbc b9_yhi,x
  bne b9p_off
  lda temp1
  cmp #250
  bcs b9p_off
  sta eyh,x
  lda b9_x,x
  sta exh,x
  jmp b9p_next
b9p_off
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b9p_next
  dex
  bpl b9p_loop
  lda bstate
  cmp #3
  bne b9p_still           ; (it turns only in the fight)
  inc borbit
b9p_still
  ; the orbit: 50 lines up and down, 64 pixels across
  ldx #4
b9p_prism
  lda etype,x
  cmp #ET_PPOD
  bne b9p_prnext
  lda eyh,x
  beq b9p_prnext          ; (the centre is off the screen: so is it)
  stx temp6
  lda b9_pang,x           ; its angle
  clc
  adc borbit
  sta temp7
  sta wang                ; x: cos * across
  lda #64
  sta wamp
  jsr weave
  ldx temp6
  lda exh,x
  clc
  adc woff
  sta exh,x
  lda temp7               ; line: sin * up and down
  sec
  sbc #64
  sta wang
  lda #50
  sta wamp
  jsr weave
  ldx temp6
  lda woff
  bmi b9p_up
  clc
  adc eyh,x
  bcs b9p_proff
  cmp #250
  bcs b9p_proff
  sta eyh,x
  jmp b9p_prnext
b9p_up
  clc
  adc eyh,x
  bcc b9p_proff           ; (above the top: off)
  beq b9p_proff
  sta eyh,x
  jmp b9p_prnext
b9p_proff
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b9p_prnext
  dex
  cpx #3
  bcs b9p_prism
end
  rem the core is shut while any prism orbits (gammaforce.bas part_core):
  rem gold; then it burns red
  ecol[5] = 4
  if etype[3] = ET_PPOD || etype[4] = ET_PPOD then ecol[5] = 0
  rem the core pulses; the prisms turn; each cannon glows in the 20
  rem frames before its ring, the emitter as its needles charge (its last
  rem 40 frames)
  eframe[5] = (tick / 8) & 1
  temp1 = tick / 8
  eframe[3] = temp1 & 1 : eframe[4] = (temp1 + 1) & 1
  temp2 = 0
  if b9can >= 10 && b9can < 30 then temp2 = 1
  eframe[0] = temp2
  temp2 = 0
  if b9can >= 75 && b9can < 95 then temp2 = 1
  eframe[1] = temp2
  temp2 = 0
  temp3 = tick & 4
  if b9beam >= 110 && temp3 then temp2 = 1
  eframe[2] = temp2
  rem the turrets turn to the ship, one a step
  temp1 = tick & 3
  k = temp1 + 6
  if etype[k] <> ET_PTURRET then return
  if eyh[k] = 0 then return
  fx = exh[k] + 4 : fy = eyh[k] + 8
  gosub aim
  eframe[k] = (fang - 48) / 32 & 7
  return

  rem In at the stage's speed, slowing, until the hull is in view
boss9_enter
  gosub boss9_place
  asm
  lda spos_lo
  cmp #<(B9_STOP-48)
  lda spos_hi
  sbc #>(B9_STOP-48)
  bcc b9e_wait
  lda #48                 ; the last 3 rows: slower
  sta pfspeed
  lda spos_lo
  cmp #<B9_STOP
  lda spos_hi
  sbc #>B9_STOP
  bcc b9e_wait
  lda #3
  sta bstate
  lda #0
  sta pfspeed
b9e_wait
end
  return

boss9_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  gosub boss9_place
  rem its clocks
  b9tur = b9tur + 1
  if b9tur >= 84 then b9tur = 0
  b9pr = b9pr + 1
  if b9pr >= 80 then b9pr = 0
  b9can = b9can + 1
  if b9can >= 130 then b9can = 0
  b9beam = b9beam + 1
  if b9beam >= 150 then b9beam = 0
  b9ring = b9ring + 1
  if b9ring >= 170 then b9ring = 0
  rem 2 minutes, and it drifts away
  if bth >= 28 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 0 : pfspeed = 250 : return
  if plvuln = 0 then return
  gosub boss9_attack
  return

boss9_attack
  rem turrets: aimed blue, each every 84 frames, by turns
  for k = 6 to 9
    if etype[k] <> ET_PTURRET then goto b9_tur_next
    if eyh[k] = 0 then goto b9_tur_next
    if b9tur <> boss9_ph[k] then goto b9_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 8
    gosub aim
    fkind = BK_BLUE : fspd = 44
    asm
    jsr bul_fire
end
b9_tur_next
  next
  rem the prisms: an aimed pink three, each every 80 frames, by turns (two
  rem prisms, not MegaGammaForce's four, firing as often as its four)
  for k = 3 to 4
    if etype[k] <> ET_PPOD then goto b9_pr_next
    if eyh[k] < 8 then goto b9_pr_next
    if b9pr <> boss9_ph[k] then goto b9_pr_next
    fx = exh[k] + 6 : fy = eyh[k] + 6
    gosub aim
    fkind = BK_PINK : fspd = 40 : fcount = 3 : fstep = 12 : gosub b9_fan
b9_pr_next
  next
  rem the cannons: a pink ring of 8, each every 130 frames, by turns
  for k = 0 to 1
    if etype[k] <> ET_PCANNON then goto b9_can_next
    if eyh[k] = 0 then goto b9_can_next
    if b9can <> boss9_ph[k] then goto b9_can_next
    fx = exh[k] + 6 : fy = eyh[k] + 26
    fang = bspin : fkind = BK_PINK : fspd = 30 : fcount = 8 : fstep = 32 : gosub b9_fan
    bspin = bspin + 11
b9_can_next
  next
  rem the emitter: three fans of needles straight down, 8 frames apart,
  rem every 150 frames
  if etype[2] <> ET_PCANNON then goto b9_core
  if eyh[2] = 0 then goto b9_core
  fx = exh[2] + 6 : fy = eyh[2] + 28 : fang = 64 : fkind = BK_NEEDLE : fspd = 70 : fstep = 8
  if b9beam = 0 || b9beam = 16 then fcount = 5 : gosub b9_fan
  if b9beam = 8 then fcount = 4 : gosub b9_fan
b9_core
  rem the core: a blue ring every 170 frames; late in the fight, a pink
  rem one every 64
  if eyh[5] = 0 then return
  fx = exh[5] + 6 : fy = eyh[5] + 14
  if b9ring = 85 then fang = bspin : fkind = BK_BLUE : fspd = 25 : fcount = 10 : fstep = 26 : gosub b9_fan : bspin = bspin + 9
  temp1 = btl & 63
  if temp1 = 32 && bth >= 14 then fang = bspin + 13 : fkind = BK_PINK : fspd = 34 : fcount = 10 : fstep = 26 : gosub b9_fan
  rem hurt, an aimed blue three every 32 frames
  if bcorehp >= 125 then goto b9_spray
  temp1 = btl & 31
  if temp1 <> 12 then goto b9_spray
  gosub aim
  fkind = BK_BLUE : fspd = 34 : fcount = 3 : fstep = 14 : gosub b9_fan
b9_spray
  rem with the emitter gone, it pours its light out at the ship: a
  rem two-armed spray (as HIVE MOTHERSHIP's: aimed, the arms swinging
  rem through 30 degrees), every 10 frames
  if etype[2] = ET_PCANNON then return
  temp1 = btl & 7
  if temp1 then return
  gosub aim
  wang = bspin : wamp = 11
  asm
  jsr weave
end
  fang = aimang + woff : fspd = 30 : fkind = BK_PINK
  asm
  jsr bul_fire
end
  fang = aimang - woff
  asm
  jsr bul_fire
end
  bspin = bspin + 16
  return

  rem The ending, after GAMMA PRIME (MegaGammaForce's): its texts, by the
  rem bank's spare vector, then the results' PRESS FIRE
finale
  tpal = 6 : tzone = 4 : temp1 = TXT_END1 : gosub text
  tpal = 3 : tzone = 6 : temp1 = TXT_END2 : gosub text
  tzone = 7 : temp1 = TXT_END3 : gosub text
  goto results_push

b9_fan
  asm
  jsr bul_fan
end
  return

  rem It burns on until it has gone below the screen
boss9_sinking
  if btl < 230 then return
  asm
  lda spos_lo
  cmp #<B9_GONE
  lda spos_hi
  sbc #>B9_GONE
  bcs b9s_gone
  lda #230
  sta btl
b9s_gone
end
  return

  rem each part's moment in its clock, so they fire by turns: the cannons
  rem (0-1), the prisms (3-4), the turrets (6-9)
  data boss9_ph
  30, 95, 0, 0, 40, 0, 0, 21, 42, 63, 0, 0
end
  rem the prisms' places round the orbit (half a turn apart)
  data b9_pang
  0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0
end

  rem ---- parts: type, image, hit points, share of the boss (%), palette
  rem (the core's 30 is counted apart; positions in gen/boss9tab.asm)
  data boss9_type
  ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PPOD, ET_PPOD, ET_PCORE, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET, 0, 0
end
  data boss9_img
  IMG_BCANNON, IMG_BCANNON, IMG_B9EMIT, IMG_B9PRISM, IMG_B9PRISM, IMG_B9CORE, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET, 0, 0
end
  data boss9_hp
  210, 210, 210, 76, 76, 255, 76, 76, 76, 76, 0, 0
end
  data boss9_wt
  10, 10, 14, 10, 10, 0, 4, 4, 4, 4, 0, 0
end
  data boss9_col
  0, 0, 0, 5, 5, 0, 4, 4, 4, 4, 0, 0
end
