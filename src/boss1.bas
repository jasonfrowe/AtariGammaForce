  rem ======================================================================
  rem  The GAMMA CORE's own code: its parts, the wings' turret columns and
  rem  the cannon's glow, its attacks. It lives in stage 1's bank (switched
  rem  in for the whole stage); the shared boss code in gammaforce.bas
  rem  calls it. Slots: 0 the cannon, 1-4 the wings (top halves 1 and 3,
  rem  bottom halves 2 and 4), 5-6 the core, 7-10 the wings' turrets.
  rem ======================================================================

boss1_build
  for k = 0 to 10
    etype[k] = boss_type[k] : eimg[k] = boss_img[k] : ehp[k] = boss_hp[k]
    bdx[k] = boss_dx[k] : bdy[k] = boss_dy[k] : bwt[k] = boss_wt[k]
  next
  return

boss1_frames
  rem shots pass through a wing's turret column while it has turrets
  temp1 = etype[7] | etype[8]
  eparam[1] = temp1 : eparam[2] = temp1
  temp1 = etype[9] | etype[10]
  eparam[3] = temp1 : eparam[4] = temp1
  rem the cannon glows before it fires
  eframe[0] = 0
  if etype[0] <> ET_PCANNON then return
  temp1 = btl & 255
  if temp1 >= 96 && temp1 < 128 then eframe[0] = (tick / 4) & 1
  return

boss1_attack
  gosub boss_burst
  rem turrets: aimed blue shots, staggered
  for k = 7 to 10
    if etype[k] = 0 then goto boss_att_next
    temp1 = (btl + k * 17) & 63
    if temp1 then goto boss_att_next
    fx = exh[k] + 4 : fy = eyh[k] + 12
    gosub aim
    fkind = BK_BLUE : fspd = 52
    asm
    jsr bul_fire
end
boss_att_next
  next
  rem wings: pink fans, alternating sides
  temp1 = btl & 127
  if temp1 = 0 && etype[1] = ET_PWING then fx = exh[1] + 8 : fy = eyh[1] + 56 : fang = 72 : gosub boss_fan
  if temp1 = 64 && etype[3] = ET_PWING then fx = exh[3] + 8 : fy = eyh[3] + 56 : fang = 56 : gosub boss_fan
  rem cannon: three big pink orbs at the player. Absorb them!
  temp1 = btl & 255
  if temp1 = 128 && etype[0] = ET_PCANNON then gosub boss_cannon
  rem core: spirals once a wing is gone, time drags on, or it is hurt
  temp2 = 0
  if etype[1] <> ET_PWING then temp2 = 1
  if etype[3] <> ET_PWING then temp2 = temp2 + 1
  temp3 = 0
  if bcorehp < 112 then temp3 = 1
  if temp2 = 0 && temp3 = 0 && bth < 6 then return
  temp1 = btl & 7
  if temp3 then temp1 = btl & 3
  if temp1 then return
  fx = bx + 2 : fy = by + 4 : fang = bspin : fspd = 42
  fkind = BK_PINK
  temp1 = btl & 16
  if temp1 then fkind = BK_BLUE
  asm
  jsr bul_fire
end
  if temp2 = 2 then fang = bspin + 128 : asm
  jsr bul_fire
end
  bspin = bspin + 11
  return

  rem Concentrated fire: twice every 256 steps the part nearest the
  rem player flashes (four times, a warning), then fires six fast aimed
  rem shots at it, pink and blue in turn. bburst counts down every 4 steps.
boss_burst
  temp1 = btl & 127
  if temp1 = 96 then gosub boss_pick
  if bburst = 0 then return
  temp1 = btl & 3
  if temp1 then return
  bburst = bburst - 1
  k = bsrc
  temp2 = etype[k]
  if temp2 = 0 then bburst = 0 : return
  if temp2 = ET_PWRECK then bburst = 0 : return
  if bburst < 6 then goto boss_burst_fire
  eflash[k] = 3
  temp5 = k + 1
  if temp2 = ET_PWING then eflash[temp5] = 3
  if temp2 = ET_PCORE then eflash[temp5] = 3
  return
boss_burst_fire
  fx = exh[k] + burst_dx[k] : fy = eyh[k] + burst_dy[k]
  gosub aim
  fkind = BK_BLUE : fspd = 64
  temp1 = bburst & 1
  if temp1 then fkind = BK_PINK
  asm
  jsr bul_fire
end
  return

  rem the live part whose middle is nearest the player across
boss_pick
  temp3 = 255 : bsrc = 255
  for k = 0 to 10
    temp2 = etype[k]
    if temp2 = 0 then goto boss_pick_next
    if temp2 = ET_PARMOR then goto boss_pick_next
    if temp2 = ET_PWRECK then goto boss_pick_next
    if k = 6 then goto boss_pick_next
    temp1 = exh[k] + burst_dx[k]
    temp4 = temp1 - pcx
    if temp1 < pcx then temp4 = pcx - temp1
    if temp4 < temp3 then temp3 = temp4 : bsrc = k
boss_pick_next
  next
  if bsrc < 255 then bburst = 10
  return

boss_fan
  fkind = BK_PINK : fspd = 49 : fcount = 3 : fstep = 12
  asm
  jsr bul_fan
end
  return

boss_cannon
  fx = exh[0] + 8 : fy = eyh[0] + 28
  gosub aim
  fkind = 3 : fspd = 38 : fcount = 3 : fstep = 18
  asm
  jsr bul_fan
  lda #SFX_HIT
  jsr sfx_play
end
  return

  rem ---- boss parts: type, image, hit points, offset from the centre ----
  data boss_type
  ET_PCANNON, ET_PWING, ET_PARMOR, ET_PWING, ET_PARMOR, ET_PCORE, ET_PCORE, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET
end
  data boss_img
  IMG_BCANNON, IMG_BWINGLT, IMG_BWINGLB, IMG_BWINGRT, IMG_BWINGRB, IMG_BCORET, IMG_BCOREB, IMG_BTURRET, IMG_BTURRET, IMG_BTURRET, IMG_BTURRET
end
  data boss_hp
  150, 180, 255, 180, 255, 255, 255, 60, 60, 60, 60
end
  rem top-left x and y of each part relative to (bx, by), two's complement
  data boss_dx
  248, 224, 224, 16, 16, 240, 240, 228, 228, 20, 20
end
  data boss_dy
  28, 220, 252, 220, 252, 224, 0, 232, 254, 232, 254
end
  rem each part's share of the boss (%; the core's 30 is counted apart)
  data boss_wt
  12, 15, 0, 15, 0, 0, 0, 7, 7, 7, 7
end
  rem where each part fires its burst from, from its top left (the wings
  rem from their bottom end, the core from its middle)
  data burst_dx
  8, 8, 0, 8, 0, 16, 16, 4, 4, 4, 4
end
  data burst_dy
  30, 60, 0, 60, 0, 36, 0, 12, 12, 12, 12
end

