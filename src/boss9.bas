  rem ======================================================================
  rem  GAMMA PRIME, the stage 9 boss, the last: the Gamma Core's true form,
  rem  built on SPIRE WARDEN (stage 2's boss) in gold. Sprites over the
  rem  flares, which keep scrolling by (the map's last chunk loops). It
  rem  sways, bobs and every so often dives at the ship (as SPIRE WARDEN).
  rem  Three prisms orbit the core firing pink threes; two shoulder turrets
  rem  fire aimed blue; the cannon below sweeps twin needles across.
  rem  Two nodes stand atop it, out of the Vulcan's reach (shots stop on
  rem  them, harmless: ET_PNODE): only the Hyper Sword's beam breaks one.
  rem  Its phases (b9phase):
  rem    0  the core is shut (gold: shots stop on it, and it keeps its
  rem       health, b9hp); both nodes live
  rem    1  a node broken: the core opens (red), the other node sealed
  rem    2  the core at half: it shuts again, the prisms grow back, and
  rem       the other node can be broken
  rem    3  both broken: the core opens for good, and pours out its light
  rem       (a spray of pink and blue at the ship)
  rem  The core fires rings throughout: all pink while shut (pink for the
  rem  sword to soak up, toward the Hyper), pink and blue open. Open, it
  rem  takes half of each hit (b9_soak).
  rem  Slots: 0 the cannon, 1-2 the turrets, 3-4 the nodes, 5-6 the core
  rem  (its top and bottom halves, sharing bcorehp), 8-10 the prisms (last:
  rem  as SPIRE WARDEN's pods, so the parts drawn before them keep their
  rem  places).
  rem  It lives in stage 9's bank; the shared boss code calls it.
  rem ======================================================================

  rem its phase (0-3); the core's health last step (shut, it keeps it);
  rem the odd point of its last hits (open, it takes half of them)
  dim b9phase = $22E5
  dim b9hp = $22E6
  dim b9odd = $22E7

boss9_build
  for k = 0 to 11
    etype[k] = boss9_type[k] : eimg[k] = boss9_img[k] : ehp[k] = boss9_hp[k]
    bdx[k] = boss9_dx[k] : bdy[k] = boss9_dy[k]
    bwt[k] = boss9_wt[k] : eparam[k] = 0 : ecol[k] = boss9_col[k]
  next
  rem (the shared code readies slots 0-10)
  eflash[11] = 0 : ehit[11] = 0 : eframe[11] = 0 : evx[11] = 0 : evy[11] = 0 : ewamp[11] = 0
  bcorehp = 250 : b9hp = 250 : b9odd = 0 : borbit = 0 : bsweep = 0 : bsdir = 1 : bring = 0 : b9phase = 0
  return

  rem In from the top (the shared code's: down to line 89)
boss9_enter
  goto boss_enter_1

boss9_fight
  btl = btl + 1
  if btl = 0 then bth = bth + 1
  rem sway: x = 80 + 12 sin(t/2), y = 89 + 7 sin(t/4) (SPIRE WARDEN's)
  wang = btl / 2 + 192 : wamp = 12
  asm
  jsr weave
end
  bx = 80 + woff
  wang = btl / 4 + 192 : wamp = 7
  asm
  jsr weave
end
  by = 89 + woff
  rem every third spell of 256 steps it swoops down at the ship and back
  rem up: 0-72 lines lower
  temp1 = bth
b9_mod3
  if temp1 >= 3 then temp1 = temp1 - 3 : goto b9_mod3
  if temp1 <> 2 then goto b9_nodive
  temp6 = by
  wang = btl : wamp = 36
  asm
  jsr weave
end
  by = temp6 + 36 - woff
b9_nodive
  rem the prisms turn: a step a frame, and one more for each gone
  borbit = borbit + 1
  for k = 8 to 10
    if etype[k] <> ET_PPOD then borbit = borbit + 1
  next
  gosub boss9_place
  rem about 2.5 minutes, and it escapes
  if bth >= 35 then bescape = 1 : gosub boss_tally : bstate = 4 : btl = 200 : return
  if plvuln = 0 then return
  gosub boss9_attack
  return

  rem Each part from the centre (bx, by): bdx, bdy, the prisms' from their
  rem orbit (40 pixels across, 44 lines up and down, a third of a turn
  rem apart); a part above the screen's top is parked at 0, wholly above
  rem it (as the shared code's boss_place). Then its phases, its frames.
boss9_place
  for k = 8 to 10
    temp7 = borbit + boss9_pang[k]
    wang = temp7 : wamp = 40
    asm
    jsr weave
end
    bdx[k] = woff - 8
    wang = temp7 - 64 : wamp = 44
    asm
    jsr weave
end
    bdy[k] = woff - 8
  next
  asm
  ldx #10
b9p_loop
  lda etype,x
  beq b9p_next
  lda bx
  clc
  adc bdx,x
  sta exh,x
  lda bdy,x
  bpl b9p_down
  clc
  adc by
  bcs b9p_y
  lda #0
  beq b9p_y
b9p_down
  clc
  adc by
b9p_y
  sta eyh,x
b9p_next
  dex
  bpl b9p_loop
end
  rem its phases: a node broken opens the core; the core at half shuts it
  rem and the prisms grow back; the other node broken opens it for good
  temp1 = 0
  if etype[3] = ET_PNODE then temp1 = 1
  if etype[4] = ET_PNODE then temp1 = temp1 + 1
  if b9phase = 0 && temp1 < 2 then b9phase = 1
  if b9phase = 1 && bcorehp < 125 then b9phase = 2 : gosub b9_regrow
  if b9phase = 2 && temp1 = 0 then b9phase = 3
  rem open (red), its hits count, half of each (twice the health the
  rem shared code gives a core); shut (gold), it keeps its health
  temp2 = b9phase & 1
  ecol[5] = 6
  if temp2 then ecol[5] = 4 : gosub b9_soak
  if temp2 = 0 then bcorehp = b9hp
  ecol[6] = ecol[5]
  rem (the shared code flashes the top half: the bottom with it)
  eflash[6] = eflash[5]
  rem the nodes: live (red, open) or sealed (gold, shut: while the core
  rem is open in phase 1, the other can't be broken)
  for k = 3 to 4
    if etype[k] <> ET_PNODE then goto b9_node_next
    eframe[k] = 1 : ecol[k] = 4
    if b9phase <> 1 then goto b9_node_next
    eframe[k] = 0 : ecol[k] = 6 : ehp[k] = 90
b9_node_next
  next
  rem the prisms turn; the open core pulses; the cannon glows before
  rem each sweep
  temp1 = (tick / 8) & 1
  eframe[8] = temp1 : eframe[10] = temp1 : eframe[9] = 1 - temp1
  eframe[5] = 0
  if temp2 then eframe[5] = temp1
  eframe[6] = eframe[5]
  eframe[0] = 0
  if etype[0] <> ET_PCANNON then goto b9_noglow
  if btl >= 40 && btl < 64 then eframe[0] = (tick / 4) & 1
b9_noglow
  rem the turrets turn to the ship, one a step
  k = (btl & 1) + 1
  if etype[k] <> ET_PTURRET then return
  fx = exh[k] + 4 : fy = eyh[k] + 8
  gosub aim
  eframe[k] = (fang - 48) / 32 & 7
  return

  rem Half the core's loss since the last step given back (the odd point
  rem kept for the next)
b9_soak
  if bcorehp >= b9hp then b9hp = bcorehp : return
  temp3 = b9hp - bcorehp + b9odd
  b9odd = temp3 & 1
  bcorehp = bcorehp + temp3 / 2
  b9hp = bcorehp
  return

  rem The prisms grow back (the core at half)
b9_regrow
  for k = 8 to 10
    etype[k] = ET_PPOD : eimg[k] = IMG_B9PRISM : ehp[k] = boss9_hp[k] : ecol[k] = 5
    eflash[k] = 0 : ehit[k] = 0
  next
  asm
  lda #SFX_READY
  jsr sfx_play
end
  return

boss9_attack
  rem prisms: aimed pink threes, one after another (faster once it is hurt)
  temp4 = 127
  if bcorehp < 125 then temp4 = 63
  for k = 8 to 10
    if etype[k] <> ET_PPOD then goto b9_pr_next
    if eyh[k] < 8 then goto b9_pr_next
    temp1 = (btl + k * 42) & temp4
    if temp1 then goto b9_pr_next
    fx = exh[k] + 6 : fy = eyh[k] + 6
    gosub aim
    fkind = BK_PINK : fspd = 52 : fcount = 3 : fstep = 12 : gosub b9_fan
b9_pr_next
  next
  rem shoulder turrets: aimed blue shots, by turns
  for k = 1 to 2
    if etype[k] <> ET_PTURRET then goto b9_tur_next
    temp1 = (btl + k * 32) & 63
    if temp1 then goto b9_tur_next
    fx = exh[k] + 4 : fy = eyh[k] + 12
    gosub aim
    fkind = BK_BLUE : fspd = 54
    asm
    jsr bul_fire
end
b9_tur_next
  next
  rem cannon: every 256 steps a stream of twin needles sweeps across the
  rem screen, one way then the other
  if etype[0] <> ET_PCANNON then goto b9_core
  if btl = 64 then bsweep = 48 : bsdir = 0 - bsdir
  if bsweep = 0 then goto b9_core
  bsweep = bsweep - 1
  temp1 = bsweep & 3
  if temp1 then goto b9_core
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
b9_core
  rem the core: turning rings of 8, always (so there is always pink for
  rem the sword, and the Hyper); shut, all pink; open, pink and blue, and
  rem twice as often once it is hurt; for good, a spray at the ship besides
  temp3 = b9phase & 1
  temp4 = 63
  if temp3 && bcorehp < 125 then temp4 = 31
  temp1 = btl & temp4
  if temp1 = 0 then bring = 8 : bspin = bspin + 7
  if bring = 0 then goto b9_spray
  fx = bx - 2 : fy = by + 4 : fspd = 38
  for k = 0 to 1
    bring = bring - 1
    fang = bring * 32 + bspin : fkind = BK_PINK
    temp1 = bring & temp3
    if temp1 then fkind = BK_BLUE
    asm
    jsr bul_fire
end
  next
b9_spray
  rem a two-armed spray, a pink arm and a blue, aimed, the arms swinging
  rem through 30 degrees, every 8 frames
  if b9phase <> 3 then return
  temp1 = btl & 7
  if temp1 then return
  fx = bx - 2 : fy = by + 4
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

  rem It burns where it is (the shared code's explosions)
boss9_sinking
  return

  rem the prisms' places round the orbit (a third of a turn apart)
  data boss9_pang
  0, 0, 0, 0, 0, 0, 0, 0, 0, 85, 170, 0
end

  rem ---- parts: type, image, hit points, offset from the centre, share
  rem of the boss (%: the core's 30 is counted apart), palette (6 the
  rem gold: P0-P2 are the stage's) ----
  data boss9_type
  ET_PCANNON, ET_PTURRET, ET_PTURRET, ET_PNODE, ET_PNODE, ET_PCORE, ET_PCORE, 0, ET_PPOD, ET_PPOD, ET_PPOD, 0
end
  data boss9_img
  IMG_BCANNON, IMG_BTURRET, IMG_BTURRET, IMG_B9NODE, IMG_B9NODE, IMG_B9CORET, IMG_B9COREB, 0, IMG_B9PRISM, IMG_B9PRISM, IMG_B9PRISM, 0
end
  data boss9_hp
  240, 120, 120, 90, 90, 255, 255, 0, 150, 150, 150, 0
end
  rem top-left x and y of each part relative to (bx, by), two's complement
  rem (the prisms' are set as they orbit): the core round the centre, the
  rem cannon under it, the turrets at its sides, the nodes above them
  data boss9_dx
  248, 230, 18, 226, 22, 240, 240, 0, 0, 0, 0, 0
end
  data boss9_dy
  28, 248, 248, 216, 216, 224, 0, 0, 0, 0, 0, 0
end
  data boss9_wt
  20, 7, 7, 12, 12, 0, 0, 0, 4, 4, 4, 0
end
  data boss9_col
  6, 6, 6, 4, 4, 6, 6, 0, 5, 5, 5, 0
end
