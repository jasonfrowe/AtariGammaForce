  rem ======================================================================
  rem  CORONA's flares (stage 9's bank; the main loop calls it each step, by
  rem  the bank's hook vector). They are map tiles in two groups: A in P0, B
  rem  in P1 (the same tiles, gen_assets stage9). Each group lies dark, then
  rem  flickers faster and faster in warning, then erupts, then fades: a
  rem  cycle of 512 frames (the clock turns every other frame: at
  rem  MegaGammaForce's 256 they changed too often), B half a cycle behind
  rem  A, so they take turns (MegaGammaForce's bg.c). Erupting, a flare is fatal to fly through
  rem  (tested at the ship's middle and 3 pixels either side, as
  rem  MegaGammaForce's); shots, bullets and the enemies pass through.
  rem  Past the flares (FL_END), P0 and P1 hold GAMMA PRIME's gold and its
  rem  spine's gamma light, which runs.
  rem ======================================================================

  rem the flares' clock (0-255)
  dim flt = $22CB

corona
  asm
  lda spos_lo
  cmp #<FL_END
  lda spos_hi
  sbc #>FL_END
  bcc cr_flares
  ; GAMMA PRIME's colors: its gold, and its spine's two lights swapped
  ; every 8 frames
  ldx #2
cr_gold
  lda b9_cols,x
  sta P0C1,x
  dex
  bpl cr_gold
  lda b9_cols+3
  sta P1C1
  ldx b9_cols+4
  ldy b9_cols+5
  lda tick
  and #8
  beq cr_spine
  ldx b9_cols+5
  ldy b9_cols+4
cr_spine
  stx P1C2
  sty P1C3
  rts
cr_flares
  lda tick
  and #1
  bne cr_slow
  inc flt
cr_slow
  ; group A's colors (P0), then B's (P1), half a cycle on
  lda flt
  jsr cr_phase
  sta obj                  ; (A's phase)
  tax
  ldy #0
  jsr cr_colors
  lda flt
  eor #128
  jsr cr_phase
  sta ob8                  ; (B's)
  tax
  ldy #4
  jsr cr_colors
  ; the one erupting (never both): its palette, in an object's bits
  lda plvuln
  beq cr_done
  lda #0
  ldx obj
  cpx #2
  beq cr_ship
  lda #$20
  ldx ob8
  cpx #2
  bne cr_done
cr_ship
  sta obi
  ; the ship's middle, and 3 pixels either side
  lda pcx
  jsr cr_test
  bcs cr_crash
  lda pcx
  sec
  sbc #3
  jsr cr_test
  bcs cr_crash
  lda pcx
  clc
  adc #3
  jsr cr_test
  bcc cr_done
cr_crash
  lda #1
  sta phit
cr_done
  rts

  ; A = the clock: A = the phase (0 dark, 1 warning, 2 erupting, 3 fading)
cr_phase
  cmp #136
  bcc cr_dark
  cmp #216
  bcs cr_late
  ; the warning: a flicker, every 8 frames, then every 4
  cmp #176
  bcs cr_fast
  and #8
  bne cr_warn
cr_dark
  lda #0
  rts
cr_fast
  and #4
  beq cr_dark
cr_warn
  lda #1
  rts
cr_late
  cmp #244
  lda #2
  bcc cr_ph_done
  lda #3
cr_ph_done
  rts

  ; phase X's three colors into the palette at P0C1 + Y (P0: 0, P1: 4)
cr_colors
  lda cr_x3,x
  tax
  lda fl_cols,x
  sta P0C1,y
  lda fl_cols+1,x
  sta P0C2,y
  lda fl_cols+2,x
  sta P0C3,y
  rts
cr_x3
  .byte 0, 3, 6, 9

  ; Is the pixel at x A, the ship's line (pcy) in an erupting flare? Carry
  ; set if so: the tile there, found among its map row's background
  ; objects (5 bytes each: its characters' address lo, $60, hi, palette
  ; and width, x), is one that kills (characters FL_C0 to FL_C1) in the
  ; palette in obi (its bits as an object's: A $00, B $20).
cr_out
  clc
  rts
cr_test
  cmp #160
  bcs cr_out
  sta ob1
  clc
  lda spos_lo
  adc #239
  sta ob3
  lda spos_hi
  adc #0
  sta ob5
  sec
  lda ob3
  sbc pcy
  sta ob3
  lda ob5
  sbc #0
  cmp #16
  bcs cr_out               ; (row 256 on: none)
  asl
  asl
  asl
  asl
  sta ob5
  lda ob3
  lsr
  lsr
  lsr
  lsr
  ora ob5                  ; the map row
  cmp stg_rows
  bcs cr_out
  tax
  lda stg_rowlo,x
  sta ob6
  lda stg_rowhi,x
  sta ob7
  ldy #0
  lda (ob6),y              ; its objects' bytes
  sta ob3
  ldx #1                   ; (an object's first byte)
cr_obj
  txa
  sec
  sbc #1
  cmp ob3
  bcs cr_clear             ; (none there)
  txa
  clc
  adc #4
  tay
  lda ob1
  sec
  sbc (ob6),y              ; past its x?
  bcc cr_next
  sta ob2                  ; (pixels in)
  dey
  lda (ob6),y              ; its palette, its width (-tiles & 31)
  ora #$E0
  eor #$FF
  clc
  adc #1                   ; (its tiles)
  asl
  asl
  asl
  cmp ob2
  bcc cr_next
  beq cr_next              ; (past its end)
  lda (ob6),y
  and #$E0
  cmp obi
  bne cr_clear             ; (the other group, or the surface)
  txa
  tay
  lda (ob6),y              ; its characters' address
  sta ob5
  iny
  iny
  lda (ob6),y
  sta ob7
  lda ob5
  sta ob6
  lda ob2
  lsr
  lsr
  lsr
  tay
  lda (ob6),y              ; the character there
  cmp #FL_C0
  bcc cr_clear
  cmp #FL_C1
  bcs cr_clear
  sec
  rts
cr_next
  txa
  clc
  adc #5
  tax
  bne cr_obj
cr_clear
  clc
  rts
end
