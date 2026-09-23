# Le journal des tampons de lecture du superviseur est purge au lieu de grossir sans fin

## Defaut cite
- 2026-09-23 : « Ok mais codex c'est pas prioritaire du tout, ça sera codex lui même qui traitera quand il voudra, vraiment en bas du bas de la pile »

## Cause connue
Signale par le worker de harness-supervisor-reader-must-be-the-supervisor (reports/.../FINDINGS.txt), non corrige ; l'owner a dit « Ok » le 23/09 (JAK-198).
`.autoport/logs/supervisor-seen.jsonl` : une ligne par prompt de chaque session, sans rotation (~150 lignes/jour).

## Livrable
1. Rotation bornee (taille ou age), la derniere decision toujours conservee.
2. `supervisor_seen_log_unbounded` = journal au-dela de la borne ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`supervisor_seen_log_unbounded == 0` dans `reports/harness-supervisor-seen-log-rotates/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-supervisor-seen-log-rotates x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
