# Si la synchro Linear est morte, le rapport d'etat le dit au lieu d'afficher un etat fige comme s'il etait frais

## Defaut cite
- 2026-09-23 : « Je pense qu'ils les faut tous... à prioriser of course mais tout est pertinent il semblerait, go »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/harness-supervisor-death-is-an-alarm/FINDINGS.txt, ligne 6), non corrige ; l'owner a dit d'ouvrir tous ces chantiers le 23/09.
`.autoport/lib/backlog.py:status_report` lit le cache pose par la synchro Linear ; si linear_watch.sh est mort, le cache vieillit et la rubrique parle d'un etat perime sans publier son age.

## Livrable
1. La rubrique publie l'age du cache ; au-dela d'un seuil, elle dit « synchro Linear arretee depuis X ».
2. `status_stale_cache_silent` = rapports rendus sur un cache perime sans le dire ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut semé rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`status_stale_cache_silent == 0` dans `reports/harness-status-says-when-linear-cache-is-stale/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-status-says-when-linear-cache-is-stale x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
