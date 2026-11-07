; ===========================================================================
; Gamma Force display engine: smooth vertical scrolling for 7800basic.
; See docs/ENGINE.md for the full picture. In short:
;
;   zone 0       HUD, 16 lines, never scrolls (7800basic manages it)
;   zones 1-13   the playfield. Each zone's display list (DL) is one of 14
;                ring buffers; each holds one map row's background (character
;                objects) followed by that frame's sprites.
;   zone 14      the bottom of the playfield: a pair of DLs used alternately,
;                its row drawn as one direct-mode object per tile.
;
; Fine scroll: zone 1 is cut to 16-s lines (s = 0..15) and zone 14 is 1+s
; lines, so the playfield is always 209 lines. MARIA always draws a zone's
; lines counting down to 0, which is right for zone 1 (it shows the bottom
; of its row) but zone 14 must show the *top* of its row, so every object
; in zone 14 points its graphics 15-s pages higher. That is why zone 14
; uses direct-mode tiles: each object carries its own graphics address,
; where character objects would all share CHARBASE.
;
; Coarse scroll: every 16 pixels the zones move down one row. Zone 1 takes
; the spare ring buffer (filled with the next row ahead of time), zone 13's
; buffer becomes the new spare, and zone 14 rebuilds its tiles for the row
; that just left zone 13.
;
; Frame order (from BASIC):
;   pf_frame       advance the scroll, rotate if needed, reset the zones
;   pf_drawimg ... plot sprites (playfield coordinates, y + 32)
;   pf_drawscreen  replaces drawscreen: terminates the DLs, then writes
;                  the new zone layout into the DLL during vblank
; ===========================================================================

; ---- zero page: 7800basic's music tracker block (we never use playsong) --
pfs         = $A5   ; fine scroll s (0-15) for the frame being built
pfshift     = $A6   ; 15-s, the page shift for zone 14
pfp         = $A7   ; pointer, 2 bytes
pfq         = $A9   ; pointer, 2 bytes
sp_lo       = $AB   ; pf_plot arguments: graphics address,
sp_hi       = $AC
sp_pw       = $AD   ;   palette<<5 | (-width & 31),
sp_x        = $AE   ;   x,
sp_y        = $AF   ;   playfield y + 32
pft1        = $B0   ; scratch
pft2        = $B1
pft3        = $B2
pft4        = $B3
pfhead      = $B4   ; ring buffer shown in zone 1
sp_h        = $C4   ; pf_plot argument: lines used in the strip (1-16)
pft5        = $C5   ; pf_object's scratch

; ---- RAM: $2200-$223F belongs to the engine --------------------------------
zonelo      = $2200 ; [15] DL address of zone k, k = 1..14
zonehi      = $2210 ; [15]
bgsize      = $2220 ; [14] background bytes at the start of ring buffer i
spos_f      = $2230 ; scroll position in pixels, 16.8 fixed point
spos_lo     = $2231
spos_hi     = $2232
pfspeed     = $2233 ; scroll speed, 1/256 pixel per frame
pfsparedirty = $2234 ; nonzero: the spare buffer needs the next row
pfnextrow   = $2235 ; map row the spare buffer gets next
pfrow14     = $2236 ; map row shown in zone 14
pfz14back   = $2237 ; zone 14 buffer (0/1) being built this frame
pfz14row    = $2238 ; [2] row each zone 14 buffer holds ($FF: none)
pfz14bg     = $223A ; [2] background bytes in each zone 14 buffer
pfstartrow  = $223C ; map row pf_reset starts at (0 = the beginning)
zonebuf     = $2290 ; [15] which DL buffer zone k uses (0-13 ring, 14-15 zone 14)
oldend      = $22A0 ; [16] each buffer's object count as last terminated
zoneold     = $22B0 ; [15] oldend of the buffer each zone uses this frame
pfframe     = $22C0 ; framecounter when this frame's logic started
pflate      = $22C1 ; nonzero: the last frame's logic ran past its frame, so
                    ; this one shows two game steps (see pf_drawscreen)
