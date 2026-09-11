# Debrider la cadence au-dela de 60 images/s

## Defaut cite
- 2026-09-05 : « on devrait pouvoir unlock le framerate, là ça lock à 60 max alors que ça pourrait ne pas être cap si le pas de temps fixe est bien fait ! Bon ça c'est un truc à faire plus tard »
- 2026-09-07 : « pour le framerate, plutôt qu'un slider faudrait des choix comme 30, 45, 60, 75, 90, 120, 240, Illimité. Mais j'ai l'impression qu'on est cap à 90FPS car en désactivant tout, framerate set à 240, sur la scène d'intro naughty god hauteur 90FPS constant, pas plus c'est étrange. Et le FPS cible du Dynamic résolution scaling devrait ajuster les options de son slider en fonction du max fps, aucun sens d… »
- 2026-09-07 : « demerdes toi pour HDR/Blanc brûlés, c'est la top priorité, la brise et la cadence c'est sensé être tout en bas de la pile, je t'ai jamais dit de reprendre ça ! La top priorité c'est la refonte du lighting, commençant par reprendre le HDR/blancs brûlés ! »

## Cause connue
srpc.cpp:491 : `(s32)(1024/target_fps)` — a 120 Hz l'horloge de scene tourne a 93,75 % du reel. Trouve par cutscene-npc-flicker le 2026-09-05.

## Livrable
`uncap_defects` = 0, preuve sur appareil. Acquis a NE PAS CASSER : la logique recoit 60 pas par seconde reelle quelle que soit la cadence affichee, l'horloge des scenes ne derive pas, rien ne s'accelere. TROIS exigences de l'owner s'ajoutent :
  (a) le reglage devient une LISTE DE CHOIX — 30, 45, 60, 75, 90, 120, 240, Illimite — pas un curseur.
  (b) `uncap_ceiling_hz` publie le plafond REELLEMENT atteint : l'owner mesure 90 img/s constant a l'ecran d'intro avec la consigne a 240 et tout le reste eteint. Nommer ce qui plafonne (vsync, presentation, composition Android) ou prouver que 240 est atteint.
  (c) la cible de l'echelle de rendu dynamique s'ADAPTE au plafond choisi : `uncap_dynscale_target_max` suit la cadence maximale, il ne doit plus etre possible de viser 60 quand on a choisi 240.

## Preuve exigee
`uncap_defects == 0` dans `reports/framerate-uncap/proof.txt`.
Le proof se produit par `lib/proof_run.sh framerate-uncap device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : un reglage de cadence qui monte au-dela de 60 (90, 120, illimite) et un jeu qui reste correct.

## Hors perimetre
Ne touche pas au pas de temps fixe lui-meme, valide par l'owner le 2026-09-05.
