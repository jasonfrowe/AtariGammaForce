  rem ======================================================================
  rem  FROZEN STRAIT's blizzards (stage 5's bank; the main loop calls it
  rem  each step while stage 5 is played). Over two stretches of the stage
  rem  (and all through GLACIER CRAWLER's last phase, the reactor sled)
  rem  snow drives across the screen (eight streak sprites), the wind drifts
  rem  the ship to the left, and in its gusts the ice turns paler, so the
  rem  white bergs, slabs and snow are harder to see. The background color
  rem  is changed off the screen (userinterrupt writes bgwant), so no line
  rem  shows two colors. In assembly: it runs every step, and as BASIC it
  rem  cost about 6 frames a second over the stage.
  rem ======================================================================

  rem the streaks' x and line (+ 32): stage 4's trail, free here
  dim snx = $2740
  dim sny = $2748

blizzard
  asm
     lda stg_bg
     sta bgwant
     ; on: scroll 1280-1791 and 2304-2815 (spos_hi 5-6, 9-10); in the
     ; boss fight, through the crawler's reactor sled (boss5.bas: phase 2)
     lda bstate
     beq bz_map
     cmp #3
     bne bz_quiet
     lda b5phase
     cmp #2
     beq bz_on
bz_quiet
     jmp bz_off
bz_map
     lda spos_hi
     cmp #5
     bcc bz_quiet
     cmp #7
     bcc bz_on
     cmp #9
     bcc bz_quiet
     cmp #11
     bcs bz_quiet
bz_on
     ; a gust for 40 steps in every 128 (the paler ice); the wind takes
     ; the ship a pixel left every 4 steps, every 2 in a gust
     lda tick
     and #127
     cmp #40
     lda tick
     bcs bz_calm
     ldx #B5_GUST
     stx bgwant
     and #1
     jmp bz_wind
bz_calm
     and #3
bz_wind
     bne bz_snow
     lda pdead
     bne bz_snow
     lda plx
     cmp #7
     bcc bz_snow
     dec plx
bz_snow
     ; the streaks: 3 pixels left and 2-3 lines down a step; one that
     ; leaves comes back in from the right or the top. One image (a single
     ; 8-line strip, palette 1), plotted straight with pf_plot.
     lda #<flake
     sta sp_lo
     lda #>flake
     sta sp_hi
     lda #(1<<5)|30          ; palette 1, 2 bytes wide
     sta sp_pw
     lda #8
     sta sp_h
     ldx #7
bz_loop
     stx temp6
     lda snx,x
     sec
     sbc #3
     sta temp4               ; x
     txa
     and #1
     sec
     adc #1                  ; 2 + (k & 1)
     clc
     adc sny,x
     sta temp5               ; line
     lda temp4
     cmp #156                ; off the left (wrapped below 0)
     bcc bz_xok
     lda #152
     sta temp4
     jsr randomize
     and #127
     clc
     adc #32
     sta temp5
bz_xok
     lda temp5
     cmp #242                ; off the bottom
     bcc bz_yok
     lda #30
     sta temp5
     jsr randomize
     and #127
     clc
     adc #24
     sta temp4
bz_yok
     lda temp4
     sta snx,x
     sta sp_x
     lda temp5
     sta sny,x
     sta sp_y
     lda pfnodraw
     bne bz_next
     jsr pf_plot             ; (uses X and Y)
     ldx temp6
bz_next
     dex
     bpl bz_loop
bz_off
end
  return
