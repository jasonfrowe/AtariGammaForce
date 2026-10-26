; ===========================================================================
; Objects: the per-object loops that are too slow in BASIC.
;
;   bul_fire / bul_fan  enemy bullets from (fx, fy) at angle fang, speed fspd
;   aim_player          aimang = angle from (fx, fy) to the player
;   ang_vel             velx/vely for angle fang at speed fspd
;   weave               woff = cos(wang) * wamp / 128 (signed)
;   bul_update          move, absorb (sword), hit the player, draw
;   en_update           move enemies by their velocity, drop the ones that
;                       leave the screen
;   en_hits             player shots, the sword and the ship against enemies
;   en_draw             draw enemies (flashing white when hit)
;   score_add           score += sadd (BCD)
;   hud_score           write the score into the HUD
;
; Positions are 8.8 fixed point: x in 160A pixels, y in playfield lines
; plus 32. Velocities are signed bytes in 1/32 pixel per frame. Angles are
; 256 per turn, 0 = right, 64 = down. All arrays are dimmed in BASIC.
; ===========================================================================

; Towers on screen this frame (en_hits notes them; bul_update stops enemy
; bullets on them): their boxes.
ntow        = $2381
towx0       = $2384 ; [3]
towx1       = $2387
towy0       = $238A
towy1       = $238D

