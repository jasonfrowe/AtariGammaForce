; ===========================================================================
; POKEY music player for data made by tools/vgm2pokey.py.
;
;   voice 0: POKEY channels 1+2 joined (16-bit, 1.79 MHz), lead/arp
;   voice 1: channel 3 (8-bit, 15 or 64 kHz clock per note), bass
;   voice 2: channel 4, drum macros
;
; mus_play (A = song number) starts a song; mus_stop silences POKEY.
; mus_tick runs once a frame from 7800basic's userinterrupt (off screen,
; inside the NMI), so it only touches its own zero page and RAM.
; ===========================================================================

POKEY       = $0450
PKAUDF1       = POKEY+0
PKAUDC1       = POKEY+1
PKAUDF2       = POKEY+2
PKAUDC2       = POKEY+3
PKAUDF3       = POKEY+4
PKAUDC3       = POKEY+5
PKAUDF4       = POKEY+6
PKAUDC4       = POKEY+7
PKAUDCTL      = POKEY+8
PKSKCTL       = POKEY+15

; zero page (the rest of 7800basic's tracker block), used only in the NMI
musp        = $B5   ; 2 bytes: stream / envelope pointer
mus_eltab   = $B7   ; 2 bytes: the song's envelope address table, low bytes
mus_ehtab   = $B9   ; 2 bytes: ...high bytes

mus_on      = $2260 ; nonzero while a song plays
mus_song    = $2261
mus_ptrlo   = $2262 ; [3] stream position per voice
mus_ptrhi   = $2265 ; [3]
mus_wait    = $2268 ; [3] frames until the next command
mus_envlo   = $226B ; [3] envelope (voice 2: drum macro) position
mus_envhi   = $226E ; [3]
mus_note    = $2271 ; [3]
mus_incall  = $2280 ; [3] nonzero while playing a $C1 phrase
mus_retlo   = $2283 ; [3] where to carry on after it
mus_rethi   = $2286 ; [3]
mus_endlo   = $2289 ; [3] the address just past the phrase
mus_endhi   = $228C ; [3]
mus_guard   = $228F ; commands a voice may still read this frame

; ---------------------------------------------------------------------------
; mus_play: start song A from the top.
mus_play
     tax
     lda #0
     sta mus_on              ; keep mus_tick out while we set up
     stx mus_song
     jsr mus_silence
     ldx mus_song
     lda mus_song_ello,x
     sta mus_eltab
     lda mus_song_elhi,x
     sta mus_eltab+1
     lda mus_song_ehlo,x
     sta mus_ehtab
     lda mus_song_ehhi,x
     sta mus_ehtab+1
     ldx #2
mus_play_v
     jsr mus_restart
     lda #0
     sta mus_wait,x
     sta mus_incall,x
     sta mus_note,x
     dex
     bpl mus_play_v
     lda #1
     sta mus_on
     rts

mus_stop
     lda #0
     sta mus_on
mus_silence
     lda #0
     sta PKSKCTL
     sta PKAUDC1
     sta PKAUDC2
     sta PKAUDC3
     sta PKAUDC4
     lda #3
     sta PKSKCTL
     lda #$50                ; ch1 at 1.79 MHz, ch1+2 joined
     sta PKAUDCTL
     rts

; Voice X back to the start of its stream, silent.
mus_restart
     lda #0
     sta mus_incall,x
     ldy mus_song
     cpx #1
     beq mus_restart1
     bcs mus_restart2
     lda mus_song_v0lo,y
     sta mus_ptrlo,x
     lda mus_song_v0hi,y
     sta mus_ptrhi,x
     jmp mus_quiet
mus_restart1
     lda mus_song_v1lo,y
     sta mus_ptrlo,x
     lda mus_song_v1hi,y
     sta mus_ptrhi,x
     jmp mus_quiet
mus_restart2
     lda mus_song_v2lo,y
     sta mus_ptrlo,x
     lda mus_song_v2hi,y
     sta mus_ptrhi,x
; Voice X silent until its next note.
mus_quiet
     lda #<mus_silent
     sta mus_envlo,x
     lda #>mus_silent
     sta mus_envhi,x
     rts

mus_silent
     .byte 0, $FF            ; envelope that holds volume 0; as a drum macro,
                             ; AUDC 0 = already over

; ---------------------------------------------------------------------------
mus_tick
     jsr sfx_tick            ; the TIA effects tick with the music
     lda mus_on
     bne mus_tick_go
     rts
mus_tick_go
     ldx #2
mus_tick_voice
     lda mus_wait,x
     beq mus_tick_read
     dec mus_wait,x
     jmp mus_tick_next
mus_tick_read
     lda #24                 ; a voice reads a few commands a frame: data
     sta mus_guard           ; that never waits (a bank switched under the
mus_tick_load                ; song) can't hold the NMI past its frame
     lda mus_ptrlo,x
     sta musp
     lda mus_ptrhi,x
     sta musp+1
mus_tick_cmd
     dec mus_guard
     bne mus_tick_cmd0
     jmp mus_tick_next
mus_tick_cmd0
     lda mus_incall,x        ; at the end of a called phrase: back to the caller
     beq mus_tick_cmd1
     lda musp
     cmp mus_endlo,x
     bne mus_tick_cmd1
     lda musp+1
     cmp mus_endhi,x
     bne mus_tick_cmd1
     lda #0
     sta mus_incall,x
     lda mus_retlo,x
     sta musp
     lda mus_rethi,x
     sta musp+1
mus_tick_cmd1
     ldy #0
     lda (musp),y
     cmp #$FF
     beq mus_tick_end
     cmp #$C0
     beq mus_tick_rest
     cmp #$C1
     beq mus_tick_call
     bcs mus_tick_skip1      ; unknown command: ignore it
     cmp #$80
     bcs mus_tick_wait
     ; A note: A = note (voice 2: drum number), then an envelope byte.
     sta mus_note,x
     cpx #2
     beq mus_tick_drum
     iny
     lda (musp),y            ; envelope number
     tay
     lda (mus_eltab),y
     sta mus_envlo,x
     lda (mus_ehtab),y
     sta mus_envhi,x
     jmp mus_tick_skip2
mus_tick_drum
     tay
     lda mus_drumlo,y
     sta mus_envlo,x
     lda mus_drumhi,y
     sta mus_envhi,x
     jmp mus_tick_skip2
mus_tick_rest
     jsr mus_quiet
mus_tick_skip1
     lda #1
     bne mus_tick_adv
mus_tick_skip2
     lda #2
mus_tick_adv
     clc
     adc musp
     sta musp
     bcc mus_tick_cmd
     inc musp+1
     jmp mus_tick_cmd
mus_tick_end
     jsr mus_restart         ; loop the song (the guard counts on)
     jmp mus_tick_load
mus_tick_call
     ; $C1 lo hi n: play n bytes at hi:lo, then carry on after these 4
     clc
     lda musp
     adc #4
     sta mus_retlo,x
     lda musp+1
     adc #0
     sta mus_rethi,x
     ldy #3
     lda (musp),y            ; n
     sta mus_endlo,x
     ldy #1
     lda (musp),y
     pha
     clc
     adc mus_endlo,x
     sta mus_endlo,x
     iny
     lda (musp),y
     sta musp+1
     adc #0
     sta mus_endhi,x
     pla
     sta musp
     lda #1
     sta mus_incall,x
     jmp mus_tick_cmd1
mus_tick_wait
     and #$3F                ; $80+n waits n+1 frames, this one included
     sta mus_wait,x
     inc musp
     bne mus_tick_waitd
     inc musp+1
mus_tick_waitd
     lda musp
     sta mus_ptrlo,x
     lda musp+1
     sta mus_ptrhi,x
mus_tick_next
     dex
     bmi mus_output
     jmp mus_tick_voice

; ---------------------------------------------------------------------------
; Write this frame's sound to POKEY.
mus_output
     ldx #0                  ; voice 0: lead, 16-bit
     jsr mus_envstep
     ora #$A0                ; pure tone
     sta PKAUDC2
     lda #0
     sta PKAUDC1
     ldy mus_note
     lda mus_p16lo,y
     sta PKAUDF1
     lda mus_p16hi,y
     sta PKAUDF2

     ldx #1                  ; voice 1: bass, 8-bit
     jsr mus_envstep
     ora #$A0
     sta PKAUDC3
     ldy mus_note+1
     lda mus_p8,y
     sta PKAUDF3
     lda mus_clk15,y
     ora #$50
     sta PKAUDCTL

     lda mus_envlo+2         ; voice 2: drum macro, AUDC/AUDF pairs
     sta musp
     lda mus_envhi+2
     sta musp+1
     ldy #0
     lda (musp),y
     sta PKAUDC4
     beq mus_output_done     ; AUDC 0: the drum is over, stay here
     iny
     lda (musp),y
     sta PKAUDF4
     clc
     lda musp
     adc #2
     sta mus_envlo+2
     lda musp+1
     adc #0
     sta mus_envhi+2
mus_output_done
     rts

; Voice X's volume this frame; steps the envelope unless the next value
; is $FF (hold).
mus_envstep
     lda mus_envlo,x
     sta musp
     lda mus_envhi,x
     sta musp+1
     ldy #1
     lda (musp),y
     cmp #$FF
     beq mus_envstep_hold
     inc mus_envlo,x
     bne mus_envstep_hold
     inc mus_envhi,x
mus_envstep_hold
     ldy #0
     lda (musp),y
     rts
