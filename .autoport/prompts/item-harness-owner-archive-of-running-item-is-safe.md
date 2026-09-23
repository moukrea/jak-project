# Si l'owner archive un chantier pendant qu'un essai tourne dessus, l'essai s'arrete proprement et rien n'est ecrit au nom d'un item archive

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »

## Cause connue
Signale par les workers de harness-owner-secret-never-copied-in-clear / harness-linear-pull-reads-archived-tickets / harness-linear-census-reads-archived-tickets / harness-supervisor-relay-command (reports/<id>/FINDINGS.txt). Owner 23/09 (JAK-235) : « Ok tu peux traiter le tout du coup, comme tu l'entends ».
`.autoport/linear_sync.py:apply_owner_archive` : un archivage de l'owner sur un chantier EN COURS l'archive tout de suite ; le comportement de l'orchestrateur sur un item archive en plein essai n'est pas mesure (essai peut-etre termine, commite et juge sur un item deja archive).

## Livrable
1. Mesurer d'abord ce qui se passe aujourd'hui (item archive pendant un essai fabrique).
2. L'orchestrateur voit l'archivage et annule l'essai sans le compter, ou l'archivage attend la fin de l'essai en le disant a l'owner.
3. `archived_item_attempt_side_effects` = commits, verdicts ou statuts ecrits apres l'archivage ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`archived_item_attempt_side_effects == 0` dans `reports/harness-owner-archive-of-running-item-is-safe/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-archive-of-running-item-is-safe x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
