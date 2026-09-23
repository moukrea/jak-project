# Le tirage Linear lit tous les commentaires neufs d'un ticket, meme plus de 50 entre deux passages

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
`.autoport/linear_sync.py:pull_owner` (requete `comments { nodes ... }`) : page par defaut de 50, plus recents d'abord, sans pagination ; plus de 50 commentaires neufs entre deux passages = les plus anciens jamais recopies (improbable a 30 s, possible apres une coupure).

## Livrable
1. Paginer jusqu'au dernier commentaire deja recopie.
2. `owner_comments_beyond_page` = commentaires owner neufs au-dela de la premiere page non recopies ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`owner_comments_beyond_page == 0` dans `reports/harness-linear-pull-paginates-comments/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-pull-paginates-comments x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
