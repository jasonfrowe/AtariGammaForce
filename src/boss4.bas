  rem ======================================================================
  rem  DUNE WYRM, the stage 4 boss (MegaGammaForce's boss4.c): a sandworm
  rem  whose head winds a figure of eight, its body following. Slots: 0 the
  rem  tail, 1-8 body segments (8 nearest the head), 9-10 the head (top;
  rem  bottom), which is the core. Every slot follows the head's path some
  rem  frames behind it (gen/boss4tab.asm: the path, each slot's lag and
  rem  offset), so no trail is kept: the path is worked out again for each
  rem  part from the path clock. A shot-off segment stays on, as a wreck.
  rem  It lives in stage 4's bank; the shared boss code calls it.
  rem ======================================================================

  rem the path clock (16 bits), how far it still has to rise into view,
  rem how far it has sunk (stage 2's boss variables: free here)
  dim b4tlo = $235C
  dim b4thi = $235D
  dim b4yoff = $235E
  dim b4drop = $2380

boss4_build
  for k = 0 to 10
    etype[k] = boss4_type[k] : eimg[k] = boss4_img[k] : ehp[k] = boss4_hp[k]
    bwt[k] = boss4_wt[k] : eparam[k] = 0
  next
  rem (the head at the top of the figure: t = 384, then up out of sight)
  bcorehp = 250 : b4tlo = 128 : b4thi = 1 : b4yoff = 150 : b4drop = 0
  return

boss4_tick
  b4tlo = b4tlo + 1
  if b4tlo = 0 then b4thi = b4thi + 1
  return

  rem Each part where the head was its lag ago: x from the path by t, the
  rem line by t / 2 (an 8: across twice for each time down), less the
  rem rise still to come, plus the sinking. Above the screen it waits
  rem off to the right.
boss4_place
  asm
  ldx #10
b4p_loop
  lda etype,x
  beq b4p_next
  sec
  lda b4tlo
  sbc b4lag,x
  sta temp1               ; t & 255
  lda b4thi
  sbc #0
  lsr                     ; (t / 2) & 255
  lda temp1
  ror
  tay
  lda b4py,y
  clc
  adc b4dy,x
  clc
  adc b4drop
  sec
  sbc b4yoff
  bcc b4p_off             ; still above the screen
  sta eyh,x
  ldy temp1
  lda b4px,y
  clc
  adc b4dx,x
  sta exh,x
  jmp b4p_next
b4p_off
  lda #0
  sta eyh,x
  lda #200
  sta exh,x
b4p_next
  dex
  bpl b4p_loop
  ; pictures: the segments by turns, the maw glowing on and off
  ldx #8
b4p_frames
  txa
  and #1
  sta eframe,x
  dex
  bne b4p_frames
  lda tick
  lsr
  lsr
  lsr
  and #1
  sta eframe+9
  sta eframe+10
end
  return

  rem It rises into view along its path
boss4_enter
  gosub boss4_tick
  if b4yoff > 0 then b4yoff = b4yoff - 1
  gosub boss4_place
  if b4yoff = 0 then bstate = 3
  return

boss4_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  gosub boss4_tick
  gosub boss4_place
  rem 90 seconds and it escapes
  if bth >= 21 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 200 : return
  if plvuln = 0 then return
  gosub boss4_attack
  return

boss4_attack
  rem the head: a pink fan of five straight down, then an aimed blue three
  temp1 = btl & 127
  if temp1 = 0 then fx = exh[9] + 10 : fy = eyh[10] + 4 : fang = 64 : fkind = BK_PINK : fspd = 34 : fcount = 5 : fstep = 12 : gosub b4_fan
  if temp1 = 64 then fx = exh[9] + 10 : fy = eyh[10] + 4 : gosub aim : fkind = BK_BLUE : fspd = 40 : fcount = 3 : fstep = 16 : gosub b4_fan
  rem every other segment: an aimed blue shot, one after another
  temp2 = temp1 & 31
  if temp2 <> 16 then goto b4_tail
  k = temp1 / 16 + 1
  if etype[k] <> ET_PCANNON then goto b4_tail
  fx = exh[k] + 6 : fy = eyh[k] + 16 : gosub aim : fkind = BK_BLUE : fspd = 40
  asm
  jsr bul_fire
end
b4_tail
  rem the tail: a pink ring of eight now and then
  if btl <> 160 then goto b4_late
  if etype[0] <> ET_PCANNON then goto b4_late
  fx = exh[0] + 6 : fy = eyh[0] + 24 : fang = bspin : fkind = BK_PINK : fspd = 30 : fcount = 8 : fstep = 32 : gosub b4_fan
b4_late
  rem hurt, or late: a blue ring of eight from the head
  temp3 = 0
  if bcorehp < 125 then temp3 = 1
  if bth >= 12 then temp3 = 1
  if temp3 = 0 then return
  if temp1 = 96 then fx = exh[9] + 10 : fy = eyh[10] + 4 : fang = bspin + 16 : fkind = BK_BLUE : fspd = 30 : fcount = 8 : fstep = 32 : gosub b4_fan
  rem hurt: a two-armed spiral
  if bcorehp >= 125 then return
  temp2 = btl & 7
  if temp2 then return
  fx = exh[9] + 10 : fy = eyh[10] + 4 : fang = bspin : fspd = 36 : fkind = BK_PINK
  asm
  jsr bul_fire
end
  fang = bspin + 128
  asm
  jsr bul_fire
end
  bspin = bspin + 11
  return

b4_fan
  asm
  jsr bul_fan
end
  return

  rem Dying: it stops and sinks into the sand, bursting along its length
  rem (the next blast at a part chosen at random)
boss4_sinking
  temp1 = btl & 3
  if temp1 = 0 then b4drop = b4drop + 1
  k = rand & 7
  bx = exh[k] + 12 : by = eyh[k] + 24
  return

  rem ---- parts: type, image, hit points, share of the boss (%) ----
  rem (the head's 30 is counted apart)
  data boss4_type
  ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCANNON, ET_PCORE, ET_PCORE
end
  data boss4_img
  IMG_B4TAIL, IMG_B4SEG, IMG_B4SEG, IMG_B4SEG, IMG_B4SEG, IMG_B4SEG, IMG_B4SEG, IMG_B4SEG, IMG_B4SEG, IMG_B4HEADT, IMG_B4HEADB
end
  data boss4_hp
  90, 50, 50, 50, 50, 50, 50, 50, 50, 0, 0
end
  data boss4_wt
  14, 7, 7, 7, 7, 7, 7, 7, 7, 0, 0
end
