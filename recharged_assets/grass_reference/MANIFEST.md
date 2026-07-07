# Jak 1 grass textures — original references (dumped 2026-07-07 via decompiler save_texture_pngs)

Texture -> tpage(s) where the game uses it. Deduped by content (sha1).

## Core (grass-named)
- `bch-beachgrass.png` (427cbeaf29) — beach-vis-shrub
- `bch-grassclump-02.png` (80ffa437ac) — beach-vis-shrub
- `vil1-medres-grass-color.png` (324f045ca3) — common
- `vil1-medres-grass.png` (1aed4f550e) — common
- `vil3-medres-ogr-mossygrass.png` (d6f036950b) — common
- `fcn-grass-burned.png` (5e744e9833) — firecanyon-vis-shrub
- `fcn-grass-burntplant.png` (bbddb446be) — firecanyon-vis-shrub
- `mis-shrub-grass.png` (54756c34a3) — intro-vis-shrub, misty-vis-shrub
- `vil1-grassclump-01.png` (1590f994a3) — jungle-vis-shrub, rolling-vis-shrub, training-vis-shrub, village1-vis-shrub
- `ya-grassclump-02.png` (1dbb95a89c) — jungle-vis-shrub, rolling-vis-shrub
- `ogr-grassclump-02.png` (d8caad6585) — ogre-vis-shrub
- `ogr-vil2grassfringe.png` (cd7fec3ee2) — ogre-vis-tfrag
- `ogr-vil2grass.png` (9561df4d20) — ogre-vis-tfrag
- `rol-dngr-grass-01.png` (5f381160b4) — rolling-vis-shrub
- `rol-grass-fringe-large.png` (3df261961b) — rolling-vis-tfrag
- `rol-grass-fringe.png` (b24422b559) — rolling-vis-tfrag
- `rol-grass-ground-hirez-fringe.png` (fe2c82e991) — rolling-vis-tfrag
- `rol-grass-ground-hirez.png` (526d35b78e) — rolling-vis-tfrag, beach-vis-tfrag, firecanyon-vis-tfrag
- `v2-grass-ground-hirez.png` (d1d37cc064) — rolling-vis-tfrag
- `snow-grassclump.png` (42cb60d540) — snow-vis-shrub
- `swp-grassclump-02.png` (11160f797c) — swamp-vis-shrub
- `vil1-beachgrass.png` (34fc2e181b) — training-vis-shrub, village1-vis-shrub
- `bch-grassfringe.png` (2c5478130b) — training-vis-tfrag
- `tra-grass.png` (0c79d1a434) — training-vis-tfrag
- `v2-grass-burned.png` (0b73c3f0d8) — village2-vis-shrub
- `vil2-grass-03.png` (1590f994a3) — village2-vis-shrub
- `vil2-grassclump-01.png` (1590f994a3) — village2-vis-shrub
- `vil2-wallgrass-02.png` (ec181dda5f) — village2-vis-shrub
- `vil2-wheatgrass.png` (a94c781114) — village2-vis-shrub
- `v2-grass-ground-hirez-fringe.png` (e4f2ca44bc) — village2-vis-tfrag
- `v2-grass-ground-hirez--village2-vis-tfrag.png` (bb5f0a8f0e, VARIANT) — village2-vis-tfrag

## Maybe (adjacent: leafyground / moss / wheat — juge visuellement)
- `bch-leafyground.png` (526d35b78e) — beach-vis-shrub, beach-vis-tfrag, firecanyon-vis-tfrag
- `bch-spanmoss.png` (e3fb83411e) — beach-vis-shrub
- `bch-leafyground-hang-2x1.png` (cb99290f5f) — beach-vis-tfrag, training-vis-tfrag
- `fin-leafygroundBACKdirt.png` (d163628223) — finalboss-vis-tfrag
- `fin-leafygroundBACK.png` (df1b2e7634) — finalboss-vis-tfrag
- `fin-leafyground.png` (0a2c39fd5a) — finalboss-vis-tfrag
- `jng-leafyground-hang-2x1long.png` (6f611d3312) — jungle-vis-tfrag
- `jng-leafyground-hang-2x1.png` (298bc6402f) — jungle-vis-tfrag
- `jng-leafyground.png` (6d1392380e) — jungle-vis-tfrag
- `farthy-moss-02.png` (ae8b2cace7) — swamp-vis-pris
- `farthy-moss-03.png` (624e72efb6) — swamp-vis-pris
- `farthy-moss.png` (2807c4bd8c) — swamp-vis-pris
- `swp-moss-hang.png` (888d7b936e) — swamp-vis-shrub, swamp-vis-tfrag
- `swp-leafyground-hang-2x1.png` (8d0d47d2ba) — swamp-vis-tfrag
- `swp-leafyground.png` (d12bf1adf8) — swamp-vis-tfrag
- `vil1-jng-leafyground-hang-2x1-hitweak.png` (cba4fed7fc) — village1-vis-tfrag
- `vil1-jng-leafyground-hang-2x1.png` (cba4fed7fc) — village1-vis-tfrag
- `vil1-jng-leafyground-hitweak.png` (4ffa6f14c1) — village1-vis-tfrag
- `vil1-jng-leafyground.png` (4ffa6f14c1) — village1-vis-tfrag

## Régénérer le dump complet des textures (8 s)
```
./build/decompiler/decompiler decompiler/config/jak1/jak1_config.jsonc iso_data decompiler_out \
  --config-override '{"save_texture_pngs": true, "decompile_code": false, "levels_extract": false, "extract_collision": false, "rip_streamed_audio": false}'
```
-> decompiler_out/jak1/textures/<tpage>/<nom>.png (4002 fichiers). Le tpage suffix -vis-tfrag = sol/terrain,
-vis-shrub = végétation posée (clumps), -vis-alpha/-pris = transparents/objets.
