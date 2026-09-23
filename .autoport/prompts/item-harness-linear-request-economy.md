# La synchro Linear depense moins de requetes et ne garde pas d'identifiants perimes

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-owner-moves-never-lost / harness-linear-archived-structures-not-recreated / harness-invisible-item-comment-has-no-capture-boilerplate / harness-linear-relinks-closed-tickets (reports/<id>/FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais.
(1) `--comment` relance ensure_label x4 + ensure_view x3 (~11 requetes, dont 3 sous la cle personnelle) au lieu du cache _ids. (2) mp['_ids'] n'est jamais re-verifie : une etiquette archivee apres mise en cache reste utilisee. (3) push_existing : 3 requetes de plus par changement d'etat (historique avant/etat/historique apres), non mesure en vrai. (4) `--no-pull` : un ticket deplace hors passage est differe a chaque passage (« ETAT NON ECRASE » repete). (5) aucune ligne « (historique : » dans le journal : le terme V3 de stale-map n'a rien a lire. (6) ensure_* en first:250 sans pagination (loin : 10/7/6). (7) sans LINEAR_API_KEY, aucune vue n'est plus creee. (8) linear_sync.py:1079 : un doublon clos d'un item deja relie n'est pas relie.

## Livrable
1. Mesurer AVANT les requetes par passage et par commentaire.
2. Cache verifie (TTL ou sur erreur), --comment sans ensure_*.
3. `linear_requests_per_comment` publie ; `linear_request_waste` = requetes evitables sur un passage type ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`linear_request_waste == 0` dans `reports/harness-linear-request-economy/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-request-economy x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
