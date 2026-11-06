  rem ======================================================================
  rem  The title screen's loop (stage 1's bank: the title shows with it in,
  rem  gammaforce.bas title switches it in): the logo, the stage and the
  rem  difficulty to choose, and on a fresh press of fire, back to the fixed
  rem  bank's title_go to start the game.
  rem ======================================================================
title2
  for i = 0 to NE1 : etype[i] = 0 : next
  for i = 0 to NB1 : bkind[i] = 0 : next
  for i = 0 to NS1 : shy[i] = 0 : next
  for i = 0 to NX1 : xt[i] = 0 : next
  temp9 = 30
  if selstage = 0 then selstage = 1
  asm
  jsr hud_hide
end
  asm
  lda #SONG_TITLE
  jsr mus_play
end
title_loop
  asm
  jsr pf_frame
end
  tick = tick + 1
  rem the logo, GAMMA over FORCE, in palette 4
  pframe = 0 : ppal = 4 : px = 34
  pimg = IMG_LOGO_GAMMA : py = 70
  asm
  jsr pf_drawimg
end
  pimg = IMG_LOGO_FORCE : py = 104
  asm
  jsr pf_drawimg
end
  tpal = 3
  tzone = 2 : temp1 = TXT_ATARI : gosub text
  rem the starting stage: left and right choose
  tpal = 6
  for k = 0 to 14 : rtline[k] = txt_sel1[k] : next
  rtline[10] = CH_0 + selstage * 2
  tzone = 9 : temp1 = TXT_SEL : gosub text
  tpal = 3
  tzone = 10 : temp1 = TXT_NAME1 + selstage - 1 : gosub text
  rem the difficulty: up and down choose
  rem (Expert in yellow, Normal in blue, Teddy Bear in the logo's colors)
  tpal = 6
  if easy = 1 then tpal = 5
  if easy = 2 then tpal = 4
  tzone = 11 : temp1 = TXT_MODE0 + easy : gosub text
  rem PRESS FIRE and the buttons, by turns
  tpal = 7 : temp1 = TXT_PUSH
  temp2 = tick & 64
  if temp2 then tpal = 3 : temp1 = TXT_B1
  tzone = 12 : gosub text
  tpal = 6
  tzone = 13 : temp1 = TXT_CREDIT : gosub text
  asm
  jsr pf_drawscreen
end
  rem Astrowing's rotating palette: each of the logo's colors steps
  rem through the 16 hues (a step every 4 frames) at its own brightness:
  rem a dark rim, the body, and the lit bevel a couple of hues ahead
  temp4 = tick / 4
  temp5 = temp4 & 15 : P4C1 = temp5 * 16 + 2
  P4C2 = temp5 * 16 + 7
  temp5 = (temp4 + 2) & 15 : P4C3 = temp5 * 16 + 13
  if selcd > 0 then selcd = selcd - 1 : goto title_fire
  if joy0left && selstage > 1 then selstage = selstage - 1 : selcd = 15
  if joy0right && selstage < NSTAGES then selstage = selstage + 1 : selcd = 15
  if joy0up && easy > 0 then easy = easy - 1 : selcd = 15
  if joy0down && easy < 2 then easy = easy + 1 : selcd = 15
title_fire
  rem Start on a fresh press of either button (released first)
  temp3 = 0
  if joy0fire0 then temp3 = 1
  if joy0fire1 then temp3 = 1
  if temp3 = 0 && temp9 > 0 then temp9 = temp9 - 1
  if temp3 = 0 then goto title_loop
  if temp9 > 0 then goto title_loop
  goto title_go
