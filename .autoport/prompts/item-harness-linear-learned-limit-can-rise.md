# La limite de tickets apprise sur un refus Linear remonte d'elle-meme si l'owner change de plan

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
`.autoport/linear_sync.py:make_room` : une limite APPRISE sur un refus (`learned_limit` dans .linear_space.json) ne remonte jamais seule ; archivage plus agressif que necessaire jusqu'a l'effacement du fichier.

## Livrable
1. La limite apprise expire ou est re-sondee (ex. une creation reussie au-dela la releve).
2. `linear_learned_limit_stale` = limite apprise plus basse qu'une creation deja reussie ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`linear_learned_limit_stale == 0` dans `reports/harness-linear-learned-limit-can-rise/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-learned-limit-can-rise x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
