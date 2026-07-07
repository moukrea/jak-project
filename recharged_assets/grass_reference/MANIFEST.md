# Jak 1 — textures d'HERBE AU SOL (terrain), toutes occurrences, pas de dédup
Sélection VISUELLE (curation des 1568 textures de terrain via pré-filtre teinte-herbe + inspection).
Exclu : touffes/shrubs (grassclump/wallgrass/beachgrass sprites), canopées, palmes, mousses suspendues.

## Sol herbeux (par tpage d'origine)
- village2-vis-tfrag/v2-grass-ground-hirez.png
- rolling-vis-tfrag/v2-grass-ground-hirez.png
- village2-vis-tfrag/v2-grass-ground-hirez-fringe.png
- rolling-vis-tfrag/rol-grass-ground-hirez.png
- rolling-vis-tfrag/rol-grass-ground-hirez-fringe.png
- rolling-vis-tfrag/rol-grass-fringe.png
- rolling-vis-tfrag/rol-grass-fringe-large.png
- training-vis-tfrag/tra-grass.png
- training-vis-tfrag/bch-grassfringe.png
- ogre-vis-tfrag/ogr-vil2grass.png
- ogre-vis-tfrag/ogr-vil2grassfringe.png
- jungle-vis-tfrag/jng-leafyground.png
- jungle-vis-tfrag/jng-leafyground-hang-2x1.png
- jungle-vis-tfrag/jng-leafyground-hang-2x1long.png
- village1-vis-tfrag/vil1-jng-leafyground.png
- village1-vis-tfrag/vil1-jng-leafyground-hitweak.png
- village1-vis-tfrag/vil1-jng-leafyground-hang-2x1.png
- village1-vis-tfrag/vil1-jng-leafyground-hang-2x1-hitweak.png
- firecanyon-vis-tfrag/bch-leafyground.png
- beach-vis-tfrag/bch-leafyground.png
- beach-vis-shrub/bch-leafyground.png
- beach-vis-tfrag/bch-leafyground-hang-2x1.png
- training-vis-tfrag/bch-leafyground-hang-2x1.png
- swamp-vis-tfrag/swp-leafyground.png
- swamp-vis-tfrag/swp-leafyground-hang-2x1.png
- finalboss-vis-tfrag/fin-leafyground.png
- finalboss-vis-tfrag/fin-leafygroundBACK.png
- finalboss-vis-tfrag/fin-leafygroundBACKdirt.png
- common/vil3-medres-ogr-mossygrass.png
- common/vil1-medres-grass-color.png
- common/vil1-medres-grass.png
- jungle-vis-tfrag/jng-path1-4x4.png

## borderline/ (végétation au sol non-herbe: parterres fleuris — juge toi-même)
- borderline/village1-vis-tfrag--vil-rosebed.png
- borderline/swamp-vis-tfrag--swp-tempthorn.png

## Régénérer le dump complet des 4002 textures (8 s)
./build/decompiler/decompiler decompiler/config/jak1/jak1_config.jsonc iso_data decompiler_out \
  --config-override '{"save_texture_pngs": true, "decompile_code": false, "levels_extract": false, "extract_collision": false, "rip_streamed_audio": false}'
