  rem ======================================================================
  rem  FROZEN STRAIT's blizzards (stage 5's bank; the main loop calls it
  rem  each step while stage 5 is played). Over two stretches of the stage
  rem  (and by turns at GLACIER CRAWLER's reactor sled)
  rem  snow drives across the screen (eight streak sprites), the wind drifts
  rem  the ship to the left, and in its gusts the ice turns paler, so the
  rem  white bergs, slabs and snow are harder to see. The background color
  rem  is changed off the screen (userinterrupt writes bgwant), so no line
  rem  shows two colors.
  rem ======================================================================

  rem the streaks' x and line (+ 32): stage 4's trail, free here
  dim snx = $2740
  dim sny = $2748

blizzard
  rem the blizzards: scroll 1280-1791 and 2304-2815; and at the crawler's
  rem reactor sled (boss5.bas: phase 2), every other 256 steps
  temp1 = 0
  if spos_hi = 5 || spos_hi = 6 then temp1 = 1
  if spos_hi = 9 || spos_hi = 10 then temp1 = 1
  if bstate then temp1 = 0
  if bstate = 3 && b5phase = 2 then temp1 = bth & 1
  bgwant = stg_bg
  if temp1 = 0 then return
  rem a gust for 40 steps in every 128
  temp2 = tick & 127
  if temp2 >= 40 then goto bz_wind
  asm
  lda #B5_GUST
  sta bgwant
end
bz_wind
  rem the wind: a pixel every 4 steps to the left (every 2 in a gust)
  temp3 = tick & 3
  if temp2 < 40 then temp3 = tick & 1
  if temp3 = 0 && plx > 6 && pdead = 0 then plx = plx - 1
  rem the streaks: 3 pixels left and 2-3 lines down a step; one that
  rem leaves comes back in from the top or the right
  for k = 0 to 7
    temp4 = snx[k] - 3
    temp5 = sny[k] + 2 + (k & 1)
    if temp4 >= 156 then temp4 = 152 : temp5 = (rand & 127) + 32
    if temp5 >= 242 then temp5 = 30 : temp4 = (rand & 127) + 24
    snx[k] = temp4 : sny[k] = temp5
    if pfnodraw then goto bz_next
    pimg = IMG_FLAKE : pframe = 0 : ppal = 1 : px = temp4 : py = temp5
    asm
    jsr pf_drawimg
end
bz_next
  next
  return
