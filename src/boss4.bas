  rem ======================================================================
  rem  DUNE WYRM, the stage 4 boss (MegaGammaForce's boss4.c): a sandworm
  rem  whose head winds a figure of eight, its body following. Slots: 0 the
  rem  tail, 1-8 body segments (8 nearest the head), 9-10 the head (top;
  rem  bottom), which is the core. The head's path is a clock and two tables
  rem  (gen/boss4tab.asm); the body follows a trail of where the head has
  rem  been (64 positions, one every 2 frames, each part its lag back, the
  rem  frames between taking the middle of two). As 3, then 6, of its tail
  rem  and segments fall it gives chase for 4 seconds: the head steers for
  rem  the ship, a little slower than the ship flies, then flies back to
  rem  where its path has got to and goes on along it. The trail carries the
  rem  body through all of it without a jump. A shot-off segment stays on,
  rem  as a wreck. The head can't be hurt until the tail and every segment
  rem  are down. It lives in stage 4's bank; the shared boss code calls it.
  rem ======================================================================

  rem the path clock (16 bits), how far it still has to rise into view,
  rem how far it has sunk (stage 2's boss variables: free here)
  dim b4tlo = $235C
  dim b4thi = $235D
  dim b4yoff = $235E
  dim b4drop = $2380
  rem 0 the path, 1 the chase, 2 back to the path; the head's centre (8.8)
  rem and heading; the trail's newest entry, and 1 between entries; the
  rem chase's time left; the number of parts down for the next chase
  dim b4mode = $2326
  dim b4hxl = $2327
  dim b4hxh = $2328
  dim b4hyl = $2329
  dim b4hyh = $232A
  dim b4ang = $232B
  dim b4ti = $232C
  dim b4ph = $232D
  dim b4ct = $232E
  dim b4next = $232F
  dim b4trx = $2740
  dim b4try = $2780

boss4_build
  for k = 0 to 10
    etype[k] = boss4_type[k] : eimg[k] = boss4_img[k] : ehp[k] = boss4_hp[k]
    bwt[k] = boss4_wt[k] : eparam[k] = 0
  next
  rem (the head at the top of the figure: t = 384, then up out of sight)
  bcorehp = 250 : b4tlo = 128 : b4thi = 1 : b4yoff = 150 : b4drop = 0
  b4mode = 0 : b4next = 3 : b4ti = 63 : b4ph = 0
  rem the trail: the path behind the head, 2 frames an entry
  asm
  lda b4tlo
  sta temp1
  lda b4thi
  sta temp2
  ldx #63
b4c_fill
  ldy temp1
  lda b4px,y
  sta b4trx,x
  lda temp2
  lsr
  lda temp1
  ror
  tay
  lda b4py,y
  sta b4try,x
  sec
  lda temp1
  sbc #2
  sta temp1
  lda temp2
  sbc #0
  sta temp2
  dex
  bpl b4c_fill
end
  rem the head where the trail ends (it is placed before its first tick:
  rem left at 0, 0 its top would wrap onto the screen's left edge)
  b4hxh = b4trx[63] : b4hyh = b4try[63] : b4hxl = 128 : b4hyl = 128
  return

  rem Each frame: the clock, the head (on the path, chasing, or flying
  rem back to the path), and every other frame the trail's next entry
boss4_tick
  b4tlo = b4tlo + 1
  if b4tlo = 0 then b4thi = b4thi + 1
  rem the path's point now: temp4, temp5
  asm
  ldy b4tlo
  lda b4px,y
  sta temp4
  lda b4thi
  lsr
  lda b4tlo
  ror
  tay
  lda b4py,y
  sta temp5
end
  if b4mode = 1 then gosub b4_chase : goto b4t_trail
  if b4mode = 2 then gosub b4_back : goto b4t_trail
  b4hxh = temp4 : b4hyh = temp5 : b4hxl = 128 : b4hyl = 128
b4t_trail
  b4ph = b4ph ^ 1
  if b4ph then return
  b4ti = (b4ti + 1) & 63
  temp1 = b4ti
  b4trx[temp1] = b4hxh : b4try[temp1] = b4hyh
  return

  rem Each part where the head was its lag ago (the head itself: where it
  rem is), less the rise still to come, plus the sinking. Above or below
  rem the screen it waits off to the right.
boss4_place
  asm
  ldx #10
b4p_loop
  lda etype,x
  beq b4p_next
  lda b4lagt,x
  bne b4p_trail
  lda b4hxh               ; the head
  sta temp2
  lda b4hyh
  jmp b4p_y
b4p_trail
  sta temp1
  lda b4ti
  sec
  sbc temp1
  and #63
  tay
  lda b4trx,y
  sta temp2
  lda b4try,y
  sta temp3
  lda b4ph                ; between entries: halfway to the next
  beq b4p_one
  iny
  tya
  and #63
  tay
  lda b4trx,y
  clc
  adc temp2
  ror
  sta temp2
  lda b4try,y
  clc
  adc temp3
  ror
  sta temp3
b4p_one
  lda temp3
b4p_y
  clc
  adc b4dy,x              ; (the sum never wraps: lines 40-222)
  clc
  adc b4drop
  bcs b4p_off             ; sunk below the screen
  sec
  sbc b4yoff
  bcc b4p_off             ; still above the screen
  sta eyh,x
  lda temp2
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

  rem The chase: the heading turns toward the ship (2 a frame), but held
  rem when close (2|dx| + |dy| < 60 lines: it lunges on past and swings
  rem back, rather than coiling round the ship); speed 44, about 1.4 lines
  rem a frame (the ship flies 1.5-2). After 4 seconds, back to the path.
b4_chase
  b4ct = b4ct - 1
  if b4ct = 0 then b4mode = 2
  temp2 = b4hxh - pcx
  if temp2 >= 128 then temp2 = 0 - temp2
  temp3 = b4hyh - pcy
  if temp3 >= 128 then temp3 = 0 - temp3
  if temp2 < 30 && temp3 < 60 then temp6 = temp2 * 2 + temp3 : if temp6 < 60 then goto b4_go
  fx = b4hxh : fy = b4hyh : gosub aim
  temp1 = fang - b4ang
  if temp1 >= 2 && temp1 < 128 then b4ang = b4ang + 2
  if temp1 >= 128 && temp1 < 255 then b4ang = b4ang - 2
b4_go
  fang = b4ang : fspd = 44
  goto b4_move

  rem Back: straight for the path's point (speed 100, faster than the path
  rem runs), and on along the path once there
b4_back
  temp2 = b4hxh - temp4
  if temp2 >= 128 then temp2 = 0 - temp2
  temp3 = b4hyh - temp5
  if temp3 >= 128 then temp3 = 0 - temp3
  if temp2 < 3 && temp3 < 6 then b4mode = 0 : b4hxh = temp4 : b4hyh = temp5 : return
  rem (aim at the point: aim_player aims at pcx, pcy)
  temp2 = pcx : temp3 = pcy : pcx = temp4 : pcy = temp5
  fx = b4hxh : fy = b4hyh : gosub aim
  pcx = temp2 : pcy = temp3
  b4ang = fang : fspd = 100
  goto b4_move

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
  rem 3, then 6, of the tail and segments down: a chase
  if b4mode then goto b4f_place
  temp2 = 0
  for k = 0 to 8
    if etype[k] <> ET_PCANNON then temp2 = temp2 + 1
  next
  if temp2 < b4next then goto b4f_place
  b4next = b4next + 3 : b4mode = 1 : b4ct = 240
  fx = b4hxh : fy = b4hyh : gosub aim
  b4ang = fang
b4f_place
  gosub boss4_place
  rem 90 seconds and it escapes
  if bth >= 21 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 200 : return
  if plvuln = 0 then return
  gosub boss4_attack
  return

  rem (the head's move, its sinking and its tables: boss4b.bas, in the
  rem bank's main area; this file is in the DMA hole)

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

