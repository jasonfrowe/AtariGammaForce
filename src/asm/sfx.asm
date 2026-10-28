; ===========================================================================
; TIA sound effects. POKEY plays the music; the TIA's two channels play
; effects, so the music never drops out.
;
;   channel 0: the player (Vulcan, sword, absorb, Hyper, death)
;   channel 1: explosions
;
; sfx_play (A = SFX_ number) starts a sound if nothing more important is
; playing on its channel. sfx_tick runs once a frame from the NMI.
; A sound is a list of AUDC, AUDF, AUDV triples, one per frame, ended by
; $FF.
; ===========================================================================

SFX_VULCAN  = 0
SFX_EXPLODE = 1
SFX_BIGBOOM = 2
SFX_ABSORB  = 3
SFX_SWORD   = 4
SFX_DIE     = 5
SFX_HYPER   = 6
SFX_HIT     = 7
SFX_1UP     = 8

sfx_ptrlo   = $2279 ; [2] per channel; hi 0 = idle
sfx_ptrhi   = $227B ; [2]
sfx_pri     = $227D ; [2] priority of what is playing

sfx_play
     tay
     ldx sfx_chan,y
     lda sfx_ptrhi,x
     beq sfx_play_go         ; channel idle
     lda sfx_prio,y
     cmp sfx_pri,x
     bcc sfx_play_done       ; something more important is playing
sfx_play_go
     lda #0                  ; idle while the pointer changes: the NMI may
     sta sfx_ptrhi,x         ; tick in the middle of this
     lda sfx_prio,y
     sta sfx_pri,x
     lda sfx_lo,y
     sta sfx_ptrlo,x
     lda sfx_hi,y
     sta sfx_ptrhi,x
sfx_play_done
     rts

sfx_tick
     ldx #1
sfx_tick_loop
     lda sfx_ptrhi,x
     beq sfx_tick_next
     sta musp+1              ; (the music pointer is free between voices)
     lda sfx_ptrlo,x
     sta musp
     ldy #0
     lda (musp),y
     cmp #$FF
     beq sfx_tick_end
     sta AUDC0,x
     iny
     lda (musp),y
     sta AUDF0,x
     iny
     lda (musp),y
     sta AUDV0,x
     clc
     lda sfx_ptrlo,x
     adc #3
     sta sfx_ptrlo,x
     bcc sfx_tick_next
     inc sfx_ptrhi,x
     jmp sfx_tick_next
sfx_tick_end
     lda #0
     sta AUDV0,x
     sta sfx_ptrhi,x
     sta sfx_pri,x
sfx_tick_next
     dex
     bpl sfx_tick_loop
     rts

;               vulcan  expl    bigboom absorb  sword   die     hyper   hit     1up
sfx_chan  .byte 0,      1,      1,      0,      0,      0,      0,      1,      0
sfx_prio  .byte 1,      2,      3,      3,      1,      9,      8,      1,      8
sfx_lo    .byte <sfx_d_vulcan, <sfx_d_expl, <sfx_d_bigboom, <sfx_d_absorb
          .byte <sfx_d_sword, <sfx_d_die, <sfx_d_hyper, <sfx_d_hit, <sfx_d_1up
sfx_hi    .byte >sfx_d_vulcan, >sfx_d_expl, >sfx_d_bigboom, >sfx_d_absorb
          .byte >sfx_d_sword, >sfx_d_die, >sfx_d_hyper, >sfx_d_hit, >sfx_d_1up

; AUDC 4 = pure tone, 8 = noise, 12 = low pure tone, 6 = buzz, 3 = rumble
sfx_d_vulcan
     .byte 4,3,5, 4,4,4, 4,5,2, $FF
sfx_d_expl
     .byte 8,8,12, 8,10,11, 8,12,10, 8,14,9, 8,16,8, 8,18,7
     .byte 8,20,6, 8,22,5, 8,24,4, 8,26,3, 8,28,2, 8,30,1, $FF
sfx_d_bigboom
     .byte 3,10,15, 8,12,15, 3,14,14, 8,16,13, 3,18,12, 8,20,11
     .byte 3,22,10, 8,24,10, 3,26,9, 8,28,8, 3,29,7, 8,30,6
     .byte 3,31,5, 8,31,4, 3,31,3, 8,31,2, 3,31,1, $FF
sfx_d_absorb
     .byte 4,8,6, 4,6,6, 4,4,5, 4,3,4, 4,2,3, $FF
sfx_d_sword
     .byte 6,18,3, 6,19,3, 6,18,2, 6,20,2, 6,19,1, $FF
sfx_d_die
     .byte 8,10,15, 8,12,15, 8,14,15, 8,16,14, 8,18,14, 8,20,13
     .byte 8,22,13, 8,24,12, 8,26,12, 8,28,11, 8,30,10, 8,31,9
     .byte 8,31,8, 8,31,7, 8,31,6, 8,31,5, 8,31,4, 8,31,3
     .byte 8,31,2, 8,31,1, $FF
sfx_d_hyper
     .byte 4,31,12, 4,28,12, 4,25,12, 4,22,12, 4,19,12, 4,16,12
     .byte 4,13,12, 4,10,12, 4,8,12, 4,6,12, 4,4,11, 4,3,10
     .byte 4,2,9, 4,1,8, 4,1,6, 4,1,4, 4,1,2, $FF
sfx_d_hit
     .byte 8,4,4, 8,6,2, $FF
sfx_d_1up                    ; an extra life: a rising arpeggio, twice
     .byte 4,17,10, 4,17,10, 4,17,10, 4,13,10, 4,13,10, 4,13,10
     .byte 4,11,10, 4,11,10, 4,11,10, 4,8,10, 4,8,10, 4,8,10
     .byte 4,17,8, 4,17,8, 4,17,8, 4,13,8, 4,13,8, 4,13,8
     .byte 4,11,8, 4,11,8, 4,11,8, 4,8,8, 4,8,7, 4,8,6
     .byte 4,8,5, 4,8,4, 4,8,3, 4,8,2, $FF
