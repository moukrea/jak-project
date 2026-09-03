# La brise dans les arbres et les buissons

## Defaut cite
- 2026-08-31 : « joue=1 et amplitude 0 »
- 2026-08-31 : « ondulation sous l'eau »
- 2026-08-31 : « tous ne sont pas pris »

## Cause connue
L'anneau de vent a 48 slots morts sur 64 (index d'ecriture multiplie par `time-adjust-ratio`, index de lecture brut) : le ressort lit du vide trois images sur quatre. Le vent TIE est un affaissement lent VOULU ; le defaut du port est le pas de temps, qui avance par image RENDUE. La vegetation statique se classe par `TIE_PROTO_NAMES`, jamais par la geometrie.

## Livrable
La brise NATIVE conforme au chemin stock (option eteinte), le pivot des buissons a leur base, la couverture par instance dessinee complete, et un spectre de brise, pas une seule frequence.

## Preuve exigee
`wind_divergent_pairs == 0` dans `reports/foliage-wind/proof.txt`.
Le proof se produit par `lib/proof_run.sh foliage-wind x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : les palmiers et les buissons de Sandover, option de brise eteinte PUIS allumee.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
