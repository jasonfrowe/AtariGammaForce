

; ---- the player ----
cs16_main
     ; which of this bank's scenes
     ldx #1-1
cs16_find
     cmp cs16_scenes,x
     beq cs16_found
     dex
     bpl cs16_find
     rts                     ; (none: not this bank's)
cs16_found
     stx cs_idx
     ifconst interrupthold
     lda #$FF
     sta interrupthold
     endif
     lda #0                  ; (stage 6's fade, still on after it: it would
     sta fadeon              ; write palette 1 and the background each frame)
     lda sINPT1              ; (a button already held doesn't count)
     and #$C0
     sta cs_prev
     ; the text rows clear
     lda #0
     ldx #0
cs16_clr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs16_clr
     jsr waitforvblankstart
     ldx cs_idx
     ; the palettes: the background, P0-P5 (the picture's), P6, P7 (the
     ; stripe's; white below it, cutvec)
     lda cs16_pallo,x
     sta pfq
     lda cs16_palhi,x
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant              ; (the picture's background, put back off the screen)
     ldx #0
cs16_pals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne cs16_palnext
     inx
cs16_palnext
     cpx #32
     bcc cs16_pals
     ldx cs_idx
     lda cs16_dlllo,x
     sta DPPL
     lda cs16_dllhi,x
     sta DPPH
     lda #<cs16_dli
     sta cutvec
     lda #>cs16_dli
     sta cutvec+1
     lda #<cs16_bottom
     sta cutvec2
     lda #>cs16_bottom
     sta cutvec2+1
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ; the first page
     lda cs16_pagelo,x
     sta pfp
     lda cs16_pagehi,x
     sta pfp+1
     jsr cs16_newpage
     lda #SONG_EPILOGUE
     jsr mus_play
cs16_loop
     jsr waitforvblankstart
     lda #3                  ; (7800basic's NMI count: as pf_drawscreen)
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     lda cs_state
     bne cs16_wait
     jsr cs16_type
     jmp cs16_input
cs16_wait
cs16_input
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev             ; (newly down)
     beq cs16_loop
     lda cs_state
     bne cs16_turn
cs16_finish                     ; typing: the rest of the page at once
     jsr cs16_type
     lda cs_state
     beq cs16_finish
     jmp cs16_loop
cs16_turn
     cmp #2
     beq cs16_exit
     jsr cs16_newpage
     jmp cs16_loop
cs16_exit
     jsr waitforvblankstart
     lda #0
     sta cutvec+1
     sta cutvec2+1
     sta bgwant
     lda #$70           ; DMA off: the caller rebuilds the screen
     sta CTRL
     lda #>DLLMEM
     sta DPPH
     lda #<DLLMEM
     sta DPPL
     jmp mus_stop
; (the high score table's: the title song plays on)
cs16_exitkeep
     jsr waitforvblankstart
     lda #0
     sta cutvec+1
     sta cutvec2+1
     sta bgwant
     lda #$70
     sta CTRL
     lda #>DLLMEM
     sta DPPH
     lda #<DLLMEM
     sta DPPL
     rts

; A new page: the rows clear, its portrait (a briefing's), typing from its
; text (pfp: its first byte, the portrait)
cs16_newpage
     lda #0
     sta cs_state
     sta cs_row
     sta cs_col
     ldx #0
cs16_npclr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs16_npclr
     ldy #0
     lda (pfp),y
     sta cs_por
     inc pfp
     bne cs16_np2
     inc pfp+1
cs16_np2
     if 0
     ldx cs_idx
     lda cs16_kind,x
     beq cs16_npdone
     jsr cs16_portrait
     endif
cs16_npdone
     rts

; One letter of the page onto its row (or a code)
cs16_type
     ldy #0
     lda (pfp),y
     inc pfp
     bne cs16_t2
     inc pfp+1
cs16_t2
     cmp #$40
     beq cs16_tnl
     cmp #$41
     beq cs16_tpage
     cmp #$42
     beq cs16_tend
     pha
     ldx cs_row
     lda cs16_rowlo,x
     sta pfq
     lda cs16_rowhi,x
     sta pfq+1
     ldy cs_col
     pla
     sta (pfq),y
     inc cs_col
     rts
cs16_tnl
     inc cs_row
     lda #0
     sta cs_col
     rts
cs16_tpage
     lda #1
     sta cs_state
     rts
cs16_tend
     lda #2
     sta cs_state
     rts

     if 0
; A briefing's top: the portrait (cs_por) in its three zones, its palettes
; (P0, P1), the two header lines beside it (the game's font: 160A)
cs16_portrait
     ldx cs_por
     lda cs16_porpal_lo,x
     sta pfq
     lda cs16_porpal_hi,x
     sta pfq+1
     ; (P0C1-P0C3 and P1C1-P1C3 are not contiguous: one by one)
     ldy #0
     lda (pfq),y
     sta P0C1
     iny
     lda (pfq),y
     sta P0C2
     iny
     lda (pfq),y
     sta P0C3
     iny
     lda (pfq),y
     sta P1C1
     iny
     lda (pfq),y
     sta P1C2
     iny
     lda (pfq),y
     sta P1C3
     ; the zones' lists (32 bytes apart): the portrait, an object a cell
     ; (16 bytes), then a header line (zones 0, 1), then the end
     lda cs16_porlo,x
     sta pfq
     lda cs16_porhi,x
     sta pfq+1
     ldy #0
cs16_pz
     lda (pfq),y
     sta $1C00,y
     iny
     cpy #16
     bne cs16_pz
cs16_pz1
     lda (pfq),y
     sta $1C10,y
     iny
     cpy #32
     bne cs16_pz1
cs16_pz2
     lda (pfq),y
     sta $1C20,y
     iny
     cpy #48
     bne cs16_pz2
     ldx cs_idx
     lda cs16_h0lo,x
     sta $1C10
     lda #$60
     sta $1C11
     lda cs16_h0hi,x
     sta $1C12
     lda cs16_h0w,x
     ora #(2<<5)
     sta $1C13
     lda #48
     sta $1C14
     lda cs16_h1lo,x
     sta $1C30
     lda #$60
     sta $1C31
     lda cs16_h1hi,x
     sta $1C32
     lda cs16_h1w,x
     ora #(3<<5)
     sta $1C33
     lda #48
     sta $1C34
     lda #0
     sta $1C15
     sta $1C16
     sta $1C35
     sta $1C36
     sta $1C50
     sta $1C51
     ; the header lines' colors: P2 amber, P3 white (the game's font: slot 3)
     lda #$2A
     sta P2C3
     lda #$0F
     sta P3C3
     rts
     endif

; The stripe's NMI (7800basic's top-of-screen one: topscreenroutine,
; cutvec): from the next line, 320A text, the font, a black background,
; palette 7 white
cs16_dli
     sta WSYNC
     lda #$43
     sta CTRL
     lda #>cs16_font
     sta CHARBASE
     lda #0
     sta BACKGRND
     lda #$0F
     sta P7C1
     sta P7C2
     sta P7C3
     rts

; The end of the screen (bottomscreenroutine, cutvec2): back for the top of
; the next frame (the background: userinterrupt, off the screen, bgwant)
cs16_bottom
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ldx cs_idx
     lda cs16_pallo,x
     sta pfq
     lda cs16_palhi,x
     sta pfq+1
     ldy #22                 ; (the stripe's colors: the scene's last three)
     lda (pfq),y
     sta P7C1
     iny
     lda (pfq),y
     sta P7C2
     iny
     lda (pfq),y
     sta P7C3
     rts

cs16_pal10 .byte $00,$0F,$91,$98,$03,$0B,$7E,$27,$7E,$91,$27,$2F,$2F,$0B,$9A,$9A,$00,$00,$00,$2A,$2A,$2A,$35,$29,$EC
cs16_dlstripe
  .byte <(cut_stripe16+0),248,>(cut_stripe16+0),0
  .byte <(cut_stripe16+0),248,>(cut_stripe16+0),32
  .byte <(cut_stripe16+0),248,>(cut_stripe16+0),64
  .byte <(cut_stripe16+0),248,>(cut_stripe16+0),96
  .byte <(cut_stripe16+0),248,>(cut_stripe16+0),128
  .byte 0,0
cs16_dlnone .byte 0,0
cs16_dlrow0
  .byte <$1900,$60,>$1900,206,8
  .byte <$1912,$60,>$1912,206,80
  .byte 0,0
cs16_dlrow1
  .byte <$1924,$60,>$1924,238,8
  .byte <$1936,$60,>$1936,238,80
  .byte 0,0
cs16_dlrow2
  .byte <$1948,$60,>$1948,238,8
  .byte <$195A,$60,>$195A,238,80
  .byte 0,0
cs16_dlrow3
  .byte <$196C,$60,>$196C,238,8
  .byte <$197E,$60,>$197E,238,80
  .byte 0,0
cs16_dlrow4
  .byte <$1990,$60,>$1990,238,8
  .byte <$19A2,$60,>$19A2,238,80
  .byte 0,0
cs16_dlrow5
  .byte <$19B4,$60,>$19B4,238,8
  .byte <$19C6,$60,>$19C6,238,80
  .byte 0,0
cs16_dlrow6
  .byte <$19D8,$60,>$19D8,238,8
  .byte <$19EA,$60,>$19EA,238,80
  .byte 0,0
cs16_dlrow7
  .byte <$19FC,$60,>$19FC,238,8
  .byte <$1A0E,$60,>$1A0E,238,80
  .byte 0,0
cs16_dlrow8
  .byte <$1A20,$60,>$1A20,238,8
  .byte <$1A32,$60,>$1A32,238,80
  .byte 0,0
cs16_dlrow9
  .byte <$1A44,$60,>$1A44,238,8
  .byte <$1A56,$60,>$1A56,238,80
  .byte 0,0
cs16_dlrow10
  .byte <$1A68,$60,>$1A68,238,8
  .byte <$1A7A,$60,>$1A7A,238,80
  .byte 0,0
cs16_dlrow11
  .byte <$1A8C,$60,>$1A8C,238,8
  .byte <$1A9E,$60,>$1A9E,238,80
  .byte 0,0
cs16_dlrow12
  .byte <$1AB0,$60,>$1AB0,238,8
  .byte <$1AC2,$60,>$1AC2,238,80
  .byte 0,0
cs16_rowlo .byte <$1900,<$1924,<$1948,<$196C,<$1990,<$19B4,<$19D8,<$19FC,<$1A20,<$1A44,<$1A68,<$1A8C,<$1AB0
cs16_rowhi .byte >$1900,>$1924,>$1948,>$196C,>$1990,>$19B4,>$19D8,>$19FC,>$1A20,>$1A44,>$1A68,>$1A8C,>$1AB0
cs16_dlpic10_0
  .byte <(cut_epilogue0+0),84,>(cut_epilogue0+0),0
  .byte <(cut_epilogue0+12),62,>(cut_epilogue0+12),48
  .byte <(cut_epilogue0+14),20,>(cut_epilogue0+14),56
  .byte <(cut_epilogue0+26),62,>(cut_epilogue0+26),104
  .byte <(cut_epilogue0+28),22,>(cut_epilogue0+28),112
  .byte <(cut_epilogue0+38),62,>(cut_epilogue0+38),152
  .byte 0,0
cs16_dlpic10_1
  .byte <(cut_epilogue1+0),82,>(cut_epilogue1+0),0
  .byte <(cut_epilogue1+14),26,>(cut_epilogue1+14),56
  .byte <(cut_epilogue1+20),62,>(cut_epilogue1+20),80
  .byte <(cut_epilogue1+22),30,>(cut_epilogue1+22),88
  .byte <(cut_epilogue1+24),62,>(cut_epilogue1+24),96
  .byte <(cut_epilogue1+26),22,>(cut_epilogue1+26),104
  .byte <(cut_epilogue1+36),94,>(cut_epilogue1+36),144
  .byte <(cut_epilogue1+38),62,>(cut_epilogue1+38),152
  .byte 0,0
cs16_dlpic10_2
  .byte <(cut_epilogue2+0),122,>(cut_epilogue2+0),0
  .byte <(cut_epilogue2+6),88,>(cut_epilogue2+6),24
  .byte <(cut_epilogue2+14),24,>(cut_epilogue2+14),56
  .byte <(cut_epilogue2+22),60,>(cut_epilogue2+22),88
  .byte <(cut_epilogue2+26),18,>(cut_epilogue2+26),104
  .byte 0,0
cs16_dlpic10_3
  .byte <(cut_epilogue3+0),120,>(cut_epilogue3+0),0
  .byte <(cut_epilogue3+8),88,>(cut_epilogue3+8),32
  .byte <(cut_epilogue3+16),30,>(cut_epilogue3+16),64
  .byte <(cut_epilogue3+18),60,>(cut_epilogue3+18),72
  .byte <(cut_epilogue3+22),16,>(cut_epilogue3+22),88
  .byte <(cut_epilogue3+38),62,>(cut_epilogue3+38),152
  .byte 0,0
cs16_dlpic10_4
  .byte <(cut_epilogue4+0),120,>(cut_epilogue4+0),0
  .byte <(cut_epilogue4+8),88,>(cut_epilogue4+8),32
  .byte <(cut_epilogue4+16),30,>(cut_epilogue4+16),64
  .byte <(cut_epilogue4+18),62,>(cut_epilogue4+18),72
  .byte <(cut_epilogue4+20),158,>(cut_epilogue4+20),80
  .byte <(cut_epilogue4+22),62,>(cut_epilogue4+22),88
  .byte <(cut_epilogue4+24),30,>(cut_epilogue4+24),96
  .byte <(cut_epilogue4+26),62,>(cut_epilogue4+26),104
  .byte <(cut_epilogue4+28),20,>(cut_epilogue4+28),112
  .byte 0,0
cs16_dlpic10_5
  .byte <(cut_epilogue5+0),120,>(cut_epilogue5+0),0
  .byte <(cut_epilogue5+8),88,>(cut_epilogue5+8),32
  .byte <(cut_epilogue5+16),28,>(cut_epilogue5+16),64
  .byte <(cut_epilogue5+20),62,>(cut_epilogue5+20),80
  .byte <(cut_epilogue5+22),24,>(cut_epilogue5+22),88
  .byte <(cut_epilogue5+30),62,>(cut_epilogue5+30),120
  .byte <(cut_epilogue5+32),30,>(cut_epilogue5+32),128
  .byte <(cut_epilogue5+34),62,>(cut_epilogue5+34),136
  .byte <(cut_epilogue5+36),28,>(cut_epilogue5+36),144
  .byte 0,0
cs16_dll10
  .byte $46,>cs16_dlnone,<cs16_dlnone
  .byte $40,>cs16_dlnone,<cs16_dlnone
  .byte $40,>cs16_dlnone,<cs16_dlnone
  .byte $07,>cs16_dlnone,<cs16_dlnone
  .byte $0F,>cs16_dlpic10_0,<cs16_dlpic10_0
  .byte $0F,>cs16_dlpic10_1,<cs16_dlpic10_1
  .byte $0F,>cs16_dlpic10_2,<cs16_dlpic10_2
  .byte $0F,>cs16_dlpic10_3,<cs16_dlpic10_3
  .byte $0F,>cs16_dlpic10_4,<cs16_dlpic10_4
  .byte $0F,>cs16_dlpic10_5,<cs16_dlpic10_5
  .byte $03,>cs16_dlnone,<cs16_dlnone
  .byte $05,>cs16_dlstripe,<cs16_dlstripe
  .byte $81,>cs16_dlnone,<cs16_dlnone
  .byte $07,>cs16_dlrow0,<cs16_dlrow0
  .byte $07,>cs16_dlrow1,<cs16_dlrow1
  .byte $07,>cs16_dlrow2,<cs16_dlrow2
  .byte $07,>cs16_dlrow3,<cs16_dlrow3
  .byte $07,>cs16_dlrow4,<cs16_dlrow4
  .byte $07,>cs16_dlrow5,<cs16_dlrow5
  .byte $07,>cs16_dlrow6,<cs16_dlrow6
  .byte $07,>cs16_dlrow7,<cs16_dlrow7
  .byte $07,>cs16_dlrow8,<cs16_dlrow8
  .byte $07,>cs16_dlrow9,<cs16_dlrow9
  .byte $07,>cs16_dlrow10,<cs16_dlrow10
  .byte $07,>cs16_dlrow11,<cs16_dlrow11
  .byte $07,>cs16_dlrow12,<cs16_dlrow12
  .byte $03,>cs16_dlnone,<cs16_dlnone
  .byte $C3,>cs16_dlnone,<cs16_dlnone
  .byte $CF,>cs16_dlnone,<cs16_dlnone
  .byte $4F,>cs16_dlnone,<cs16_dlnone
  .byte $4F,>cs16_dlnone,<cs16_dlnone
  .byte $4F,>cs16_dlnone,<cs16_dlnone
cs16_scenes .byte 10
cs16_kind .byte 0
cs16_pagelo .byte <cs16_text10
cs16_pagehi .byte >cs16_text10
cs16_dlllo .byte <cs16_dll10
cs16_dllhi .byte >cs16_dll10
cs16_pallo .byte <cs16_pal10
cs16_palhi .byte >cs16_pal10
cs16_text10
  .byte 0,23,19,29,29,19,25,24,0,28,15,29,31,22,30,29,0,45,45,0,11,22,22,0
  .byte 24,25,23,19,24,11,22,64,17,11,23,23,11,0,26,28,19,23,15,0,13,25,22,22
  .byte 11,26,29,15,14,37,0,29,25,22,11,28,0,25,31,30,26,31,30,64,24,25,28,23
  .byte 11,22,19,36,19,24,17,37,0,30,18,15,0,16,22,11,28,15,29,0,11,28,15,64
  .byte 29,31,12,29,19,14,19,24,17,37,64,64,11,22,22,0,13,22,15,11,28,37,0,30
  .byte 18,15,0,17,11,23,23,11,0,13,25,28,15,0,19,29,0,14,15,11,14,37,64,30
  .byte 18,15,0,29,31,24,0,12,31,28,24,29,0,13,22,15,11,24,37,65
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,30,15,22,15,23,15,30,28,35,0,19,29,0,13
  .byte 22,15,11,24,38,0,23,11,35,11,37,0,15,11,28,30,18,0,19,29,64,33,11,19
  .byte 30,19,24,17,0,16,25,28,0,35,25,31,37,64,64,33,15,22,13,25,23,15,0,18
  .byte 25,23,15,38,0,13,11,26,30,11,19,24,37,65
  .byte 1,13,11,26,30,37,0,32,11,24,13,15,0,45,45,0,17,11,23,23,11,43,2,64
  .byte 17,11,23,23,11,43,2,38,0,13,25,23,19,24,17,0,18,25,23,15,37,66
