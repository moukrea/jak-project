# Des proprietes PBR par matiere, pas deux curseurs globaux

## Defaut cite
- 2026-08-31 : « defaut IDENTITE = enregistrement non applique invisible »
- 2026-08-31 : « j'ai l'impression que ça prend pas en compte les propriétés individuelles de Recharged assets et que ça applique le PBR uniquement aux 7 textures PBR qui étaient dans le projet depuis un bail et que ça ignore les autres »
- 2026-08-31 : « ça applique le PBR uniquement aux 7 textures qui étaient dans le projet depuis un bail et ça ignore les autres »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh pbr-per-material device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > PBR Materials, puis regarde le sable, la pierre et le tissu de Sandover.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
