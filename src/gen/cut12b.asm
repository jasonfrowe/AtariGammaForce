

; ---- the player ----
cs12_main
     ; which of this bank's scenes
     ldx #5-1
cs12_find
     cmp cs12_scenes,x
     beq cs12_found
     dex
     bpl cs12_find
     rts                     ; (none: not this bank's)
cs12_found
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
cs12_clr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs12_clr
     jsr waitforvblankstart
     ldx cs_idx
     ; the palettes: the background, P0-P5 (the picture's), P6, P7 (the
     ; stripe's; white below it, cutvec)
     lda cs12_pallo,x
     sta pfq
     lda cs12_palhi,x
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant              ; (the picture's background, put back off the screen)
     ldx #0
cs12_pals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne cs12_palnext
     inx
cs12_palnext
     cpx #32
     bcc cs12_pals
     ldx cs_idx
     lda cs12_dlllo,x
     sta DPPL
     lda cs12_dllhi,x
     sta DPPH
     lda #<cs12_dli
     sta cutvec
     lda #>cs12_dli
     sta cutvec+1
     lda #<cs12_bottom
     sta cutvec2
     lda #>cs12_bottom
     sta cutvec2+1
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ; the first page
     lda cs12_pagelo,x
     sta pfp
     lda cs12_pagehi,x
     sta pfp+1
     jsr cs12_newpage
     lda #SONG_BRIEFING
     jsr mus_play
cs12_loop
     jsr waitforvblankstart
     lda #3                  ; (7800basic's NMI count: as pf_drawscreen)
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     lda cs_state
     bne cs12_wait
     jsr cs12_type
     jmp cs12_input
cs12_wait
cs12_input
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev             ; (newly down)
     beq cs12_loop
     lda cs_state
     bne cs12_turn
cs12_finish                     ; typing: the rest of the page at once
     jsr cs12_type
     lda cs_state
     beq cs12_finish
     jmp cs12_loop
cs12_turn
     cmp #2
     beq cs12_exit
     jsr cs12_newpage
     jmp cs12_loop
cs12_exit
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
     jsr mus_stop
     rts

; A new page: the rows clear, its portrait (a briefing's), typing from its
; text (pfp: its first byte, the portrait)
cs12_newpage
     lda #0
     sta cs_state
     sta cs_row
     sta cs_col
     ldx #0
cs12_npclr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs12_npclr
     ldy #0
     lda (pfp),y
     sta cs_por
     inc pfp
     bne cs12_np2
     inc pfp+1
cs12_np2
     if 1
     ldx cs_idx
     lda cs12_kind,x
     beq cs12_npdone
     jsr cs12_portrait
     endif
cs12_npdone
     rts

; One letter of the page onto its row (or a code)
cs12_type
     ldy #0
     lda (pfp),y
     inc pfp
     bne cs12_t2
     inc pfp+1
cs12_t2
     cmp #$40
     beq cs12_tnl
     cmp #$41
     beq cs12_tpage
     cmp #$42
     beq cs12_tend
     pha
     ldx cs_row
     lda cs12_rowlo,x
     sta pfq
     lda cs12_rowhi,x
     sta pfq+1
     ldy cs_col
     pla
     sta (pfq),y
     inc cs_col
     rts
cs12_tnl
     inc cs_row
     lda #0
     sta cs_col
     rts
cs12_tpage
     lda #1
     sta cs_state
     rts
cs12_tend
     lda #2
     sta cs_state
     rts

     if 1
; A briefing's top: the portrait (cs_por) in its three zones, its palettes
; (P0, P1), the two header lines beside it (the game's font: 160A)
cs12_portrait
     ldx cs_por
     lda cs12_porpal_lo,x
     sta pfq
     lda cs12_porpal_hi,x
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
     lda cs12_porlo,x
     sta pfq
     lda cs12_porhi,x
     sta pfq+1
     ldy #0
cs12_pz
     lda (pfq),y
     sta $1C00,y
     iny
     cpy #16
     bne cs12_pz
cs12_pz1
     lda (pfq),y
     sta $1C10,y
     iny
     cpy #32
     bne cs12_pz1
cs12_pz2
     lda (pfq),y
     sta $1C20,y
     iny
     cpy #48
     bne cs12_pz2
     ldx cs_idx
     lda cs12_h0lo,x
     sta $1C10
     lda #$60
     sta $1C11
     lda cs12_h0hi,x
     sta $1C12
     lda cs12_h0w,x
     ora #(2<<5)
     sta $1C13
     lda #48
     sta $1C14
     lda cs12_h1lo,x
     sta $1C30
     lda #$60
     sta $1C31
     lda cs12_h1hi,x
     sta $1C32
     lda cs12_h1w,x
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
cs12_dli
     sta WSYNC
     lda #$43
     sta CTRL
     lda #>cs12_font
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
cs12_bottom
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     ldx cs_idx
     lda cs12_pallo,x
     sta pfq
     lda cs12_palhi,x
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

; ---- the high score table ----
cs12_hs
     sta hs_mode
     lda easy                ; (the difficulty: a table each)
     sta gamedifficulty
     jsr loaddifficultytable
     ; an empty table (no save device, or nothing saved yet): the defaults
     ldx #14
     lda #0
cs12_hsempty
     ora HSRAMScores,x
     dex
     bpl cs12_hsempty
     tax
     bne cs12_hsfull
     ldx #14
cs12_hsdef
     lda cs12_hsdefs,x
     sta HSRAMScores,x
     lda cs12_hsdefi,x
     sta HSRAMInitials,x
     dex
     bpl cs12_hsdef
cs12_hsfull
     lda #$FF
     sta hs_pos
     lda hs_mode
     beq cs12_hs1
     jsr cs12_hsinsert
cs12_hs1
     lda #0
     sta cs_idx              ; (the screen of this bank's first briefing)
     sta hs_t
     sta fadeon
     lda #$FF
     sta hs_rep
     lda #0
     ifconst interrupthold
     lda #$FF
     sta interrupthold
     endif
     lda sINPT1
     and #$C0
     sta cs_prev
     lda #0
     tax
cs12_hsclr
     sta $1900,x
     sta $1A00,x
     sta $1B00,x
     inx
     bne cs12_hsclr
     ; the header (the game's font, centred): HIGH SCORES, the difficulty
     ldx easy
     lda #<cs12_hshead
     sta $1C00
     lda #$60
     sta $1C01
     sta $1C21
     lda #>cs12_hshead
     sta $1C02
     lda #(cs12_hsheadw|(2<<5))
     sta $1C03
     lda #cs12_hsheadx
     sta $1C04
     lda cs12_hsmodelo,x
     sta $1C20
     lda cs12_hsmodehi,x
     sta $1C22
     lda cs12_hsmodew,x
     ora #(3<<5)
     sta $1C23
     lda cs12_hsmodex,x
     sta $1C24
     lda #0
     sta $1C05
     sta $1C06
     sta $1C25
     sta $1C26
     sta $1C40
     sta $1C41
     ; the texts: the title, and (entering) the prompt
     ldx #0
     lda #<cs12_hstitle
     ldy #>cs12_hstitle
     jsr cs12_hsline
     lda hs_pos
     bmi cs12_hs2
     jsr cs12_hsprompt
cs12_hs2
     jsr waitforvblankstart
     lda cs12_pallo
     sta pfq
     lda cs12_palhi
     sta pfq+1
     ldy #0
     lda (pfq),y
     sta cs_bg
     sta BACKGRND
     sta bgwant
     ldx #0
cs12_hspals
     iny
     lda (pfq),y
     sta P0C1,x
     inx
     txa
     and #3
     cmp #3
     bne cs12_hspaln
     inx
cs12_hspaln
     cpx #32
     bcc cs12_hspals
     lda #$2A
     sta P2C3
     lda #$0F
     sta P3C3
     lda cs12_dlllo
     sta DPPL
     lda cs12_dllhi
     sta DPPH
     lda #<cs12_dli
     sta cutvec
     lda #>cs12_dli
     sta cutvec+1
     lda #<cs12_bottom
     sta cutvec2
     lda #>cs12_bottom
     sta cutvec2+1
     lda #$50
     sta CTRL
     lda #$C0
     sta CHARBASE
     lda #SONG_BRIEFING
     jsr mus_play
cs12_hsloop
     jsr waitforvblankstart
     lda #3
     sta interruptindex
     lda #0
     sta visibleover
     dec frameslost
     inc hs_t
     jsr cs12_hsrows
     ; a fresh press of either button
     lda sINPT1
     and #$C0
     tax
     eor cs_prev
     and #$C0
     stx cs_prev
     and cs_prev
     sta hs_fire
     lda hs_pos
     bmi cs12_hsshow
     ; entering: up and down choose the letter (repeating while held),
     ; fire takes it
     lda SWCHA
     and #$30
     cmp #$30
     bne cs12_hsstick
     lda #$FF                ; (released)
     sta hs_rep
     bne cs12_hsfire
cs12_hsstick
     lda hs_rep
     bpl cs12_hsheld
     lda #20                 ; a press: a letter, and 20 frames before it repeats
     sta hs_rep
     bne cs12_hsstep
cs12_hsheld
     dec hs_rep
     bne cs12_hsfire
     lda #8                  ; held: a letter every 8 frames
     sta hs_rep
cs12_hsstep
     jsr cs12_hsletter
     lda SWCHA
     and #$10                ; up: the next letter
     bne cs12_hsdown
     lda (pfq),y
     clc
     adc #1
     cmp #27
     bcc cs12_hsput
     lda #0
     beq cs12_hsput
cs12_hsdown
     lda (pfq),y
     sec
     sbc #1
     bcs cs12_hsput
     lda #26
cs12_hsput
     sta (pfq),y
cs12_hsfire
     lda hs_fire
     beq cs12_hsback
     inc hs_cur
     lda hs_cur
     cmp #3
     bcs cs12_hstaken
cs12_hsback
     jmp cs12_hsloop
cs12_hstaken
     ; the initials taken: saved, and the table shown a while
     jsr savedifficultytable
     lda #$FF
     sta hs_pos
     lda #0
     sta hs_t
     ldx #12
     jsr cs12_hsblank
     ldx #13
     jsr cs12_hsblank
     ldx #14
     jsr cs12_hsblank
     jmp cs12_hsloop
cs12_hsshow
     ; the table: until fire, or a while (hs_mode counts 250 frames to 3:
     ; 12 seconds from the title, 8 after an entry)
     lda hs_fire
     bne cs12_hsdone
     lda hs_t
     cmp #250
     bcc cs12_hsagain
     inc hs_mode             ; (counting the 250s)
     lda #0
     sta hs_t
     lda hs_mode
     cmp #3
     bcs cs12_hsdone
cs12_hsagain
     jmp cs12_hsloop
cs12_hsdone
     jmp cs12_exit

; pfq/y: the initial being entered (HSRAMInitials, hs_pos * 3 + hs_cur)
cs12_hsletter
     lda hs_pos
     asl
     adc hs_pos
     adc hs_cur
     tay
     lda #<HSRAMInitials
     sta pfq
     lda #>HSRAMInitials
     sta pfq+1
     rts

; The five entries onto rows HS_ROW0 on: the place, the initials (the one
; being entered blinking), the score (its six digits, and the 0 they
; leave off)
cs12_hsrows
     ldx #0
cs12_hsr
     stx hs_x
     txa
     asl                     ; (every other row)
     adc #2
     tay
     lda cs12_rowlo,y
     sta pfq
     lda cs12_rowhi,y
     sta pfq+1
     ldy #9
     txa
     clc
     adc #2                  ; (the font's 1: its code 2)
     sta (pfq),y
     ; the initials
     txa
     asl
     adc hs_x
     tax                     ; (the entry's first initial)
     ldy #13
cs12_hsri
     lda HSRAMInitials,x
     cmp #27
     bcc cs12_hsri1
     lda #26
cs12_hsri1
     stx hs_y
     tax
     lda cs12_hsglyph,x
     ldx hs_y
     sta hs_c
     ; (the one being entered blinks)
     lda hs_pos
     cmp hs_x
     bne cs12_hsri2
     tya
     sec
     sbc #13
     cmp hs_cur
     bne cs12_hsri2
     lda hs_t
     and #16
     beq cs12_hsri2
     lda #43
     sta hs_c
cs12_hsri2
     lda hs_c
     sta (pfq),y
     inx
     iny
     cpy #16
     bne cs12_hsri
     ; the score
     ldx hs_x
     txa
     asl
     adc hs_x
     tax
     ldy #20
cs12_hsrs
     lda HSRAMScores,x
     lsr
     lsr
     lsr
     lsr
     clc
     adc #1                  ; (the font's digits from code 1)
     sta (pfq),y
     iny
     lda HSRAMScores,x
     and #$0F
     clc
     adc #1
     sta (pfq),y
     iny
     inx
     cpy #26
     bne cs12_hsrs
     lda #1                  ; (the 0 left off)
     sta (pfq),y
     ldx hs_x
     inx
     cpx #5
     bcs cs12_hsrend
     jmp cs12_hsr
cs12_hsrend
     rts

; A text (A/Y: its address, $FF-ended) onto row X
cs12_hsline
     sta pfp
     sty pfp+1
     lda cs12_rowlo,x
     sta pfq
     lda cs12_rowhi,x
     sta pfq+1
     ldy #0
cs12_hsl
     lda (pfp),y
     cmp #$FF
     beq cs12_hsl2
     sta (pfq),y
     iny
     bne cs12_hsl
cs12_hsl2
     rts

; Row X cleared
cs12_hsblank
     lda cs12_rowlo,x
     sta pfq
     lda cs12_rowhi,x
     sta pfq+1
     lda #0
     ldy #35
cs12_hsb
     sta (pfq),y
     dey
     bpl cs12_hsb
     rts

cs12_hsprompt
     ldx #12
     lda #<cs12_hsnew
     ldy #>cs12_hsnew
     jsr cs12_hsline
     ldx #13
     lda #<cs12_hshelp1
     ldy #>cs12_hshelp1
     jsr cs12_hsline
     ldx #14
     lda #<cs12_hshelp2
     ldy #>cs12_hshelp2
     jmp cs12_hsline

; The score (its six digits past the first, three BCD bytes: the last
; digit, always 0, left off) into the table if it beats an entry: the
; entries below it move down; its initials start as AAA. hs_pos: its
; place, or $FF.
cs12_hsinsert
     lda score_bcd
     asl
     asl
     asl
     asl
     sta hs_b0
     lda score_bcd+1
     lsr
     lsr
     lsr
     lsr
     ora hs_b0
     sta hs_b0
     lda score_bcd+1
     asl
     asl
     asl
     asl
     sta hs_b1
     lda score_bcd+2
     lsr
     lsr
     lsr
     lsr
     ora hs_b1
     sta hs_b1
     lda score_bcd+2
     asl
     asl
     asl
     asl
     sta hs_b2
     lda score_bcd+3
     lsr
     lsr
     lsr
     lsr
     ora hs_b2
     sta hs_b2
     ldx #0                  ; (each entry's first score byte: 0, 3, ...)
     ldy #0                  ; (its place)
cs12_hsi
     lda hs_b0
     cmp HSRAMScores,x
     bcc cs12_hsinext
     bne cs12_hsiput
     lda hs_b1
     cmp HSRAMScores+1,x
     bcc cs12_hsinext
     bne cs12_hsiput
     lda hs_b2
     cmp HSRAMScores+2,x
     bcc cs12_hsinext
     bne cs12_hsiput
cs12_hsinext
     inx
     inx
     inx
     iny
     cpy #5
     bne cs12_hsi
     rts                     ; (not in the table)
cs12_hsiput
     sty hs_pos
     stx hs_x3               ; (its first byte: its place * 3)
     lda #0
     sta hs_cur
     ; the entries from its place down move down one (the last is lost)
     ldx #11                 ; (the 4th entry's first byte: copied to the 5th's)
cs12_hsmove
     cpx hs_x3
     bcc cs12_hsmoved
     lda HSRAMScores,x
     sta HSRAMScores+3,x
     lda HSRAMInitials,x
     sta HSRAMInitials+3,x
     dex
     bpl cs12_hsmove
cs12_hsmoved
     ldx hs_x3
     lda hs_b0
     sta HSRAMScores,x
     lda hs_b1
     sta HSRAMScores+1,x
     lda hs_b2
     sta HSRAMScores+2,x
     lda #0
     sta HSRAMInitials,x
     sta HSRAMInitials+1,x
     sta HSRAMInitials+2,x
     rts

cs12_pal2 .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2A,$2A,$2A,$35,$29,$EC
cs12_pal3 .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2A,$2A,$2A,$35,$29,$EC
cs12_pal4 .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2A,$2A,$2A,$35,$29,$EC
cs12_pal5 .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2A,$2A,$2A,$35,$29,$EC
cs12_pal7 .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2A,$2A,$2A,$35,$29,$EC
cs12_dlstripe
  .byte <(cut_stripe12+0),248,>(cut_stripe12+0),0
  .byte <(cut_stripe12+0),248,>(cut_stripe12+0),32
  .byte <(cut_stripe12+0),248,>(cut_stripe12+0),64
  .byte <(cut_stripe12+0),248,>(cut_stripe12+0),96
  .byte <(cut_stripe12+0),248,>(cut_stripe12+0),128
  .byte 0,0
cs12_dlnone .byte 0,0
cs12_dlrow0
  .byte <$1900,$60,>$1900,206,8
  .byte <$1912,$60,>$1912,206,80
  .byte 0,0
cs12_dlrow1
  .byte <$1924,$60,>$1924,238,8
  .byte <$1936,$60,>$1936,238,80
  .byte 0,0
cs12_dlrow2
  .byte <$1948,$60,>$1948,238,8
  .byte <$195A,$60,>$195A,238,80
  .byte 0,0
cs12_dlrow3
  .byte <$196C,$60,>$196C,238,8
  .byte <$197E,$60,>$197E,238,80
  .byte 0,0
cs12_dlrow4
  .byte <$1990,$60,>$1990,238,8
  .byte <$19A2,$60,>$19A2,238,80
  .byte 0,0
cs12_dlrow5
  .byte <$19B4,$60,>$19B4,238,8
  .byte <$19C6,$60,>$19C6,238,80
  .byte 0,0
cs12_dlrow6
  .byte <$19D8,$60,>$19D8,238,8
  .byte <$19EA,$60,>$19EA,238,80
  .byte 0,0
cs12_dlrow7
  .byte <$19FC,$60,>$19FC,238,8
  .byte <$1A0E,$60,>$1A0E,238,80
  .byte 0,0
cs12_dlrow8
  .byte <$1A20,$60,>$1A20,238,8
  .byte <$1A32,$60,>$1A32,238,80
  .byte 0,0
cs12_dlrow9
  .byte <$1A44,$60,>$1A44,238,8
  .byte <$1A56,$60,>$1A56,238,80
  .byte 0,0
cs12_dlrow10
  .byte <$1A68,$60,>$1A68,238,8
  .byte <$1A7A,$60,>$1A7A,238,80
  .byte 0,0
cs12_dlrow11
  .byte <$1A8C,$60,>$1A8C,238,8
  .byte <$1A9E,$60,>$1A9E,238,80
  .byte 0,0
cs12_dlrow12
  .byte <$1AB0,$60,>$1AB0,238,8
  .byte <$1AC2,$60,>$1AC2,238,80
  .byte 0,0
cs12_dlrow13
  .byte <$1AD4,$60,>$1AD4,238,8
  .byte <$1AE6,$60,>$1AE6,238,80
  .byte 0,0
cs12_dlrow14
  .byte <$1AF8,$60,>$1AF8,238,8
  .byte <$1B0A,$60,>$1B0A,238,80
  .byte 0,0
cs12_dlrow15
  .byte <$1B1C,$60,>$1B1C,238,8
  .byte <$1B2E,$60,>$1B2E,238,80
  .byte 0,0
cs12_rowlo .byte <$1900,<$1924,<$1948,<$196C,<$1990,<$19B4,<$19D8,<$19FC,<$1A20,<$1A44,<$1A68,<$1A8C,<$1AB0,<$1AD4,<$1AF8,<$1B1C
cs12_rowhi .byte >$1900,>$1924,>$1948,>$196C,>$1990,>$19B4,>$19D8,>$19FC,>$1A20,>$1A44,>$1A68,>$1A8C,>$1AB0,>$1AD4,>$1AF8,>$1B1C
cs12_dll2
  .byte $46,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlnone,<cs12_dlnone
  .byte $0F,>$1C00,<$1C00
  .byte $0F,>$1C20,<$1C20
  .byte $0F,>$1C40,<$1C40
  .byte $03,>cs12_dlnone,<cs12_dlnone
  .byte $05,>cs12_dlstripe,<cs12_dlstripe
  .byte $81,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlrow0,<cs12_dlrow0
  .byte $07,>cs12_dlrow1,<cs12_dlrow1
  .byte $07,>cs12_dlrow2,<cs12_dlrow2
  .byte $07,>cs12_dlrow3,<cs12_dlrow3
  .byte $07,>cs12_dlrow4,<cs12_dlrow4
  .byte $07,>cs12_dlrow5,<cs12_dlrow5
  .byte $07,>cs12_dlrow6,<cs12_dlrow6
  .byte $07,>cs12_dlrow7,<cs12_dlrow7
  .byte $07,>cs12_dlrow8,<cs12_dlrow8
  .byte $07,>cs12_dlrow9,<cs12_dlrow9
  .byte $07,>cs12_dlrow10,<cs12_dlrow10
  .byte $07,>cs12_dlrow11,<cs12_dlrow11
  .byte $07,>cs12_dlrow12,<cs12_dlrow12
  .byte $07,>cs12_dlrow13,<cs12_dlrow13
  .byte $07,>cs12_dlrow14,<cs12_dlrow14
  .byte $07,>cs12_dlrow15,<cs12_dlrow15
  .byte $0F,>cs12_dlnone,<cs12_dlnone
  .byte $0B,>cs12_dlnone,<cs12_dlnone
  .byte $C3,>cs12_dlnone,<cs12_dlnone
  .byte $CF,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
cs12_head2_0 .byte 58,30,26,60,50,56,20,4
cs12_headlen2_0 = 8
cs12_head2_1 .byte 48,30,50,48,20,58,52,38,56,30,58
cs12_headlen2_1 = 11
cs12_dll3
  .byte $46,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlnone,<cs12_dlnone
  .byte $0F,>$1C00,<$1C00
  .byte $0F,>$1C20,<$1C20
  .byte $0F,>$1C40,<$1C40
  .byte $03,>cs12_dlnone,<cs12_dlnone
  .byte $05,>cs12_dlstripe,<cs12_dlstripe
  .byte $81,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlrow0,<cs12_dlrow0
  .byte $07,>cs12_dlrow1,<cs12_dlrow1
  .byte $07,>cs12_dlrow2,<cs12_dlrow2
  .byte $07,>cs12_dlrow3,<cs12_dlrow3
  .byte $07,>cs12_dlrow4,<cs12_dlrow4
  .byte $07,>cs12_dlrow5,<cs12_dlrow5
  .byte $07,>cs12_dlrow6,<cs12_dlrow6
  .byte $07,>cs12_dlrow7,<cs12_dlrow7
  .byte $07,>cs12_dlrow8,<cs12_dlrow8
  .byte $07,>cs12_dlrow9,<cs12_dlrow9
  .byte $07,>cs12_dlrow10,<cs12_dlrow10
  .byte $07,>cs12_dlrow11,<cs12_dlrow11
  .byte $07,>cs12_dlrow12,<cs12_dlrow12
  .byte $07,>cs12_dlrow13,<cs12_dlrow13
  .byte $07,>cs12_dlrow14,<cs12_dlrow14
  .byte $07,>cs12_dlrow15,<cs12_dlrow15
  .byte $0F,>cs12_dlnone,<cs12_dlnone
  .byte $0B,>cs12_dlnone,<cs12_dlnone
  .byte $C3,>cs12_dlnone,<cs12_dlnone
  .byte $CF,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
cs12_head3_0 .byte 58,30,26,60,50,56,20,6
cs12_headlen3_0 = 8
cs12_head3_1 .byte 38,56,50,48,20,60,38,28,30
cs12_headlen3_1 = 9
cs12_dll4
  .byte $46,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlnone,<cs12_dlnone
  .byte $0F,>$1C00,<$1C00
  .byte $0F,>$1C20,<$1C20
  .byte $0F,>$1C40,<$1C40
  .byte $03,>cs12_dlnone,<cs12_dlnone
  .byte $05,>cs12_dlstripe,<cs12_dlstripe
  .byte $81,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlrow0,<cs12_dlrow0
  .byte $07,>cs12_dlrow1,<cs12_dlrow1
  .byte $07,>cs12_dlrow2,<cs12_dlrow2
  .byte $07,>cs12_dlrow3,<cs12_dlrow3
  .byte $07,>cs12_dlrow4,<cs12_dlrow4
  .byte $07,>cs12_dlrow5,<cs12_dlrow5
  .byte $07,>cs12_dlrow6,<cs12_dlrow6
  .byte $07,>cs12_dlrow7,<cs12_dlrow7
  .byte $07,>cs12_dlrow8,<cs12_dlrow8
  .byte $07,>cs12_dlrow9,<cs12_dlrow9
  .byte $07,>cs12_dlrow10,<cs12_dlrow10
  .byte $07,>cs12_dlrow11,<cs12_dlrow11
  .byte $07,>cs12_dlrow12,<cs12_dlrow12
  .byte $07,>cs12_dlrow13,<cs12_dlrow13
  .byte $07,>cs12_dlrow14,<cs12_dlrow14
  .byte $07,>cs12_dlrow15,<cs12_dlrow15
  .byte $0F,>cs12_dlnone,<cs12_dlnone
  .byte $0B,>cs12_dlnone,<cs12_dlnone
  .byte $C3,>cs12_dlnone,<cs12_dlnone
  .byte $CF,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
cs12_head4_0 .byte 58,30,26,60,50,56,20,8
cs12_headlen4_0 = 8
cs12_head4_1 .byte 58,26,50,56,26,36,30,28,20,58,22,48,28,58
cs12_headlen4_1 = 14
cs12_dll5
  .byte $46,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlnone,<cs12_dlnone
  .byte $0F,>$1C00,<$1C00
  .byte $0F,>$1C20,<$1C20
  .byte $0F,>$1C40,<$1C40
  .byte $03,>cs12_dlnone,<cs12_dlnone
  .byte $05,>cs12_dlstripe,<cs12_dlstripe
  .byte $81,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlrow0,<cs12_dlrow0
  .byte $07,>cs12_dlrow1,<cs12_dlrow1
  .byte $07,>cs12_dlrow2,<cs12_dlrow2
  .byte $07,>cs12_dlrow3,<cs12_dlrow3
  .byte $07,>cs12_dlrow4,<cs12_dlrow4
  .byte $07,>cs12_dlrow5,<cs12_dlrow5
  .byte $07,>cs12_dlrow6,<cs12_dlrow6
  .byte $07,>cs12_dlrow7,<cs12_dlrow7
  .byte $07,>cs12_dlrow8,<cs12_dlrow8
  .byte $07,>cs12_dlrow9,<cs12_dlrow9
  .byte $07,>cs12_dlrow10,<cs12_dlrow10
  .byte $07,>cs12_dlrow11,<cs12_dlrow11
  .byte $07,>cs12_dlrow12,<cs12_dlrow12
  .byte $07,>cs12_dlrow13,<cs12_dlrow13
  .byte $07,>cs12_dlrow14,<cs12_dlrow14
  .byte $07,>cs12_dlrow15,<cs12_dlrow15
  .byte $0F,>cs12_dlnone,<cs12_dlnone
  .byte $0B,>cs12_dlnone,<cs12_dlnone
  .byte $C3,>cs12_dlnone,<cs12_dlnone
  .byte $CF,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
cs12_head5_0 .byte 58,30,26,60,50,56,20,10
cs12_headlen5_0 = 8
cs12_head5_1 .byte 32,56,50,72,30,48,20,58,60,56,22,38,60
cs12_headlen5_1 = 13
cs12_dll7
  .byte $46,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $40,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlnone,<cs12_dlnone
  .byte $0F,>$1C00,<$1C00
  .byte $0F,>$1C20,<$1C20
  .byte $0F,>$1C40,<$1C40
  .byte $03,>cs12_dlnone,<cs12_dlnone
  .byte $05,>cs12_dlstripe,<cs12_dlstripe
  .byte $81,>cs12_dlnone,<cs12_dlnone
  .byte $07,>cs12_dlrow0,<cs12_dlrow0
  .byte $07,>cs12_dlrow1,<cs12_dlrow1
  .byte $07,>cs12_dlrow2,<cs12_dlrow2
  .byte $07,>cs12_dlrow3,<cs12_dlrow3
  .byte $07,>cs12_dlrow4,<cs12_dlrow4
  .byte $07,>cs12_dlrow5,<cs12_dlrow5
  .byte $07,>cs12_dlrow6,<cs12_dlrow6
  .byte $07,>cs12_dlrow7,<cs12_dlrow7
  .byte $07,>cs12_dlrow8,<cs12_dlrow8
  .byte $07,>cs12_dlrow9,<cs12_dlrow9
  .byte $07,>cs12_dlrow10,<cs12_dlrow10
  .byte $07,>cs12_dlrow11,<cs12_dlrow11
  .byte $07,>cs12_dlrow12,<cs12_dlrow12
  .byte $07,>cs12_dlrow13,<cs12_dlrow13
  .byte $07,>cs12_dlrow14,<cs12_dlrow14
  .byte $07,>cs12_dlrow15,<cs12_dlrow15
  .byte $0F,>cs12_dlnone,<cs12_dlnone
  .byte $0B,>cs12_dlnone,<cs12_dlnone
  .byte $C3,>cs12_dlnone,<cs12_dlnone
  .byte $CF,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
  .byte $4F,>cs12_dlnone,<cs12_dlnone
cs12_head7_0 .byte 58,30,26,60,50,56,20,14
cs12_headlen7_0 = 8
cs12_head7_1 .byte 60,56,22,48,54,62,38,44,38,60,70
cs12_headlen7_1 = 11
cs12_por0pal .byte $01,$3B,$CA,$01,$02,$3B
cs12_por0z0 .byte <(cut_thorne0+0),30,>(cut_thorne0+0),8,<(cut_thorne0+2),30,>(cut_thorne0+2),16,<(cut_thorne0+4),30,>(cut_thorne0+4),24,<(cut_thorne0+6),30,>(cut_thorne0+6),32
cs12_por0z1 .byte <(cut_thorne1+0),30,>(cut_thorne1+0),8,<(cut_thorne1+2),30,>(cut_thorne1+2),16,<(cut_thorne1+4),30,>(cut_thorne1+4),24,<(cut_thorne1+6),30,>(cut_thorne1+6),32
cs12_por0z2 .byte <(cut_thorne2+0),62,>(cut_thorne2+0),8,<(cut_thorne2+2),62,>(cut_thorne2+2),16,<(cut_thorne2+4),62,>(cut_thorne2+4),24,<(cut_thorne2+6),62,>(cut_thorne2+6),32
cs12_por1pal .byte $36,$3C,$EC,$02,$36,$3C
cs12_por1z0 .byte <(cut_maya0+0),30,>(cut_maya0+0),8,<(cut_maya0+2),30,>(cut_maya0+2),16,<(cut_maya0+4),30,>(cut_maya0+4),24,<(cut_maya0+6),30,>(cut_maya0+6),32
cs12_por1z1 .byte <(cut_maya1+0),30,>(cut_maya1+0),8,<(cut_maya1+2),62,>(cut_maya1+2),16,<(cut_maya1+4),62,>(cut_maya1+4),24,<(cut_maya1+6),30,>(cut_maya1+6),32
cs12_por1z2 .byte <(cut_maya2+0),62,>(cut_maya2+0),8,<(cut_maya2+2),62,>(cut_maya2+2),16,<(cut_maya2+4),62,>(cut_maya2+4),24,<(cut_maya2+6),62,>(cut_maya2+6),32
cs12_por2pal .byte $33,$E0,$FA,$00,$00,$00
cs12_por2z0 .byte <(cut_gamma0+0),30,>(cut_gamma0+0),8,<(cut_gamma0+2),30,>(cut_gamma0+2),16,<(cut_gamma0+4),30,>(cut_gamma0+4),24,<(cut_gamma0+6),30,>(cut_gamma0+6),32
cs12_por2z1 .byte <(cut_gamma1+0),30,>(cut_gamma1+0),8,<(cut_gamma1+2),30,>(cut_gamma1+2),16,<(cut_gamma1+4),30,>(cut_gamma1+4),24,<(cut_gamma1+6),30,>(cut_gamma1+6),32
cs12_por2z2 .byte <(cut_gamma2+0),30,>(cut_gamma2+0),8,<(cut_gamma2+2),30,>(cut_gamma2+2),16,<(cut_gamma2+4),30,>(cut_gamma2+4),24,<(cut_gamma2+6),30,>(cut_gamma2+6),32
cs12_porlo .byte <cs12_por0z0,<cs12_por1z0,<cs12_por2z0
cs12_porhi .byte >cs12_por0z0,>cs12_por1z0,>cs12_por2z0
cs12_porpal_lo .byte <cs12_por0pal,<cs12_por1pal,<cs12_por2pal
cs12_porpal_hi .byte >cs12_por0pal,>cs12_por1pal,>cs12_por2pal
cs12_scenes .byte 2,3,4,5,7
cs12_kind .byte 1,1,1,1,1
cs12_pagelo .byte <cs12_text2,<cs12_text3,<cs12_text4,<cs12_text5,<cs12_text7
cs12_pagehi .byte >cs12_text2,>cs12_text3,>cs12_text4,>cs12_text5,>cs12_text7
cs12_dlllo .byte <cs12_dll2,<cs12_dll3,<cs12_dll4,<cs12_dll5,<cs12_dll7
cs12_dllhi .byte >cs12_dll2,>cs12_dll3,>cs12_dll4,>cs12_dll5,>cs12_dll7
cs12_pallo .byte <cs12_pal2,<cs12_pal3,<cs12_pal4,<cs12_pal5,<cs12_pal7
cs12_palhi .byte >cs12_pal2,>cs12_pal3,>cs12_pal4,>cs12_pal5,>cs12_pal7
cs12_h0lo .byte <cs12_head2_0,<cs12_head3_0,<cs12_head4_0,<cs12_head5_0,<cs12_head7_0
cs12_h0hi .byte >cs12_head2_0,>cs12_head3_0,>cs12_head4_0,>cs12_head5_0,>cs12_head7_0
cs12_h0w .byte (-cs12_headlen2_0)&31,(-cs12_headlen3_0)&31,(-cs12_headlen4_0)&31,(-cs12_headlen5_0)&31,(-cs12_headlen7_0)&31
cs12_h1lo .byte <cs12_head2_1,<cs12_head3_1,<cs12_head4_1,<cs12_head5_1,<cs12_head7_1
cs12_h1hi .byte >cs12_head2_1,>cs12_head3_1,>cs12_head4_1,>cs12_head5_1,>cs12_head7_1
cs12_h1w .byte (-cs12_headlen2_1)&31,(-cs12_headlen3_1)&31,(-cs12_headlen4_1)&31,(-cs12_headlen5_1)&31,(-cs12_headlen7_1)&31
cs12_hstitle .byte 30,18,15,0,17,11,23,23,11,0,16,25,28,13,15,0,45,45,0,30,25,26,0,26,19,22,25,30,29,$FF ; THE GAMMA FORCE // TOP PILOTS
cs12_hsnew .byte 24,15,33,0,18,19,17,18,0,29,13,25,28,15,39,$FF ; NEW HIGH SCORE!
cs12_hshelp1 .byte 31,26,0,11,24,14,0,14,25,33,24,0,13,18,25,25,29,15,0,11,0,22,15,30,30,15,28,38,$FF ; UP AND DOWN CHOOSE A LETTER,
cs12_hshelp2 .byte 16,19,28,15,0,30,11,21,15,29,0,19,30,37,$FF ; FIRE TAKES IT.
cs12_hshead .byte 36,38,34,36,20,58,26,50,56,30,58
cs12_hsheadw = (-11)&31
cs12_hsheadx = 36
cs12_hsmode0 .byte 30,68,52,30,56,60
cs12_hsmode1 .byte 48,50,56,46,22,44
cs12_hsmode2 .byte 60,30,28,28,70,20,24,30,22,56
cs12_hsmodelo .byte <cs12_hsmode0,<cs12_hsmode1,<cs12_hsmode2
cs12_hsmodehi .byte >cs12_hsmode0,>cs12_hsmode1,>cs12_hsmode2
cs12_hsmodew .byte (-6)&31,(-6)&31,(-10)&31
cs12_hsmodex .byte 56,56,40
cs12_hsdefs .byte $01,$00,$00,$00,$80,$00,$00,$60,$00,$00,$40,$00,$00,$20,$00
cs12_hsdefi .byte 12,0,24,13,0,19,4,3,2,18,14,11,6,5,23
cs12_hsglyph .byte 11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,0
cs12_text2
  .byte 0,14,28,37,0,30,18,25,28,24,15,0,45,45,0,29,15,13,30,25,28,0,3,0
  .byte 18,11,36,11,28,14,0,11,22,15,28,30,64,17,25,25,14,0,16,22,35,19,24,17
  .byte 38,0,23,11,35,11,37,0,30,18,15,0,16,25,28,30,28,15,29,29,0,19,29,64
  .byte 14,25,33,24,37,64,64,35,25,31,28,0,28,25,31,30,15,0,28,31,24,29,0,30
  .byte 18,28,25,31,17,18,0,30,18,15,0,24,15,25,24,64,29,26,19,28,15,29,37,0
  .byte 30,18,15,19,28,0,30,25,33,15,28,29,0,11,28,15,64,19,24,14,15,29,30,28
  .byte 31,13,30,19,12,22,15,44,0,30,18,15,35,0,29,30,25,26,0,35,25,31,28,64
  .byte 29,18,25,30,29,38,0,30,18,15,35,0,29,18,25,32,15,0,35,25,31,28,0,29
  .byte 18,19,26,38,0,11,24,14,64,30,18,15,35,0,33,19,22,22,0,13,28,31,29,18
  .byte 0,35,25,31,0,11,17,11,19,24,29,30,0,30,18,15,64,12,25,30,30,25,23,0
  .byte 25,16,0,30,18,15,0,29,13,28,15,15,24,37,64,64,33,15,11,32,15,0,11,28
  .byte 25,31,24,14,0,30,18,15,23,38,0,11,24,14,0,30,11,21,15,0,30,18,15,64
  .byte 30,11,24,21,29,0,19,24,0,30,18,15,0,29,30,28,15,15,30,29,37,65
  .byte 0,14,28,37,0,30,18,25,28,24,15,0,45,45,0,29,15,13,30,25,28,0,3,0
  .byte 18,11,36,11,28,14,0,11,22,15,28,30,64,30,18,15,0,29,26,19,28,15,0,33
  .byte 11,28,14,15,24,0,17,31,11,28,14,29,0,30,18,15,0,13,19,30,35,37,64,19
  .byte 30,29,0,15,35,15,0,29,30,11,35,29,0,29,18,31,30,0,33,18,19,22,15,0
  .byte 19,30,29,0,26,25,14,29,64,13,19,28,13,22,15,0,19,30,37,0,12,28,15,11
  .byte 21,0,15,32,15,28,35,0,26,25,14,0,16,19,28,29,30,37,65
  .byte 1,13,11,26,30,37,0,32,11,24,13,15,0,45,45,0,17,11,23,23,11,43,2,64
  .byte 13,25,26,35,0,30,18,11,30,38,0,24,11,30,18,11,24,37,0,30,18,28,15,11
  .byte 14,19,24,17,0,30,18,15,64,29,26,19,28,15,29,37,66
cs12_text3
  .byte 0,14,28,37,0,30,18,25,28,24,15,0,45,45,0,29,15,13,30,25,28,0,4,0
  .byte 18,11,36,11,28,14,0,11,22,15,28,30,64,30,18,15,0,16,19,17,18,30,0,23
  .byte 25,32,15,29,0,25,31,30,0,30,25,0,29,15,11,37,0,11,28,23,25,28,15,14
  .byte 64,17,31,24,12,25,11,30,29,0,18,25,22,14,0,30,18,15,0,13,18,11,24,24
  .byte 15,22,29,0,12,15,30,33,15,15,24,64,30,18,15,0,19,29,22,11,24,14,29,38
  .byte 0,11,24,14,0,30,18,15,35,0,29,26,28,11,35,0,16,11,24,29,0,11,24,14
  .byte 64,28,19,24,17,29,0,25,16,0,16,19,28,15,37,64,64,11,24,14,0,29,25,24
  .byte 11,28,0,29,11,35,29,0,29,25,23,15,30,18,19,24,17,0,18,31,17,15,0,19
  .byte 29,64,13,25,23,19,24,17,0,31,26,0,12,15,18,19,24,14,0,30,18,15,23,44
  .byte 0,30,18,15,64,22,15,32,19,11,30,18,11,24,38,0,11,0,12,11,30,30,22,15
  .byte 29,18,19,26,0,22,25,24,17,15,28,0,30,18,11,24,64,35,25,31,28,0,29,13
  .byte 28,15,15,24,37,65
  .byte 1,13,11,26,30,37,0,32,11,24,13,15,0,45,45,0,17,11,23,23,11,43,2,64
  .byte 17,31,24,12,25,11,30,29,0,19,24,0,23,35,0,29,19,17,18,30,29,37,0,29
  .byte 33,25,28,14,0,28,15,11,14,35,37,64,17,25,19,24,17,0,19,24,39,66
cs12_text4
  .byte 0,14,28,37,0,30,18,25,28,24,15,0,45,45,0,29,15,13,30,25,28,0,5,0
  .byte 18,11,36,11,28,14,0,11,22,15,28,30,64,29,13,25,28,13,18,15,14,0,29,11
  .byte 24,14,29,0,11,18,15,11,14,37,0,11,28,23,25,28,15,14,0,30,28,11,19,24
  .byte 29,64,28,31,24,0,30,18,15,0,14,15,29,15,28,30,0,28,11,19,22,33,11,35
  .byte 38,0,15,32,15,28,35,0,13,11,28,64,18,15,11,32,35,0,33,19,30,18,0,11
  .byte 28,23,25,28,0,11,24,14,0,17,31,24,29,37,64,64,11,24,14,0,33,11,30,13
  .byte 18,0,30,18,15,0,29,11,24,14,0,19,30,29,15,22,16,38,0,23,11,35,11,37
  .byte 0,30,18,15,64,29,15,19,29,23,19,13,0,28,15,11,14,19,24,17,29,0,11,28
  .byte 15,0,33,28,25,24,17,37,64,29,25,23,15,30,18,19,24,17,0,15,24,25,28,23
  .byte 25,31,29,0,19,29,0,23,25,32,19,24,17,0,31,24,14,15,28,64,30,18,15,0
  .byte 14,31,24,15,29,37,65
  .byte 1,13,11,26,30,37,0,32,11,24,13,15,0,45,45,0,17,11,23,23,11,43,2,64
  .byte 19,0,29,15,15,0,30,18,15,0,30,28,11,13,21,29,37,0,19,24,30,15,28,13
  .byte 15,26,30,19,24,17,0,30,18,15,64,30,28,11,19,24,39,66
cs12_text5
  .byte 0,14,28,37,0,30,18,25,28,24,15,0,45,45,0,29,15,13,30,25,28,0,6,0
  .byte 18,11,36,11,28,14,0,11,22,15,28,30,64,11,0,26,25,22,11,28,0,29,30,25
  .byte 28,23,0,18,11,29,0,30,18,15,0,16,28,25,36,15,24,0,29,30,28,11,19,30
  .byte 37,64,12,22,19,36,36,11,28,14,0,33,19,24,14,29,0,33,19,22,22,0,26,31
  .byte 29,18,0,35,25,31,28,0,29,18,19,26,64,25,16,16,0,13,25,31,28,29,15,38
  .byte 0,11,24,14,0,29,22,11,12,29,0,25,16,0,19,13,15,0,11,28,15,64,16,11
  .byte 22,22,19,24,17,0,16,28,25,23,0,30,18,15,0,29,18,15,22,32,15,29,37,64
  .byte 64,19,13,15,12,15,28,17,29,0,12,22,25,13,21,0,35,25,31,28,0,16,19,28
  .byte 15,37,0,30,18,15,64,17,22,11,13,19,15,28,0,13,28,11,33,22,15,28,0,19
  .byte 29,0,17,28,19,24,14,19,24,17,0,11,13,28,25,29,29,64,30,18,15,0,26,11
  .byte 13,21,0,19,13,15,44,0,29,30,25,26,0,19,30,37,65
  .byte 1,13,11,26,30,37,0,32,11,24,13,15,0,45,45,0,17,11,23,23,11,43,2,64
  .byte 13,11,24,25,26,35,0,18,15,11,30,19,24,17,0,25,24,37,0,16,19,17,18,30
  .byte 19,24,17,0,30,18,15,64,33,19,24,14,37,66
cs12_text7
  .byte 0,14,28,37,0,30,18,25,28,24,15,0,45,45,0,29,15,13,30,25,28,0,8,0
  .byte 18,11,36,11,28,14,0,11,22,15,28,30,64,35,25,31,41,28,15,0,25,32,15,28
  .byte 0,30,18,15,0,23,25,25,24,38,0,23,11,35,11,38,0,12,31,30,64,33,11,30
  .byte 13,18,0,35,25,31,28,0,12,11,13,21,39,64,64,22,31,24,11,28,0,28,11,19
  .byte 22,0,12,11,29,15,29,0,16,19,28,15,0,13,11,28,17,25,64,13,11,24,19,29
  .byte 30,15,28,29,0,31,26,0,16,28,25,23,0,12,15,18,19,24,14,0,35,25,31,37
  .byte 0,22,19,29,30,15,24,64,16,25,28,0,30,18,15,0,18,19,29,29,38,0,11,24
  .byte 14,0,33,11,30,13,18,0,16,25,28,0,30,18,15,0,28,15,14,64,11,24,14,0
  .byte 35,15,22,22,25,33,0,12,22,19,24,21,0,11,30,0,30,18,15,0,12,25,30,30
  .byte 25,23,0,25,16,64,30,18,15,0,29,13,28,15,15,24,37,0,30,18,15,24,0,23
  .byte 25,32,15,37,64,64,30,18,15,0,23,11,29,29,0,14,28,19,32,15,28,0,19,29
  .byte 0,30,18,15,19,28,0,17,31,24,44,0,11,0,28,11,19,22,64,13,11,24,24,25
  .byte 24,0,30,18,15,0,29,19,36,15,0,25,16,0,11,0,13,19,30,35,37,65
  .byte 1,13,11,26,30,37,0,32,11,24,13,15,0,45,45,0,17,11,23,23,11,43,2,64
  .byte 15,35,15,29,0,25,24,0,23,35,0,29,19,34,37,0,31,24,14,15,28,29,30,25
  .byte 25,14,37,66
