# harness-linear-watch-comment-matches-its-period — essai 2

DIRECTIVES v84e185a920

**Verdict : le texte de la veille Linear dit maintenant la periode qu'elle execute ; ecart mesure = 0, avec 3 controles vivants.**

## Ce qui a change
- `linear_watch.sh` : `LINEAR_WATCH_PERIOD_S=30` est la seule source. Le `sleep` la lit ; le commentaire
  d'en-tete et une nouvelle ligne de demarrage du journal (`veille Linear demarree : synchro toutes les 30 s`)
  la citent. Plus aucun chiffre de periode ecrit en dur.
- `lib/census/harness-linear-watch-comment-matches-its-period.sh` (neuf) : LANCE le script dans un bac a
  sable jetable (`python3` et `sleep` remplaces par des temoins ; `sleep` consigne l'argument recu puis
  arrete la veille), et compare cette periode EXECUTEE a chaque « toutes les <N|$VAR> <unite> » du texte.
  Inconnu = defaut (aucune annonce, annonce non resolue, aucun sleep execute). Trois controles sur copies :
  historique dc7eb801a7 (« 5 min » / sleep 30), defaut seme (sleep 7), copie saine. Un controle qui ne
  se comporte pas comme attendu s'ajoute au compte.

## Preuve (recopiee de proof.txt)
    linear_watch_period_mismatch=0
    linear_watch_period_lw_announcements=2
    linear_watch_period_lw_announced_s=30,30
    linear_watch_period_lw_executed_s=30
    linear_watch_period_ctl_pos_hist_culprit=linear_watch.hist.sh:2:annonce=300s:execute=30s
    linear_watch_period_ctl_pos_seed_mismatch=2
    linear_watch_period_ctl_neg_mismatch=0
    linear_watch_period_controls_blind=0

Denominateur : 2 annonces dans le script reel, 1 appel de `sleep` execute, 3 controles.

## Ce que l'owner doit regarder
Rien a regarder dans le jeu : c'est un changement de l'outillage (owner_test: false).

## Non prouve
- non prouve : la ligne de demarrage dans `logs/linear_sync.txt` du VRAI veilleur — le processus vivant
  (pid 2798050) date d'avant le changement et ne l'ecrira qu'a son prochain redemarrage (FINDINGS).
