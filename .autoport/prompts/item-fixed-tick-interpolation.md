# Le pas de temps fixe et l'interpolation du rendu

## Defaut cite
- 2026-08-26 : « Ça permettrait de tourner sans réel souci à des framerates inférieurs (imaginons qu'on aille all in avec les settings PBR, realtime lighting, grass etc etc... mais que ça permette que de maintenir un framerate à 25FPS sur le device concerné, faudrait pas que ça casse le gameplay ni le confort de jeu) et dans l'autre sens, imaginons qu'on puisse aller au delà de 60FPS (75, 90, 120, etc... variable… »
- 2026-08-31 : « Fixed timestep : Aucun crash mais difficile a valider... ca a l'air bon »
- 2026-09-03 : « je trouve les animations très jittery (un autre chantier si je dis pas de bêtises que j'ai auparavant lié au fixed time truc machin ou le gameplay n'est plus tied au framerate... d'ailleurs c'est très jittery quelque soit le framerate, 60 FPS comme 15 fps comme 45... etc. »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh fixed-tick-interpolation x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Fixed timestep, puis joue autour de 20 images/s.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
