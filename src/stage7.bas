  rem ======================================================================
  rem  The launch rails (stage 7's bank; the main loop calls it each step
  rem  while stage 7 is played): the bases fire cargo canisters up from
  rem  behind the ship. Every 2.5 seconds or so one comes in under the ship,
  rem  at the bottom of the screen, its nose showing, blinking red
  rem  and yellow for 48 frames; then it shoots up the screen. It is a
  rem  tower (shots stop on it), but rising it is a projectile: touching it
  rem  is a hit. Canisters come from early in the stage until the boss is
  rem  beaten or escapes. A canister's line is the scroll plus
  rem  eparam (objects.asm en_update): waiting, eparam keeps it on its line;
  rem  rising, it loses 3 a step (about 2.4 lines a frame up the screen).
  rem  estate: 1 waiting (ewang its count: etimer is en_think's), 2 rising.
  rem  Waiting, it hisses, rising in pitch to the launch (on the TIA's
  rem  explosions channel, below them all; its data is here, in stage 7's
  rem  bank). In the fight, one every 4.2 seconds.
  rem ======================================================================

  rem the next launch's count
  dim b7launch = $22E4

lunar
  rem launches: from scroll 512 on, through MASS DRIVER's fight, not once
  rem it is beaten
  if bstate >= 4 then goto lunar_move
  if spos_hi < 2 then goto lunar_move
  b7launch = b7launch + 1
  temp1 = 150
  if bstate then temp1 = 250
  if b7launch < temp1 then goto lunar_move
  b7launch = 0
  rem in the fight only slots 10 and 11: a destroyed part's slot is empty
  rem but still MASS DRIVER's
  temp2 = 0
  if bstate then temp2 = 10
  for k = temp2 to NEW1
    if etype[k] = 0 then goto lunar_spawn
  next
  goto lunar_move
lunar_spawn
  rem under the ship (its middle), kept on the screen
  temp1 = plx + 4
  if temp1 > 150 then temp1 = 150
  etype[k] = ET_TOWER : eimg[k] = IMG_B7CAN : ehp[k] = 255 : ecol[k] = 4
  exh[k] = temp1 : eparam[k] = 228 - spos_lo : estate[k] = 1 : ewang[k] = 48
  evx[k] = 0 : evy[k] = 0 : ewamp[k] = 0 : eframe[k] = 0 : ehit[k] = 0 : eflash[k] = 0
  rem its hiss, unless an explosion is playing (sfx.asm's channel 1, by
  rem hand: the sound's data is in this bank)
  asm
  lda sfx_ptrhi+1
  beq lu_hiss
  lda sfx_pri+1
  cmp #2
  bcs lu_quiet
lu_hiss
  lda #0
  sta sfx_ptrhi+1
  lda #1
  sta sfx_pri+1
  lda #<lu_sfx
  sta sfx_ptrlo+1
  lda #>lu_sfx
  sta sfx_ptrhi+1
lu_quiet
end
lunar_move
  for i = 0 to NEW1
    if etype[i] <> ET_TOWER then goto lunar_next
    if estate[i] = 2 then goto lunar_rise
    if estate[i] <> 1 then goto lunar_next
    rem waiting: on its line, blinking
    eparam[i] = 228 - spos_lo
    temp1 = ewang[i] & 4
    ecol[i] = 4
    if temp1 then ecol[i] = 6
    ewang[i] = ewang[i] - 1
    if ewang[i] = 0 then estate[i] = 2 : ecol[i] = 4
    goto lunar_next
lunar_rise
    eparam[i] = eparam[i] - 3
    rem a hit: the ship's body (plx + 3 to plx + 12 across, ply + 2 to
    rem ply + 21 down) touching it, or just above it (the tower's push may
    rem have moved the ship out of it)
    if plvuln = 0 then goto lunar_next
    temp1 = exh[i] + 8
    if plx + 3 >= temp1 then goto lunar_next
    temp1 = plx + 12
    if temp1 < exh[i] then goto lunar_next
    temp1 = ply + 26
    if temp1 < eyh[i] then goto lunar_next
    temp1 = eyh[i] + 31
    if ply + 2 > temp1 then goto lunar_next
    phit = 1
lunar_next
  next
  return

  rem the canister's hiss (sfx.asm's format: AUDC, AUDF, AUDV a frame;
  rem noise, rising)
  asm
lu_sfx
  .byte 8,26,2,8,26,2,8,25,2,8,25,2,8,24,2,8,24,3,8,23,3,8,23,3
  .byte 8,22,3,8,22,3,8,21,3,8,21,3,8,20,3,8,20,3,8,19,4,8,19,4
  .byte 8,18,4,8,18,4,8,17,4,8,17,4,8,16,4,8,16,4,8,15,4,8,15,5
  .byte 8,14,5,8,14,5,8,13,5,8,13,5,8,12,5,8,12,5,8,11,5,8,11,5
  .byte 8,10,6,8,10,6,8,9,6,8,9,6,8,8,6,8,8,6,8,7,6,8,7,6
  .byte 8,6,6,8,6,7,8,5,7,8,5,7,8,4,7,8,4,7,8,3,4,8,3,2
  .byte $FF
end
