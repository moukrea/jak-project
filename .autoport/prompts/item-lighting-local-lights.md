# Les lampes, torches et laves eclairent enfin

## Defaut cite
- 2026-09-03 : « les sources de lumiere en sus du soleil/lune sont d'autant plus importantes a valoriser »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Zero lumiere ponctuelle, alors que la donnee les nomme : 62 prototypes candidats, 1192 instances, dont 16 jumeaux -glow.mb qui SONT les surfaces emissives authorees. SPEC 5.3.8 et annexe C.

## Livrable
light_emitters.txt cote assets (un verdict par prototype, residu publie), extraction hors ligne, grille de clusters remplie sur le fil de rendu, vacillement branche sur update-mood-flames. SPEC 4.9 et 5.7.1. PREUVE : `FEATURE lighting-local-lights armed=1 hits=<pixels eclaires par au moins une lumiere locale>` + la ligne `lights_unjudged=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-local-lights"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`lights_unjudged == 0` dans `reports/lighting-local-lights/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-local-lights device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sandover a la nuit tombee sous un lampadaire, les torches de la neige, la lave du lavatube.

## Hors perimetre
Tout ce qui n'est pas cet item. Le mode ORIGINE (master OFF) doit rester bit-identique : la garde de reference de lighting-census le verifie. Ne touche a aucune feature validee. Pas de mesure visuelle. Pas d'ombre par lumiere locale a cet item.