ob1         = $BB   ; zero page scratch (7800basic's tracker block)
ob2         = $BC
ob3         = $BD
ob5         = $BE
ob6         = $BF
ob7         = $C0
ob8         = $C1
obi         = $C2
obj         = $C3

; ---------------------------------------------------------------------------
; Multiply: ob1 * ob6 -> A (high), ob1 (low). Unsigned.
ob_mul8
     lda #0
     ldx #8
     lsr ob1
ob_mul8_loop
     bcc ob_mul8_skip
     clc
     adc ob6
ob_mul8_skip
     ror
     ror ob1
     dex
     bne ob_mul8_loop
     rts

; A (signed) * fspd -> A = product >> 8 (vel8) or >> 7 (vel7), signed.
ob_vel8
     jsr ob_smul
     jmp ob_sign
ob_vel7
     jsr ob_smul
     asl ob1
     rol
ob_sign
     bit ob5
     bpl ob_sign_done
     eor #$FF
     clc
     adc #1
ob_sign_done
     rts
ob_smul
     sta ob5
     bpl ob_smul_pos
     eor #$FF
     clc
     adc #1
ob_smul_pos
     sta ob1
     lda fspd
     sta ob6
     jmp ob_mul8

; ang_vel: velx, vely for angle fang, speed fspd (<= 127). x is halved,
; since 160A pixels are twice as wide as a line is tall.
ang_vel
     lda fang
     sec
     sbc #64
     tay
     lda cos8,y              ; sin(a) = cos(a - 64)
     jsr ob_vel7
     sta vely
     ldy fang
     lda cos8,y
     jsr ob_vel8
     sta velx
     rts

; weave: woff = cos(wang) * wamp >> 7, signed.
weave
     lda wamp
     sta fspd
     ldy wang
     lda cos8,y
     jsr ob_vel7
     sta woff
     rts

; ---------------------------------------------------------------------------
; Enemy bullets.

bul_fire
     ldx #NB-1
bul_fire_find
     lda bkind,x
     beq bul_fire_slot
     dex
     bpl bul_fire_find
bul_fire_none
     rts                     ; all in use: the bullet is never fired
bul_fire_slot
     stx obi
     lda fkind
     sta bkind,x
     lda fx
     sta bxh,x
     lda fy
     sta byh,x
     lda #$80
     sta bxl,x
     sta byl,x
     jsr ang_vel
     lda velx                ; store velocities x8 as 16 bits (1/256 px),
     jsr ob_x8               ; so moving a bullet is two plain adds
     ldx obi
     lda ob1
     sta bvx,x
     lda ob2
     sta bvxh,x
     lda vely
     jsr ob_x8
     ldx obi
     lda ob1
     sta bvy,x
     lda ob2
     sta bvyh,x
     rts

; fcount bullets, fstep apart, centred on fang.
bul_fan
     lda fang
     sta ob7
     lda #0
     ldx fcount
bul_fan_off
     dex
     beq bul_fan_off2
     clc
     adc fstep
     jmp bul_fan_off
bul_fan_off2
     lsr
     sta ob8
     lda fang
     sec
     sbc ob8
     sta fang
     lda fcount
     sta obj
bul_fan_loop
     jsr bul_fire
     lda fang
     clc
     adc fstep
     sta fang
     dec obj
     bne bul_fan_loop
     lda ob7
     sta fang
     rts

; aimang = angle from (fx, fy) to the player's centre (pcx, pcy).
aim_player
     lda #0
     sta ob7                 ; bit 0: dx < 0, bit 1: dy < 0
     lda pcx
     sec
     sbc fx
     bcs aim_dxpos
     eor #$FF
     adc #1
     inc ob7
aim_dxpos
     sta ob2                 ; |dx|, in 160A pixels (each two lines wide)
     lda pcy
     sec
     sbc fy
     bcs aim_dypos
     eor #$FF
     adc #1
     pha
     lda ob7
     ora #2
     sta ob7
     pla
aim_dypos
     lsr                     ; |dy| / 2 matches |dx| in visible distance
     sta ob3
     ora ob2
     bne aim_go
     lda #64                 ; on top of the player: straight down
     sta aimang
     rts
aim_go
     lda ob3
     cmp ob2
     bcs aim_steep
     sta ob1                 ; shallow: q = atan(dy/dx)
     jsr aim_ratio
     tay
     lda atan32,y
     jmp aim_quadrant
aim_steep
     lda ob2                 ; steep: q = 64 - atan(dx/dy)
     sta ob1
     lda ob3
     sta ob2
     jsr aim_ratio
     tay
     lda #64
     sec
     sbc atan32,y
aim_quadrant
     sta ob8                 ; q, 0-64
     lda ob7
     beq aim_q0
     cmp #1
     beq aim_q1
     cmp #3
     beq aim_q3
     lda #0                  ; dx >= 0, dy < 0: -q
     sec
     sbc ob8
     sta aimang
     rts
aim_q0
     lda ob8
     sta aimang
     rts
aim_q1
     lda #128                ; dx < 0, dy >= 0: 128 - q
     sec
     sbc ob8
     sta aimang
     rts
aim_q3
     lda #128                ; dx < 0, dy < 0: 128 + q
     clc
     adc ob8
     sta aimang
     rts

; A = 32 * ob1 / ob2, for ob1 <= ob2 (result 0-32).
aim_ratio
     lda ob1
     cmp ob2
     bcc aim_ratio_go
     lda #32
     rts
aim_ratio_go
     lda #0
     sta ob3
     ldx #5
aim_ratio_loop
     asl ob1
     bcs aim_ratio_sub
     lda ob1
     cmp ob2
     bcc aim_ratio_no
aim_ratio_sub
     lda ob1
     sec
     sbc ob2
     sta ob1
     sec
     rol ob3
     jmp aim_ratio_next
aim_ratio_no
     clc
     rol ob3
aim_ratio_next
     dex
     bne aim_ratio_loop
     lda ob3
     rts

; v (signed, A) * 8 -> ob1 (low), ob2 (high), sign extended.
ob_x8
     sta ob1
     ldy #0
     cmp #$80
     bcc ob_x8_pos
     ldy #$FF
ob_x8_pos
     sty ob2
     asl ob1
     rol ob2
     asl ob1
     rol ob2
     asl ob1
     rol ob2
     rts

; Move, absorb, collide and draw every enemy bullet.
bul_update
     lda #$FF                ; palette 7, 1 byte wide: the same for all
     sta sp_pw
     ldx #NB-1
bul_update_loop
     lda bkind,x
     bne bul_update_live
     jmp bul_update_next
bul_update_live
     clc
     lda bxl,x
     adc bvx,x
     sta bxl,x
     lda bxh,x
     adc bvxh,x
     sta bxh,x
     clc
     lda byl,x
     adc bvy,x
     sta byl,x
     lda byh,x
     adc bvyh,x
     sta byh,x
     ; off screen?
     lda bxh,x
     cmp #2
     bcc bul_update_off
     cmp #158
     bcs bul_update_off
     lda byh,x
     cmp #24
     bcc bul_update_off
     cmp #244
     bcc bul_update_on
bul_update_off
     jmp bul_update_kill
bul_update_on
     ; towers stop bullets
     ldy ntow
     beq bul_update_sw
bul_update_tow
     dey
     lda bxh,x
     cmp towx0,y
     bcc bul_update_tnext
     cmp towx1,y
     bcs bul_update_tnext
     lda byh,x
     cmp towy0,y
     bcc bul_update_tnext
     cmp towy1,y
     bcs bul_update_tnext
     jmp bul_update_kill
bul_update_tnext
     tya
     bne bul_update_tow
bul_update_sw
     ; the sword absorbs pink bullets (odd kinds)
     lda swon
     beq bul_update_hit
     lda bkind,x
     and #1
     beq bul_update_hit
     lda bxh,x
     cmp swx0
     bcc bul_update_hit
     cmp swx1
     bcs bul_update_hit
     lda byh,x
     cmp swy0
     bcc bul_update_hit
     cmp swy1
     bcs bul_update_hit
     inc absorbed
     jmp bul_update_kill
bul_update_hit
     lda plvuln
     beq bul_update_draw
     lda bxh,x
     sec
     sbc pcx
     bcs bul_update_hx
     eor #$FF
     adc #1
bul_update_hx
     cmp #3
     bcs bul_update_draw
     lda byh,x
     sec
     sbc pcy
     bcs bul_update_hy
     eor #$FF
     adc #1
bul_update_hy
     cmp #4
     bcs bul_update_draw
     lda #1
     sta phit
     jmp bul_update_kill
bul_update_draw
     ldy bkind,x
     lda bul_imglo-1,y
     sta sp_lo
     lda bul_imghi-1,y
     sta sp_hi
     lda bul_h-1,y
     sta sp_h
     lda bxh,x
     sec
     sbc #2
     sta sp_x
     lda byh,x
     sbc #4                  ; (no borrow above: carry still set)
     sta sp_y
     stx obi
     jsr pf_plot
     ldx obi
     jmp bul_update_next
bul_update_kill
     lda #0
     sta bkind,x
bul_update_next
     dex
     bmi bul_update_done
     jmp bul_update_loop
bul_update_done
     rts

; Images for bullet kinds 1-5: pink, blue, big pink, big blue, needle.
bul_imglo .byte <pinkbullet, <bluebullet, <pinkbullet, <bluebullet, <needle
bul_imghi .byte >pinkbullet, >bluebullet, >pinkbullet, >bluebullet, >needle
bul_h     .byte 8, 8, 8, 8, 6

; Every bullet becomes 20 points (the Hyper Sword). Returns A = how many.
bul_cancel
     lda #0
     sta obj
     ldx #NB-1
bul_cancel_loop
     lda bkind,x
     beq bul_cancel_next
     lda #0
     sta bkind,x
     inc obj
bul_cancel_next
     dex
     bpl bul_cancel_loop
     lda obj
     rts

; ---------------------------------------------------------------------------
; Enemies.

en_update
     ldx #NE-1
en_update_loop
     lda etype,x
     bne en_update_live
     jmp en_update_next
en_update_live
     cmp #ET_TURRET
     beq en_update_ground
     cmp #ET_TOWER
     beq en_update_ground
     cmp #ET_TANK
     bne en_update_air
     ; tanks drive along their road, and leave at the screen's edge
     lda evx,x
     jsr ob_x8
     clc
     lda exl,x
     adc ob1
     sta exl,x
     lda exh,x
     adc ob2
     sta exh,x
     cmp #2
     bcc en_update_tankoff
     cmp #152
     bcc en_update_ground
en_update_tankoff
     jmp en_update_kill
en_update_ground
     ; ground units ride the map: their line follows the scroll exactly
     lda spos_lo
     clc
     adc eparam,x
     sta eyh,x
     cmp #250
     bcs en_update_kill
     jmp en_update_next
en_update_air
     cmp #ET_PART
     bcc en_update_move
     jmp en_update_next      ; boss parts: placed by the boss code, never culled
en_update_move
     lda evx,x
     beq en_update_y         ; most enemies have no sideways speed
     jsr ob_x8
     clc
     lda exl,x
     adc ob1
     sta exl,x
     lda exh,x
     adc ob2
     sta exh,x
en_update_y
     lda evy,x
     beq en_update_ycheck
     jsr ob_x8
     clc
     lda eyl,x
     adc ob1
     sta eyl,x
     lda eyh,x
     adc ob2
     sta eyh,x
en_update_ycheck
     lda eyh,x
     cmp #250
     bcs en_update_kill
     cmp #4
     bcc en_update_kill
     ; weaving: x = base + cos(angle) * amplitude / 128. The multiply is the
     ; dear part, so each enemy does it every other frame, at twice the step.
     lda ewamp,x
     beq en_update_xcheck
     sta fspd
     txa
     eor tick
     lsr
     bcs en_update_xcheck
     lda ewstep,x
     asl
     clc
     adc ewang,x
     sta ewang,x
     tay
     lda cos8,y
     stx obi
     jsr ob_vel7
     ldx obi
     clc
     adc ebase,x
     sta exh,x
en_update_xcheck
     lda exh,x
     cmp #160
     bcc en_update_next
en_update_kill
     lda #0
     sta etype,x
en_update_next
     dex
     bmi en_update_done
     jmp en_update_loop
en_update_done
     rts

; A tower (box exh..ob2, eyh..ob3): every shot inside it is stopped; its box
; is noted for bul_update; and the ship, if it overlaps (its body: plx+3 to
; plx+12, ply+2 to ply+21), is pushed out the shortest way. Pushed down off
; the bottom, it is crushed.
en_hits_tower
     ldy #NS-1
eht_shot
     lda shy,y
     beq eht_shotnext
     lda shx,y
     clc
     adc #3
     cmp exh,x
     bcc eht_shotnext
     lda shx,y
     cmp ob2
     bcs eht_shotnext
     lda shy,y
     clc
     adc #7
     cmp eyh,x
     bcc eht_shotnext
     lda shy,y
     cmp ob3
     bcs eht_shotnext
     lda #0
     sta shy,y
eht_shotnext
     dey
     bpl eht_shot
     ldy ntow
     cpy #3
     bcs eht_ship
     lda exh,x
     sta towx0,y
     lda ob2
     sta towx1,y
     lda eyh,x
     sta towy0,y
     lda ob3
     sta towy1,y
     inc ntow
     jmp eht_ship
eht_out
     jmp en_hits_next        ; (in branch range of the tests below)
eht_ship
     lda pdead
     bne eht_out
     ; how far to push the ship left (ob1), right (ob5), up (ob6), down (ob8)
     lda plx
     clc
     adc #13
     sec
     sbc exh,x
     bcc eht_out            ; wholly left of it
     beq eht_out
     sta ob1
     lda plx
     clc
     adc #3
     sta ob5
     lda ob2
     sec
     sbc ob5
     bcc eht_out            ; wholly right of it
     adc #0                  ; (+1: carry set)
     sta ob5
     lda ply
     clc
     adc #22
     sec
     sbc eyh,x
     bcc eht_out            ; wholly above it
     beq eht_out
     sta ob6
     lda ply
     clc
     adc #2
     sta ob8
     lda ob3
     sec
     sbc ob8
     bcc eht_out            ; wholly below it
     adc #0
     sta ob8
     ldy #0                  ; the smallest push (sideways first on a tie)
     lda ob1
     cmp ob5
     bcc eht_m1
     lda ob5
     ldy #1
eht_m1
     cmp ob6
     bcc eht_m2
     lda ob6
     ldy #2
eht_m2
     cmp ob8
     bcc eht_m3
     lda ob8
     ldy #3
eht_m3
     sta obj                 ; the push
     cpy #0
     beq eht_left
     cpy #1
     beq eht_right
     cpy #2
     bne eht_down
     lda ply
     sec
     sbc obj
     sta ply
     jmp eht_done
eht_down
     lda ply
     clc
     adc obj
     cmp #217
     bcs eht_aside
     sta ply
     jmp eht_done
eht_aside
     ; at the bottom: shoved aside instead, the shorter way that fits
     lda ob1
     cmp ob5
     bcs eht_tryright
     lda plx
     cmp ob1
     bcs eht_goleft
eht_tryright
     lda plx
     clc
     adc ob5
     cmp #144
     bcc eht_setx
     lda plx                 ; (right doesn't fit: left, if that does)
     cmp ob1
     bcs eht_goleft
     lda plvuln              ; pinned in a corner: crushed
     beq eht_done
     lda #1
     sta phit
     jmp eht_done
eht_left
     lda plx
     cmp ob1
     bcc eht_done            ; (no room: next frame tries again)
eht_goleft
     lda plx
     sec
     sbc ob1
     jmp eht_setx
eht_right
     lda plx
     clc
     adc ob5
     cmp #144
     bcs eht_done
eht_setx
     sta plx
eht_done
     jmp en_hits_next

; Shots, sword and ship against enemies. Adds damage to ehit; sets phit.
; An enemy's box is its image: imgw*4 pixels wide, 16 lines (32 for
; 2-strip images), less a pixel or two all round.
en_hits
     lda #0
     sta ntow
     ldx #NE-1
en_hits_loop
     lda etype,x
     beq en_hits_skip
     cmp #ET_PWRECK
     bne en_hits_live
en_hits_skip
     jmp en_hits_next
en_hits_live
     ; ob7: nonzero for a boss wing whose turrets are still there; shots
     ; pass through its middle column (where the turrets sit) to them
     ldy #0
     cmp #ET_PWING
     bcc en_hits_hole
     cmp #ET_PARMOR+1
     bcs en_hits_hole
     ldy eparam,x
en_hits_hole
     sty ob7
     ; box: ob2 = right edge, ob3 = bottom edge
     ldy eimg,x
     lda imgw,y
     asl
     asl
     clc
     adc exh,x
     sec
     sbc #1
     sta ob2
     lda imgstrips,y
     cmp #2                  ; 1 strip: 16 lines, 2 strips: 32 (less 2)
     lda #14
     bcc en_hits_h
     lda #30
en_hits_h
     clc
     adc eyh,x
     sta ob3
     ; towers are solid: they can't be hurt, but stop shots and bullets
     ; and push the ship out of them
     lda etype,x
     cmp #ET_TOWER
     bne en_hits_weapons
     jmp en_hits_tower
en_hits_weapons
     ; Vulcan: every live shot inside the box. Each enemy is checked every
     ; other frame: a shot moves 12 lines in two, and the overlap window
     ; (enemy 16 + shot 12 lines) is wider, so none slip through.
     lda shcount
     beq en_hits_sword
     txa
     eor tick
     lsr
     bcs en_hits_sword
     ldy #NS-1
en_hits_shot
     lda shy,y
     beq en_hits_shotnext
     lda shx,y               ; shot spans x..x+3
     clc
     adc #3
     cmp exh,x
     bcc en_hits_shotnext
     lda shx,y
     cmp ob2
     bcs en_hits_shotnext
     lda shy,y               ; and y..y+7
     clc
     adc #7
     cmp eyh,x
     bcc en_hits_shotnext
     lda shy,y
     cmp ob3
     bcs en_hits_shotnext
     lda ob7
     beq en_hits_take
     lda shx,y               ; through the turret column: x - exh in 2..10
     sec
     sbc exh,x
     sec
     sbc #2
     cmp #9
     bcc en_hits_shotnext
en_hits_take
     lda ehit,x
     clc
     adc vdmg
     sta ehit,x
     sta anyhit
     lda #0
     sta shy,y
en_hits_shotnext
     dey
     bpl en_hits_shot
en_hits_sword
     ; Sword
     lda swdmg
     beq en_hits_ship
     lda swx1
     cmp exh,x
     bcc en_hits_ship
     lda swx0
     cmp ob2
     bcs en_hits_ship
     lda swy1
     cmp eyh,x
     bcc en_hits_ship
     lda swy0
     cmp ob3
     bcs en_hits_ship
     lda ehit,x
     clc
     adc swdmg
     sta ehit,x
     sta anyhit
en_hits_ship
     ; Ship: its centre inside the box shrunk by 2
     lda plvuln
     beq en_hits_next
     lda pcx
     sec
     sbc #2
     cmp exh,x
     bcc en_hits_next
     clc
     adc #4
     cmp ob2
     bcs en_hits_next
     lda pcy
     sec
     sbc #2
     cmp eyh,x
     bcc en_hits_next
     clc
     adc #4
     cmp ob3
     bcs en_hits_next
     lda #1
     sta phit
en_hits_next
     dex
     bmi en_hits_done
     jmp en_hits_loop
en_hits_done
     rts

en_draw
     lda tick
     lsr
     lsr
     lsr
     sta ob8                 ; animation step: a new frame every 8 ticks
     ; two passes: the ground (turrets, tanks, towers), then everything
     ; that flies over it; first to last slot: later slots draw on top
     lda #0
     sta ob7
en_draw_pass
     ldx #0
en_draw_loop
     lda etype,x
     bne en_draw_live
     jmp en_draw_next
en_draw_live
     ldy #1                  ; 1: flies
     cmp #ET_TURRET
     beq en_draw_gnd
     cmp #ET_TANK
     bcc en_draw_side
     cmp #ET_TOWER+1
     bcs en_draw_side
en_draw_gnd
     ldy #0
en_draw_side
     cpy ob7
     beq en_draw_go
     jmp en_draw_next
en_draw_go
     ldy eimg,x
     ; palette | width: white (palette 3) while flashing
     lda eflash,x
     beq en_draw_color
     dec eflash,x
     lda etype,x             ; boss parts flash on alternate frames only:
     cmp #ET_PART            ; all white is too much on parts that big
     bcc en_draw_white
     lda pfdraws             ; (frames shown, not game steps: at 30 frames a
     lsr                     ; second only every other step is drawn)
     bcc en_draw_color
en_draw_white
     lda #3<<5
     bne en_draw_pal
en_draw_color
     lda ecol,x
     asl
     asl
     asl
     asl
     asl
en_draw_pal
     ora imgnegw,y
     sta sp_pw
     ; frame: turrets, tanks and boss parts choose theirs (eframe); others
     ; animate, (step & (frames-1)); offset = frame * width
     lda etype,x
     cmp #ET_TURRET
     beq en_draw_set
     cmp #ET_TANK
     beq en_draw_set
     cmp #ET_PART
     bcc en_draw_anim
en_draw_set
     lda eframe,x
     jmp en_draw_frame
en_draw_anim
     lda imgframes,y
     sec
     sbc #1
     and ob8
en_draw_frame
     sta ob1
     lda #0
     clc
en_draw_mul
     dec ob1
     bmi en_draw_w2
     adc imgw,y
     jmp en_draw_mul
en_draw_w2
     sta ob2                 ; frame offset
     clc
     adc imglo,y
     sta sp_lo
     lda imghi,y
     sta sp_hi
     lda exh,x
     sta sp_x
     lda eyh,x
     sta sp_y
     lda imgstrips,y
     cmp #2
     lda imgh,y
     bcc en_draw_h
     lda #16
en_draw_h
     sta sp_h
     stx obi
     sty obj
     jsr pf_plot
     ldy obj
     lda imgstrips,y
     cmp #2
     bcc en_draw_done1
     lda imglo2,y            ; the second strip, 16 lines down
     clc
     adc ob2
     sta sp_lo
     lda imghi2,y
     sta sp_hi
     lda imgh,y
     sta sp_h
     lda sp_y
     clc
     adc #16
     bcs en_draw_done1
     sta sp_y
     jsr pf_plot
en_draw_done1
     ldx obi
en_draw_next
     inx
     cpx #NE
     bcs en_draw_passdone
     jmp en_draw_loop
en_draw_passdone
     inc ob7
     lda ob7
     cmp #2
     bcs en_draw_out
     jmp en_draw_pass
en_draw_out
     rts

; ---------------------------------------------------------------------------
; Score: 4 BCD bytes, score_bcd (most significant) to score_bcd+3.

score_add
     sed
     clc
     lda score_bcd+3
     adc sadd0
     sta score_bcd+3
     lda score_bcd+2
     adc sadd1
     sta score_bcd+2
     lda score_bcd+1
     adc sadd2
     sta score_bcd+1
     lda score_bcd
     adc #0
     sta score_bcd
     cld
     lda #0
     sta sadd0
     sta sadd1
     sta sadd2
     rts

; Score into hudtext columns 0-6 (7 digits: the 8th, always 0, is dropped).
hud_score
     ldx #0
     ldy #0
hud_score_loop
     lda score_bcd,y
     and #$0F                ; first byte: skip its high digit
     cpx #0
     beq hud_score_low
     lda score_bcd,y
     lsr
     lsr
     lsr
     lsr
     jsr hud_digit
     lda score_bcd,y
     and #$0F
hud_score_low
     jsr hud_digit
     iny
     cpy #4
     bne hud_score_loop
     rts
hud_digit
     asl
     clc
     adc #FONTBASE
     cpx #7
     bcs hud_digit_done
     sta hudtext,x
     inx
hud_digit_done
     rts

; ---------------------------------------------------------------------------
; Player shots: move up 6 lines, drop off the top, draw.
sh_update
     lda #0
     sta shcount
     lda #<vulcan
     sta sp_lo
     lda #>vulcan
     sta sp_hi
     lda #(3<<5)|31          ; palette 3, 1 byte wide
     sta sp_pw
     lda #8
     sta sp_h
     ldx #NS-1
sh_update_loop
     lda shy,x
     beq sh_update_next
     sec
     sbc #6
     cmp #32
     bcs sh_update_live
     lda #0
     sta shy,x
     beq sh_update_next
sh_update_live
     sta shy,x
     sta sp_y
     inc shcount
     lda shx,x
     sta sp_x
     stx obi
     jsr pf_plot
     ldx obi
sh_update_next
     dex
     bpl sh_update_loop
     rts

; Explosions: xt counts 1-23 (4 frames a picture), then frees the slot.
fx_update
     lda #<expl
     sta pft4                ; (pf_plot leaves pft4 alone)
     lda #>expl
     sta sp_hi
     lda #(4<<5)|30          ; palette 4, 2 bytes wide
     sta sp_pw
     lda #16
     sta sp_h
     ldx #NX-1
fx_update_loop
     lda xt,x
     beq fx_update_next
     clc
     adc #1
     cmp #24
     bcc fx_update_live
     lda #0
     sta xt,x
     beq fx_update_next
fx_update_live
     sta xt,x
     and #$FC                ; picture = xt/4, 2 bytes each: (xt/4)*2
     lsr
     clc
     adc pft4
     sta sp_lo
     lda xx,x
     sta sp_x
     lda xy,x
     sta sp_y
     stx obi
     jsr pf_plot
     ldx obi
fx_update_next
     dex
     bpl fx_update_loop
     rts

; ---------------------------------------------------------------------------
; en_think: enemy behavior (MegaGammaForce's enemies.c think(), scaled:
; speeds are 1/32 pixel per frame, so its 1/16 values are about x1.75).
; Each enemy thinks every other frame, its timer counting in twos; movement
; and weaving run every frame in en_update. Boss parts (ET_PART and up) are
; the boss code's business.
thi         = $C6   ; the enemy being thought about (the bullet routines use X)

en_think
     ldx #NE-1
en_think_loop
     lda etype,x
     beq en_think_next
     cmp #ET_PART
     bcs en_think_next
     txa
     eor tick
     lsr
     bcs en_think_next       ; the other half thinks next frame
     inc etimer,x
     inc etimer,x
     stx thi
     lda exh,x
     clc
     adc #4
     sta fx
     lda eyh,x
     clc
     adc #8
     sta fy
     lda etype,x
     cmp #ET_DART
     bne en_think_1
     jsr think_dart
     jmp en_think_done
en_think_1
     cmp #ET_SAUCER
     bne en_think_2
     jsr think_saucer
     jmp en_think_done
en_think_2
     cmp #ET_DRONE
     bne en_think_3
     jsr think_drone
     jmp en_think_done
en_think_3
     cmp #ET_GUNSHIP
     bne en_think_4
     jsr think_gunship
     jmp en_think_done
en_think_4
     cmp #ET_TURRET
     bne en_think_5
     jsr think_turret
     jmp en_think_done
en_think_5
     cmp #ET_WASP
     bne en_think_6
     jsr think_wasp
     jmp en_think_done
en_think_6
     cmp #ET_TANK
     bne en_think_done
     jsr think_tank
en_think_done
     ldx thi
en_think_next
     dex
     bmi en_think_out
     jmp en_think_loop
en_think_out
     rts

; fang = angle from (fx, fy) to the player
th_aim
     jsr aim_player
     lda aimang
     sta fang
     rts

; Dives to its line, then turns on the player and fires once.
think_dart
     lda estate,x
     bne th_rts
     lda #70
     sta evy,x
     lda eyh,x
     cmp eparam,x
     bcc th_rts
     lda #1
     sta estate,x
     jsr th_aim
     lda #77
     sta fspd
     jsr ang_vel
     ldx thi
     lda velx
     sta evx,x
     lda vely
     sta evy,x
     lda plvuln
     beq th_rts
     lda #BK_PINK
     sta fkind
     lda #63
     sta fspd
     jmp bul_fire
th_rts
     rts

; Weaves down (en_update); every so often a 3-way pink fan at the player.
think_saucer
     lda #24
     sta evy,x
     lda etimer,x
     and #63
     cmp #40
     bne th_rts
     lda eyh,x
     cmp #201
     bcs th_rts
     lda plvuln
     beq th_rts
     jsr th_aim
     lda #BK_PINK
     sta fkind
     lda #52
     sta fspd
     lda #3
     sta fcount
     lda #14
     sta fstep
     jmp bul_fan

; Wasp: weaves down (the weave is set at spawn, as for saucers) and stings
; once on the way, with three aimed needles.
think_wasp
     lda #45
     sta evy,x
     lda etimer,x
     cmp #40
     bne th_rts
     lda plvuln
     beq th_rts
     jsr th_aim
     lda #BK_NEEDLE
     sta fkind
     lda #64
     sta fspd
     lda #3
     sta fcount
     lda #10
     sta fstep
     jmp bul_fan

; Tank: drives along its road (en_update); its turret tracks the player
; and fires a pink shell every two seconds or so.
think_tank
     lda eyh,x
     cmp #40
     bcc th_tank_rts
     cmp #211
     bcs th_tank_rts
     jsr th_aim
     ldx thi
     lda fang
     sec
     sbc #48
     lsr
     lsr
     lsr
     lsr
     lsr
     sta eframe,x            ; 8 directions
     lda etimer,x
     and #127
     cmp #64
     bne th_tank_rts
     lda plvuln
     beq th_tank_rts
     lda #BK_PINK
     sta fkind
     lda #44
     sta fspd
     jmp bul_fire
th_tank_rts
     rts

; Stops, fires a blue ring then a pink ring, and leaves.
think_drone
     lda estate,x
     beq th_drone_in
     cmp #1
     beq th_drone_hold
     lda #214                ; -42: away up the screen
     sta evy,x
     rts
th_drone_in
     lda #49
     sta evy,x
     lda eyh,x
     cmp eparam,x
     bcc th_drone_rts
     lda #1
     sta estate,x
     lda #0
     sta etimer,x
     sta evy,x
     rts
th_drone_hold
     lda etimer,x
     cmp #20
     bne th_drone_h2
     lda #BK_BLUE
     sta fkind
     lda #112
     bne th_drone_ring
th_drone_h2
     cmp #70
     bne th_drone_h3
     lda #BK_PINK
     sta fkind
     lda #128
     bne th_drone_ring
th_drone_h3
     cmp #121
     bcc th_drone_rts
     lda #2
     sta estate,x
     rts
th_drone_ring
     sta fang
     lda plvuln
     beq th_drone_rts
     lda #45
     sta fspd
     lda #8
     sta fcount
     lda #32
     sta fstep
     jmp bul_fan

th_drone_rts
     rts

; Big, strafes (weave in en_update), drops needles and aimed blue fans;
; leaves after a while.
think_gunship
     lda exh,x
     clc
     adc #8
     sta fx
     lda eyh,x
     clc
     adc #24
     sta fy
     lda estate,x
     bne th_gun_on
     lda #21
     sta evy,x
     lda eyh,x
     cmp eparam,x
     bcc th_rts2
     lda #1                  ; start strafing: x = base + 33 sin(t)
     sta estate,x
     sta ewstep,x
     lda #0
     sta etimer,x
     lda #33
     sta ewamp,x
     lda #192
     sta ewang,x
th_rts2
     rts
th_gun_on
     cmp #3
     bne th_gun_fight
     lda #228                ; -28: away
     sta evy,x
     rts
th_gun_fight
     lda #0
     sta evy,x
     lda etimer,x
     cmp #254
     bne th_gun_f1
     inc estate,x
th_gun_f1
     lda plvuln
     beq th_rts2
     lda etimer,x
     and #63
     cmp #24
     bne th_gun_f2
     lda #64                 ; three needles straight down
     sta fang
     lda #70
     sta fspd
     lda #BK_NEEDLE
     sta fkind
     lda fx
     sec
     sbc #7
     sta fx
     jsr bul_fire
     lda fx
     clc
     adc #7
     sta fx
     jsr bul_fire
     lda fx
     clc
     adc #7
     sta fx
     jsr bul_fire
     lda fx
     sec
     sbc #7
     sta fx
     ldx thi
th_gun_f2
     lda etimer,x
     and #127
     cmp #60
     bne th_rts2
     jsr th_aim
     lda #BK_BLUE
     sta fkind
     lda #42
     sta fspd
     lda #3
     sta fcount
     lda #20
     sta fstep
     jmp bul_fan

; Ground turret: turns to face the player, a blue shot every so often.
think_turret
     lda eyh,x
     cmp #40
     bcc th_tur_rts
     cmp #211
     bcs th_tur_rts
     jsr th_aim
     ldx thi
     lda fang
     sec
     sbc #48
     lsr
     lsr
     lsr
     lsr
     lsr
     sta eframe,x            ; 8 directions
     lda etimer,x
     and #127
     bne th_tur_rts
     lda plvuln
     beq th_tur_rts
     lda #BK_BLUE
     sta fkind
     lda #49
     sta fspd
     jmp bul_fire
th_tur_rts
     rts

; ---------------------------------------------------------------------------
; pl_update: the ship for one frame. In: plfire (Vulcan held), plsword
; (sword out, or Hyper running), hyper. Moves (slower firing, slower still
; with the sword), banks, fires the Vulcan, sets the sword's box and its
; damage this frame. The rest (Hyper trigger, absorbing, dying) is BASIC.
pl_update
     ; steps: idle 1 across / 2 down; firing 3/4 and 1-2; sword 1/2 and 1
     lda #1
     sta ob1                 ; horizontal step
     lda #2
     sta ob2                 ; vertical step
     lda plfire
     beq pl_u_sw
     lda tick
     and #1
     clc
     adc #1
     sta ob2
     lda tick
     and #3
     bne pl_u_sw
     lda #0
     sta ob1
pl_u_sw
     lda plsword
     beq pl_u_move
     lda #1
     sta ob2
     lda tick
     and #1
     sta ob1
pl_u_move
     lda #0
     sta bank
     bit sSWCHA
     bvs pl_u_r              ; bit 6 clear = left
     lda #1
     sta bank
     lda plx
     cmp #3
     bcc pl_u_r
     sec
     sbc ob1
     sta plx
pl_u_r
     bit sSWCHA
     bmi pl_u_u              ; bit 7 clear = right
     lda #2
     sta bank
     lda plx
     cmp #143
     bcs pl_u_u
     clc
     adc ob1
     sta plx
pl_u_u
     lda sSWCHA
     and #$10                ; up
     bne pl_u_d
     lda ply
     cmp #41
     bcc pl_u_d
     sec
     sbc ob2
     sta ply
pl_u_d
     lda sSWCHA
     and #$20                ; down
     bne pl_u_c
     lda ply
     cmp #214
     bcs pl_u_c
     clc
     adc ob2
     sta ply
pl_u_c
     lda plx
     clc
     adc #8
     sta pcx
     lda ply
     clc
     adc #12
     sta pcy
     ; Vulcan (not while the sword is out)
     lda firecd
     beq pl_u_f0
     dec firecd
pl_u_f0
     lda plsword
     bne pl_u_sword
     lda plfire
     beq pl_u_sword
     lda firecd
     bne pl_u_sword
     ldx #NS-1
pl_u_find
     lda shy,x
     beq pl_u_shot
     dex
     bpl pl_u_find
     bmi pl_u_sword
pl_u_shot
     lda plx
     clc
     adc #6
     sta shx,x
     lda ply
     sec
     sbc #6
     sta shy,x
     lda #4                  ; a pair of bolts every 4 frames
     sta firecd
     lda #SFX_VULCAN
     jsr sfx_play
pl_u_sword
     lda plsword
     bne pl_u_sw1
     rts
pl_u_sw1
     lda #1
     sta swon
     lda pcx
     sec
     sbc #12
     sta swx0
     clc
     adc #24
     sta swx1
     lda pcy
     sec
     sbc #30
     sta swy0
     clc
     adc #26
     sta swy1
     ; it strikes for 4 every 6 frames
     lda swcd
     beq pl_u_strike
     dec swcd
     bne pl_u_hum
pl_u_strike
     lda #4
     sta swdmg
     lda #6
     sta swcd
pl_u_hum
     lda tick
     and #15
     bne pl_u_hyper
     lda #SFX_SWORD
     jsr sfx_play
pl_u_hyper
     lda hyper
     beq pl_u_done
     ; Hyper: a wider blade and a beam up the whole screen
     lda pcx
     sec
     sbc #20
     sta swx0
     clc
     adc #40
     sta swx1
     lda #24
     sta swy0
     lda #0
     sta swdmg
     lda tick
     and #3
     bne pl_u_done
     lda #3
     sta swdmg
pl_u_done
     rts
