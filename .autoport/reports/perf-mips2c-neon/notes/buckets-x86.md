DIRECTIVES vaff5c1afea

Observations x86, un passage livré et un scalaire par proof_run.sh (120 s chacun).
Livré : 6980 images, crash=0 ; scalaire : 6990 images, crash=0.

| Seau | Livré + comparaison, ms/image | Scalaire, ms/image | Écart brut livré − scalaire, ms |
|---|---:|---:|---:|
| goal_busy_ms | 3.139 | 3.090 | +0.049 |
| goal_bucket_ms_bones | 0.001 | 0.001 | +0.000 |
| goal_bucket_ms_math_engine | 0.008 | 0.007 | +0.001 |
| goal_bucket_ms_process_particles | 0.059 | 0.058 | +0.001 |
| goal_bucket_ms_ocean | 0.092 | 0.089 | +0.003 |
| goal_bucket_ms_shadow | 0.000 | 0.000 | +0.000 |

Gain non prouvé : faute de passage dans le noyau des os, la comparaison scalaire reste active dans le bras livré. Ces durées incluent son coût et ne mesurent pas le gain du chemin de production seul.
refset_replay_maxdiff livré=255 ; scalaire=255 ; références manquantes=1.
Les deux logs donnent origine/h09 maxdiff=200, beach-start-h09 maxdiff=247 et beach-sun-h09 absent. Cela ne constitue pas une égalité bit à bit entre les deux sorties.
La suppression du diagnostic OOB est commune aux deux bras : aucun gain de ce lot n’est isolé ici.