pfnodraw    = $22C2 ; nonzero: pf_plot draws nothing (a catch-up step)
pfdraws     = $22C3 ; counts frames drawn (for things that alternate as shown)
pfvbl       = $22C4 ; counts overscan NMIs (one a frame, just before vblank)
pfvbl0      = $22C5 ; pfvbl when this frame began
cutvec      = $22DE ; [2] a cutscene's stripe NMI handler (hi 0: none; gammaforce.bas)
cutvec2     = $22CE ; [2] its end-of-screen one
; a cutscene's own (tools/gen_cutscenes.py; the stage's clocks' bytes: a
; cutscene plays between stages)
cs_idx      = $22E0 ; which of its bank's scenes
cs_state    = $22E1 ; 0 typing, 1 a page done, 2 the last page done
cs_row      = $22E2
cs_col      = $22E3
cs_prev     = $22E4 ; the buttons last frame
cs_bg       = $22E5 ; the picture's background color
cs_por      = $22E6 ; the page's portrait
; the high score screen's (gen_cutscenes.py HISCORES)
hs_mode     = $22E8 ; 0 the table, 1 a new score; then counting its time
hs_pos      = $22E9 ; the new score's place ($FF: none, or entered)
hs_cur      = $22EA ; the initial being entered (0-2)
hs_t        = $22EB
hs_rep      = $22EC ; the stick's repeat
hs_fire     = $22ED
hs_x        = $22EE
hs_y        = $22EF
hs_c        = $22F0
hs_b0       = $22F1 ; [3] the new score
hs_b1       = $22F2
hs_b2       = $22F3
hs_x3       = $22F4
titleidle   = $22F5 ; the title's time with nothing pressed (title.bas)
hs_d        = $22F6 ; the table shown (the difficulty, 0-2)
; the jukebox's (gammaforce.bas jukebox)
jb_track    = $22F7 ; the track chosen (0 - JB_N-1)
jb_play     = $22F8 ; nonzero while it plays
jb_stk      = $22F9 ; the stick's left and right last frame (pressed: set)
jb_prev     = $22FA ; the buttons last frame
hudtext     = $2240 ; [20] HUD characters, shown live in zone 0
txtold      = $2560 ; [16] where each buffer's text was as last terminated ($FF: none)
txtnow      = $2570 ; [15] where each zone's text is this frame ($FF: none)

RINGN       = 14
RINGBASE    = $1900
BUFSIZE     = 108
PFCAP       = BUFSIZE-6     ; room for one more 4-byte object + terminator
Z14BASE     = RINGBASE+RINGN*BUFSIZE ; $1EE8
Z14SIZE     = 140
Z14BG       = 80            ; 20 tiles x 4 bytes
Z14CAP      = Z14SIZE-6
DLLZONE1    = DLLMEM+18     ; 3 blank entries + the HUD's three (pf_init)
DLLNONVIS   = DLLZONE1+42   ; 14 playfield entries later

; 7800basic's DLL table always names zones 1-11, even with ZONECOUNT = 1.
; Point them at ring buffers; pf_init rewrites the DLL anyway.
ZONE1ADDRESS  = RINGBASE+0*BUFSIZE
ZONE2ADDRESS  = RINGBASE+1*BUFSIZE
ZONE3ADDRESS  = RINGBASE+2*BUFSIZE
ZONE4ADDRESS  = RINGBASE+3*BUFSIZE
ZONE5ADDRESS  = RINGBASE+4*BUFSIZE
ZONE6ADDRESS  = RINGBASE+5*BUFSIZE
ZONE7ADDRESS  = RINGBASE+6*BUFSIZE
ZONE8ADDRESS  = RINGBASE+7*BUFSIZE
ZONE9ADDRESS  = RINGBASE+8*BUFSIZE
ZONE10ADDRESS = RINGBASE+9*BUFSIZE
ZONE11ADDRESS = RINGBASE+10*BUFSIZE

     if Z14BASE+2*Z14SIZE > $2000
         echo "ERROR: engine DL buffers overflow $1FFF"
         err
     endif

; ---------------------------------------------------------------------------
; pf_init: palettes, HUD, the first screen of map rows, and the DLL.
; Call once, after "characterset charset".
pf_init
     jsr pf_palettes

     ; HUD: one 20-character object in zone 0, reading hudtext live.
     ldx #19
pf_init_hud
     lda hudinit,x
     sta hudtext,x
     dex
     bpl pf_init_hud
     ldx #4
pf_init_hudobj
     lda pfhudobj,x
     sta ZONE0ADDRESS,x
     dex
     bpl pf_init_hudobj
     lda #5
     sta dlend
     sta dlendsave

     ; The DLL. 7800basic built 3 blank entries, the HUD (zone 0), some
     ; zone entries we replace, and then 5 non-visible entries carrying its
     ; NMIs. Move those 5 down past our 14 playfield entries (copying from
     ; the end, since they move up in memory). pf_reset fills the playfield.
     jsr waitforvblankstart
     ldx #14
