# Restes des dependances mortes : un archivage fait par l'owner redirige aussi ses dependants, et le statut machine compte les chantiers geles

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de harness-dead-dependency-is-named-never-silent (reports/.../FINDINGS.txt), non corrige ; ouvert sous la delegation de l'owner pour les signalements de harnais.
(1) `linear_sync.py:1045` : l'archivage venu de Linear ne pose jamais `superseded_by` : aucun dependant n'est redirige, seul le lint le nomme ensuite ; une archive de l'owner gele sa descendance jusqu'a ce que quelqu'un lise le lint. (2) `autoport:29 cmd_status --json` ne porte ni le nombre de chantiers geles ni prenables/ouverts : watch.py et le digest restent aveugles a une file gelee. (3) `lighting-unify` (valide) depend encore de lighting-census (archive) : sans cout tant qu'il ne rouvre pas.

## Livrable
1. Un archivage owner d'un item dont d'autres dependent : les dependants sont nommes au superviseur (reveil) et a l'owner (commentaire), et redirigeables en une commande.
2. `status --json` porte `game_open`, `game_takeable`, `frozen`.
3. Nettoyer les dependances vers archive des items valides.
4. `dead_dependency_leftovers` ; doit valoir 0.
CONTROLE POSITIF + CONTROLE NEGATIF.

## Preuve exigee
`dead_dependency_leftovers == 0` dans `reports/harness-dead-dependency-leftovers/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-dead-dependency-leftovers x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
