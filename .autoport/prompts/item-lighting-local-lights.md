# Les lampes, torches et laves eclairent enfin

## Defaut cite
- 2026-09-03 : « les sources de lumiere en sus du soleil/lune sont d'autant plus importantes a valoriser »
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Zero lumiere ponctuelle, alors que la donnee les nomme : 62 prototypes candidats, 1192 instances, dont 16 jumeaux -glow.mb qui SONT les surfaces emissives authorees. SPEC 5.3.8 et annexe C.

## Livrable
light_emitters.txt cote assets (un verdict par prototype, residu publie), extraction hors ligne, grille de clusters remplie sur le fil de rendu, vacillement branche sur update-mood-flames. SPEC 4.9 et 5.7.1. PREUVE : `FEATURE lighting-local-lights armed=1 hits=<pixels eclaires par au moins une lumiere locale>` + la ligne `lights_unjudged=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-local-lights"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`lights_unjudged == 0` dans `reports/lighting-local-lights/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-local-lights device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sandover a la nuit tombee sous un lampadaire, les torches de la neige, la lave du lavatube.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas d'ombre par lumiere locale a cet item.

## Appris par lighting-bake (24/09, reports/lighting-bake/FINDINGS.txt)
- `common/custom_data/LightBake.cpp` (version 1) ecrit PROBES, LIGHTS, LIGHTVIS VIDES (count=0) : sondes, emetteurs et visibilite par lumiere ne sont PAS encore cuits. A produire ici.
- Le compagnon derive part dans le pack de l'APK via `android/build_custom_pack.sh`, pas `scripts/package_game_assets.sh` (SPEC 5.6 perimee sur ce point).
