# Nommer chaque goutte d'eau du jeu avant de la refaire

## Defaut cite
- 2026-09-09 : « faire une spec de l'enfer pour l'eau, que ce soit la mer ou les points d'eau genre marres, flaques, fontaines, etc... Faudrait un truc moderne ou l'eau rend vraiment moderne, avec tous les effets attendus d'un jeu moderne mais en restant dans un esprit stylisé of course. Quand on marche dans l'eau ou tombe dedans, faut de la déformation (via tesselation je suppose) que ça soit impressionant, des c… »
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. La nappe des cascades est de la geometrie de niveau sans classe GOAL (SPEC 2.4) ; 48 looks water-anim et 102 entites recensees (SPEC 2.2, annexe A) ; `lod-force-ocean` est un reglage MORT sans consommateur (SPEC 2.5).

## Livrable
Les 48 looks recoivent une matiere (water_overrides.txt), les prototypes TIE/tfrag a texture d'eau un verdict (water_falls.txt : CHUTE/JET/NAPPE/EXCLU, aucun implicite), les 10 cartes d'ocean et leurs 36 spheres exportees, `gpu_ms_ocean` de reference a 4 vantages, l'outil tools/water_bake cree (inventaire seul), `lod-force-ocean` retire. SPEC 5.7, 5.8, 9 item 0. PREUVE : `FEATURE water-census armed=1 hits=<prototypes et looks d'eau classes>` + la ligne `water_proto_unassigned=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("water-census"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`water_proto_unassigned == 0` dans `reports/water-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-census x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : c'est un inventaire machine ; owner_test=false.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Aucun rendu ne change : cet item ne touche pas un pixel.
