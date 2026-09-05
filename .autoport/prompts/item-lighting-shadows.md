# Deux astres, deux jeux d'ombres, et les acteurs qui en projettent

## Defaut cite
- 2026-09-03 : « quand les deux overlap... Bah ca doit etre pris en compte, ca l'est pour nous aussi quand on a la lune et le soleil visibles en meme temps ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Une seule cascade attribuee a « l'astre le plus haut », avec fondu et EMA pour cacher une bascule qui n'a pas lieu d'etre : les deux astres sont leves ENSEMBLE 3 h 30 par jour. Et aucun acteur n'entre dans la carte. SPEC 3.4 et 4.8.

## Livrable
Atlas unique tuile, cascades stabilisees pour l'astre dominant, une tuile pour le second, les acteurs dans la passe de profondeur avec leur maillage skinne, ombres de contact sur la prepasse. L'aplat PS2 reste le repli et le mode Original. SPEC 4.8. PREUVE : `FEATURE lighting-shadows armed=1 hits=<pixels de sol ombres par un acteur>` + la ligne `shadow_caster_classes=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-shadows"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`shadow_caster_classes == 4` dans `reports/lighting-shadows/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-shadows device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : l'ombre de Jak et des PNJ au sol, et le matin quand les deux astres sont leves.

## Hors perimetre
Tout ce qui n'est pas cet item. Le mode ORIGINE (master OFF) doit rester bit-identique : la garde de reference de lighting-census le verifie. Ne touche a aucune feature validee. Pas de mesure visuelle. L'aplat PS2 de shadow-geo n'est pas retire ici : il devient le repli et le mode original (decision owner 2026-09-03). Son remplacement en champ proche est lighting-actors.
