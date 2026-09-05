# Pre-calculer ce qui peut l'etre au lieu de le refaire a chaque chargement

## Defaut cite
- 2026-08-26 : « le logo apparait bien apres le son qui est sense etre la au moment de son apparition [...] aucun probleme sur x86, Redmi ou Honor »
- 2026-08-26 : « les textures HD rechargees, le PBR »
- 2026-08-26 : « tout ce qu'on peut pre-computer devrait l'etre au lieu de prendre du temps CPU/GPU c'est debile. Ca profitera a tout materiel ! Of course les trucs real time, c'est different, mais ce qui peut etre fait en aval devrait l'etre ! »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh precompute-deterministic-bake device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : le temps de chargement d'un niveau.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
