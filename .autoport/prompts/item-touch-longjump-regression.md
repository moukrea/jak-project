# Le long jump au tactile qui ne part plus

## Defaut cite
- 2026-08-04 : « Pour le long jump j'ai pas de manette, mais faut faire en sorte qu'avec le tactile ça fonctionne aussi ! **Ça fonctionnait avant** donc il n'y a pas de raisons que ça fonctionne plus ! »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh touch-longjump-regression device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : au tactile : avance + R1/R2 + saut, tu dois partir en long jump.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
