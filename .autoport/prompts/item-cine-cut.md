# Les coupes de camera des cinematiques qui glissent au lieu de couper

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Ouvert en juin, jamais pris. La logique de coupe est partagee avec x86 : le defaut peut s'y reproduire, ce qui rendrait la preuve possible au clavier.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh cine-cut x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les changements de plan d'une cinematique : ils doivent couper, pas glisser.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
