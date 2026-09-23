# Ce que DIRECTIVES promet est fait par du code : le rapport perime est refuse, et DIRECTIVES.md suit le checkpoint

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-owner-moves-never-lost / harness-linear-archived-structures-not-recreated / harness-invisible-item-comment-has-no-capture-boilerplate / harness-linear-relinks-closed-tickets (reports/<id>/FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais.
`lib/directives.py:block` annonce « Le validateur recalcule la version et refuse un rapport perime » : aucun code ne le fait (seul supervisor_cost.py cherche la sous-chaine). `orchestrator.py:1703` (_HARNESS_STATE_FILES contient DIRECTIVES.md) : le checkpoint n'emporte jamais DIRECTIVES.md ; un item qui doit le modifier le commite a la main par chemin.

## Livrable
1. Implementer le refus du rapport perime OU retirer la promesse.
2. DIRECTIVES.md suit le checkpoint quand l'item a le droit de le modifier.
3. `directives_unkept_promises` ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`directives_unkept_promises == 0` dans `reports/harness-directives-promises-are-implemented/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-directives-promises-are-implemented x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
