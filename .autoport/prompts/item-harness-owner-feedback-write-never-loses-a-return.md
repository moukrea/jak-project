# Deux ecritures simultanees d'un retour de l'owner (synchro Linear et superviseur) ne perdent jamais l'une des deux

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »

## Cause connue
Signale par les workers de harness-owner-secret-never-copied-in-clear / harness-linear-pull-reads-archived-tickets / harness-linear-census-reads-archived-tickets / harness-supervisor-relay-command (reports/<id>/FINDINGS.txt). Owner 23/09 (JAK-235) : « Ok tu peux traiter le tout du coup, comme tu l'entends ».
`.autoport/lib/backlog.py:480` `add_owner_feedback` reecrit la liste LUE EN MEMOIRE (set_status ne relit que l'item) : un retour ajoute entre le load et l'ecriture est PERDU ; appele par linear_sync.py:877 et :1607. `relay()` (autoport feedback) evite ce chemin.

## Livrable
1. Tout ajout d'owner_feedback relit l'item SOUS le verrou et ajoute, jamais ne remplace la liste.
2. `owner_feedback_lost_on_race` = retours perdus quand deux ecrivains ajoutent en meme temps (course fabriquee) ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`owner_feedback_lost_on_race == 0` dans `reports/harness-owner-feedback-write-never-loses-a-return/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-feedback-write-never-loses-a-return x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
