# Un projet, une etiquette ou une vue Linear archives par l'owner ne sont jamais recrees en double

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »

## Cause connue
Signale par les workers de harness-owner-secret-never-copied-in-clear / harness-linear-pull-reads-archived-tickets / harness-linear-census-reads-archived-tickets / harness-supervisor-relay-command (reports/<id>/FINDINGS.txt). Owner 23/09 (JAK-235) : « Ok tu peux traiter le tout du coup, comme tu l'entends ».
`.autoport/linear_sync.py:615,632,643` (ensure_projects, ensure_label, ensure_view) lisent `team{projects}`, `team{labels}`, `customViews` sans `includeArchived` : un element archive est invisible et serait RECREE. Aussi : une etiquette « A lire » posee sur un ticket archive y reste (enumerations 1029,1378,1390,1718), sans effet visible.

## Livrable
1. Les trois lectures voient les archives et respectent le choix de l'owner (pas de recreation).
2. `linear_structures_duplicated` ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`linear_structures_duplicated == 0` dans `reports/harness-linear-archived-structures-not-recreated/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-archived-structures-not-recreated x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
