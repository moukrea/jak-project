# Le jeu ne charge plus une sauvegarde

## Defaut cite
- 2026-08-30 : « le jeu ne charge plus »
- 2026-08-30 : « pour le chargement, le look est nickel bravo... par contre quand je charge ma sauvegarde a Geyser Rock... bah sur la fin l'animation freeze, puis reprend et le jeu crash complet... je peux meme plus charger une partie il semblerait »
- 2026-08-30 : « quand je charge ma sauvegarde a Geyser Rock... sur la fin l'animation freeze, puis reprend et le jeu crash complet... je peux meme plus charger une partie »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh loadgate-crash-regression device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : charge ta sauvegarde de Geyser Rock.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
