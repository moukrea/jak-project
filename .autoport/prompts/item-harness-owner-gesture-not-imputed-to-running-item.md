# Un geste de l'owner pendant un essai (ticket Linear adopte, etc.) n'est plus impute au chantier qui tourne ; un ticket owner adopte n'est plus classe « jeu » d'office

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-owner-moves-never-lost / harness-linear-archived-structures-not-recreated / harness-invisible-item-comment-has-no-capture-boilerplate / harness-linear-relinks-closed-tickets (reports/<id>/FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais.
`lib/suite_gate.py` impute a l'essai en cours un rouge ne d'un GESTE DE L'OWNER (ticket Linear adopte dans backlog.yaml, JAK-265) : l'essai 2 de harness-invisible-item-comment-has-no-capture-boilerplate a ete refuse pour deux tests. `linear_sync.py:adopt_owner_issues` classe tout ticket adopte `code_scope: jeu` en dur, meme un sujet de harnais (JAK-265 = profils de modeles).

## Livrable
1. suite_gate distingue un rouge ne d'une ecriture du backlog par linear_sync/superviseur (auteur, horodatage) et ne l'impute pas.
2. Un ticket adopte recoit `code_scope: a-cadrer`, que l'orchestrateur ne prend pas tant que le superviseur ne l'a pas cadre.
3. `owner_gesture_misimputed` ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`owner_gesture_misimputed == 0` dans `reports/harness-owner-gesture-not-imputed-to-running-item/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-gesture-not-imputed-to-running-item x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
