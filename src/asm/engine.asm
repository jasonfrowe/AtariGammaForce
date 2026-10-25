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
hudtext     = $2240 ; [20] HUD characters, shown live in zone 0

RINGN       = 14
RINGBASE    = $1900
BUFSIZE     = 108
PFCAP       = BUFSIZE-6     ; room for one more 4-byte object + terminator
Z14BASE     = RINGBASE+RINGN*BUFSIZE ; $1EE8
Z14SIZE     = 140
Z14BG       = 80            ; 20 tiles x 4 bytes
Z14CAP      = Z14SIZE-6
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
     if Z14BASE+2*Z14SIZE > $2000
         echo "ERROR: engine DL buffers overflow $1FFF"
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

     ; Scroll state. At position 0, zone k (1-13) shows row 14-k and zone
     ; 14 shows row 0. Row r lives in ring buffer r mod 14, so rows 1-14 go
     ; into buffers 1-13 and 0 (row 14 being the spare).
     lda #0
     sta spos_f
     sta spos_lo
     sta spos_hi
     sta pfsparedirty
     sta pfrow14
     sta pfz14back
     lda #$FF
     sta pfz14row
     sta pfz14row+1
     lda #160
     sta pfspeed
     ldy #14
pf_init_rows
     tya
     cmp #RINGN
     bcc pf_init_rows1
     lda #0
pf_init_rows1
     tax
     sty pft4
     jsr pf_buildrow
     ldy pft4
     dey
     bne pf_init_rows
     lda #15
     sta pfnextrow
     lda #13
     sta pfhead
     jsr pf_mapzones
     lda #15
     sta pfs
     lda #0
     sta pfshift
     jsr pf_zone14
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
     jmp pf_commit

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
     dex
     bne pf_restore_loop
     rts

; ---------------------------------------------------------------------------
; pf_zone14: get this frame's zone 14 buffer ready: its tiles for the row
; (rebuilt if it holds another row) pointing 15-s pages up.
pf_zone14
     ldx pfz14back
     lda z14lo,x
     sta pfq
     sta zonelo+14
     lda z14hi,x
     sta pfq+1
     sta zonehi+14
     lda pfz14row,x
     cmp pfrow14
     beq pf_zone14_hi
     lda pfrow14
     sta pfz14row,x
     tay
     lda s1charlo,y
     sta pfp
     lda s1charhi,y
     sta pfp+1
     ; One object per tile that isn't open sea (that is the background
     ; color): lo = character, palette|width, hi, x.
     lda #0
     sta pft1                ; tile column
     sta pft3                ; object offset
pf_zone14_tile
     ldy pft1
     lda (pfp),y             ; character (2 x tile; charset is at offset 0)
     cmp #2*SEATILES
     bcc pf_zone14_skip
     tax
     ldy pft3
     sta (pfq),y
     iny
     lda tilepw,x
     sta (pfq),y
     iny
     iny                     ; hi is set below, every frame
     lda pft1
     asl
     asl
     asl
     sta (pfq),y             ; x = column * 8
     iny
     sty pft3
pf_zone14_skip
     inc pft1
     lda pft1
     cmp #20
     bne pf_zone14_tile
     ldx pfz14back
     lda pft3
     sta pfz14bg,x
pf_zone14_hi
     ldx pfz14back
     lda pfz14bg,x
     sta dlendsave+14
     beq pf_zone14_done      ; all sea
     sta pft3
     lda #>charset
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
     jmp pf_restore

; A = the map row after row A (past the end, loop the boss section).
pf_nextrow
     clc
     adc #1
     cmp #S1_ROWS
     bcc pf_nextrow_done
     sbc #S1_LOOP_ROWS
pf_nextrow_done
     rts

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
; pf_plot: one 16-line strip. sp_lo/sp_hi = graphics, sp_pw = palette and
; width, sp_x, sp_y = playfield y + 32, sp_h = lines the strip uses from
; its top (a strip shorter than 16 lines skips the zone below when it ends
; above it). Clips at the HUD and the bottom.
pf_plot
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
     cpx #15
     bcs pf_plot_out
     cpx #0
     beq pf_plot_lower       ; the top part would be in the HUD
     lda sp_hi
     ora pft2                ; upper part: hi + line
     jsr pf_object
pf_plot_lower
     lda pft2
     beq pf_plot_out         ; lined up with the zone: no lower part
     clc
     adc sp_h
     cmp #17
     bcc pf_plot_out         ; ends inside this zone
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
     sta pft3
     lda zonelo,x
     sta pfp
     lda zonehi,x
     sta pfp+1
     ldy dlend,x
     cpx #14
     bne pf_object_ring
     cpy #Z14CAP
     bcs pf_object_full
     lda pft3
     clc
     adc pfshift             ; zone 14 shows its row's top lines
     sta pft3
     jmp pf_object_put
pf_object_ring
     cpy #PFCAP
     bcs pf_object_full
pf_object_put
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
     jsr waitforvblankstart  ; the start of MARIA's vblank (a full frame if late)
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
