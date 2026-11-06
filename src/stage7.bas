  rem ======================================================================
  rem  The launch rails (stage 7's bank; the main loop calls it each step
  rem  while stage 7 is played): the bases fire cargo canisters up from
  rem  behind the ship. Every 2.5 seconds or so one comes in under the ship,
  rem  at the bottom of the screen, its nose showing, blinking red
  rem  and yellow for 48 frames; then it shoots up the screen. It is a
  rem  tower (shots stop on it), but rising it is a projectile: touching it
  rem  is a hit. Canisters come from the stage's start to its last ground
  rem  units, not in the boss fight. A canister's line is the scroll plus
  rem  eparam (objects.asm en_update): waiting, eparam keeps it on its line;
  rem  rising, it loses 3 a step (about 2.4 lines a frame up the screen).
  rem  estate: 1 waiting (ewang its count: etimer is en_think's), 2 rising.
  rem ======================================================================

  rem the next launch's count
  dim b7launch = $22E4

lunar
  rem launches: from scroll 512 to 2815, not once the boss is on its way
  if bstate then goto lunar_move
  if spos_hi < 2 then goto lunar_move
  if spos_hi >= 11 then goto lunar_move
  b7launch = b7launch + 1
  if b7launch < 150 then goto lunar_move
  b7launch = 0
  for k = 0 to NEW1
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
