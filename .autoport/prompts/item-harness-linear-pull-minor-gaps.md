# Petits trous du tirage Linear : pagination des tickets hors backlog, doublons d'anciens retours, liens bloques jamais retentes

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »
- 2026-09-23 : « Vas-y traite comme tu l'entends »

## Cause connue
Signale par les workers de harness-owner-secret-never-copied-in-clear / harness-linear-pull-reads-archived-tickets / harness-linear-census-reads-archived-tickets / harness-supervisor-relay-command (reports/<id>/FINDINGS.txt). Owner 23/09 (JAK-235) : « Ok tu peux traiter le tout du coup, comme tu l'entends ».
Signale par les workers de harness-linear-relink-keeps-owner-comments / harness-linear-stale-map-never-fakes-an-owner-move / harness-wake-unanswered-list-carries-its-age / harness-workers-reply-in-the-owner-thread (reports/<id>/FINDINGS.txt). Owner 23/09 : « Ok tu peux traiter le tout du coup, comme tu l'entends » (pose sur JAK-235, applique aussi a la question JAK-237 posee juste avant).
(1) `linear_sync.py:1154` pull_labeled_unmapped : 50 commentaires max, un pouce ou retour enfoui est invisible. (2) pull_owner/have_ids : dedoublonnage seulement par `via.comment` : un ancien retour recopie sans `via` (ou absorbe par le superviseur, JAK-189) est recopie une 2e fois si son ticket est relie. (3) sync_relations : une relation refusee parce qu'un ticket est archive est nommee puis consideree posee, jamais retentee.

## Livrable
1. Paginer ; 2. dedoublonner aussi par texte+date d'un retour sans `via` ; 3. retenter (ou desarchiver) une relation refusee.
4. `linear_pull_minor_gaps` = somme des trois ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`linear_pull_minor_gaps == 0` dans `reports/harness-linear-pull-minor-gaps/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-pull-minor-gaps x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
