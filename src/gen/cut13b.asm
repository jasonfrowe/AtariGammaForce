

; ---- the player ----
cs13_main
     ; which of this bank's scenes
     ldx #1-1
cs13_find
     cmp cs13_scenes,x
     beq cs13_found
     dex
     bpl cs13_find
     rts                     ; (none: not this bank's)
cs13_found
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
cs13_clr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs13_clr
     jsr waitforvblankstart
     ldx cs_idx
     ; the palettes: the background, P0-P5 (the picture's), P6, P7 (the
     ; stripe's; white below it, cutvec)
     lda cs13_pallo,x
     sta pfq
     lda cs13_palhi,x
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant              ; (the picture's background, put back off the screen)
     ldx #0
cs13_pals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne cs13_palnext
     inx
cs13_palnext
     cpx #32
     bcc cs13_pals
     ldx cs_idx
     lda cs13_dlllo,x
     sta DPPL
     lda cs13_dllhi,x
     sta DPPH
     lda #<cs13_dli
     sta cutvec
     lda #>cs13_dli
     sta cutvec+1
     lda #<cs13_bottom
     sta cutvec2
     lda #>cs13_bottom
     sta cutvec2+1
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ; the first page
     lda cs13_pagelo,x
     sta pfp
     lda cs13_pagehi,x
     sta pfp+1
     jsr cs13_newpage
     lda #SONG_ACTBREAK
     jsr mus_play
cs13_loop
     jsr waitforvblankstart
     lda #3                  ; (7800basic's NMI count: as pf_drawscreen)
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     lda cs_state
     bne cs13_wait
     jsr cs13_type
     jmp cs13_input
cs13_wait
cs13_input
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev             ; (newly down)
     beq cs13_loop
     lda cs_state
     bne cs13_turn
cs13_finish                     ; typing: the rest of the page at once
     jsr cs13_type
     lda cs_state
     beq cs13_finish
     jmp cs13_loop
cs13_turn
     cmp #2
     beq cs13_exit
     jsr cs13_newpage
     jmp cs13_loop
cs13_exit
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
cs13_exitkeep
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
cs13_newpage
     lda #0
     sta cs_state
     sta cs_row
     sta cs_col
     ldx #0
cs13_npclr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs13_npclr
     ldy #0
     lda (pfp),y
     sta cs_por
     inc pfp
     bne cs13_np2
     inc pfp+1
cs13_np2
     if 0
     ldx cs_idx
     lda cs13_kind,x
     beq cs13_npdone
     jsr cs13_portrait
     endif
cs13_npdone
     rts

; One letter of the page onto its row (or a code)
cs13_type
     ldy #0
     lda (pfp),y
     inc pfp
     bne cs13_t2
     inc pfp+1
cs13_t2
     cmp #$40
     beq cs13_tnl
     cmp #$41
     beq cs13_tpage
     cmp #$42
     beq cs13_tend
     pha
     ldx cs_row
     lda cs13_rowlo,x
     sta pfq
     lda cs13_rowhi,x
     sta pfq+1
     ldy cs_col
     pla
     sta (pfq),y
     inc cs_col
     rts
cs13_tnl
     inc cs_row
     lda #0
     sta cs_col
     rts
cs13_tpage
     lda #1
     sta cs_state
     rts
cs13_tend
     lda #2
     sta cs_state
     rts

     if 0
; A briefing's top: the portrait (cs_por) in its three zones, its palettes
; (P0, P1), the two header lines beside it (the game's font: 160A)
cs13_portrait
     ldx cs_por
     lda cs13_porpal_lo,x
     sta pfq
     lda cs13_porpal_hi,x
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
     lda cs13_porlo,x
     sta pfq
     lda cs13_porhi,x
     sta pfq+1
     ldy #0
cs13_pz
     lda (pfq),y
     sta $1C00,y
     iny
     cpy #16
     bne cs13_pz
cs13_pz1
     lda (pfq),y
     sta $1C10,y
     iny
     cpy #32
     bne cs13_pz1
cs13_pz2
     lda (pfq),y
     sta $1C20,y
     iny
     cpy #48
     bne cs13_pz2
     ldx cs_idx
     lda cs13_h0lo,x
     sta $1C10
     lda #$60
     sta $1C11
     lda cs13_h0hi,x
     sta $1C12
     lda cs13_h0w,x
     ora #(2<<5)
     sta $1C13
     lda #48
     sta $1C14
     lda cs13_h1lo,x
     sta $1C30
     lda #$60
     sta $1C31
     lda cs13_h1hi,x
     sta $1C32
     lda cs13_h1w,x
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
cs13_dli
     sta WSYNC
     lda #$43
     sta CTRL
     lda #>cs13_font
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
cs13_bottom
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ldx cs_idx
     lda cs13_pallo,x
     sta pfq
     lda cs13_palhi,x
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

cs13_pal6 .byte $00,$04,$06,$0F,$04,$06,$37,$03,$0B,$63,$0F,$63,$9B,$63,$84,$9B,$0F,$84,$9B,$2A,$2A,$2A,$35,$29,$EC
cs13_dlstripe
  .byte <(cut_stripe13+0),248,>(cut_stripe13+0),0
  .byte <(cut_stripe13+0),248,>(cut_stripe13+0),32
  .byte <(cut_stripe13+0),248,>(cut_stripe13+0),64
  .byte <(cut_stripe13+0),248,>(cut_stripe13+0),96
  .byte <(cut_stripe13+0),248,>(cut_stripe13+0),128
  .byte 0,0
cs13_dlnone .byte 0,0
cs13_dlrow0
  .byte <$1900,$60,>$1900,206,8
  .byte <$1912,$60,>$1912,206,80
  .byte 0,0
cs13_dlrow1
  .byte <$1924,$60,>$1924,238,8
  .byte <$1936,$60,>$1936,238,80
  .byte 0,0
cs13_dlrow2
  .byte <$1948,$60,>$1948,238,8
  .byte <$195A,$60,>$195A,238,80
  .byte 0,0
cs13_dlrow3
  .byte <$196C,$60,>$196C,238,8
  .byte <$197E,$60,>$197E,238,80
  .byte 0,0
cs13_dlrow4
  .byte <$1990,$60,>$1990,238,8
  .byte <$19A2,$60,>$19A2,238,80
  .byte 0,0
cs13_dlrow5
  .byte <$19B4,$60,>$19B4,238,8
  .byte <$19C6,$60,>$19C6,238,80
  .byte 0,0
cs13_dlrow6
  .byte <$19D8,$60,>$19D8,238,8
  .byte <$19EA,$60,>$19EA,238,80
  .byte 0,0
cs13_dlrow7
  .byte <$19FC,$60,>$19FC,238,8
  .byte <$1A0E,$60,>$1A0E,238,80
  .byte 0,0
cs13_dlrow8
  .byte <$1A20,$60,>$1A20,238,8
  .byte <$1A32,$60,>$1A32,238,80
  .byte 0,0
cs13_dlrow9
  .byte <$1A44,$60,>$1A44,238,8
  .byte <$1A56,$60,>$1A56,238,80
  .byte 0,0
cs13_dlrow10
  .byte <$1A68,$60,>$1A68,238,8
  .byte <$1A7A,$60,>$1A7A,238,80
  .byte 0,0
cs13_dlrow11
  .byte <$1A8C,$60,>$1A8C,238,8
  .byte <$1A9E,$60,>$1A9E,238,80
  .byte 0,0
cs13_dlrow12
  .byte <$1AB0,$60,>$1AB0,238,8
  .byte <$1AC2,$60,>$1AC2,238,80
  .byte 0,0
cs13_rowlo .byte <$1900,<$1924,<$1948,<$196C,<$1990,<$19B4,<$19D8,<$19FC,<$1A20,<$1A44,<$1A68,<$1A8C,<$1AB0
cs13_rowhi .byte >$1900,>$1924,>$1948,>$196C,>$1990,>$19B4,>$19D8,>$19FC,>$1A20,>$1A44,>$1A68,>$1A8C,>$1AB0
cs13_dlpic6_0
  .byte <(cut_act10+0),2,>(cut_act10+0),0
  .byte <(cut_act10+30),22,>(cut_act10+30),120
  .byte 0,0
cs13_dlpic6_1
  .byte <(cut_act11+0),26,>(cut_act11+0),0
  .byte <(cut_act11+6),62,>(cut_act11+6),24
  .byte <(cut_act11+8),14,>(cut_act11+8),32
  .byte <(cut_act11+26),62,>(cut_act11+26),104
  .byte <(cut_act11+28),30,>(cut_act11+28),112
  .byte <(cut_act11+30),62,>(cut_act11+30),120
  .byte <(cut_act11+32),30,>(cut_act11+32),128
  .byte <(cut_act11+34),62,>(cut_act11+34),136
  .byte <(cut_act11+36),28,>(cut_act11+36),144
  .byte 0,0
cs13_dlpic6_2
  .byte <(cut_act12+0),14,>(cut_act12+0),0
  .byte <(cut_act12+18),92,>(cut_act12+18),72
  .byte <(cut_act12+22),20,>(cut_act12+22),88
  .byte <(cut_act12+34),94,>(cut_act12+34),136
  .byte <(cut_act12+36),28,>(cut_act12+36),144
  .byte 0,0
cs13_dlpic6_3
  .byte <(cut_act13+0),92,>(cut_act13+0),0
  .byte <(cut_act13+4),126,>(cut_act13+4),16
  .byte <(cut_act13+6),92,>(cut_act13+6),24
  .byte <(cut_act13+10),124,>(cut_act13+10),40
  .byte <(cut_act13+14),82,>(cut_act13+14),56
  .byte <(cut_act13+28),122,>(cut_act13+28),112
  .byte <(cut_act13+34),90,>(cut_act13+34),136
  .byte 0,0
cs13_dlpic6_4
  .byte <(cut_act14+0),88,>(cut_act14+0),0
  .byte <(cut_act14+8),122,>(cut_act14+8),32
  .byte <(cut_act14+14),156,>(cut_act14+14),56
  .byte <(cut_act14+18),186,>(cut_act14+18),72
  .byte <(cut_act14+24),154,>(cut_act14+24),96
  .byte <(cut_act14+30),126,>(cut_act14+30),120
  .byte <(cut_act14+32),88,>(cut_act14+32),128
  .byte 0,0
cs13_dlpic6_5
  .byte <(cut_act15+0),94,>(cut_act15+0),0
  .byte <(cut_act15+2),126,>(cut_act15+2),8
  .byte <(cut_act15+4),158,>(cut_act15+4),16
  .byte <(cut_act15+6),168,>(cut_act15+6),24
  .byte <(cut_act15+30),154,>(cut_act15+30),120
  .byte <(cut_act15+36),126,>(cut_act15+36),144
  .byte <(cut_act15+38),94,>(cut_act15+38),152
  .byte 0,0
cs13_dll6
  .byte $46,>cs13_dlnone,<cs13_dlnone
  .byte $40,>cs13_dlnone,<cs13_dlnone
  .byte $40,>cs13_dlnone,<cs13_dlnone
  .byte $07,>cs13_dlnone,<cs13_dlnone
  .byte $0F,>cs13_dlpic6_0,<cs13_dlpic6_0
  .byte $0F,>cs13_dlpic6_1,<cs13_dlpic6_1
  .byte $0F,>cs13_dlpic6_2,<cs13_dlpic6_2
  .byte $0F,>cs13_dlpic6_3,<cs13_dlpic6_3
  .byte $0F,>cs13_dlpic6_4,<cs13_dlpic6_4
  .byte $0F,>cs13_dlpic6_5,<cs13_dlpic6_5
  .byte $03,>cs13_dlnone,<cs13_dlnone
  .byte $05,>cs13_dlstripe,<cs13_dlstripe
  .byte $81,>cs13_dlnone,<cs13_dlnone
  .byte $07,>cs13_dlrow0,<cs13_dlrow0
  .byte $07,>cs13_dlrow1,<cs13_dlrow1
  .byte $07,>cs13_dlrow2,<cs13_dlrow2
  .byte $07,>cs13_dlrow3,<cs13_dlrow3
  .byte $07,>cs13_dlrow4,<cs13_dlrow4
  .byte $07,>cs13_dlrow5,<cs13_dlrow5
  .byte $07,>cs13_dlrow6,<cs13_dlrow6
  .byte $07,>cs13_dlrow7,<cs13_dlrow7
  .byte $07,>cs13_dlrow8,<cs13_dlrow8
  .byte $07,>cs13_dlrow9,<cs13_dlrow9
  .byte $07,>cs13_dlrow10,<cs13_dlrow10
  .byte $07,>cs13_dlrow11,<cs13_dlrow11
  .byte $07,>cs13_dlrow12,<cs13_dlrow12
  .byte $03,>cs13_dlnone,<cs13_dlnone
  .byte $C7,>cs13_dlnone,<cs13_dlnone
  .byte $CB,>cs13_dlnone,<cs13_dlnone
  .byte $4F,>cs13_dlnone,<cs13_dlnone
  .byte $4F,>cs13_dlnone,<cs13_dlnone
  .byte $4F,>cs13_dlnone,<cs13_dlnone
cs13_scenes .byte 6
cs13_kind .byte 0
cs13_pagelo .byte <cs13_text6
cs13_pagehi .byte >cs13_text6
cs13_dlllo .byte <cs13_dll6
cs13_dllhi .byte >cs13_dll6
cs13_pallo .byte <cs13_pal6
cs13_palhi .byte >cs13_pal6
cs13_text6
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,12,25,25,29,30,15,28,0,29,15,26,11,28,11
  .byte 30,19,25,24,0,13,25,24,16,19,28,23,15,14,37,0,35,25,31,64,18,11,32,15
  .byte 0,13,22,15,11,28,15,14,0,15,11,28,30,18,41,29,0,29,31,28,16,11,13,15
  .byte 38,0,23,11,35,11,39,64,64,35,25,31,0,11,28,15,0,13,22,19,23,12,19,24
  .byte 17,0,26,11,29,30,0,30,18,15,64,11,30,23,25,29,26,18,15,28,15,37,65
  .byte 1,13,11,26,30,37,0,23,11,35,11,0,21,15,29,30,28,15,22,0,45,45,0,17
  .byte 11,23,23,11,43,2,64,24,11,30,18,11,24,37,37,37,0,30,18,15,0,29,21,35
  .byte 0,19,29,0,30,31,28,24,19,24,17,64,19,24,21,43,12,22,11,13,21,37,64,64
  .byte 12,15,22,25,33,0,23,15,38,0,15,11,28,30,18,0,19,29,0,11,0,29,18,19
  .byte 24,19,24,17,0,12,22,31,15,64,20,15,33,15,22,37,0,33,15,0,33,25,24,0
  .byte 30,18,15,0,15,24,30,19,28,15,0,29,31,28,16,11,13,15,64,12,11,13,21,37
  .byte 0,33,15,0,11,13,30,31,11,22,22,35,0,28,15,13,22,11,19,23,15,14,0,25
  .byte 31,28,64,33,25,28,22,14,37,65
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,35,25,31,0,14,19,14,0,19,30,38,0,23,11
  .byte 35,11,37,0,12,31,30,0,22,25,25,21,0,11,18,15,11,14,37,64,64,22,25,33
  .byte 0,25,28,12,19,30,0,19,29,0,13,18,25,21,15,14,0,33,19,30,18,0,14,15
  .byte 11,14,64,29,11,30,15,22,22,19,30,15,29,0,11,24,14,0,30,31,23,12,22,19
  .byte 24,17,0,29,26,11,13,15,64,14,15,12,28,19,29,37,0,30,18,15,35,0,33,19
  .byte 22,22,0,29,18,25,32,15,0,11,24,14,0,13,28,31,29,18,64,35,25,31,28,0
  .byte 29,18,19,26,39,64,64,11,24,14,0,11,12,25,32,15,0,30,18,15,23,0,29,19
  .byte 30,29,0,18,11,22,25,0,29,30,11,30,19,25,24,37,64,12,28,15,11,21,0,19
  .byte 30,29,0,15,29,13,25,28,30,0,29,11,30,15,22,22,19,30,15,29,0,16,19,28
  .byte 29,30,39,65
  .byte 1,13,11,26,30,37,0,23,11,35,11,0,21,15,29,30,28,15,22,0,45,45,0,17
  .byte 11,23,23,11,43,2,64,14,15,12,28,19,29,0,16,19,15,22,14,0,19,24,0,29
  .byte 19,17,18,30,37,0,23,11,19,24,0,15,24,17,19,24,15,29,64,11,30,0,16,31
  .byte 22,22,0,30,18,28,25,30,30,22,15,39,64,64,18,11,22,25,0,29,30,11,30,19
  .byte 25,24,38,0,35,25,31,28,0,25,13,13,31,26,11,30,19,25,24,0,25,16,0,25
  .byte 31,28,64,29,21,35,0,15,24,14,29,0,24,25,33,39,0,12,28,15,11,21,19,24
  .byte 17,0,25,28,12,19,30,39,66
