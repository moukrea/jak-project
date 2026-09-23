# Un ticket termine ou annule que la synchro a perdu est retrouve, et les nouveaux commentaires de l'owner dessus sont lus

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »
- 2026-09-23 : « Vas-y traite comme tu l'entends »

## Cause connue
Signale par les workers de harness-linear-relink-keeps-owner-comments / harness-linear-stale-map-never-fakes-an-owner-move / harness-wake-unanswered-list-carries-its-age / harness-workers-reply-in-the-owner-thread (reports/<id>/FINDINGS.txt). Owner 23/09 : « Ok tu peux traiter le tout du coup, comme tu l'entends » (pose sur JAK-235, applique aussi a la question JAK-237 posee juste avant).
`.autoport/linear_sync.py:adopt_owner_issues` ne relie que les tickets NON clos : un ticket Done/Canceled perdu de la carte, dont l'item n'est plus envoye (ensure_ticket), n'est jamais relie ; un « ca marche toujours pas » de l'owner dessus n'est jamais tire.

## Livrable
1. La reliaison couvre aussi les tickets clos et archives.
2. `closed_tickets_unlinked` = tickets clos portant une cle d'item et absents de la carte ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`closed_tickets_unlinked == 0` dans `reports/harness-linear-relinks-closed-tickets/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-relinks-closed-tickets x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
