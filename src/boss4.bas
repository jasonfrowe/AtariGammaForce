  rem ======================================================================
  rem  DUNE WYRM, the stage 4 boss (MegaGammaForce's boss4.c): a sandworm
  rem  whose head winds a figure of eight, its body following. Slots: 0 the
  rem  tail, 1-8 body segments (8 nearest the head), 9-10 the head (top;
  rem  bottom), which is the core. Every slot follows the head's path some
  rem  frames behind it (gen/boss4tab.asm: the path, each slot's lag and
  rem  offset), so no trail is kept: the path is worked out again for each
  rem  part from the path clock. A shot-off segment stays on, as a wreck.
  rem  Once three of its tail and segments are down it gives chase: the head
  rem  steers for the ship, slower than the ship can fly, and the body
  rem  follows a trail of where the head has been. The head can't be hurt
  rem  until the tail and every segment are down.
  rem  It lives in stage 4's bank; the shared boss code calls it.
  rem ======================================================================

  rem the path clock (16 bits), how far it still has to rise into view,
  rem how far it has sunk (stage 2's boss variables: free here)
  dim b4tlo = $235C
  dim b4thi = $235D
  dim b4yoff = $235E
  dim b4drop = $2380
  rem the chase: on (1); the head's centre (8.8) and heading; the trail
  rem (64 positions, one every 2 frames) and its newest entry
  dim b4mode = $2326
  dim b4hxl = $2327
  dim b4hxh = $2328
  dim b4hyl = $2329
  dim b4hyh = $232A
  dim b4ang = $232B
  dim b4ti = $232C
  dim b4pc = $232D
  dim b4trx = $2740
  dim b4try = $2780

boss4_build
  for k = 0 to 10
    etype[k] = boss4_type[k] : eimg[k] = boss4_img[k] : ehp[k] = boss4_hp[k]
    bwt[k] = boss4_wt[k] : eparam[k] = 0
  next
  rem (the head at the top of the figure: t = 384, then up out of sight)
  bcorehp = 250 : b4tlo = 128 : b4thi = 1 : b4yoff = 150 : b4drop = 0 : b4mode = 0
  return

boss4_tick
  b4tlo = b4tlo + 1
  if b4tlo = 0 then b4thi = b4thi + 1
  return

  rem Each part where the head was its lag ago: on the path, x by t and
  rem the line by t / 2 (an 8: across twice for each time down); in the
  rem chase, from the trail. Less the rise still to come, plus the sinking.
  rem Above or below the screen it waits off to the right.
boss4_place
  asm
  ldx #10
b4p_loop
  lda etype,x
  beq b4p_next
  lda b4mode
  beq b4p_path
  lda b4ti                ; the chase: the trail, lag entries back
  sec
  sbc b4lagt,x
  and #63
  tay
  lda b4trx,y
  sta temp2
  lda b4try,y
  jmp b4p_y
b4p_path
  sec
  lda b4tlo
  sbc b4lag,x
  sta temp1               ; t & 255
  tay
  lda b4px,y
  sta temp2
  lda b4thi
  sbc #0
  lsr                     ; (t / 2) & 255
  lda temp1
  ror
  tay
  lda b4py,y
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

  rem The chase begins: the trail filled from the path behind the head
  rem (each entry 2 frames of the path apart), the head where it is, and
  rem heading for the ship
b4_chase_start
  b4mode = 1 : b4ti = 63 : b4pc = 0
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
  b4hxh = b4trx[63] : b4hyh = b4try[63] : b4hxl = 128 : b4hyl = 128
  fx = b4hxh : fy = b4hyh : gosub aim
  b4ang = fang
  return

  rem The chase, each frame: the heading turns toward the ship (1 every
  rem other frame: a wide, snaking turn), the head moves on (speed 16: about half a line a
  rem frame, slower than the ship), and every 9th frame the trail takes its
  rem place (the head is slow now: entries 4 or 5 lines apart keep the body's
  rem segments about 25 lines apart; those from the path were 2 frames
  rem apart, and the body draws together as they pass)
b4_chase
  rem close to the ship (2|dx| + |dy| < 60 lines) it holds its heading:
  rem it lunges on past and swings back, rather than circling the ship
  rem with its body coiled round it; and it turns only every other frame
  rem (a circle about as long as its body)
  temp1 = tick & 1
  if temp1 then goto b4_go
  temp2 = b4hxh - pcx
  if temp2 >= 128 then temp2 = 0 - temp2
  temp3 = b4hyh - pcy
  if temp3 >= 128 then temp3 = 0 - temp3
  if temp2 < 30 && temp3 < 60 then temp4 = temp2 * 2 + temp3 : if temp4 < 60 then goto b4_go
  fx = b4hxh : fy = b4hyh : gosub aim
  temp1 = fang - b4ang
  if temp1 >= 1 && temp1 < 128 then b4ang = b4ang + 1
  if temp1 >= 128 then b4ang = b4ang - 1
b4_go
  fang = b4ang : fspd = 16
  asm
  jsr ang_vel
  lda velx
  jsr ob_x8
  clc
  lda b4hxl
  adc ob1
  sta b4hxl
  lda b4hxh
  adc ob2
  sta b4hxh
  lda vely
  jsr ob_x8
  clc
  lda b4hyl
  adc ob1
  sta b4hyl
  lda b4hyh
  adc ob2
  sta b4hyh
end
  if b4hxh < 20 then b4hxh = 20
  if b4hxh > 140 then b4hxh = 140
  if b4hyh < 64 then b4hyh = 64
  if b4hyh > 210 then b4hyh = 210
  b4pc = b4pc + 1
  if b4pc < 9 then return
  b4pc = 0
  b4ti = (b4ti + 1) & 63
  temp1 = b4ti
  b4trx[temp1] = b4hxh : b4try[temp1] = b4hyh
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
  rem three of the tail and segments down: the chase
  if b4mode then gosub b4_chase : goto b4f_place
  temp2 = 0
  for k = 0 to 8
    if etype[k] <> ET_PCANNON then temp2 = temp2 + 1
  next
  if temp2 >= 3 then gosub b4_chase_start
b4f_place
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
  rem each slot's lag on the chase's trail (entries, 2 frames each: the
  rem path's lag, b4lag, halved)
  data b4lagt
  50, 44, 39, 33, 28, 22, 17, 11, 6, 0, 0
end
