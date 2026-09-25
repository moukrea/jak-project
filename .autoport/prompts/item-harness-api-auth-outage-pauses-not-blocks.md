# Une panne d'authentification de l'API met l'orchestrateur en pause au lieu de bloquer toute la file

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
25/09 vers 15h : le jeton OAuth de la CLI a expire (renouvele a 15:16). Chaque essai lance a rendu « erreur API 401 » immediatement ; l'orchestrateur a marque chaque item BLOQUE l'un apres l'autre (25 items en cascade, dont lighting-local-lights en plein travail) puis s'est arrete, orch=0. Le superviseur a tout rouvert a la main. Une panne d'authentification n'est PAS un echec du chantier : c'est l'environnement.

## Livrable
1. Un 401/403 (ou tout refus d'authentification) sur un essai : l'essai n'est ni compte ni bloque ; l'orchestrateur se met en PAUSE, re-sonde l'API toutes les N minutes (appel minimal) et reprend seul quand elle repond, en le journalisant.
2. Au-dela d'un seuil (ex. 30 min), alerte au superviseur (reveil) une seule fois.
3. `autoport status` dit « En pause : authentification API refusee depuis X ».
4. `auth_outage_items_blocked` = items bloques pour une cause d'authentification ; doit valoir 0.
CONTROLE POSITIF (API simulee qui rend 401 puis 200) + CONTROLE NEGATIF (un vrai echec de modele reste compte).

## Preuve exigee
`auth_outage_items_blocked == 0` dans `reports/harness-api-auth-outage-pauses-not-blocks/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-api-auth-outage-pauses-not-blocks x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
