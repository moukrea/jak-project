# Les gardes anti-secret couvrent aussi les cas limites : --no-verify, reponses de l'outil d'identite, secret sur deux lignes, requete ecrite en morceaux

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »

## Cause connue
Signale par les workers de harness-owner-secret-never-copied-in-clear / harness-linear-pull-reads-archived-tickets / harness-linear-census-reads-archived-tickets / harness-supervisor-relay-command (reports/<id>/FINDINGS.txt). Owner 23/09 (JAK-235) : « Ok tu peux traiter le tout du coup, comme tu l'entends ».
(1) `.autoport/hooks/git/pre-commit + pre-push` contournables par `--no-verify` (l'orchestrateur ne l'utilise pas, orchestrator.py:1991). (2) `.autoport/linear_identity.py:gql` : ses reponses ne passent pas par le masque. (3) `lib/census/harness-owner-secret-never-copied-in-clear.sh` : un « Client Secret » et sa valeur sur deux lignes YAML ne sont pas vus dans l'historique. (4) `lib/census/harness-linear-census-reads-archived-tickets.sh` (S) : une requete assemblee par morceaux echappe au recensement statique.

## Livrable
1. Controle cote serveur ou porte du juge qui rejoue la recherche de secret sur les commits de l'essai (independant des hooks locaux).
2. linear_identity passe par le masque.
3. Recherche multi-lignes dans l'historique ; recensement structurel des requetes.
4. `secret_guard_gaps` ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`secret_guard_gaps == 0` dans `reports/harness-secret-guards-hardening/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-secret-guards-hardening x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
