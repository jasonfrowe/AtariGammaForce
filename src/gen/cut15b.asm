

; ---- the player ----
cs15_main
     ; which of this bank's scenes
     ldx #1-1
cs15_find
     cmp cs15_scenes,x
     beq cs15_found
     dex
     bpl cs15_find
     rts                     ; (none: not this bank's)
cs15_found
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
cs15_clr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs15_clr
     jsr waitforvblankstart
     ldx cs_idx
     ; the palettes: the background, P0-P5 (the picture's), P6, P7 (the
     ; stripe's; white below it, cutvec)
     lda cs15_pallo,x
     sta pfq
     lda cs15_palhi,x
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant              ; (the picture's background, put back off the screen)
     ldx #0
cs15_pals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne cs15_palnext
     inx
cs15_palnext
     cpx #32
     bcc cs15_pals
     ldx cs_idx
     lda cs15_dlllo,x
     sta DPPL
     lda cs15_dllhi,x
     sta DPPH
     lda #<cs15_dli
     sta cutvec
     lda #>cs15_dli
     sta cutvec+1
     lda #<cs15_bottom
     sta cutvec2
     lda #>cs15_bottom
     sta cutvec2+1
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ; the first page
     lda cs15_pagelo,x
     sta pfp
     lda cs15_pagehi,x
     sta pfp+1
     jsr cs15_newpage
     lda #SONG_ACTBREAK
     jsr mus_play
cs15_loop
     jsr waitforvblankstart
     lda #3                  ; (7800basic's NMI count: as pf_drawscreen)
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     lda cs_state
     bne cs15_wait
     jsr cs15_type
     jmp cs15_input
cs15_wait
cs15_input
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev             ; (newly down)
     beq cs15_loop
     lda cs_state
     bne cs15_turn
cs15_finish                     ; typing: the rest of the page at once
     jsr cs15_type
     lda cs_state
     beq cs15_finish
     jmp cs15_loop
cs15_turn
     cmp #2
     beq cs15_exit
     jsr cs15_newpage
     jmp cs15_loop
cs15_exit
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
cs15_exitkeep
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
cs15_newpage
     lda #0
     sta cs_state
     sta cs_row
     sta cs_col
     ldx #0
cs15_npclr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs15_npclr
     ldy #0
     lda (pfp),y
     sta cs_por
     inc pfp
     bne cs15_np2
     inc pfp+1
cs15_np2
     if 0
     ldx cs_idx
     lda cs15_kind,x
     beq cs15_npdone
     jsr cs15_portrait
     endif
cs15_npdone
     rts

; One letter of the page onto its row (or a code)
cs15_type
     ldy #0
     lda (pfp),y
     inc pfp
     bne cs15_t2
     inc pfp+1
cs15_t2
     cmp #$40
     beq cs15_tnl
     cmp #$41
     beq cs15_tpage
     cmp #$42
     beq cs15_tend
     pha
     ldx cs_row
     lda cs15_rowlo,x
     sta pfq
     lda cs15_rowhi,x
     sta pfq+1
     ldy cs_col
     pla
     sta (pfq),y
     inc cs_col
     rts
cs15_tnl
     inc cs_row
     lda #0
     sta cs_col
     rts
cs15_tpage
     lda #1
     sta cs_state
     rts
cs15_tend
     lda #2
     sta cs_state
     rts

     if 0
; A briefing's top: the portrait (cs_por) in its three zones, its palettes
; (P0, P1), the two header lines beside it (the game's font: 160A)
cs15_portrait
     ldx cs_por
     lda cs15_porpal_lo,x
     sta pfq
     lda cs15_porpal_hi,x
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
     lda cs15_porlo,x
     sta pfq
     lda cs15_porhi,x
     sta pfq+1
     ldy #0
cs15_pz
     lda (pfq),y
     sta $1C00,y
     iny
     cpy #16
     bne cs15_pz
cs15_pz1
     lda (pfq),y
     sta $1C10,y
     iny
     cpy #32
     bne cs15_pz1
cs15_pz2
     lda (pfq),y
     sta $1C20,y
     iny
     cpy #48
     bne cs15_pz2
     ldx cs_idx
     lda cs15_h0lo,x
     sta $1C10
     lda #$60
     sta $1C11
     lda cs15_h0hi,x
     sta $1C12
     lda cs15_h0w,x
     ora #(2<<5)
     sta $1C13
     lda #48
     sta $1C14
     lda cs15_h1lo,x
     sta $1C30
     lda #$60
     sta $1C31
     lda cs15_h1hi,x
     sta $1C32
     lda cs15_h1w,x
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
cs15_dli
     sta WSYNC
     lda #$43
     sta CTRL
     lda #>cs15_font
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
cs15_bottom
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ldx cs_idx
     lda cs15_pallo,x
     sta pfq
     lda cs15_palhi,x
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

cs15_pal9 .byte $20,$23,$3F,$FA,$28,$34,$FA,$23,$28,$FA,$28,$2C,$34,$0E,$28,$34,$00,$00,$00,$2A,$2A,$2A,$35,$29,$EC
cs15_dlstripe
  .byte <(cut_stripe15+0),248,>(cut_stripe15+0),0
  .byte <(cut_stripe15+0),248,>(cut_stripe15+0),32
  .byte <(cut_stripe15+0),248,>(cut_stripe15+0),64
  .byte <(cut_stripe15+0),248,>(cut_stripe15+0),96
  .byte <(cut_stripe15+0),248,>(cut_stripe15+0),128
  .byte 0,0
cs15_dlnone .byte 0,0
cs15_dlrow0
  .byte <$1900,$60,>$1900,206,8
  .byte <$1912,$60,>$1912,206,80
  .byte 0,0
cs15_dlrow1
  .byte <$1924,$60,>$1924,238,8
  .byte <$1936,$60,>$1936,238,80
  .byte 0,0
cs15_dlrow2
  .byte <$1948,$60,>$1948,238,8
  .byte <$195A,$60,>$195A,238,80
  .byte 0,0
cs15_dlrow3
  .byte <$196C,$60,>$196C,238,8
  .byte <$197E,$60,>$197E,238,80
  .byte 0,0
cs15_dlrow4
  .byte <$1990,$60,>$1990,238,8
  .byte <$19A2,$60,>$19A2,238,80
  .byte 0,0
cs15_dlrow5
  .byte <$19B4,$60,>$19B4,238,8
  .byte <$19C6,$60,>$19C6,238,80
  .byte 0,0
cs15_dlrow6
  .byte <$19D8,$60,>$19D8,238,8
  .byte <$19EA,$60,>$19EA,238,80
  .byte 0,0
cs15_dlrow7
  .byte <$19FC,$60,>$19FC,238,8
  .byte <$1A0E,$60,>$1A0E,238,80
  .byte 0,0
cs15_dlrow8
  .byte <$1A20,$60,>$1A20,238,8
  .byte <$1A32,$60,>$1A32,238,80
  .byte 0,0
cs15_dlrow9
  .byte <$1A44,$60,>$1A44,238,8
  .byte <$1A56,$60,>$1A56,238,80
  .byte 0,0
cs15_dlrow10
  .byte <$1A68,$60,>$1A68,238,8
  .byte <$1A7A,$60,>$1A7A,238,80
  .byte 0,0
cs15_dlrow11
  .byte <$1A8C,$60,>$1A8C,238,8
  .byte <$1A9E,$60,>$1A9E,238,80
  .byte 0,0
cs15_dlrow12
  .byte <$1AB0,$60,>$1AB0,238,8
  .byte <$1AC2,$60,>$1AC2,238,80
  .byte 0,0
cs15_rowlo .byte <$1900,<$1924,<$1948,<$196C,<$1990,<$19B4,<$19D8,<$19FC,<$1A20,<$1A44,<$1A68,<$1A8C,<$1AB0
cs15_rowhi .byte >$1900,>$1924,>$1948,>$196C,>$1990,>$19B4,>$19D8,>$19FC,>$1A20,>$1A44,>$1A68,>$1A8C,>$1AB0
cs15_dlpic9_0
  .byte <(cut_act30+0),2,>(cut_act30+0),0
  .byte <(cut_act30+30),22,>(cut_act30+30),120
  .byte 0,0
cs15_dlpic9_1
  .byte <(cut_act31+0),28,>(cut_act31+0),0
  .byte <(cut_act31+4),122,>(cut_act31+4),16
  .byte <(cut_act31+10),14,>(cut_act31+10),40
  .byte <(cut_act31+28),122,>(cut_act31+28),112
  .byte <(cut_act31+34),26,>(cut_act31+34),136
  .byte 0,0
cs15_dlpic9_2
  .byte <(cut_act32+0),28,>(cut_act32+0),0
  .byte <(cut_act32+4),120,>(cut_act32+4),16
  .byte <(cut_act32+12),16,>(cut_act32+12),48
  .byte <(cut_act32+28),120,>(cut_act32+28),112
  .byte <(cut_act32+36),28,>(cut_act32+36),144
  .byte 0,0
cs15_dlpic9_3
  .byte <(cut_act33+0),30,>(cut_act33+0),0
  .byte <(cut_act33+2),124,>(cut_act33+2),8
  .byte <(cut_act33+6),28,>(cut_act33+6),24
  .byte <(cut_act33+10),126,>(cut_act33+10),40
  .byte <(cut_act33+12),58,>(cut_act33+12),48
  .byte <(cut_act33+18),94,>(cut_act33+18),72
  .byte <(cut_act33+20),58,>(cut_act33+20),80
  .byte <(cut_act33+26),124,>(cut_act33+26),104
  .byte <(cut_act33+30),30,>(cut_act33+30),120
  .byte <(cut_act33+32),124,>(cut_act33+32),128
  .byte <(cut_act33+36),28,>(cut_act33+36),144
  .byte 0,0
cs15_dlpic9_4
  .byte <(cut_act34+0),24,>(cut_act34+0),0
  .byte <(cut_act34+8),40,>(cut_act34+8),32
  .byte <(cut_act34+32),24,>(cut_act34+32),128
  .byte 0,0
cs15_dlpic9_5
  .byte <(cut_act35+0),28,>(cut_act35+0),0
  .byte <(cut_act35+4),50,>(cut_act35+4),16
  .byte <(cut_act35+18),156,>(cut_act35+18),72
  .byte <(cut_act35+22),50,>(cut_act35+22),88
  .byte <(cut_act35+36),28,>(cut_act35+36),144
  .byte 0,0
cs15_dll9
  .byte $46,>cs15_dlnone,<cs15_dlnone
  .byte $40,>cs15_dlnone,<cs15_dlnone
  .byte $40,>cs15_dlnone,<cs15_dlnone
  .byte $07,>cs15_dlnone,<cs15_dlnone
  .byte $0F,>cs15_dlpic9_0,<cs15_dlpic9_0
  .byte $0F,>cs15_dlpic9_1,<cs15_dlpic9_1
  .byte $0F,>cs15_dlpic9_2,<cs15_dlpic9_2
  .byte $0F,>cs15_dlpic9_3,<cs15_dlpic9_3
  .byte $0F,>cs15_dlpic9_4,<cs15_dlpic9_4
  .byte $0F,>cs15_dlpic9_5,<cs15_dlpic9_5
  .byte $03,>cs15_dlnone,<cs15_dlnone
  .byte $05,>cs15_dlstripe,<cs15_dlstripe
  .byte $81,>cs15_dlnone,<cs15_dlnone
  .byte $07,>cs15_dlrow0,<cs15_dlrow0
  .byte $07,>cs15_dlrow1,<cs15_dlrow1
  .byte $07,>cs15_dlrow2,<cs15_dlrow2
  .byte $07,>cs15_dlrow3,<cs15_dlrow3
  .byte $07,>cs15_dlrow4,<cs15_dlrow4
  .byte $07,>cs15_dlrow5,<cs15_dlrow5
  .byte $07,>cs15_dlrow6,<cs15_dlrow6
  .byte $07,>cs15_dlrow7,<cs15_dlrow7
  .byte $07,>cs15_dlrow8,<cs15_dlrow8
  .byte $07,>cs15_dlrow9,<cs15_dlrow9
  .byte $07,>cs15_dlrow10,<cs15_dlrow10
  .byte $07,>cs15_dlrow11,<cs15_dlrow11
  .byte $07,>cs15_dlrow12,<cs15_dlrow12
  .byte $03,>cs15_dlnone,<cs15_dlnone
  .byte $C3,>cs15_dlnone,<cs15_dlnone
  .byte $CF,>cs15_dlnone,<cs15_dlnone
  .byte $4F,>cs15_dlnone,<cs15_dlnone
  .byte $4F,>cs15_dlnone,<cs15_dlnone
  .byte $4F,>cs15_dlnone,<cs15_dlnone
cs15_scenes .byte 9
cs15_kind .byte 0
cs15_pagelo .byte <cs15_text9
cs15_pagehi .byte >cs15_text9
cs15_dlllo .byte <cs15_dll9
cs15_dllhi .byte >cs15_dll9
cs15_pallo .byte <cs15_pal9
cs15_palhi .byte >cs15_pal9
cs15_text9
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,30,18,19,29,0,19,29,0,30,18,15,0,16,19
  .byte 24,11,22,0,29,15,13,30,25,28,38,0,23,11,35,11,44,0,30,18,15,64,12,22
  .byte 19,24,14,19,24,17,0,13,25,28,25,24,11,0,25,16,0,30,18,15,0,29,31,24
  .byte 37,64,64,30,15,23,26,15,28,11,30,31,28,15,29,0,15,34,13,15,15,14,0,30
  .byte 33,25,0,23,19,22,22,19,25,24,64,14,15,17,28,15,15,29,37,65
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,23,11,29,29,19,32,15,0,30,18,15,28,23,25
  .byte 24,31,13,22,15,11,28,0,16,22,11,28,15,29,0,15,28,31,26,30,64,19,24,0
  .byte 11,22,30,15,28,24,11,30,19,24,17,0,13,35,13,22,15,29,37,0,33,11,30,13
  .byte 18,0,30,18,15,64,29,31,28,16,11,13,15,0,16,22,19,13,21,15,28,0,12,15
  .byte 16,25,28,15,0,30,18,15,35,0,12,31,28,29,30,39,64,64,25,24,15,0,30,25
  .byte 31,13,18,0,25,16,0,11,0,22,19,32,15,0,16,22,11,28,15,0,11,24,14,0
  .byte 30,18,15,64,29,18,19,26,0,33,19,22,22,0,12,15,0,32,11,26,25,28,19,36
  .byte 15,14,39,65
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,17,11,23,23,11,0,26,28,19,23,15,0,19,29
  .byte 0,16,15,15,14,19,24,17,0,14,19,28,15,13,30,22,35,0,25,24,64,29,25,22
  .byte 39,64,64,30,18,28,15,15,0,26,28,19,29,23,29,0,25,28,12,19,30,0,19,30
  .byte 29,0,13,25,28,15,38,0,11,24,14,0,30,18,15,64,13,25,28,15,0,29,30,11
  .byte 35,29,0,29,15,11,22,15,14,37,0,25,24,22,35,0,30,18,15,0,18,35,26,15
  .byte 28,64,29,33,25,28,14,0,13,11,24,0,12,28,15,11,21,0,30,18,15,0,24,25
  .byte 14,15,29,0,11,30,25,26,0,19,30,44,64,12,28,15,11,21,0,25,24,15,0,30
  .byte 25,0,25,26,15,24,0,30,18,15,0,13,25,28,15,37,0,33,18,15,24,0,19,30
  .byte 64,29,15,11,22,29,0,11,17,11,19,24,38,0,12,28,15,11,21,0,30,18,15,0
  .byte 25,30,18,15,28,37,65
  .byte 2,13,25,23,23,0,19,24,30,15,28,13,15,26,30,0,45,45,0,31,24,21,24,25
  .byte 33,24,0,29,19,17,24,11,22,64,15,34,30,28,11,13,30,19,25,24,0,13,35,13
  .byte 22,15,0,10,10,0,26,15,28,13,15,24,30,37,0,26,31,28,17,15,64,30,18,15
  .byte 0,11,24,25,23,11,22,35,37,0,18,11,28,32,15,29,30,0,30,18,15,0,29,30
  .byte 11,28,37,65
  .byte 1,13,11,26,30,37,0,23,11,35,11,0,32,11,24,13,15,0,45,45,0,17,11,23
  .byte 23,11,43,2,64,23,35,0,13,11,24,25,26,35,0,19,29,0,17,22,25,33,19,24
  .byte 17,0,13,18,15,28,28,35,43,28,15,14,38,0,12,31,30,64,30,18,15,0,13,25
  .byte 24,30,11,19,24,23,15,24,30,0,29,18,19,15,22,14,0,19,29,0,18,25,22,14
  .byte 19,24,17,39,64,64,35,25,31,0,12,31,19,22,30,0,30,18,19,29,0,29,18,19
  .byte 26,0,30,25,0,29,31,28,32,19,32,15,0,30,18,15,64,29,31,24,38,0,24,11
  .byte 30,18,11,24,37,0,19,0,30,28,31,29,30,0,35,25,31,28,0,33,25,28,21,38
  .byte 0,11,24,14,64,19,0,30,28,31,29,30,0,23,35,0,28,15,16,22,15,34,15,29
  .byte 37,65
  .byte 1,13,11,26,30,37,0,23,11,35,11,0,32,11,24,13,15,0,45,45,0,17,11,23
  .byte 23,11,43,2,64,18,25,22,14,0,30,18,15,0,13,18,11,24,24,15,22,0,25,26
  .byte 15,24,37,64,64,16,25,28,0,15,11,28,30,18,38,0,11,24,14,0,16,25,28,0
  .byte 25,31,28,0,29,30,11,28,37,37,37,0,30,18,19,29,64,15,24,14,29,0,24,25
  .byte 33,39,66
