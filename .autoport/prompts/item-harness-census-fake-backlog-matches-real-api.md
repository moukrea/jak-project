# Les faux backlogs des recensements Linear suivent l'API reelle : deux gardes rouges depuis un changement d'API redeviennent justes

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-owner-moves-never-lost / harness-linear-archived-structures-not-recreated / harness-invisible-item-comment-has-no-capture-boilerplate / harness-linear-relinks-closed-tickets (reports/<id>/FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais.
`lib/census/harness-linear-pull-reads-archived-tickets.sh:253` et `lib/census/harness-linear-stale-map-never-fakes-an-owner-move.sh:170` : leur FakeBL n'a pas de methode `update` ; depuis a0d1b96220 (apply_owner_move / pull_owner passent par Backlog.update) la simulation leve : owner_archived_comments_lost=1 et fake_owner_moves=5, 4 controles positifs morts (rouge deja a e24135c281). Deux acquis rougissent sur une panne du banc, pas du code.

## Livrable
1. Un seul faux backlog partage, derive de l'interface reelle (ou la vraie classe sur un fichier jetable), pour tous les recensements.
2. Les deux gardes retrouvent leur verdict ; leurs controles positifs rougissent de nouveau.
3. `census_fake_api_drift` = methodes de Backlog appelees par linear_sync et absentes d'un faux ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`census_fake_api_drift == 0` dans `reports/harness-census-fake-backlog-matches-real-api/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-census-fake-backlog-matches-real-api x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
