# Le pas de temps fixe et l'interpolation du rendu

## Defaut cite
- 2026-08-26 : « quand le jeu va en dessous de ce qu'il est sensé tourner sur PS2, les sauts, les mouvements de caméra, etc etc ça chie un peu dans la colle et ça casse le gameplay (skips, camera jumps, sauts trop courts...) je sais qu'OpenGoal a déjà du travail pour ça, mais j'ai l'impression que c'est pas bon [...] On devrait en fait faire de l'interpolation VERSUS l'original histoire de mitiger tous les problèm… »
- 2026-08-26 : « Ça permettrait de tourner sans réel souci à des framerates inférieurs (imaginons qu'on aille all in avec les settings PBR, realtime lighting, grass etc etc... mais que ça permette que de maintenir un framerate à 25FPS sur le device concerné, faudrait pas que ça casse le gameplay ni le confort de jeu) et dans l'autre sens, imaginons qu'on puisse aller au delà de 60FPS (75, 90, 120, etc... variable… »
- 2026-08-31 : « Fixed timestep : Aucun crash mais difficile a valider... ca a l'air bon »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh fixed-tick-interpolation device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Fixed timestep, puis joue autour de 20 images/s.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
