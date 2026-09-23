# Un commentaire de l'owner sur un ticket archive est lu, et un chantier ouvert qu'il archive lui-meme est pris comme sa decision

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
`.autoport/linear_sync.py:pull_owner` ne demande pas `includeArchived` : un commentaire pose sur un ticket ARCHIVE n'est jamais recopie, et un ticket de chantier ouvert que l'owner archive a la main n'est pas lu comme une decision. D'autant plus probable que la synchro archive maintenant d'elle-meme. Meme famille : owner_sla poste une alerte via post_comment sur un ticket d'origine archive sans le desarchiver (post_failed en boucle).

## Livrable
1. Le tirage lit aussi les tickets archives (commentaires owner + archivage fait par l'owner).
2. Toute ecriture sur un ticket archive le desarchive d'abord, ou est nommee.
3. `owner_archived_comments_lost` = commentaires owner sur ticket archive non recopies + archivages owner non appliques ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`owner_archived_comments_lost == 0` dans `reports/harness-linear-pull-reads-archived-tickets/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-pull-reads-archived-tickets x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
