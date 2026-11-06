  rem ======================================================================
  rem  MASS DRIVER, the stage 7 boss (MegaGammaForce's boss7.c): a hovering
  rem  gun platform built round a rail cannon that runs its whole length.
  rem  Its hull is part of the map, as the crawler's is (map rows after the
  rem  stage's last bare regolith), and the scroll brings it in and stops
  rem  with it near the top of the screen. In the fight it sways slowly
  rem  from side to side (its rows' x: engine.asm pfsway, moved a pixel at
  rem  a time by b7_sway), so the slugs sweep across the screen; the rail's
  rem  coils run (P2's three colors turned round). Every 160 frames the
  rem  muzzle glows, then fires six bursts of needles straight down: move
  rem  out from under it. The muzzle shields the breech, the core, from
  rem  below (shots stop at the first part up the middle). Capacitor pods
  rem  fire pink fans, turrets aimed blue, launch hatches send darts; with
  rem  the muzzle gone the charge has nowhere to go but out: the breech
  rem  sprays at the ship.
  rem  Slots: 0-1 the capacitor pods, 2 the muzzle, 3-4 the hatches
  rem  (LEVIATHAN's bays: shut, open, a crater), 5 the breech (the core),
  rem  6-9 the turrets; 10 is free (a dart may take it).
  rem  Beaten (or gone), it sinks away below: the scroll carries it off.
  rem  It lives in stage 7's bank; the shared boss code calls it.
  rem ======================================================================

  rem its clocks: the slugs (0-159), the turrets (0-89), the pods (0-119);
  rem the coils' turn (0-2)
  dim b7slug = $22E0
  dim b7tur = $22E1
  dim b7cap = $22E2
  dim b7coil = $22E3
  rem (engine.asm's)
  dim pfsway = $22C8
  dim pfswayrow = $22C9

boss7_build
  for k = 0 to 10
    etype[k] = boss7_type[k] : eimg[k] = boss7_img[k] : ehp[k] = boss7_hp[k]
    bwt[k] = boss7_wt[k] : eparam[k] = 0 : ecol[k] = boss7_col[k]
  next
  rem (bx, by: where it burns, round its middle)
  bcorehp = 250 : bx = 80 : by = 60
  b7slug = 0 : b7tur = 0 : b7cap = 0 : b7coil = 0
  rem its rows sway from here on (still, for now)
  pfsway = 0
  asm
  lda #B7_ROW
  sta pfswayrow
end
  return

  rem Each part's line from the scroll: spos + 240 - its top's world
  rem height (16 bits), its x the table's plus the sway; off the screen,
  rem it waits off to the right
boss7_place
  asm
  ldx #9
b7p_loop
  lda etype,x
  cmp #ET_PART
  bcc b7p_next            ; (not a part: a dart from the hatches)
  clc
  lda spos_lo
  adc #240
  sta temp1
  lda spos_hi
  adc #0
  sta temp2
  sec
  lda temp1
  sbc b7_ylo,x
  sta temp1
  lda temp2
  sbc b7_yhi,x
  bne b7p_off
  lda temp1
  cmp #250
  bcs b7p_off
  sta eyh,x
  lda b7_x,x
  clc
  adc pfsway
  sta exh,x
  jmp b7p_next
b7p_off
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b7p_next
  dex
  bpl b7p_loop
end
  rem the breech and the pods pulse; the muzzle blinks as the next burst
  rem charges (its last 40 frames)
  temp1 = tick / 8
  eframe[5] = temp1 & 1
  eframe[0] = temp1 & 1
  eframe[1] = (temp1 + 1) & 1
  temp2 = 0
  if b7slug >= 120 then temp2 = tick / 4 & 1
  eframe[2] = temp2
  rem the hatches: open while they launch (btl 48-79 the left, 160-191
  rem the right), a crater once destroyed
  temp4 = 0 : temp5 = 0
  if btl >= 48 && btl < 80 then temp4 = 1
  if btl >= 160 && btl < 192 then temp5 = 1
  if etype[3] = ET_PWRECK then temp4 = 2
  if etype[4] = ET_PWRECK then temp5 = 2
  eframe[3] = temp4 : eframe[4] = temp5
  rem the coils run: P2's colors a step round every 4 frames
  temp1 = tick & 3
  if temp1 = 0 then b7coil = b7coil + 1
  if b7coil >= 3 then b7coil = 0
  temp1 = b7coil
  P2C1 = b7_coil[temp1] : temp1 = temp1 + 1
  P2C2 = b7_coil[temp1] : temp1 = temp1 + 1
  P2C3 = b7_coil[temp1]
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
boss7_enter
  gosub boss7_place
  asm
  lda spos_lo
  cmp #<(B7_STOP-48)
  lda spos_hi
  sbc #>(B7_STOP-48)
  bcc b7e_wait
  lda #48                 ; the last 3 rows: slower
  sta pfspeed
  lda spos_lo
  cmp #<B7_STOP
  lda spos_hi
  sbc #>B7_STOP
  bcc b7e_wait
  lda #3
  sta bstate
  lda #0
  sta pfspeed
b7e_wait
end
  return

boss7_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  rem the sway: B7_SWAY sin(t / 4), about 17 seconds a sweep there and back
  wang = bth * 64 + btl / 4 + 192
  asm
  lda #B7_SWAY
  sta wamp
  jsr weave
  lda woff
  jsr .b7_sway
end
  gosub boss7_place
  rem its clocks
  b7slug = b7slug + 1
  if b7slug >= 160 then b7slug = 0
  b7tur = b7tur + 1
  if b7tur >= 90 then b7tur = 0
  b7cap = b7cap + 1
  if b7cap >= 120 then b7cap = 0
  rem 100 seconds, and it drifts away
  if bth >= 23 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 0 : pfspeed = 250 : return
  if plvuln = 0 then return
  gosub boss7_attack
  return

  rem Move the sway (pfsway) a pixel toward A (signed), and the rows already
  rem built with it: the ring buffers' background objects (x, each one's
  rem fifth byte) and zone 14's tiles (x, each one's fourth) of the rows
  rem from pfswayrow on
b7_sway
  asm
  sec
  sbc pfsway
  beq b7s_done
  bmi b7s_left
  lda #1
  bne b7s_go
b7s_left
  lda #$FF
b7s_go
  sta temp1
  clc
  adc pfsway
  sta pfsway
  ldx #RINGN-1
b7s_ring
  lda ringrow,x
  cmp pfswayrow
  bcc b7s_ringnext
  lda ringlo,x
  sta pfq
  lda ringhi,x
  sta pfq+1
  ldy #4
b7s_obj
  tya
  cmp bgsize,x
  bcs b7s_ringnext
  lda (pfq),y
  clc
  adc temp1
  sta (pfq),y
  tya
  clc
  adc #5
  tay
  bne b7s_obj
b7s_ringnext
  dex
  bpl b7s_ring
  ldx #1
b7s_z14
  lda pfz14row,x
  cmp #$FF
  beq b7s_z14next         ; (it holds no row)
  cmp pfswayrow
  bcc b7s_z14next
  lda z14lo,x
  sta pfq
  lda z14hi,x
  sta pfq+1
  ldy #3
b7s_tile
  tya
  cmp pfz14bg,x
  bcs b7s_z14next
  lda (pfq),y
  clc
  adc temp1
  sta (pfq),y
  iny
  iny
  iny
  iny
  bne b7s_tile
b7s_z14next
  dex
  bpl b7s_z14
b7s_done
end
  return

boss7_attack
  rem the slugs: six bursts of three needles straight down, 4 frames apart
  if etype[2] <> ET_PCANNON then goto b7_turrets
  if eyh[2] = 0 then goto b7_turrets
  if b7slug >= 24 then goto b7_turrets
  temp1 = b7slug & 3
  if temp1 then goto b7_turrets
  fx = exh[2] + 6 : fy = eyh[2] + 28 : fang = 64
  fkind = BK_NEEDLE : fspd = 80 : fcount = 3 : fstep = 6 : gosub b7_fan
b7_turrets
  rem turrets: aimed blue, each every 90 frames, by turns
  for k = 6 to 9
    if etype[k] <> ET_PTURRET then goto b7_tur_next
    if eyh[k] = 0 then goto b7_tur_next
    if b7tur <> boss7_tph[k] then goto b7_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 8
    gosub aim
    fkind = BK_BLUE : fspd = 44
    asm
    jsr bul_fire
end
b7_tur_next
  next
  rem the capacitor pods: an aimed pink five, each every 120 frames
  for k = 0 to 1
    if etype[k] <> ET_PCANNON then goto b7_cap_next
    if eyh[k] = 0 then goto b7_cap_next
    if b7cap <> boss7_cph[k] then goto b7_cap_next
    fx = exh[k] + 6 : fy = eyh[k] + 16
    gosub aim
    fkind = BK_PINK : fspd = 36 : fcount = 5 : fstep = 12 : gosub b7_fan
b7_cap_next
  next
  rem the hatches: a dart from each, by turns
  if btl = 64 then temp2 = 0 : gosub b7_hatch
  if btl = 176 then temp2 = 1 : gosub b7_hatch
  rem the breech: a blue ring now and then once it is hurt, a pink one
  rem late in the fight; with the muzzle gone, a two-armed spray at the
  rem ship (as GLACIER CRAWLER's reactor: aimed, the arms swinging through
  rem 30 degrees)
  if eyh[5] = 0 then return
  fx = exh[5] + 6 : fy = eyh[5] + 14
  temp1 = btl & 127
  if temp1 = 50 && bcorehp < 125 then fang = bspin : fkind = BK_BLUE : fspd = 28 : fcount = 12 : fstep = 21 : gosub b7_fan : bspin = bspin + 9
  if temp1 = 110 && bth >= 12 then fang = bspin + 10 : fkind = BK_PINK : fspd = 34 : fcount = 12 : fstep = 21 : gosub b7_fan
  if etype[2] = ET_PCANNON then return
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

b7_fan
  asm
  jsr bul_fan
end
  return

  rem A dart from hatch temp2 (slot 3 or 4, while it stands and is in
  rem view) into a free enemy slot: yellow from the left, red from the
  rem right; it dives to a line below the hatch, then turns on the ship
b7_hatch
  temp1 = temp2 + 3
  if etype[temp1] <> ET_PCANNON then return
  if eyh[temp1] = 0 then return
  if eyh[temp1] > 180 then return
  for k = 0 to NE1
    if etype[k] = 0 then goto b7_hatch_slot
  next
  return
b7_hatch_slot
  etype[k] = ET_DART : ecol[k] = 6 - temp2 - temp2 : eimg[k] = IMG_DART : ehp[k] = 2
  temp6 = eyh[temp1] + 8
  exh[k] = exh[temp1] : ebase[k] = exh[temp1] : exl[k] = 128 : eyh[k] = temp6 : eyl[k] = 0
  eparam[k] = temp6 + 40
  evx[k] = 0 : evy[k] = 0 : estate[k] = 0 : etimer[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  ewamp[k] = 0 : ewang[k] = 0 : ewstep[k] = 3 : eframe[k] = 0
  return

  rem It burns on, settling back to the middle, until it has gone below
  rem the screen
boss7_sinking
  temp1 = 0
  asm
  lda temp1
  jsr .b7_sway
end
  if btl < 230 then return
  asm
  lda spos_lo
  cmp #<B7_GONE
  lda spos_hi
  sbc #>B7_GONE
  bcs b7s_gone
  lda #230
  sta btl
b7s_gone
end
  return

  rem each turret's (slots 6-9) and each pod's moment in its clock, so
  rem they fire by turns
  data boss7_tph
  0, 0, 0, 0, 0, 0, 30, 52, 75, 7
end
  data boss7_cph
  60, 100
end

  rem ---- parts: type, image, hit points, share of the boss (%), palette
  rem (the breech's 30 is counted apart; positions in gen/boss7tab.asm)
  data boss7_type
  ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCORE, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET, 0
end
  data boss7_img
  IMG_B7CAP, IMG_B7CAP, IMG_B7MUZZLE, IMG_B3BAY, IMG_B3BAY, IMG_B7BREECH, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET, 0
end
  data boss7_hp
  170, 170, 255, 110, 110, 255, 70, 70, 70, 70, 0
end
  data boss7_wt
  10, 10, 16, 5, 5, 0, 6, 6, 6, 6, 0
end
  data boss7_col
  0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 0
end
