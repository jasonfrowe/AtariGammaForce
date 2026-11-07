

; ---- the player ----
cs11_main
     ; which of this bank's scenes
     ldx #1-1
cs11_find
     cmp cs11_scenes,x
     beq cs11_found
     dex
     bpl cs11_find
     rts                     ; (none: not this bank's)
cs11_found
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
cs11_clr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs11_clr
     jsr waitforvblankstart
     ldx cs_idx
     ; the palettes: the background, P0-P5 (the picture's), P6, P7 (the
     ; stripe's; white below it, cutvec)
     lda cs11_pallo,x
     sta pfq
     lda cs11_palhi,x
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant              ; (the picture's background, put back off the screen)
     ldx #0
cs11_pals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne cs11_palnext
     inx
cs11_palnext
     cpx #32
     bcc cs11_pals
     ldx cs_idx
     lda cs11_dlllo,x
     sta DPPL
     lda cs11_dllhi,x
     sta DPPH
     lda #<cs11_dli
     sta cutvec
     lda #>cs11_dli
     sta cutvec+1
     lda #<cs11_bottom
     sta cutvec2
     lda #>cs11_bottom
     sta cutvec2+1
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ; the first page
     lda cs11_pagelo,x
     sta pfp
     lda cs11_pagehi,x
     sta pfp+1
     jsr cs11_newpage
     lda #SONG_PROLOGUE
     jsr mus_play
cs11_loop
     jsr waitforvblankstart
     lda #3                  ; (7800basic's NMI count: as pf_drawscreen)
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     lda cs_state
     bne cs11_wait
     jsr cs11_type
     jmp cs11_input
cs11_wait
cs11_input
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev             ; (newly down)
     beq cs11_loop
     lda cs_state
     bne cs11_turn
cs11_finish                     ; typing: the rest of the page at once
     jsr cs11_type
     lda cs_state
     beq cs11_finish
     jmp cs11_loop
cs11_turn
     cmp #2
     beq cs11_exit
     jsr cs11_newpage
     jmp cs11_loop
cs11_exit
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
cs11_exitkeep
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
cs11_newpage
     lda #0
     sta cs_state
     sta cs_row
     sta cs_col
     ldx #0
cs11_npclr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs11_npclr
     ldy #0
     lda (pfp),y
     sta cs_por
     inc pfp
     bne cs11_np2
     inc pfp+1
cs11_np2
     if 0
     ldx cs_idx
     lda cs11_kind,x
     beq cs11_npdone
     jsr cs11_portrait
     endif
cs11_npdone
     rts

; One letter of the page onto its row (or a code)
cs11_type
     ldy #0
     lda (pfp),y
     inc pfp
     bne cs11_t2
     inc pfp+1
cs11_t2
     cmp #$40
     beq cs11_tnl
     cmp #$41
     beq cs11_tpage
     cmp #$42
     beq cs11_tend
     pha
     ldx cs_row
     lda cs11_rowlo,x
     sta pfq
     lda cs11_rowhi,x
     sta pfq+1
     ldy cs_col
     pla
     sta (pfq),y
     inc cs_col
     rts
cs11_tnl
     inc cs_row
     lda #0
     sta cs_col
     rts
cs11_tpage
     lda #1
     sta cs_state
     rts
cs11_tend
     lda #2
     sta cs_state
     rts

     if 0
; A briefing's top: the portrait (cs_por) in its three zones, its palettes
; (P0, P1), the two header lines beside it (the game's font: 160A)
cs11_portrait
     ldx cs_por
     lda cs11_porpal_lo,x
     sta pfq
     lda cs11_porpal_hi,x
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
     lda cs11_porlo,x
     sta pfq
     lda cs11_porhi,x
     sta pfq+1
     ldy #0
cs11_pz
     lda (pfq),y
     sta $1C00,y
     iny
     cpy #16
     bne cs11_pz
cs11_pz1
     lda (pfq),y
     sta $1C10,y
     iny
     cpy #32
     bne cs11_pz1
cs11_pz2
     lda (pfq),y
     sta $1C20,y
     iny
     cpy #48
     bne cs11_pz2
     ldx cs_idx
     lda cs11_h0lo,x
     sta $1C10
     lda #$60
     sta $1C11
     lda cs11_h0hi,x
     sta $1C12
     lda cs11_h0w,x
     ora #(2<<5)
     sta $1C13
     lda #48
     sta $1C14
     lda cs11_h1lo,x
     sta $1C30
     lda #$60
     sta $1C31
     lda cs11_h1hi,x
     sta $1C32
     lda cs11_h1w,x
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
cs11_dli
     sta WSYNC
     lda #$43
     sta CTRL
     lda #>cs11_font
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
cs11_bottom
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ldx cs_idx
     lda cs11_pallo,x
     sta pfq
     lda cs11_palhi,x
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

cs11_pal1 .byte $A1,$01,$A0,$A5,$03,$0B,$A5,$08,$A0,$A5,$08,$0B,$A5,$08,$9A,$A5,$37,$A0,$A0,$2A,$2A,$2A,$35,$29,$EC
cs11_dlstripe
  .byte <(cut_stripe11+0),248,>(cut_stripe11+0),0
  .byte <(cut_stripe11+0),248,>(cut_stripe11+0),32
  .byte <(cut_stripe11+0),248,>(cut_stripe11+0),64
  .byte <(cut_stripe11+0),248,>(cut_stripe11+0),96
  .byte <(cut_stripe11+0),248,>(cut_stripe11+0),128
  .byte 0,0
cs11_dlnone .byte 0,0
cs11_dlrow0
  .byte <$1900,$60,>$1900,206,8
  .byte <$1912,$60,>$1912,206,80
  .byte 0,0
cs11_dlrow1
  .byte <$1924,$60,>$1924,238,8
  .byte <$1936,$60,>$1936,238,80
  .byte 0,0
cs11_dlrow2
  .byte <$1948,$60,>$1948,238,8
  .byte <$195A,$60,>$195A,238,80
  .byte 0,0
cs11_dlrow3
  .byte <$196C,$60,>$196C,238,8
  .byte <$197E,$60,>$197E,238,80
  .byte 0,0
cs11_dlrow4
  .byte <$1990,$60,>$1990,238,8
  .byte <$19A2,$60,>$19A2,238,80
  .byte 0,0
cs11_dlrow5
  .byte <$19B4,$60,>$19B4,238,8
  .byte <$19C6,$60,>$19C6,238,80
  .byte 0,0
cs11_dlrow6
  .byte <$19D8,$60,>$19D8,238,8
  .byte <$19EA,$60,>$19EA,238,80
  .byte 0,0
cs11_dlrow7
  .byte <$19FC,$60,>$19FC,238,8
  .byte <$1A0E,$60,>$1A0E,238,80
  .byte 0,0
cs11_dlrow8
  .byte <$1A20,$60,>$1A20,238,8
  .byte <$1A32,$60,>$1A32,238,80
  .byte 0,0
cs11_dlrow9
  .byte <$1A44,$60,>$1A44,238,8
  .byte <$1A56,$60,>$1A56,238,80
  .byte 0,0
cs11_dlrow10
  .byte <$1A68,$60,>$1A68,238,8
  .byte <$1A7A,$60,>$1A7A,238,80
  .byte 0,0
cs11_dlrow11
  .byte <$1A8C,$60,>$1A8C,238,8
  .byte <$1A9E,$60,>$1A9E,238,80
  .byte 0,0
cs11_dlrow12
  .byte <$1AB0,$60,>$1AB0,238,8
  .byte <$1AC2,$60,>$1AC2,238,80
  .byte 0,0
cs11_rowlo .byte <$1900,<$1924,<$1948,<$196C,<$1990,<$19B4,<$19D8,<$19FC,<$1A20,<$1A44,<$1A68,<$1A8C,<$1AB0
cs11_rowhi .byte >$1900,>$1924,>$1948,>$196C,>$1990,>$19B4,>$19D8,>$19FC,>$1A20,>$1A44,>$1A68,>$1A8C,>$1AB0
cs11_dlpic1_0
  .byte <(cut_prologue0+0),30,>(cut_prologue0+0),0
  .byte <(cut_prologue0+2),190,>(cut_prologue0+2),8
  .byte <(cut_prologue0+4),2,>(cut_prologue0+4),16
  .byte <(cut_prologue0+34),30,>(cut_prologue0+34),136
  .byte <(cut_prologue0+36),190,>(cut_prologue0+36),144
  .byte <(cut_prologue0+38),30,>(cut_prologue0+38),152
  .byte 0,0
cs11_dlpic1_1
  .byte <(cut_prologue1+0),26,>(cut_prologue1+0),0
  .byte <(cut_prologue1+6),184,>(cut_prologue1+6),24
  .byte <(cut_prologue1+14),20,>(cut_prologue1+14),56
  .byte <(cut_prologue1+26),184,>(cut_prologue1+26),104
  .byte <(cut_prologue1+34),26,>(cut_prologue1+34),136
  .byte 0,0
cs11_dlpic1_2
  .byte <(cut_prologue2+0),2,>(cut_prologue2+0),0
  .byte <(cut_prologue2+30),22,>(cut_prologue2+30),120
  .byte 0,0
cs11_dlpic1_3
  .byte <(cut_prologue3+0),14,>(cut_prologue3+0),0
  .byte <(cut_prologue3+18),60,>(cut_prologue3+18),72
  .byte <(cut_prologue3+22),14,>(cut_prologue3+22),88
  .byte 0,0
cs11_dlpic1_4
  .byte <(cut_prologue4+0),92,>(cut_prologue4+0),0
  .byte <(cut_prologue4+4),30,>(cut_prologue4+4),16
  .byte <(cut_prologue4+6),86,>(cut_prologue4+6),24
  .byte <(cut_prologue4+16),126,>(cut_prologue4+16),64
  .byte <(cut_prologue4+18),62,>(cut_prologue4+18),72
  .byte <(cut_prologue4+20),124,>(cut_prologue4+20),80
  .byte <(cut_prologue4+24),88,>(cut_prologue4+24),96
  .byte <(cut_prologue4+32),30,>(cut_prologue4+32),128
  .byte <(cut_prologue4+34),90,>(cut_prologue4+34),136
  .byte 0,0
cs11_dlpic1_5
  .byte <(cut_prologue5+0),86,>(cut_prologue5+0),0
  .byte <(cut_prologue5+10),30,>(cut_prologue5+10),40
  .byte <(cut_prologue5+12),90,>(cut_prologue5+12),48
  .byte <(cut_prologue5+18),156,>(cut_prologue5+18),72
  .byte <(cut_prologue5+22),94,>(cut_prologue5+22),88
  .byte <(cut_prologue5+24),30,>(cut_prologue5+24),96
  .byte <(cut_prologue5+26),84,>(cut_prologue5+26),104
  .byte <(cut_prologue5+38),30,>(cut_prologue5+38),152
  .byte 0,0
cs11_dll1
  .byte $46,>cs11_dlnone,<cs11_dlnone
  .byte $40,>cs11_dlnone,<cs11_dlnone
  .byte $40,>cs11_dlnone,<cs11_dlnone
  .byte $07,>cs11_dlnone,<cs11_dlnone
  .byte $0F,>cs11_dlpic1_0,<cs11_dlpic1_0
  .byte $0F,>cs11_dlpic1_1,<cs11_dlpic1_1
  .byte $0F,>cs11_dlpic1_2,<cs11_dlpic1_2
  .byte $0F,>cs11_dlpic1_3,<cs11_dlpic1_3
  .byte $0F,>cs11_dlpic1_4,<cs11_dlpic1_4
  .byte $0F,>cs11_dlpic1_5,<cs11_dlpic1_5
  .byte $03,>cs11_dlnone,<cs11_dlnone
  .byte $05,>cs11_dlstripe,<cs11_dlstripe
  .byte $81,>cs11_dlnone,<cs11_dlnone
  .byte $07,>cs11_dlrow0,<cs11_dlrow0
  .byte $07,>cs11_dlrow1,<cs11_dlrow1
  .byte $07,>cs11_dlrow2,<cs11_dlrow2
  .byte $07,>cs11_dlrow3,<cs11_dlrow3
  .byte $07,>cs11_dlrow4,<cs11_dlrow4
  .byte $07,>cs11_dlrow5,<cs11_dlrow5
  .byte $07,>cs11_dlrow6,<cs11_dlrow6
  .byte $07,>cs11_dlrow7,<cs11_dlrow7
  .byte $07,>cs11_dlrow8,<cs11_dlrow8
  .byte $07,>cs11_dlrow9,<cs11_dlrow9
  .byte $07,>cs11_dlrow10,<cs11_dlrow10
  .byte $07,>cs11_dlrow11,<cs11_dlrow11
  .byte $07,>cs11_dlrow12,<cs11_dlrow12
  .byte $03,>cs11_dlnone,<cs11_dlnone
  .byte $C3,>cs11_dlnone,<cs11_dlnone
  .byte $CF,>cs11_dlnone,<cs11_dlnone
  .byte $4F,>cs11_dlnone,<cs11_dlnone
  .byte $4F,>cs11_dlnone,<cs11_dlnone
  .byte $4F,>cs11_dlnone,<cs11_dlnone
cs11_scenes .byte 1
cs11_kind .byte 0
cs11_pagelo .byte <cs11_text1
cs11_pagehi .byte >cs11_text1
cs11_dlllo .byte <cs11_dll1
cs11_dllhi .byte >cs11_dll1
cs11_pallo .byte <cs11_pal1
cs11_palhi .byte >cs11_pal1
cs11_text1
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,17,11,23,23,11,43,2,38,0,30,18,15,0,12
  .byte 11,35,0,19,29,0,16,22,25,25,14,15,14,0,11,24,14,0,30,18,15,64,30,31
  .byte 12,15,0,19,29,0,35,25,31,28,29,37,0,30,18,15,0,13,25,28,25,24,11,22
  .byte 0,29,33,11,28,23,64,18,25,22,14,29,0,15,32,15,28,35,0,29,21,35,0,16
  .byte 28,25,23,0,18,15,28,15,0,30,25,0,30,18,15,64,29,31,24,38,0,11,24,14
  .byte 0,30,18,15,0,17,16,43,1,2,0,19,29,0,11,22,22,0,15,11,28,30,18,0
  .byte 18,11,29,64,22,15,16,30,37,64,64,12,31,30,30,25,24,0,2,0,16,19,28,15
  .byte 29,0,35,25,31,28,0,30,33,19,24,0,32,31,22,13,11,24,37,64,12,31,30,30
  .byte 25,24,0,3,0,29,33,19,24,17,29,0,30,18,15,0,28,11,14,19,11,24,30,0
  .byte 29,33,25,28,14,37,65
  .byte 0,15,14,13,0,17,28,25,31,24,14,0,13,25,24,30,28,25,22,0,45,45,0,14
  .byte 28,37,0,30,18,25,28,24,15,64,30,18,15,0,29,33,25,28,14,0,14,28,19,24
  .byte 21,29,0,26,19,24,21,0,16,19,28,15,44,0,15,32,15,28,35,64,26,19,24,21
  .byte 0,12,31,22,22,15,30,0,19,30,0,13,11,30,13,18,15,29,0,13,18,11,28,17
  .byte 15,29,0,35,25,31,28,64,18,35,26,15,28,0,17,11,31,17,15,37,0,12,22,31
  .byte 15,0,16,19,28,15,0,26,11,29,29,15,29,0,28,19,17,18,30,64,30,18,28,25
  .byte 31,17,18,0,19,30,37,0,14,25,14,17,15,0,30,18,15,0,12,22,31,15,37,64
  .byte 64,17,11,31,17,15,0,16,31,22,22,40,0,26,28,15,29,29,0,12,25,30,18,0
  .byte 12,31,30,30,25,24,29,44,0,30,18,15,64,18,35,26,15,28,0,29,33,25,28,14
  .byte 0,12,31,28,24,29,0,11,0,12,15,11,23,0,31,26,0,30,18,15,64,33,18,25
  .byte 22,15,0,29,13,28,15,15,24,37,64,64,14,25,33,24,0,30,18,28,15,15,0,25
  .byte 16,0,25,24,15,0,13,25,22,25,28,0,19,24,0,11,0,28,25,33,0,30,25,64
  .byte 13,18,11,19,24,0,30,18,15,23,37,65
  .byte 1,13,11,26,30,37,0,23,11,35,11,0,32,11,24,13,15,0,45,45,0,17,11,23
  .byte 23,11,43,2,64,13,11,30,11,26,31,22,30,0,17,28,15,15,24,37,0,29,33,25
  .byte 28,14,0,13,11,26,11,13,19,30,25,28,64,18,25,22,14,19,24,17,0,29,30,15
  .byte 11,14,35,37,64,64,23,11,35,11,0,32,11,24,13,15,38,0,28,25,22,22,19,24
  .byte 17,0,25,31,30,39,66
