  rem ======================================================================
  rem  DEEP FIELD's asteroids (stage 8's bank; the main loop calls it each
  rem  step, by the bank's hook vector). They are map tiles, and the solid
  rem  ones (mostly rock) stop the player's shots and the enemies' bullets,
  rem  and the ship crashes on them (MegaGammaForce's: tested at its middle,
  rem  and here at its nose too, so it can graze one). Each map row's solid
  rem  columns follow its background objects (gen_assets stage_bank: a bit
  rem  for each of its 20 columns, in 3 bytes). The swords pass through, as
  rem  in MegaGammaForce.
  rem  A pixel at playfield y + 32 (py) is at world height spos + 240 - py,
  rem  so in map row (spos + 239 - py) / 16.
  rem ======================================================================

deep
  asm
  lda spos_hi
  cmp #DP_END
  bcs dp_done              ; (past the last drift)
  ; the shots: each one's tip
  ldx #NS-1
dp_shots
  lda shy,x
  beq dp_snext
  tay
  lda shx,x
  clc
  adc #2
  stx obi
  jsr dp_solid
  ldx obi
  bcc dp_snext
  lda #0
  sta shy,x
dp_snext
  dex
  bpl dp_shots
  ; the bullets: half of them a step, by turns
  lda tick
  and #1
  tax
dp_buls
  lda bkind,x
  beq dp_bnext
  ldy byh,x
  lda bxh,x
  stx obi
  jsr dp_solid
  ldx obi
  bcc dp_bnext
  lda #0
  sta bkind,x
dp_bnext
  inx
  inx
  cpx #NB
  bcc dp_buls
  ; the ship: its middle and its nose
  lda plvuln
  beq dp_done
  ldy pcy
  lda pcx
  jsr dp_solid
  bcs dp_crash
  lda ply
  clc
  adc #4
  tay
  lda pcx
  jsr dp_solid
  bcc dp_done
dp_crash
  lda #1
  sta phit
dp_done
end
  return

  rem Is the pixel at x A, playfield y + 32 Y in a solid tile? Carry set
  rem if so.
  asm
dp_solid
  cmp #160
  bcs dp_clear
  sta ob1
  sty ob2
  clc
  lda spos_lo
  adc #239
  sta ob3
  lda spos_hi
  adc #0
  sta ob5
  sec
  lda ob3
  sbc ob2
  sta ob3
  lda ob5
  sbc #0
  cmp #16
  bcs dp_clear             ; (row 256 on: none; or above the map's start)
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
  bcs dp_clear
  tax
  lda stg_rowlo,x
  sta ob6
  lda stg_rowhi,x
  sta ob7
  ldy #0
  lda (ob6),y              ; its objects' bytes
  sta ob3
  lda ob1
  lsr
  lsr
  lsr
  tax                      ; the column
  lsr
  lsr
  lsr                      ; its byte of the mask (carry clear)
  sec                      ; (+1: past the count)
  adc ob3
  tay
  lda (ob6),y
  and dp_bit,x
  beq dp_clear
  sec
  rts
dp_clear
  clc
  rts
dp_bit
  .byte 1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128,1,2,4,8
end
