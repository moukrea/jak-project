# La verification de coherence Linear continue apres un ticket en erreur

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
`.autoport/linear_sync.py:--check` : la boucle des orphelins (issueUpdate Canceled + commentaire) n'est pas gardee : un ticket qui refuse arrete tout `--check`.

## Livrable
1. Chaque ticket est traite dans sa garde ; les echecs sont comptes et nommes.
2. `linear_check_aborted` = passages --check interrompus par un ticket ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`linear_check_aborted == 0` dans `reports/harness-linear-check-survives-a-bad-ticket/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-check-survives-a-bad-ticket x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
