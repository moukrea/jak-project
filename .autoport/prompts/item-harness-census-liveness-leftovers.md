# Restes des recensements : les compteurs qui attendent 0 sont eux aussi juges vivants, et le suivi de source suit le flux

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de harness-census-seeds-anchored-structurally, non corrige ; ouvert sous la delegation de l'owner pour les signalements de harnais.
(1) une aiguille qui transite par un TUPLE de boucle echappe au recensement des ancres ; (2) la « source lue » est un tracage par NOMS, insensible au flux ; (3) `grep -c/-q/-l` et `tok_count/ws_count` qui attendent 0 : leur VIVANCE n'est pas jugee (un compteur mort qui rend 0 passe pour un succes) ; (4) le terme G de harness-archived-census-controls-are-alive ne lit que les blocs python.

## Livrable
1. Traiter les quatre ; en priorite (3) : un compteur qui attend 0 doit prouver qu'il PEUT rendre non nul (controle positif seme).
2. `census_liveness_leftovers` ; doit valoir 0.
CONTROLE POSITIF + CONTROLE NEGATIF.

## Preuve exigee
`census_liveness_leftovers == 0` dans `reports/harness-census-liveness-leftovers/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-census-liveness-leftovers x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