pf_init_dll
     lda DLLMEM+[DLLLUTNONVISSTART-DLLLUT],x
     sta DLLNONVIS,x
     dex
     bpl pf_init_dll
     ; The HUD: 7800basic's 16-line zone 0 becomes 3 empty lines, a
     ; 7-line zone 0 (its DL: the HUD's text and sprites) and 6 empty lines:
     ; MARIA reads the HUD's objects 7 lines a frame, not 16. The font's
     ; glyphs (and the HUD's sprites) are on the last 7 lines of their 16,
     ; which a 7-line zone shows. The NMI stays 16 lines down, where it was.
     ldx #8
pf_init_hud2
     lda pfhuddll,x
     sta DLLMEM+9,x
     dex
     bpl pf_init_hud2
     ; The playfield is 209 lines (16-s + 12*16 + 1+s), one more than 13
     ; zones, so take a line off the top border to keep the frame length.
     dec DLLMEM
     lda #(DLLNONVIS-DLLMEM)
     sta overscanDLLstart
     lda #0
     sta pfspeed
     sta pfstartrow
     sta pfnodraw
     sta pflate

; ---------------------------------------------------------------------------
; pf_reset: back to the start of the map (keeps pfspeed).
pf_reset
     ; Scroll state, starting with map row pfstartrow (R) in zone 14. Zone
     ; k (1-13) shows row R+14-k; rows R+1..R+14 go into ring buffers 0-13
     ; in order, so zone 1 has buffer 12 and the spare (row R+14) is 13.
     lda #0
     sta spos_f
     sta pfsparedirty
     sta pfz14back
     lda pfstartrow
     sta pfrow14
     sta spos_lo             ; spos = R * 16
     lda #0
     sta spos_hi
     ldx #4
pf_reset_x16
     asl spos_lo
     rol spos_hi
     dex
     bne pf_reset_x16
     lda #$FF
     sta pfz14row
     sta pfz14row+1
     ldx #0
pf_init_rows
     stx pft4
     txa
     sec                     ; row R + buffer + 1
     adc pfstartrow
     tay
     jsr pf_buildrow
     ldx pft4
     inx
     cpx #RINGN
     bne pf_init_rows
     lda pfstartrow
     clc
     adc #15
     sta pfnextrow
     lda #12
     sta pfhead
     jsr pf_mapzones
     lda #15
     sta pfs
     lda #0
     sta pfshift
     jsr pf_zone14
     jsr pf_restore
     jsr waitforvblankstart
     jsr pf_terminate
     jmp pf_commit

pfhudobj
     ; lo, mode ($60 = 5-byte header, character mode), hi, palette 3 | 20 wide, x
     .byte <hudtext, $60, >hudtext, (3<<5)|((-20)&31), 0
pfhuddll
     .byte 2, >pfnodl, <pfnodl             ; 3 lines, an empty DL
     .byte 6, >ZONE0ADDRESS, <ZONE0ADDRESS ; 7 lines, the HUD
     .byte $80|5, >pfnodl, <pfnodl         ; 6 lines, empty; NMI
pfnodl
     .byte 0, 0

; ---------------------------------------------------------------------------
; pf_buildrow: copy map row Y's background objects into ring buffer X.
pf_buildrow
     tya
     sta ringrow,x
     lda stg_rowshift,y
     jsr pf_rowshift
     lda stg_rowlo,y
     sta pfp
     lda stg_rowhi,y
     sta pfp+1
     lda ringlo,x
     sta pfq
     lda ringhi,x
     sta pfq+1
     lda #$FF
     sta txtold,x            ; a new row: no text
     ldy #0
     lda (pfp),y             ; byte count
     sta bgsize,x
     tay
     beq pf_buildrow_done
pf_buildrow_copy
     lda (pfp),y             ; source bytes 1..n go to 0..n-1
     dey
     sta (pfq),y
     bne pf_buildrow_copy
     ; then move the objects by the row's shift (each object's x is its
     ; fifth byte)
     ldy #4
pf_buildrow_x
     tya
     cmp bgsize,x
     bcs pf_buildrow_done
     lda (pfq),y
     jsr pf_shiftx
     sta (pfq),y
     tya
     clc
     adc #5
     tay
     bne pf_buildrow_x
pf_buildrow_done
     rts

; pf_rowshift: A = a row's shift byte (stg_rowshift): high nibble, a signed
; whole-row shift in tiles; low nibble, a gap in tiles opened at the
; city's middle (x 80: everything right of it moves on by the gap, so the
; city splits). -> pft2 = the shift in pixels, pft5 = the gap in pixels.
pf_rowshift
     pha
     and #$0F
     asl
     asl
     asl
     sta pft5
     pla
     and #$F0
     cmp #$80                ; (the sign into carry)
     ror                     ; nibble * 16 / 2 = nibble * 8, signed
     cpy pfswayrow           ; (Y: the row) a swaying row: plus the sway
     bcc pf_rowshift_still
     cpy pfswayend
     bcs pf_rowshift_still
     clc
     adc pfsway
pf_rowshift_still
     sta pft2
     rts

; pf_shiftx: A = an x before the shift -> A = x after it.
pf_shiftx
     cmp #80
     bcc pf_shiftx_left
     clc
     adc pft5
pf_shiftx_left
     clc
     adc pft2
     rts

; ---------------------------------------------------------------------------
; pf_mapzones: zone k (1..13) gets ring buffer head-(k-1), mod 14.
pf_mapzones
     ldy pfhead
     ldx #1
pf_mapzones_loop
     lda ringlo,y
     sta zonelo,x
     lda ringhi,y
     sta zonehi,x
     lda bgsize,y
     sta dlendsave,x
     tya
     sta zonebuf,x
     dey
     bpl pf_mapzones_next
     ldy #RINGN-1
pf_mapzones_next
     inx
     cpx #14
     bne pf_mapzones_loop
     rts

; pf_restore: every playfield zone back to just its background.
pf_restore
     ldx #14
pf_restore_loop
     lda dlendsave,x
     sta dlend,x
     lda #$FF
     sta txtnow,x
     dex
     bne pf_restore_loop
     rts

