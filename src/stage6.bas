  rem ======================================================================
  rem  ASCENT's fade (stage 6's bank; the main loop calls it each step
  rem  while stage 6 is played): as the ship climbs, the ocean far below
  rem  (the background color) and its clouds (palette 1) darken toward
  rem  black, by the scroll position (gen/boss6tab.asm b6_fbg, b6_fp0-2,
  rem  a step every 64 pixels). The colors are written off the screen
  rem  (userinterrupt, from fadebg and fadep1), so no line shows two.
  rem ======================================================================

ascent
  asm
     lda spos_hi             ; step = scroll position / 64, at most the last
     cmp #(B6_FADEN+3)/4
     bcs as_last
     asl
     asl
     sta temp1
     lda spos_lo
     rol
     rol
     rol
     and #3
     ora temp1
     cmp #B6_FADEN
     bcc as_step
as_last
     lda #B6_FADEN-1
as_step
     tax
     lda b6_fbg,x
     sta fadebg
     lda b6_fp0,x
     sta fadep1
     lda b6_fp1,x
     sta fadep1+1
     lda b6_fp2,x
     sta fadep1+2
     lda #1
     sta fadeon
end
  return
