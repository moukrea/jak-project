# Les garde-fous de lecture des tickets archives redetectent reellement : leurs controles ne visent plus un code reecrit depuis

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »
- 2026-09-23 : « Vas-y traite comme tu l'entends »

## Cause connue
Signale par les workers de harness-linear-relink-keeps-owner-comments / harness-linear-stale-map-never-fakes-an-owner-move / harness-wake-unanswered-list-carries-its-age / harness-workers-reply-in-the-owner-thread (reports/<id>/FINDINGS.txt). Owner 23/09 : « Ok tu peux traiter le tout du coup, comme tu l'entends » (pose sur JAK-235, applique aussi a la question JAK-237 posee juste avant).
`.autoport/lib/census/harness-linear-pull-reads-archived-tickets.sh:415-416` : le controle C+_statique seme sa graine sur `    return on_ticket(L, issue_id, lambda: L.q('mutation($i:CommentCreateInput!)`, ligne reecrite par ef3327822c (harness-owner-test-requires-a-capture) en `r = on_ticket(...)` : le controle est MORT, la porte ne peut plus rougir. Et `lib/census/harness-linear-census-reads-archived-tickets.sh:45` : la regex SITE accuse la chaine de dispatch `"team(id:$t){issues("` du faux Linear de lib/census/harness-linear-relink-keeps-owner-comments.sh:186 (faux positif).

## Livrable
1. Le controle positif est seme sur une forme STRUCTURELLE (noeud d'appel, AST), pas sur un litteral de ligne (voir feedback_another_items_witness_pins_the_literal_you_want_to_factor).
2. Le faux Linear d'un recensement n'est plus accuse.
3. `archived_census_dead_controls` = controles positifs qui ne rougissent plus + faux positifs ; doit valoir 0. Recenser AUSSI les autres census/*.sh dont le controle vise un litteral de ligne.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`archived_census_dead_controls == 0` dans `reports/harness-archived-census-controls-are-alive/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-archived-census-controls-are-alive x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
