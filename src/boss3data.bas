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