; ---------------------------------------------------------------------------
; pf_zone14: get this frame's zone 14 buffer ready: its tiles for the row
; (rebuilt if it holds another row) pointing 15-s pages up.
pf_zone14
     ldx pfz14back
     txa
     ora #14
     sta zonebuf+14
     lda z14lo,x
     sta pfq
     sta zonelo+14
     lda z14hi,x
     sta pfq+1
     sta zonehi+14
     lda pfz14row,x
     cmp pfrow14
     bne pf_zone14_new
     jmp pf_zone14_hi
pf_zone14_new
     lda pfrow14
     sta pfz14row,x
     tay
     lda stg_rowshift,y
     jsr pf_rowshift
     lda stg_rowlo,y
     sta pfp
     lda stg_rowhi,y
     sta pfp+1
     ; One direct-mode object per tile of the row's background objects (the
     ; runs of tiles that aren't background: open sea, say): lo = character,
     ; palette|width, hi, x. Each run object is lo, hi = its characters,
     ; palette|width, x; its tiles are 8 pixels apart.
     ldy #0
     lda (pfp),y
     sta pft4                ; the row's object bytes
     lda #0
     sta pft3                ; output offset
     ldy #1
pf_zone14_obj
     sty sp_y                ; this object's offset
     lda pft4
     cmp sp_y
     bcc pf_zone14_end       ; past the last
     lda (pfp),y
     sta sp_lo               ; its characters
     iny
     iny
     lda (pfp),y
     sta sp_hi
     iny
     lda (pfp),y             ; palette | -width & 31
     pha
     and #$E0
     ora #(-2)&31            ; a tile: 2 bytes wide
     sta sp_pw
     pla
     eor #$FF                ; width = -(pw & 31) & 31
     clc
     adc #1
     and #31
     sta sp_h
     iny
     lda (pfp),y
     jsr pf_shiftx
     sta sp_x
     iny
     sty sp_y
     ldy #0
pf_zone14_tile
     sty pft1
     lda (sp_lo),y           ; the character
     ldy pft3
     sta (pfq),y
     iny
     lda sp_pw
     sta (pfq),y
     iny
     iny                     ; hi is set below, every frame
     lda sp_x
     sta (pfq),y
     clc
     adc #8
     sta sp_x
     iny
     sty pft3
     ldy pft1
     iny
     cpy sp_h
     bcc pf_zone14_tile
     ldy sp_y
     jmp pf_zone14_obj
pf_zone14_end
     ldx pfz14back
     lda pft3
     sta pfz14bg,x
pf_zone14_hi
     ldx pfz14back
     lda pfz14bg,x
     sta dlendsave+14
     beq pf_zone14_done      ; all sea
     sta pft3
     lda stg_charbase
     clc
     adc pfshift
     ldy #2
pf_zone14_hiloop
     sta (pfq),y
     iny
     iny
     iny
     iny
     cpy pft3
     bcc pf_zone14_hiloop
pf_zone14_done
     rts

z14lo .byte <Z14BASE, <(Z14BASE+Z14SIZE)
z14hi .byte >Z14BASE, >(Z14BASE+Z14SIZE)

; ---------------------------------------------------------------------------
; pf_frame: start a frame. Fills the spare buffer if a coarse step used it
; up, advances the scroll by pfspeed, rotates the zones on a 16 pixel
; boundary, readies zone 14, and empties the zones of last frame's sprites.
pf_frame
     lda framecounter
     sta pfframe
     lda pfsparedirty
     beq pf_frame_scroll
     ldx pfhead              ; spare = head + 1, mod 14
     inx
     cpx #RINGN
     bcc pf_frame_spare
     ldx #0
pf_frame_spare
     ldy pfnextrow
     jsr pf_buildrow
     lda pfnextrow
     jsr pf_nextrow
     sta pfnextrow
     lda #0
     sta pfsparedirty

pf_frame_scroll
     lda spos_lo
     and #$F0
     sta pft1
     ldx pflate              ; two or three game steps this frame: as far again
pf_frame_step
     clc                     ; (under a line a step, so two steps cross at
     lda spos_f              ; most one 16-line boundary)
     adc pfspeed
     sta spos_f
     lda spos_lo
     adc #0
     sta spos_lo
     lda spos_hi
     adc #0
     sta spos_hi
     dex
     bpl pf_frame_step
     lda spos_lo
     and #$F0
     cmp pft1
     beq pf_frame_fine
     ; Crossed a 16 pixel boundary: the spare becomes zone 1.
     ldx pfhead
     inx
     cpx #RINGN
     bcc pf_frame_rot
     ldx #0
pf_frame_rot
     stx pfhead
     lda #1
     sta pfsparedirty
     lda pfrow14
     jsr pf_nextrow
     sta pfrow14
     jsr pf_mapzones
pf_frame_fine
     lda spos_lo             ; s = 15 - (pos & 15)
     and #15
     sta pfshift
     eor #15
     sta pfs
     jsr pf_zone14
     ; each zone's DL as MARIA shows it now (see pf_object)
     ldx #14
