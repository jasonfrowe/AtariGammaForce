; ===========================================================================
; Gamma Force display engine: smooth vertical scrolling for 7800basic.
; See docs/ENGINE.md for the full picture. In short:
;
;   zone 0       HUD, 16 lines, never scrolls (7800basic manages it)
;   zones 1-14   the playfield. Each zone's display list (DL) is one of 15
;                ring buffers; each buffer holds one map row's background
;                objects followed by that frame's sprites.
;
; Fine scroll: zone 1 is cut to 16-s lines (s = 0..15) and zone 14 is
; 1+s lines, so the playfield is always 209 lines. Zone 14 has to show the
; *top* lines of its row, which MARIA can't do by itself (it always counts
; a zone's lines down to 0), so its graphics are shifted up by 15-s pages:
; the DLI on zone 13 moves CHARBASE for the background, and the plotter
; adds 15-s to the high byte of sprite objects it puts in zone 14.
;
; Coarse scroll: every 16 pixels the zones move down one buffer. Zone 1
; gets the spare buffer, which was filled with the next map row ahead of
; time, and the buffer leaving the bottom becomes the new spare. Nothing
; else is copied, so a coarse step costs about as much as a fine one.
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

; ---- RAM: $2200-$22FF belongs to the engine --------------------------------
zonelo      = $2200 ; [15] DL address of zone k, k = 1..14
zonehi      = $2210 ; [15]
bgsize      = $2220 ; [15] background bytes at the start of ring buffer i
spos_f      = $2230 ; scroll position in pixels, 16.8 fixed point
spos_lo     = $2231
spos_hi     = $2232
pfspeed     = $2233 ; scroll speed, 1/256 pixel per frame
pfsparedirty = $2234 ; nonzero: the spare buffer needs the next row
pfnextrow   = $2235 ; map row the spare buffer gets next
pfdliflag   = $2236 ; bit 7 set: the next NMI is our zone 13 DLI
pfdlicharbase = $2237 ; CHARBASE for zone 14
pfdlienable = $2238 ; $80 once the DLI is in the DLL
hudtext     = $2240 ; [20] HUD characters, shown live in zone 0

RINGBASE    = $1900
BUFSIZE     = 112
PFCAP       = BUFSIZE-6     ; room for one more 4-byte object + terminator
DLLZONE1    = DLLMEM+12     ; 3 blank entries + the HUD entry
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

     if S1_ROWS > 255
         echo "ERROR: the engine indexes map rows with a byte"
         err
     endif

; ---------------------------------------------------------------------------
; pf_init: palettes, HUD, the first screen of map rows, and the DLL.
; Call once, after "characterset charset".
pf_init
     lda #BGCOLOR
     sta BACKGRND
     ldx #0
     ldy #0
pf_init_pal
     lda palettedata,x
     sta P0C1,y
     inx
     iny
     tya
     and #3
     cmp #3
     bne pf_init_pal1
     iny                     ; skip the 4th register of each palette group
pf_init_pal1
     cpx #24
     bne pf_init_pal

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

     ; Scroll state. At position 0, zone k shows row 14-k, and row r lives
     ; in ring buffer r mod 15, so rows 0-14 go straight into buffers 0-14
     ; (row 14 being the spare).
     lda #0
     sta spos_f
     sta spos_lo
     sta spos_hi
     sta pfsparedirty
     sta pfdliflag
     lda #160
     sta pfspeed
     ldx #14
pf_init_rows
     txa
     tay
     stx pft4
     jsr pf_buildrow
     ldx pft4
     dex
     bpl pf_init_rows
     lda #15
     sta pfnextrow
     lda #13
     sta pfhead
     jsr pf_mapzones
     lda #15
     sta pfs
     lda #0
     sta pfshift
     jsr pf_restore

     ; The DLL. 7800basic built 3 blank entries, the HUD (zone 0), some
     ; zone entries we replace, and then 5 non-visible entries carrying its
     ; NMIs. Move those 5 down past our 14 playfield entries (copying from
     ; the end, since they move up in memory), then fill the playfield.
     jsr waitforvblankstart
     ldx #14
pf_init_dll
     lda DLLMEM+[DLLLUTNONVISSTART-DLLLUT],x
     sta DLLNONVIS,x
     dex
     bpl pf_init_dll
     ; The playfield is 209 lines (16-s + 12*16 + 1+s), one more than 13
     ; zones, so take a line off the top border to keep the frame length.
     dec DLLMEM
     lda #(DLLNONVIS-DLLMEM)
     sta overscanDLLstart
     jsr pf_terminate
     jsr pf_commit
     lda #$80
     sta pfdlienable
     rts

pfhudobj
     ; lo, mode ($60 = 5-byte header, character mode), hi, palette 3 | 20 wide, x
     .byte <hudtext, $60, >hudtext, (3<<5)|((-20)&31), 0

; ---------------------------------------------------------------------------
; pf_buildrow: copy map row Y's background objects into ring buffer X.
pf_buildrow
     lda s1rowlo,y
     sta pfp
     lda s1rowhi,y
     sta pfp+1
     lda ringlo,x
     sta pfq
     lda ringhi,x
     sta pfq+1
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
pf_buildrow_done
     rts

; ---------------------------------------------------------------------------
; pf_mapzones: zone k (1..14) gets ring buffer head-(k-1), mod 15.
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
     dey
     bpl pf_mapzones_next
     ldy #14
