  rem LEVIATHAN's tables (in stage 3's bank, in the DMA hole after its
  rem graphics: they don't fit before them).
  rem ---- parts: type, image, hit points, share of the boss (%) ----
  rem (the reactor's 30 is counted apart; positions in gen/boss3tab.asm)
  inline boss3tab.asm

  data boss3_type
  ET_PCANNON, ET_PCANNON, ET_PWING, ET_PARMOR, ET_PCANNON, ET_PCORE, ET_PCANNON, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET
end
  data boss3_img
  IMG_B3GUN, IMG_B3GUN, IMG_B3BRIDGET, IMG_B3BRIDGEB, IMG_B3BAY, IMG_B3REACTOR, IMG_B3BAY, IMG_TURRET, IMG_TURRET, IMG_TURRET, IMG_TURRET
end
  data boss3_hp
  160, 160, 240, 255, 120, 255, 120, 60, 60, 60, 60
end
  data boss3_wt
  11, 11, 22, 0, 3, 0, 3, 5, 5, 5, 5
end

  rem ---- escort waves (boss3.bas b3_escort): the reactor's hit points
  rem that send each; type, color, x, x step, count, gap, param (darts:
  rem the line they dive to; saucers: their weave; drones: where they stop)
  data b3_escorthp
  240, 185, 125, 65
end
  data b3_esctype
  ET_DART, ET_SAUCER, ET_DART, ET_DRONE
end
  data b3_escpal
  4, 5, 6, 4
end
  data b3_escx
  16, 116, 136, 24
end
  data b3_escdx
  24, 0, 232, 48
end
  data b3_esccount
  6, 3, 6, 3
end
  data b3_escgap
  8, 16, 8, 22
end
  data b3_escparam
  120, 33, 120, 80
end
