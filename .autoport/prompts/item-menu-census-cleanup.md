# Le menu contient des options inutiles ou incomprehensibles

## Defaut cite
- 2026-08-31 : « je vois que des options sont un peu chelou ou carrement inutilisées... recharged assets VS HD texture pack ? WTF. Modern Materials c'est quoi ? PBR test preset et PBR isolate c'est quoi ? »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh menu-census-cleanup x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options : les lignes qui ne servent a rien doivent avoir disparu.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
