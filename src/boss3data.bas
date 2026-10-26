  rem LEVIATHAN's tables (in stage 3's bank, in the DMA hole after its
  rem graphics: they don't fit before them).
  rem ---- parts: type, image, hit points, share of the boss (%) ----
  rem (the reactor's 30 is counted apart; positions in gen/boss3tab.asm)
  inline boss3tab.asm

  data boss3_type
  ET_PCANNON, ET_PCANNON, ET_PWING, ET_PARMOR, 0, ET_PCORE, 0, ET_PTURRET, ET_PTURRET, ET_PTURRET, ET_PTURRET
end
  data boss3_img
  IMG_B3GUN, IMG_B3GUN, IMG_B3BRIDGET, IMG_B3BRIDGEB, 0, IMG_B3REACTOR, 0, IMG_BTURRET, IMG_BTURRET, IMG_BTURRET, IMG_BTURRET
end
  data boss3_hp
  160, 160, 240, 255, 0, 255, 0, 60, 60, 60, 60
end
  data boss3_wt
  14, 14, 22, 0, 0, 0, 0, 5, 5, 5, 5
end
