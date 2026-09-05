# Debrider la cadence au-dela de 60 images/s

## Defaut cite
- 2026-09-05 : « on devrait pouvoir unlock le framerate, là ça lock à 60 max alors que ça pourrait ne pas être cap si le pas de temps fixe est bien fait ! Bon ça c'est un truc à faire plus tard »

## Cause connue
srpc.cpp:491 : `(s32)(1024/target_fps)` — a 120 Hz l'horloge de scene tourne a 93,75 % du reel. Trouve par cutscene-npc-flicker le 2026-09-05.

## Livrable
`target_fps` (gfx.h:99, fige a 60) devient reglable au-dela de 60 : le moteur emet `uncap_defects=N` = somme des verdicts — la logique recoit toujours 60 ticks par seconde reelle quelle que soit la cadence affichee, les animations restent lisses (meme mesure que anim-interp-low-fps), l'horloge des scenes ne derive pas (srpc.cpp:491 `(s32)(1024/target_fps)` tourne a 93,75 % a 120 Hz), et rien ne s'accelere ni ne ralentit. Zero.

## Preuve exigee
`uncap_defects == 0` dans `reports/framerate-uncap/proof.txt`.
Le proof se produit par `lib/proof_run.sh framerate-uncap device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : un reglage de cadence qui monte au-dela de 60 (90, 120, illimite) et un jeu qui reste correct.

## Hors perimetre
Ne touche pas au pas de temps fixe lui-meme, valide par l'owner le 2026-09-05.
