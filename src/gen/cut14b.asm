

; ---- the player ----
cs14_main
     ; which of this bank's scenes
     ldx #1-1
cs14_find
     cmp cs14_scenes,x
     beq cs14_found
     dex
     bpl cs14_find
     rts                     ; (none: not this bank's)
cs14_found
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
cs14_clr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs14_clr
     jsr waitforvblankstart
     ldx cs_idx
     ; the palettes: the background, P0-P5 (the picture's), P6, P7 (the
     ; stripe's; white below it, cutvec)
     lda cs14_pallo,x
     sta pfq
     lda cs14_palhi,x
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant              ; (the picture's background, put back off the screen)
     ldx #0
cs14_pals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne cs14_palnext
     inx
cs14_palnext
     cpx #32
     bcc cs14_pals
     ldx cs_idx
     lda cs14_dlllo,x
     sta DPPL
     lda cs14_dllhi,x
     sta DPPH
     lda #<cs14_dli
     sta cutvec
     lda #>cs14_dli
     sta cutvec+1
     lda #<cs14_bottom
     sta cutvec2
     lda #>cs14_bottom
     sta cutvec2+1
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ; the first page
     lda cs14_pagelo,x
     sta pfp
     lda cs14_pagehi,x
     sta pfp+1
     jsr cs14_newpage
     lda #SONG_ACTBREAK
     jsr mus_play
cs14_loop
     jsr waitforvblankstart
     lda #3                  ; (7800basic's NMI count: as pf_drawscreen)
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     lda cs_state
     bne cs14_wait
     jsr cs14_type
     jmp cs14_input
cs14_wait
cs14_input
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev             ; (newly down)
     beq cs14_loop
     lda cs_state
     bne cs14_turn
cs14_finish                     ; typing: the rest of the page at once
     jsr cs14_type
     lda cs_state
     beq cs14_finish
     jmp cs14_loop
cs14_turn
     cmp #2
     beq cs14_exit
     jsr cs14_newpage
     jmp cs14_loop
cs14_exit
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
cs14_exitkeep
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
cs14_newpage
     lda #0
     sta cs_state
     sta cs_row
     sta cs_col
     ldx #0
cs14_npclr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs14_npclr
     ldy #0
     lda (pfp),y
     sta cs_por
     inc pfp
     bne cs14_np2
     inc pfp+1
cs14_np2
     if 0
     ldx cs_idx
     lda cs14_kind,x
     beq cs14_npdone
     jsr cs14_portrait
     endif
cs14_npdone
     rts

; One letter of the page onto its row (or a code)
cs14_type
     ldy #0
     lda (pfp),y
     inc pfp
     bne cs14_t2
     inc pfp+1
cs14_t2
     cmp #$40
     beq cs14_tnl
     cmp #$41
     beq cs14_tpage
     cmp #$42
     beq cs14_tend
     pha
     ldx cs_row
     lda cs14_rowlo,x
     sta pfq
     lda cs14_rowhi,x
     sta pfq+1
     ldy cs_col
     pla
     sta (pfq),y
     inc cs_col
     rts
cs14_tnl
     inc cs_row
     lda #0
     sta cs_col
     rts
cs14_tpage
     lda #1
     sta cs_state
     rts
cs14_tend
     lda #2
     sta cs_state
     rts

     if 0
; A briefing's top: the portrait (cs_por) in its three zones, its palettes
; (P0, P1), the two header lines beside it (the game's font: 160A)
cs14_portrait
     ldx cs_por
     lda cs14_porpal_lo,x
     sta pfq
     lda cs14_porpal_hi,x
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
     lda cs14_porlo,x
     sta pfq
     lda cs14_porhi,x
     sta pfq+1
     ldy #0
cs14_pz
     lda (pfq),y
     sta $1C00,y
     iny
     cpy #16
     bne cs14_pz
cs14_pz1
     lda (pfq),y
     sta $1C10,y
     iny
     cpy #32
     bne cs14_pz1
cs14_pz2
     lda (pfq),y
     sta $1C20,y
     iny
     cpy #48
     bne cs14_pz2
     ldx cs_idx
     lda cs14_h0lo,x
     sta $1C10
     lda #$60
     sta $1C11
     lda cs14_h0hi,x
     sta $1C12
     lda cs14_h0w,x
     ora #(2<<5)
     sta $1C13
     lda #48
     sta $1C14
     lda cs14_h1lo,x
     sta $1C30
     lda #$60
     sta $1C31
     lda cs14_h1hi,x
     sta $1C32
     lda cs14_h1w,x
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
cs14_dli
     sta WSYNC
     lda #$43
     sta CTRL
     lda #>cs14_font
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
cs14_bottom
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ldx cs_idx
     lda cs14_pallo,x
     sta pfq
     lda cs14_palhi,x
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

cs14_pal8 .byte $00,$02,$05,$7E,$05,$53,$56,$36,$53,$56,$02,$05,$53,$04,$08,$05,$05,$0B,$7E,$2A,$2A,$2A,$35,$29,$EC
cs14_dlstripe
  .byte <(cut_stripe14+0),248,>(cut_stripe14+0),0
  .byte <(cut_stripe14+0),248,>(cut_stripe14+0),32
  .byte <(cut_stripe14+0),248,>(cut_stripe14+0),64
  .byte <(cut_stripe14+0),248,>(cut_stripe14+0),96
  .byte <(cut_stripe14+0),248,>(cut_stripe14+0),128
  .byte 0,0
cs14_dlnone .byte 0,0
cs14_dlrow0
  .byte <$1900,$60,>$1900,206,8
  .byte <$1912,$60,>$1912,206,80
  .byte 0,0
cs14_dlrow1
  .byte <$1924,$60,>$1924,238,8
  .byte <$1936,$60,>$1936,238,80
  .byte 0,0
cs14_dlrow2
  .byte <$1948,$60,>$1948,238,8
  .byte <$195A,$60,>$195A,238,80
  .byte 0,0
cs14_dlrow3
  .byte <$196C,$60,>$196C,238,8
  .byte <$197E,$60,>$197E,238,80
  .byte 0,0
cs14_dlrow4
  .byte <$1990,$60,>$1990,238,8
  .byte <$19A2,$60,>$19A2,238,80
  .byte 0,0
cs14_dlrow5
  .byte <$19B4,$60,>$19B4,238,8
  .byte <$19C6,$60,>$19C6,238,80
  .byte 0,0
cs14_dlrow6
  .byte <$19D8,$60,>$19D8,238,8
  .byte <$19EA,$60,>$19EA,238,80
  .byte 0,0
cs14_dlrow7
  .byte <$19FC,$60,>$19FC,238,8
  .byte <$1A0E,$60,>$1A0E,238,80
  .byte 0,0
cs14_dlrow8
  .byte <$1A20,$60,>$1A20,238,8
  .byte <$1A32,$60,>$1A32,238,80
  .byte 0,0
cs14_dlrow9
  .byte <$1A44,$60,>$1A44,238,8
  .byte <$1A56,$60,>$1A56,238,80
  .byte 0,0
cs14_dlrow10
  .byte <$1A68,$60,>$1A68,238,8
  .byte <$1A7A,$60,>$1A7A,238,80
  .byte 0,0
cs14_dlrow11
  .byte <$1A8C,$60,>$1A8C,238,8
  .byte <$1A9E,$60,>$1A9E,238,80
  .byte 0,0
cs14_dlrow12
  .byte <$1AB0,$60,>$1AB0,238,8
  .byte <$1AC2,$60,>$1AC2,238,80
  .byte 0,0
cs14_rowlo .byte <$1900,<$1924,<$1948,<$196C,<$1990,<$19B4,<$19D8,<$19FC,<$1A20,<$1A44,<$1A68,<$1A8C,<$1AB0
cs14_rowhi .byte >$1900,>$1924,>$1948,>$196C,>$1990,>$19B4,>$19D8,>$19FC,>$1A20,>$1A44,>$1A68,>$1A8C,>$1AB0
cs14_dlpic8_0
  .byte <(cut_act20+0),2,>(cut_act20+0),0
  .byte <(cut_act20+30),22,>(cut_act20+30),120
  .byte 0,0
cs14_dlpic8_1
  .byte <(cut_act21+0),4,>(cut_act21+0),0
  .byte <(cut_act21+28),56,>(cut_act21+28),112
  .byte <(cut_act21+36),28,>(cut_act21+36),144
  .byte 0,0
cs14_dlpic8_2
  .byte <(cut_act22+0),30,>(cut_act22+0),0
  .byte <(cut_act22+2),154,>(cut_act22+2),8
  .byte <(cut_act22+8),12,>(cut_act22+8),32
  .byte <(cut_act22+28),62,>(cut_act22+28),112
  .byte <(cut_act22+30),92,>(cut_act22+30),120
  .byte <(cut_act22+34),62,>(cut_act22+34),136
  .byte <(cut_act22+36),28,>(cut_act22+36),144
  .byte 0,0
cs14_dlpic8_3
  .byte <(cut_act23+0),150,>(cut_act23+0),0
  .byte <(cut_act23+10),24,>(cut_act23+10),40
  .byte <(cut_act23+18),190,>(cut_act23+18),72
  .byte <(cut_act23+20),24,>(cut_act23+20),80
  .byte <(cut_act23+28),126,>(cut_act23+28),112
  .byte <(cut_act23+30),58,>(cut_act23+30),120
  .byte <(cut_act23+36),28,>(cut_act23+36),144
  .byte 0,0
cs14_dlpic8_4
  .byte <(cut_act24+0),148,>(cut_act24+0),0
  .byte <(cut_act24+12),28,>(cut_act24+12),48
  .byte <(cut_act24+16),186,>(cut_act24+16),64
  .byte <(cut_act24+22),14,>(cut_act24+22),88
  .byte 0,0
cs14_dlpic8_5
  .byte <(cut_act25+0),148,>(cut_act25+0),0
  .byte <(cut_act25+12),26,>(cut_act25+12),48
  .byte <(cut_act25+18),190,>(cut_act25+18),72
  .byte <(cut_act25+20),12,>(cut_act25+20),80
  .byte 0,0
cs14_dll8
  .byte $46,>cs14_dlnone,<cs14_dlnone
  .byte $40,>cs14_dlnone,<cs14_dlnone
  .byte $40,>cs14_dlnone,<cs14_dlnone
  .byte $07,>cs14_dlnone,<cs14_dlnone
  .byte $0F,>cs14_dlpic8_0,<cs14_dlpic8_0
  .byte $0F,>cs14_dlpic8_1,<cs14_dlpic8_1
  .byte $0F,>cs14_dlpic8_2,<cs14_dlpic8_2
  .byte $0F,>cs14_dlpic8_3,<cs14_dlpic8_3
  .byte $0F,>cs14_dlpic8_4,<cs14_dlpic8_4
  .byte $0F,>cs14_dlpic8_5,<cs14_dlpic8_5
  .byte $03,>cs14_dlnone,<cs14_dlnone
  .byte $05,>cs14_dlstripe,<cs14_dlstripe
  .byte $81,>cs14_dlnone,<cs14_dlnone
  .byte $07,>cs14_dlrow0,<cs14_dlrow0
  .byte $07,>cs14_dlrow1,<cs14_dlrow1
  .byte $07,>cs14_dlrow2,<cs14_dlrow2
  .byte $07,>cs14_dlrow3,<cs14_dlrow3
  .byte $07,>cs14_dlrow4,<cs14_dlrow4
  .byte $07,>cs14_dlrow5,<cs14_dlrow5
  .byte $07,>cs14_dlrow6,<cs14_dlrow6
  .byte $07,>cs14_dlrow7,<cs14_dlrow7
  .byte $07,>cs14_dlrow8,<cs14_dlrow8
  .byte $07,>cs14_dlrow9,<cs14_dlrow9
  .byte $07,>cs14_dlrow10,<cs14_dlrow10
  .byte $07,>cs14_dlrow11,<cs14_dlrow11
  .byte $07,>cs14_dlrow12,<cs14_dlrow12
  .byte $03,>cs14_dlnone,<cs14_dlnone
  .byte $C7,>cs14_dlnone,<cs14_dlnone
  .byte $CB,>cs14_dlnone,<cs14_dlnone
  .byte $4F,>cs14_dlnone,<cs14_dlnone
  .byte $4F,>cs14_dlnone,<cs14_dlnone
  .byte $4F,>cs14_dlnone,<cs14_dlnone
cs14_scenes .byte 8
cs14_kind .byte 0
cs14_pagelo .byte <cs14_text8
cs14_pagehi .byte >cs14_text8
cs14_dlllo .byte <cs14_dll8
cs14_dllhi .byte >cs14_dll8
cs14_pallo .byte <cs14_pal8
cs14_palhi .byte >cs14_pal8
cs14_text8
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,30,18,15,0,23,25,25,24,0,16,11,22,22,29
  .byte 0,12,15,18,19,24,14,0,19,24,30,25,0,30,18,15,0,32,25,19,14,37,64,11
  .byte 18,15,11,14,0,22,19,15,29,0,30,18,15,0,14,15,15,26,0,16,19,15,22,14
  .byte 37,64,64,13,25,23,23,31,24,19,13,11,30,19,25,24,0,14,15,22,11,35,0,19
  .byte 29,0,19,24,13,28,15,11,29,19,24,17,37,65
  .byte 1,13,11,26,30,37,0,23,11,35,11,0,21,15,29,30,28,15,22,0,45,45,0,17
  .byte 11,23,23,11,43,2,64,29,30,11,30,19,13,0,19,29,0,17,15,30,30,19,24,17
  .byte 0,30,18,19,13,21,0,25,24,0,30,18,19,29,64,13,18,11,24,24,15,22,38,0
  .byte 24,11,30,18,11,24,37,64,64,25,31,30,0,18,15,28,15,0,12,15,30,33,15,15
  .byte 24,0,30,18,15,0,29,30,11,28,29,38,0,19,30,0,19,29,64,14,15,11,14,0
  .byte 13,25,22,14,37,0,32,31,22,13,11,24,0,28,25,31,24,14,29,0,11,28,15,64
  .byte 29,26,11,28,21,19,24,17,0,18,11,28,23,22,15,29,29,22,35,0,25,16,16,0
  .byte 30,18,15,29,15,64,11,29,30,15,28,25,19,14,29,39,65
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,30,18,25,29,15,0,11,29,30,15,28,25,19,14
  .byte 29,0,11,28,15,0,29,25,22,19,14,64,24,19,13,21,15,22,43,19,28,25,24,39
  .byte 0,30,18,15,35,0,29,30,25,26,0,11,22,22,0,12,31,22,22,15,30,29,64,13
  .byte 25,22,14,38,0,11,24,14,0,11,0,13,25,22,22,19,29,19,25,24,0,33,19,22
  .byte 22,0,33,28,15,13,21,64,35,25,31,28,0,18,31,22,22,37,64,64,24,25,30,0
  .byte 15,32,15,24,0,30,18,15,0,29,33,25,28,14,0,13,11,24,0,13,31,30,0,30
  .byte 18,15,23,37,0,16,22,35,64,30,18,15,0,17,11,26,29,39,64,64,24,11,32,0
  .byte 16,19,34,0,25,24,0,23,19,24,25,28,0,26,22,11,24,15,30,0,3,1,1,8
  .byte 0,22,26,4,1,37,64,21,15,15,26,0,19,30,0,25,16,16,0,35,25,31,28,0
  .byte 22,15,16,30,0,33,19,24,17,0,11,24,14,64,35,25,31,41,22,22,0,13,22,15
  .byte 11,28,0,30,18,15,0,14,28,19,16,30,37,65
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,11,24,14,0,12,15,33,11,28,15,44,0,22,25
  .byte 24,17,43,28,11,24,17,15,0,29,13,11,24,29,0,29,18,25,33,0,11,64,22,19
  .byte 32,19,24,17,0,12,19,25,43,23,15,13,18,11,24,19,13,11,22,0,15,24,30,19
  .byte 30,35,0,24,15,29,30,15,14,64,19,24,0,30,18,15,0,28,25,13,21,29,44,0
  .byte 30,18,15,0,18,19,32,15,0,23,25,30,18,15,28,29,18,19,26,37,64,64,19,30
  .byte 29,0,15,35,15,0,33,25,24,41,30,0,25,26,15,24,0,31,24,30,19,22,0,11
  .byte 0,23,11,24,14,19,12,22,15,64,16,11,22,22,29,37,65
  .byte 1,13,11,26,30,37,0,23,11,35,11,0,21,15,29,30,28,15,22,0,45,45,0,17
  .byte 11,23,23,11,43,2,64,19,0,29,15,15,0,11,0,17,19,11,24,30,0,18,25,24
  .byte 15,35,13,25,23,12,0,29,33,11,35,19,24,17,0,19,24,64,30,18,15,0,14,11
  .byte 28,21,37,0,15,15,28,19,15,37,37,37,0,12,31,30,0,19,30,0,19,29,0,19
  .byte 24,0,23,35,64,33,11,35,39,64,64,28,11,14,19,11,24,30,0,29,33,25,28,14
  .byte 0,15,24,15,28,17,19,36,15,14,37,0,30,18,28,15,11,14,19,24,17,64,30,18
  .byte 15,0,14,28,19,16,30,39,66
