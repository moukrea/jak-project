# Le jeu cesse de payer 6,8 Mo de VRAM pour un chemin de halo qui ne tourne jamais

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
MESURE DU 11/09 (reports/hdr-glow-range/proof.txt, appareil eae4df44). `GlowRenderer` est construit en membre de `Sprite3` sur jak1 (Sprite3.h:82) et alloue ses SIX cibles — sonde plus cinq reductions — alors que `render_jak1` ne l'appelle JAMAIS : sur 9 091 images de sprites, `hdr_glow_flush_calls` = 0, `hdr_glow_dma_enters` = 0, `hdr_glow_sprites_submitted` = 0, pendant que 16 385 088 sprites 2D et 204 397 distorteurs passaient par les deux autres chemins. Son unique appelant est `render_jak2` (Sprite3.cpp:1084), et `grep sprite-glow goal_src/jak1/` rend 0 contre 178 en jak2. Cout mesure : `hdr_glow_stage_bytes` = 6 822 400 o quand le maitre Recharged est ON, 3 411 200 o quand il est OFF. Sur un appareil qui plafonne a ~44 img/s et que le tueur de memoire visite, c'est de la VRAM payee pour rien.

## Livrable
`glow_targets_waste_bytes` = 0 : sur jak1, aucun octet n'est alloue pour les cibles du halo.
1. La construction est conditionnee au JEU, pas supprimee : jak2 garde son chemin intact. Publier le jeu observe a cote du compte d'octets.
2. Publier `glow_targets_bytes_before` et `glow_targets_bytes_after` sur la MEME course : un zero apres sans un non-zero avant ne prouve rien.
3. Le chemin jak2 reste constructible : publier un temoin qui dit que la construction A LIEU quand le jeu est jak2, sinon l'item a seulement debranche du code sans preuve de reversibilite.
4. Rien d'autre ne change de comportement : `hdr_glow_sprite_render_calls` reste non nul et les deux chemins vivants (`hdr_glow_other_2d_sprites`, `hdr_glow_other_aux_sprites`) gardent des comptes du meme ordre qu'avant.

## Preuve exigee
`glow_targets_waste_bytes == 0` dans `reports/glow-targets-not-built-on-jak1/proof.txt`.
Le proof se produit par `lib/proof_run.sh glow-targets-not-built-on-jak1 device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est de la VRAM rendue, aucun pixel ne bouge..

## Hors perimetre
Ne touche pas au halo que l'owner VOIT : il vient de `render_2d_group0` (parts 411/412 du feu, 1971/1968 du portail) et du distorteur d'aux-list. Ne supprime aucun fichier jak2.
