# Le navigateur de mesh de debug

## Defaut cite
- 2026-07-31 : « Quand on a sélectionné un mesh, on devrait avoir la possibilité de cacher les autres — plus pratique pour marquer tous les polygones sans jouer avec la caméra au travers des autres mesh »
- 2026-07-31 : « le device est avec l'owner / indisponible »
- 2026-07-31 : « triangle sous le réticule »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-mesh-browser device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : le navigateur de mesh de debug.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
