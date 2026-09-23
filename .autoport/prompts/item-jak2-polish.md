# Les finitions de Jak II (mapping L1/R1, cadrage, menus, particules)

## Defaut cite
- 2026-09-17 : « En vrai c'est toujours pertinent qu'il soit là ce ticket ? On s'en cogne un peu non ? On a fait rouler Jak II, ça marchottais un peu mais bof.. et on a parké ça… Mais de toutes façons on est all in sur Jak 1, donc bon… »
- 2026-09-17 : « Bah du coup la colonne a arbitrer ne contient plus rien du tout, si ? »
- 2026-09-17 : « Bah du coup comment ça se fait que tu m'a dit le contraire… à éviter ce genre de conneries ! »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh jak2-polish device` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
