; Up to $B700, where the title song goes, in bank 2 and bank 12 alike (so
; it plays on through the switch between them: gammaforce.bas, gen_music.sh).

     if . > $B700
         echo "ERROR: the code reaches past $B700, where the title song goes"
         err
     endif
     ds $B700 - ., 0