pf_frame_old
     ldy zonebuf,x
     lda txtold,y            ; text: objects from it on are appended anew
     cmp #$FF
     bne pf_frame_oldset
     lda oldend,y
pf_frame_oldset
     sta zoneold,x
     dex
     bne pf_frame_old
     jmp pf_restore

; pf_palettes: load all eight palettes, and the stage's background color
; and palettes 0-2 (the title cycles palette 4's hues, so the game reloads
; them when it starts).
pf_palettes
     ldx #0
     ldy #0
pf_palettes_loop
     lda palettedata,x
     sta P0C1,y
     inx
     iny
     tya
     and #3
     cmp #3
     bne pf_palettes_next
     iny                     ; skip the 4th register of each palette group
pf_palettes_next
     cpx #24
     bne pf_palettes_loop
     ; the stage's own background color and palettes 0-2 (and no color
     ; for userinterrupt to set: bgwant)
     lda #0
     sta bgwant
     sta fadeon              ; (stage 6's fade: off until its code sets it)
     lda stg_bg
     sta BACKGRND
     ldx #2
pf_palettes_stage
     lda stg_pal,x
     sta P0C1,x
     lda stg_pal+3,x
     sta P1C1,x
     lda stg_pal+6,x
     sta P2C1,x
     dex
     bpl pf_palettes_stage
     rts

; A = the map row after row A (past the end, loop the boss section).
pf_nextrow
     clc
     adc #1
     cmp stg_rows
     bcc pf_nextrow_done
     sbc stg_loop
pf_nextrow_done
     rts

; pf_newstage: start stage A mid-game: blank the screen (MARIA's DMA off
; until the next pf_drawscreen; the old DLs point into the old bank), then
; pf_stage and pf_reset.
pf_newstage
     pha
     jsr waitforvblankstart
     lda sCTRL
     ora #%01100000          ; DMA off
     sta CTRL
     pla
     jsr pf_stage
     jmp pf_reset

; pf_stage: switch in stage A's bank (1 = bank 2, 2 = bank 3, ...), point
; CHARBASE at its character block and load its palettes. Then pf_reset.
; The music and the sound effects stop first: a song plays from its
; stage's bank, and with another bank in its addresses hold other bytes,
; which can keep the NMI past vblank (the main loop, waiting for vblank,
; then waits for ever), or play noise.
; The caller starts the new stage's song.
pf_stage
     pha
     jsr mus_stop
     pla
; (pf_stage_keep: the same, the music playing on: the title song, which
; banks 2 and 12 hold at the same address)
pf_stage_keep
     pha
     ; and the sound effects: a stage's own sound plays from its bank
     ; (stage 7's canisters), and the new bank holds other bytes there
     lda #0
     sta sfx_ptrhi
     sta sfx_ptrhi+1
     sta AUDV0
     sta AUDV1
     lda #$FF                ; no rows sway
     sta pfswayrow
     pla
     sec
     sbc #1
     sta $8000               ; SuperGame bank select: bank - 2
     lda stg_charbase
     sta sCHARBASE
     jmp pf_palettes

; ---------------------------------------------------------------------------
; pf_drawimg: draw image pimg, frame pframe, at (px, py - 32) in palette
; ppal. py is the playfield y plus 32, so sprites can start above the top.
pf_drawimg
     ldx pimg
     lda imgw,x
     sta pft1
     lda #0
     sec
     sbc pft1
     and #31
     sta pft2
     lda ppal
     asl
     asl
     asl
     asl
     asl
     ora pft2
     sta sp_pw
     lda #0                  ; frame offset = pframe * width
     ldy pframe
     beq pf_drawimg_f1
pf_drawimg_f0
     clc
     adc pft1
     dey
     bne pf_drawimg_f0
pf_drawimg_f1
     sta pft4
     clc
     adc imglo,x
     sta sp_lo
     lda imghi,x
     sta sp_hi
     lda px
     sta sp_x
     lda py
     sta sp_y
     lda imgh,x
     ldy imgstrips,x
     cpy #2
     bcc pf_drawimg_h
     lda #16                 ; the first of two strips is full height
pf_drawimg_h
     sta sp_h
     jsr pf_plot
     ldx pimg
     lda imgstrips,x
     cmp #2
     bcc pf_drawimg_done
     lda imgh,x
     sta sp_h
     lda imglo2,x
     clc
     adc pft4
     sta sp_lo
     lda imghi2,x
     sta sp_hi
     lda py
     clc
     adc #16
     bcs pf_drawimg_done
     sta sp_y
     jmp pf_plot
pf_drawimg_done
     rts

; ---------------------------------------------------------------------------
; pf_plot: one 16-line strip (nothing while pfnodraw is set). sp_lo/sp_hi = graphics, sp_pw = palette and
; width, sp_x, sp_y = playfield y + 32, sp_h = lines the strip uses from
; its top (a strip shorter than 16 lines skips the zone below when it ends
; above it). Clips at the HUD and the bottom.
pf_plot
     lda pfnodraw
     bne pf_plot_out
     clc
     lda sp_y
     adc pfs
     bcs pf_plot_out         ; past line 255: below the playfield
     sbc #15                 ; (carry clear) virtual y = y + s - 16
     bcc pf_plot_out         ; wholly above zone 1
     sta pft1
     and #15
     sta pft2                ; line within the zone
     lda pft1
     lsr
     lsr
     lsr
     lsr
     tax                     ; zone
     beq pf_plot_lower       ; zone 0: the top part would be in the HUD
     cpx #15
     bcs pf_plot_out
     lda sp_hi
     ora pft2                ; upper part: hi + line
     jsr pf_object
pf_plot_lower
     ; A strip that reaches the zone's last line gets a lower part even
     ; when that part is empty (lined up with the zone, its graphics are
     ; all in the DMA holes and cost only the header). The number of
     ; objects then doesn't change as a full strip moves, so later objects
     ; in the zone keep their slots and are updated in place (pf_object).
     lda pft2
     clc
     adc sp_h
     cmp #16
     bcc pf_plot_out         ; ends above the zone's last line
     inx
     cpx #15
     bcs pf_plot_out
     lda sp_hi
     ora pft2
     sec
     sbc #16                 ; lower part: hi + line - 16
     jmp pf_object
pf_plot_out
     rts

; pf_object: add a 4-byte object with graphics high byte A to zone X.
;
; MARIA rereads a DL every line, and this one may be on screen now (the
; frame is built while the last one shows), so the list must be valid after
; every single store:
; - past the end the DL had last frame there is no terminator to stop
;   MARIA running into old bytes, so a terminator goes in first and the
;   palette|width byte, which makes the object exist, goes in last;
; - over one of last frame's objects, the slot is hidden first (x = 160 is
;   off the right edge) and the real x goes in last.
pf_object
     cpx #14
     bne pf_object_ptr
     clc
     adc pfshift             ; zone 14 shows its row's top lines
pf_object_ptr
     sta pft3
     ldy dlend,x
     tya
     cmp zonecap,x
     bcs pf_object_full
     adc #4                  ; (carry clear) the new end
     sta dlend,x
     tya                     ; pfp = the slot itself, so the stores below
     clc                     ; use fixed offsets
     adc zonelo,x
     sta pfp
     lda zonehi,x
     adc #0
     sta pfp+1
     tya
     cmp zoneold,x
     bcc pf_object_over
     ; appending (over last frame's text, possibly: so the list is first
     ; ended at the slot, before anything of the old object changes)
     ldy #1
     lda #0
     sta (pfp),y
     ldy #5
     sta (pfp),y             ; terminator after the new object
     ldy #3
     lda sp_x
     sta (pfp),y
     dey
     lda pft3
     sta (pfp),y
     ldy #0
     lda sp_lo
     sta (pfp),y
     iny
     lda sp_pw
     sta (pfp),y             ; now it exists
     rts
pf_object_over
     ; The same image (low byte and width) as last frame's object here, as
     ; for a part that stays put or moves a line: rewrite palette, high
     ; byte and x one at a time. Each store is one byte, and a line drawn
     ; between them shows the object at most a line or pixel off, never
     ; garbage, so it needn't be hidden (hiding drops it from that line).
     ldy #0
     lda (pfp),y
     cmp sp_lo
     bne pf_object_new
     iny
     lda (pfp),y
     eor sp_pw
     and #$1F
     bne pf_object_new
     lda sp_pw
     sta (pfp),y
     iny
     lda pft3
     sta (pfp),y
     iny
     lda sp_x
     sta (pfp),y
     rts
pf_object_new
     ldy #3
     lda #160
     sta (pfp),y             ; hide the old object
     dey
     lda pft3
     sta (pfp),y
     ldy #0
     lda sp_lo
     sta (pfp),y
     iny
     lda sp_pw
     sta (pfp),y
     ldy #3
     lda sp_x
     sta (pfp),y             ; and show the new one
pf_object_full
     rts

; Capacity per zone: the last offset a 4-byte object (+ terminator) fits.
zonecap
     .byte 0
     REPEAT 13
     .byte PFCAP
     REPEND
     .byte Z14CAP

; ---------------------------------------------------------------------------
; pf_text: text string A (TXT_ number) centred in zone tzone (1-13), in
; palette tpal (bit 7 set: hidden, at x 160, off the right edge; texts up
; to 12 characters). A character object, so it stays put only while the
; scroll is still (the title and other screens).
;
; Draw text after the zone's sprites, so it shows on top of them. The frame
; is built in the DLs while MARIA shows them, and pf_object rewrites last
; frame's 4-byte objects in place, so the text must not move: where it
; would move up (fewer sprites in the zone than last frame), the slots
; between are hidden (x 160) and it stays where it was; where sprites
; have taken its place (more of them), they were appended there anew
; (pf_frame stops zoneold at the old text), with the list ended at each
; slot first, and the text goes on after them. A text that is already
; there, the same, is left alone; a new one is written with the list
; ended at its slot until its header is whole.
pf_text
     tay
     ldx tzone
     lda zonelo,x
     sta pfp
     lda zonehi,x
     sta pfp+1
     lda txtlen,y
     sta pft1
     asl                     ; x = (160 - 8 * len) / 2 = 80 - 4 * len
     asl
     sta pft2
     lda #80
     sec
     sbc pft2
     sta pft2
     bit tpal
     bpl pf_text_shown
     lda #160                ; hidden
     sta pft2
pf_text_shown
     lda txtlo,y
     sta pft3
     lda txthi,y
     sta pft4
     lda tpal                ; palette | width
     asl
     asl
     asl
     asl
     asl
     sta pft5
     lda #0
     sec
     sbc pft1
     and #31
     ora pft5
     sta pft5
     ; hide the slots up to last frame's text, if it was further on
     ldy zonebuf,x
     lda txtold,y
     sta pft1
     cmp #$FF
     beq pf_text_slot
pf_text_pad
     lda dlend,x
     cmp pft1
     bcs pf_text_slot
     clc
     adc #3
     tay
     lda #160
     sta (pfp),y
     iny
     sty dlend,x
     bne pf_text_pad
pf_text_slot
     lda dlend,x
     cmp #PFCAP-1
     bcs pf_text_full
     sta txtnow,x
     ; pfp = the slot itself
     clc
     adc pfp
     sta pfp
     bcc pf_text_same
     inc pfp+1
pf_text_same
     ; already there, the same?
     ldy #1
     lda (pfp),y
     cmp #$60
     bne pf_text_new
     dey
     lda (pfp),y
     cmp pft3
     bne pf_text_new
     ldy #2
     lda (pfp),y
     cmp pft4
     bne pf_text_new
     iny
     lda (pfp),y
     cmp pft5
     bne pf_text_new
     iny
     lda (pfp),y
     cmp pft2
     beq pf_text_done
pf_text_new
     ldy #1
     lda #0
     sta (pfp),y             ; the DL ends here for now
     ldy #6
     sta (pfp),y             ; and after the text, once it is whole
     dey
     dey
     lda pft2
     sta (pfp),y             ; x
     dey
     lda pft5
     sta (pfp),y             ; palette | width
     dey
     lda pft4
     sta (pfp),y             ; high byte
     dey
     dey
     lda pft3
     sta (pfp),y             ; low byte
     iny
     lda #$60                ; 5-byte header, character mode: now it exists
     sta (pfp),y
pf_text_done
     lda dlend,x
     clc
     adc #5
     sta dlend,x
pf_text_full
     rts

; ---------------------------------------------------------------------------
; pf_drawscreen: use instead of drawscreen.
;
; It syncs to MARIA's own vblank flag rather than 7800basic's visibleover,
; and resets 7800basic's NMI bookkeeping every frame. 7800basic counts its
; three NMIs (top of screen, end of screen, overscan) to know which is
; which; if that count ever slips, visibleover is only set for a few lines
; that its long top-of-screen handler covers, and anything waiting on it
; waits forever. Resetting the count in vblank, after all three have fired,
; heals any slip within a frame.
pf_drawscreen
     ifconst interrupthold
         lda #$FF
         sta interrupthold
     endif
     ; Late? The frame started in vblank, one top-of-screen NMI ago; two or
     ; more means the logic ran into the next frame. This frame then shows
     ; for two, and the next one runs two game steps (a catch-up step that
     ; draws nothing, then the usual one), so the game keeps its speed and
     ; only the display drops to 30 frames a second. (Counted after the
     ; wait, below.)
     ifconst FPS30
         ; Always 30: every frame shows for two and runs two steps.
         jsr waitforvblankstart
     endif
     jsr waitforvblankstart  ; the start of MARIA's vblank (a full frame if late)
     ifconst IDLELOG
         jsr il_take         ; (from main_early's il_go: the early steps too)
         sec
         sbc il_e
         sta il_w
         ldx #5
il_pub   lda il_c,x          ; publish this frame's record at once
         sta il_out,x
         dex
         bpl il_pub
     endif
     ; How many frames this one took: the overscan NMIs since it began
     ; (one a frame, just before each vblank; pfvbl, from userinterrupt).
     ; Each frame past the first is a step to catch up (at most 2). Counting
     ; to vblank itself matters: a frame that ends after vblank has begun
     ; waits for the next one, and must get its catch-up step however close
     ; it came (the top-of-screen NMI, counted before, is some 25 lines
     ; later, and a frame ending between the two lost its step).
     lda pfvbl
     sec
     sbc pfvbl0
     sbc #1                  ; (carry set: 1 or more frames)
     bcs pf_drawscreen_late
     lda #0
pf_drawscreen_late
     cmp #3
     bcc pf_drawscreen_cap
     lda #2
pf_drawscreen_cap
     sta pflate
     lda pfvbl
     sta pfvbl0
     lda #3
     sta interruptindex
     lda #0
     sta visibleover
     lda sCTRL
     sta CTRL
     lda sCHARBASE
     sta CHARBASE
     jsr terminatedisplaylist ; zone 0 (7800basic's)
     jsr pf_terminate
     jsr pf_commit
     inc pfdraws
     dec frameslost
     rts

; End every playfield DL after its last object.
pf_terminate
     ldx #14
pf_terminate_loop
     lda zonelo,x
     sta pfp
     lda zonehi,x
     sta pfp+1
     ldy zonebuf,x
     lda txtnow,x
     sta txtold,y
     lda dlend,x
     sta oldend,y            ; what MARIA will show of this buffer
     tay
     iny
     lda #0
     sta (pfp),y
     dex
     bne pf_terminate_loop
     rts

; Write the zone layout into the DLL. Must run while MARIA is in vblank.
; Then the zone 14 buffer just shown becomes next frame's one to build.
pf_commit
     ldx #1
     ldy #0
pf_commit_loop
     lda #$4F                ; holey DMA for 16-line zones | 16 lines
     sta DLLZONE1,y
     lda zonehi,x
     sta DLLZONE1+1,y
     lda zonelo,x
     sta DLLZONE1+2,y
     iny
     iny
     iny
     inx
     cpx #15
     bne pf_commit_loop
     lda #$4F                ; zone 1: 16-s lines
     sec
     sbc pfs
     sta DLLZONE1
     lda pfs                 ; zone 14: 1+s lines
     ora #$40
     sta DLLZONE1+3*13
     lda pfz14back
     eor #1
     sta pfz14back
     rts

; Ring buffer addresses.
ringlo
RINGI SET 0
     REPEAT RINGN
     .byte <(RINGBASE+RINGI*BUFSIZE)
RINGI SET RINGI+1
     REPEND
ringhi
RINGI SET 0
     REPEAT RINGN
     .byte >(RINGBASE+RINGI*BUFSIZE)
RINGI SET RINGI+1
     REPEND

; ---------------------------------------------------------------------------
; pf_early: after the draw step, should a catch-up step run now? (A = 1,
; Z clear: yes.) Only when the frame is late already: a vblank has passed
; since it began, so at the next one it will owe a catch-up step for each
; (at most 2; pfahead of them run so far). And only when one fits before
; that vblank: the RIOT timer, restarted by the NMI just before each
; vblank (userinterrupt), says how far into the frame it is, in 1024-cycle
; ticks (29 a frame): up to 16 in, as a catch-up step takes 11 (16 at
; most in 99 of 100, stage 2's busiest stretches). One that runs over only
; shows the frame one later, with a step fewer owed. (13, 16 and 19 did
; about the same; 10 less well.)
PF_EARLYMAX = 16
pfahead     = $22C6 ; catch-up steps run early, before the frame showed
pfowe       = $22C7 ; catch-up steps still owed when the next frame begins
pfsway      = $22C8 ; MASS DRIVER's sway (stage 7): pixels, signed, added to the
pfswayrow   = $22C9 ;   x of map rows from pfswayrow on ($FF: none; pf_stage)
pfswayend   = $22CA ;   up to (not including) pfswayend
ringrow     = $22D0 ; [14] the map row each ring buffer holds
pf_early
     lda pfvbl
     sec
     sbc pfvbl0              ; vblanks passed: steps owed at the next
     beq pf_early_no
     cmp #3
     bcc pf_early_cap
     lda #2
pf_early_cap
     cmp pfahead
     beq pf_early_no
     bcc pf_early_no
     lda #255
     sec
     sbc INTIM               ; ticks since the NMI
     cmp #PF_EARLYMAX+1
     bcs pf_early_no
     lda #1
     rts
pf_early_no
     lda #0
     rts

; Idle log (debug, IDLELOG): each displayed frame's catch-up steps after
; the vblank (il_c, il_n of them), draw step (il_d), catch-up steps run
; early (il_e, il_a of them) and wait for vblank (il_w), in 1024-cycle
; ticks, published together at il_out for a script to read.
il_out      = $25F0 ; [6] c, d, w, n, e, a
il_c        = $25F6
il_d        = $25F7
il_w        = $25F8
il_n        = $25F9
il_e        = $25FA
il_a        = $25FB
il_v0       = $25FC
il_t0       = $25FD
     ifconst IDLELOG
il_go
     lda pfvbl
     sta il_v0
     lda INTIM
     sta il_t0
     rts
; A = ticks since il_go: frames passed * 29 + the timer's fall
il_take
     lda pfvbl
     sec
     sbc il_v0
     tax
     lda il_t0
     sec
     sbc INTIM
il_take_v
     dex
     bmi il_take_done
     clc
     adc #29
     jmp il_take_v
il_take_done
     rts
     endif

; Profiling (debug): prof_start starts the RIOT timer counting down in
; 64-cycle steps; prof_mark stores the time since the last mark (in 64s of
; cycles, wall time, so MARIA's DMA counts too) at profbuf+A, and restarts.
profbuf     = $25F0
prof_start
     lda #255
     sta TIM64T
     rts
prof_mark
     tax
     lda #255
     sec
     sbc INTIM
     sta profbuf,x
     lda #255
     sta TIM64T
     rts
