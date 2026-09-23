# Un commentaire de l'owner poste pendant que la synchro a perdu la trace d'un ticket est quand meme recopie

## Defaut cite
- 2026-09-23 : « Ok »

## Cause connue
Signale par le worker de harness-linear-sync-never-creates-two-tickets-for-one-item (reports/.../FINDINGS.txt), non corrige ; l'owner a dit « Ok » pour l'ouvrir le 23/09 (JAK-229).
`.autoport/linear_sync.py:ensure_ticket` (ticket retrouve dans Linear apres perte de la carte) pose `pulled_at = maintenant` : un commentaire de l'owner poste entre la perte de carte et la reliaison n'est jamais recopie. Ne se produit que si le cliche de la carte est aussi perdu.

## Livrable
1. A la reliaison, `pulled_at` repart de la date de creation du ticket (ou du dernier commentaire deja recopie dans owner_feedback), jamais de maintenant.
2. `owner_comments_skipped_on_relink` = commentaires owner non recopies apres reliaison ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`owner_comments_skipped_on_relink == 0` dans `reports/harness-linear-relink-keeps-owner-comments/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-relink-keeps-owner-comments x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
