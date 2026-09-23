# La synchro sait que l'autre equipe de l'espace Linear (JAU) partage la limite de tickets, et n'archive jamais ses tickets sans le dire

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
`.autoport/linear_sync.py` : l'espace compte une autre equipe (JAU-*, archivee en partie par le superviseur le 23/09) qui partage la limite de 250 ; la synchro n'archive ses tickets clos qu'apres les notres. Si JAU grossit, nos creations peuvent etre refusees pour la place d'une autre equipe.

## Livrable
1. Publier la place prise par chaque equipe.
2. Archiver une equipe etrangere seulement en dernier recours, en le NOMMANT dans le journal et au ticket.
3. `linear_foreign_archive_unnamed` = tickets d'une autre equipe archives sans trace ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`linear_foreign_archive_unnamed == 0` dans `reports/harness-linear-space-counts-other-teams/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-space-counts-other-teams x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
