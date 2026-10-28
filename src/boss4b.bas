  rem ======================================================================
  rem  DUNE WYRM's head moving on its heading (the chase, the way back),
  rem  its sinking, and its tables (boss4.bas has the rest). In stage 4's
  rem  bank, before its graphics block.
  rem ======================================================================

  rem the head on by heading b4ang at speed fspd, kept on the screen
b4_move
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
  rem each slot's lag on the trail (entries, 2 frames each: 11 frames a
  rem segment; the head, 0, is where it is)
  data b4lagt
  50, 44, 39, 33, 28, 22, 17, 11, 6, 0, 0
end