pf_mapzones_next
     inx
     cpx #15
     bne pf_mapzones_loop
     rts

; pf_restore: every playfield zone back to just its background.
pf_restore
     ldx #14
pf_restore_loop
     lda dlendsave,x
     sta dlend,x
     dex
     bne pf_restore_loop
     rts

; ---------------------------------------------------------------------------
; pf_frame: start a frame. Fills the spare buffer if a coarse step used it
; up, advances the scroll by pfspeed, rotates the zones on a 16 pixel
; boundary, and empties the zones of last frame's sprites.
pf_frame
     lda pfsparedirty
     beq pf_frame_scroll
     ldx pfhead              ; spare = head + 1, mod 15
     inx
     cpx #15
     bcc pf_frame_spare
     ldx #0
pf_frame_spare
     ldy pfnextrow
     jsr pf_buildrow
     inc pfnextrow           ; past the end, loop the boss section
     lda pfnextrow
     cmp #S1_ROWS
     bcc pf_frame_spare1
     sbc #S1_LOOP_ROWS
     sta pfnextrow
pf_frame_spare1
     lda #0
     sta pfsparedirty

pf_frame_scroll
     lda spos_lo
     and #$F0
     sta pft1
     clc
     lda spos_f
     adc pfspeed
     sta spos_f
     lda spos_lo
     adc #0
     sta spos_lo
     lda spos_hi
     adc #0
     sta spos_hi
     lda spos_lo
     and #$F0
     cmp pft1
     beq pf_frame_fine
     ; Crossed a 16 pixel boundary: the spare becomes zone 1.
     ldx pfhead
     inx
     cpx #15
     bcc pf_frame_rot
     ldx #0
pf_frame_rot
     stx pfhead
     lda #1
     sta pfsparedirty
     jsr pf_mapzones
pf_frame_fine
     lda spos_lo             ; s = 15 - (pos & 15)
     and #15
     sta pfshift
     eor #15
     sta pfs
     jmp pf_restore

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
     jsr pf_plot
     ldx pimg
     lda imgstrips,x
     cmp #2
     bcc pf_drawimg_done
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
; pf_plot: one 16-line strip. sp_lo/sp_hi = graphics, sp_pw = palette and
; width, sp_x, sp_y = playfield y + 32. Clips at the HUD and the bottom.
pf_plot
     clc
     lda sp_y
     adc pfs
     bcs pf_plot_out         ; past line 255: below the playfield
     sec
     sbc #16                 ; virtual y = playfield y + 16 + s
     bcc pf_plot_out         ; wholly above zone 1
     sta pft1
     lsr
     lsr
     lsr
     lsr
     tax                     ; zone
     cpx #15
     bcs pf_plot_out
     lda pft1
     and #15
     sta pft2                ; line within the zone
     cpx #0
     beq pf_plot_lower       ; the top part would be in the HUD
     lda sp_hi
     ora pft2                ; upper part: hi + line
     jsr pf_object
pf_plot_lower
     lda pft2
     beq pf_plot_out         ; lined up with the zone: no lower part
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

; pf_object: append a 4-byte object with high byte A to zone X.
pf_object
     cpx #14
     bne pf_object1
     clc
     adc pfshift             ; zone 14 shows its row's top lines
pf_object1
     sta pft3
     lda zonelo,x
     sta pfp
     lda zonehi,x
     sta pfp+1
     ldy dlend,x
     cpy #PFCAP
     bcs pf_object_full
     lda sp_lo
     sta (pfp),y
     iny
     lda sp_pw
     sta (pfp),y
     iny
     lda pft3
     sta (pfp),y
     iny
     lda sp_x
     sta (pfp),y
     iny
     sty dlend,x
pf_object_full
     rts

; ---------------------------------------------------------------------------
; pf_drawscreen: use instead of drawscreen.
pf_drawscreen
     ifconst interrupthold
         lda #$FF
         sta interrupthold
     endif
pf_drawscreen_wait1
     lda visibleover
     bne pf_drawscreen_wait1 ; wait for the visible screen to end
     lda sCTRL
     sta CTRL
     lda sCHARBASE
     sta CHARBASE
     jsr terminatedisplaylist ; zone 0 (7800basic's)
     jsr pf_terminate
     jsr pf_commit
pf_drawscreen_wait2
     lda visibleover
     beq pf_drawscreen_wait2 ; and for the next one to start
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
     ldy dlend,x
     iny
     lda #0
     sta (pfp),y
     dex
     bne pf_terminate_loop
     rts

; Write the zone layout into the DLL. Must run while MARIA is in vblank.
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
     lda pfs                 ; zone 14: 1+s lines. Its DLI fires as MARIA
     ora #$C0                ; reaches the entry, i.e. before the zone.
     sta DLLZONE1+3*13
     lda #>charset
     clc
     adc pfshift
     sta pfdlicharbase
     rts

; Ring buffer addresses.
ringlo
RINGI SET 0
     REPEAT 15
     .byte <(RINGBASE+RINGI*BUFSIZE)
RINGI SET RINGI+1
     REPEND
ringhi
RINGI SET 0
     REPEAT 15
     .byte >(RINGBASE+RINGI*BUFSIZE)
RINGI SET RINGI+1
     REPEND
