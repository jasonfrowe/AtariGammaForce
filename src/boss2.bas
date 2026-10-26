  rem ======================================================================
  rem  SPIRE WARDEN, the stage 2 boss (MegaGammaForce's boss2.c). It lives
  rem  in stage 2's bank (switched in for the whole stage); the shared boss
  rem  code in gammaforce.bas calls it.
  rem  Slots: 0 the twin cannon, 1-2 the shoulder turrets, 5-6 the core
  rem  (two halves sharing bcorehp), 8-10 the pods that orbit the core. The
  rem  pods are last: as they cross between zones the parts drawn before
  rem  them keep their places in the display lists (engine.asm pf_object).
  rem ======================================================================

boss2_build
  for k = 0 to 10
    etype[k] = boss2_type[k] : eimg[k] = boss2_img[k] : ehp[k] = boss2_hp[k]
    bdx[k] = boss2_dx[k] : bdy[k] = boss2_dy[k]
  next
  bcorehp = 250 : borbit = 0 : bsweep = 0 : bsdir = 1 : bring = 0
  return

  rem The pods circle the core on a flattened orbit (29 pixels across, 35
  rem lines up and down; gen/boss2tab.asm), a third of a turn apart, faster
  rem as they fall.
boss2_orbit
  asm
  ldy #1
  ldx #10
b2_orbit_dead
  lda etype,x
  bne b2_orbit_alive
  iny
b2_orbit_alive
  dex
  cpx #7
  bne b2_orbit_dead
  tya
  clc
  adc borbit
  sta borbit
  ldx #8
b2_orbit_pod
  sta temp2
  lsr
  tay
  lda orb2x,y
  sta bdx,x
  lda orb2y,y
  sta bdy,x
  lda temp2
  clc
  adc #85
  inx
  cpx #11
  bne b2_orbit_pod
end
  return

  rem The pods' lights turn; the cannon glows before each sweep.
boss2_frames
  temp1 = (tick / 8) & 1
  eframe[8] = temp1 : eframe[10] = temp1
  eframe[9] = 1 - temp1
  eframe[0] = 0
  if etype[0] <> ET_PCANNON then return
  if btl >= 40 && btl < 64 then eframe[0] = (tick / 4) & 1
  return

boss2_attack
  rem pods: aimed pink triplets, one pod after another (faster when hurt)
  temp3 = 0
  for k = 8 to 10
    if etype[k] = 0 then temp3 = temp3 + 1
  next
  temp4 = 127
  if bcorehp < 125 then temp4 = 63
  for k = 8 to 10
    if etype[k] = 0 then goto b2_pod_next
    temp1 = (btl + k * 42) & temp4
    if temp1 then goto b2_pod_next
    fx = exh[k] + 6 : fy = eyh[k] + 14
    gosub aim
    fkind = BK_PINK : fspd = 52 : fcount = 3 : fstep = 12
    asm
    jsr bul_fan
end
b2_pod_next
  next
  rem shoulder turrets: aimed blue shots, by turns
  for k = 1 to 2
    if etype[k] = 0 then goto b2_tur_next
    temp1 = (btl + k * 32) & 63
    if temp1 then goto b2_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 12
    gosub aim
    fkind = BK_BLUE : fspd = 54
    asm
    jsr bul_fire
end
b2_tur_next
  next
  rem cannon: every 256 steps a stream of twin needles sweeps across
  rem the screen, one way then the other
  if etype[0] <> ET_PCANNON then goto b2_core
  if btl = 64 then bsweep = 48 : bsdir = 0 - bsdir
  if bsweep = 0 then goto b2_core
  bsweep = bsweep - 1
  temp1 = bsweep & 3
  if temp1 then goto b2_core
  temp1 = 24 - bsweep
  fang = 64 + temp1
  if bsdir > 1 then fang = 64 - temp1
  fkind = BK_NEEDLE : fspd = 64
  fx = exh[0] + 3 : fy = eyh[0] + 30
  asm
  jsr bul_fire
end
  fx = exh[0] + 10
  asm
  jsr bul_fire
end
b2_core
  rem core: turning rings once two pods are gone, time drags on, or it
  rem is hurt (and twice as often then)
  temp5 = 0
  if temp3 >= 2 then temp5 = 1
  if bth >= 6 then temp5 = 1
  if bcorehp < 125 then temp5 = 1
  if temp5 = 0 then return
  temp4 = 63
  if bcorehp < 125 then temp4 = 31
  temp1 = btl & temp4
  if temp1 = 0 then bring = 8 : bspin = bspin + 7
  rem a ring of 8, pink and blue, two a step (bring counts them down)
  if bring = 0 then return
  fx = bx - 2 : fy = by + 4 : fspd = 38
  for k = 0 to 1
    bring = bring - 1
    fang = bring * 32 + bspin : fkind = BK_PINK
    temp1 = bring & 1
    if temp1 then fkind = BK_BLUE
    asm
    jsr bul_fire
end
  next
  return

  rem ---- parts: type, image, hit points, offset from the centre ----
  rem the pods' orbit table
  inline boss2tab.asm

  data boss2_type
  ET_PCANNON, ET_PTURRET, ET_PTURRET, 0, 0, ET_PCORE, ET_PCORE, 0, ET_PPOD, ET_PPOD, ET_PPOD
end
  data boss2_img
  IMG_B2CANNON, IMG_BTURRET, IMG_BTURRET, 0, 0, IMG_B2CORET, IMG_B2COREB, 0, IMG_B2POD, IMG_B2POD, IMG_B2POD
end
  data boss2_hp
  160, 50, 50, 0, 0, 255, 255, 0, 120, 120, 120
end
  rem top-left x and y of each part relative to (bx, by), two's complement
  rem (the pods' are set as they orbit)
  data boss2_dx
  248, 239, 9, 0, 0, 240, 240, 0, 0, 0, 0
end
  data boss2_dy
  21, 231, 231, 0, 0, 224, 0, 0, 0, 0, 0
end
