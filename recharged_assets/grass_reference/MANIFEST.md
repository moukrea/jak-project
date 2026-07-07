# Jak 1 grass textures — TOUTES les occurrences (pas de dédup), structure <tpage>/<nom>.png

## Core (grass-named)
- beach-vis-shrub/bch-beachgrass.png
- beach-vis-shrub/bch-grassclump-02.png
- common/vil1-medres-grass-color.png
- common/vil1-medres-grass.png
- common/vil3-medres-ogr-mossygrass.png
- firecanyon-vis-shrub/fcn-grass-burned.png
- firecanyon-vis-shrub/fcn-grass-burntplant.png
- intro-vis-shrub/mis-shrub-grass.png
- jungle-vis-shrub/vil1-grassclump-01.png
- jungle-vis-shrub/ya-grassclump-02.png
- misty-vis-shrub/mis-shrub-grass.png
- ogre-vis-shrub/ogr-grassclump-02.png
- ogre-vis-tfrag/ogr-vil2grassfringe.png
- ogre-vis-tfrag/ogr-vil2grass.png
- rolling-vis-shrub/rol-dngr-grass-01.png
- rolling-vis-shrub/vil1-grassclump-01.png
- rolling-vis-shrub/ya-grassclump-02.png
- rolling-vis-tfrag/rol-grass-fringe-large.png
- rolling-vis-tfrag/rol-grass-fringe.png
- rolling-vis-tfrag/rol-grass-ground-hirez-fringe.png
- rolling-vis-tfrag/rol-grass-ground-hirez.png
- rolling-vis-tfrag/v2-grass-ground-hirez.png
- snow-vis-shrub/snow-grassclump.png
- swamp-vis-shrub/swp-grassclump-02.png
- training-vis-shrub/vil1-beachgrass.png
- training-vis-shrub/vil1-grassclump-01.png
- training-vis-tfrag/bch-grassfringe.png
- training-vis-tfrag/tra-grass.png
- village1-vis-shrub/vil1-beachgrass.png
- village1-vis-shrub/vil1-grassclump-01.png
- village2-vis-shrub/v2-grass-burned.png
- village2-vis-shrub/vil2-grass-03.png
- village2-vis-shrub/vil2-grassclump-01.png
- village2-vis-shrub/vil2-wallgrass-02.png
- village2-vis-shrub/vil2-wheatgrass.png
- village2-vis-tfrag/v2-grass-ground-hirez-fringe.png
- village2-vis-tfrag/v2-grass-ground-hirez.png

## Maybe (leafyground / moss / wheat — juge visuellement)
- maybe-beach-vis-shrub/bch-leafyground.png
- maybe-beach-vis-shrub/bch-spanmoss.png
- maybe-beach-vis-tfrag/bch-leafyground-hang-2x1.png
- maybe-beach-vis-tfrag/bch-leafyground.png
- maybe-finalboss-vis-tfrag/fin-leafygroundBACKdirt.png
- maybe-finalboss-vis-tfrag/fin-leafygroundBACK.png
- maybe-finalboss-vis-tfrag/fin-leafyground.png
- maybe-firecanyon-vis-tfrag/bch-leafyground.png
- maybe-jungle-vis-tfrag/jng-leafyground-hang-2x1long.png
- maybe-jungle-vis-tfrag/jng-leafyground-hang-2x1.png
- maybe-jungle-vis-tfrag/jng-leafyground.png
- maybe-swamp-vis-pris/farthy-moss-02.png
- maybe-swamp-vis-pris/farthy-moss-03.png
- maybe-swamp-vis-pris/farthy-moss.png
- maybe-swamp-vis-shrub/swp-moss-hang.png
- maybe-swamp-vis-tfrag/swp-leafyground-hang-2x1.png
- maybe-swamp-vis-tfrag/swp-leafyground.png
- maybe-swamp-vis-tfrag/swp-moss-hang.png
- maybe-training-vis-tfrag/bch-leafyground-hang-2x1.png
- maybe-village1-vis-tfrag/vil1-jng-leafyground-hang-2x1-hitweak.png
- maybe-village1-vis-tfrag/vil1-jng-leafyground-hang-2x1.png
- maybe-village1-vis-tfrag/vil1-jng-leafyground-hitweak.png
- maybe-village1-vis-tfrag/vil1-jng-leafyground.png

## Régénérer le dump complet (8 s)
./build/decompiler/decompiler decompiler/config/jak1/jak1_config.jsonc iso_data decompiler_out \
  --config-override '{"save_texture_pngs": true, "decompile_code": false, "levels_extract": false, "extract_collision": false, "rip_streamed_audio": false}'
