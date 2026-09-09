# Une seule matiere d'eau, eclairee par shade()

## Defaut cite
- 2026-09-09 : « faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau o… »
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. L'eau n'a aucune lumiere : env map statique environment-ocean-alphamod, aucun Fresnel, aucune profondeur (SPEC 2.1). SURF_WATER=8 existe deja dans le contrat de shade() (spec eclairage 4.2).

## Livrable
Le chunk shaders/water/water_surface.glsl (SPEC 5.6 : normales a deux cartes, Fresnel plafonne, paliers de couleur par profondeur, absorption, shade() avec SURF_WATER, SSS deux couleurs, etincelles) inclus par la clipmap ET par un programme merc2_water pour les buckets water 58/59. W0 en profondeur seule. Aucun dFdx pour construire N. Publie water_refract_front_reject et water_dfdx_sites=0. Shaders neufs dans kChunks. PREUVE : `FEATURE water-surface-material armed=1 hits=<fragments d'eau passes par shade()>` + la ligne `water_shade_calls_outside_shade=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-surface-material"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`water_shade_calls_outside_shade == 0` dans `reports/water-surface-material/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-surface-material device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la mer et la fontaine de Sandover : une lumiere, un ciel dedans, des couleurs par profondeur, un soleil en eclats.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de refraction couleur ni de reflet planaire (item 5), pas de rivage (item 3).
