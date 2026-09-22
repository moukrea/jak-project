# A relancer apres le redemarrage de la session du superviseur (2026-09-22 23:3x)

L'owner redemarre sa session pour passer la CLI de 2.1.275 a 2.1.280 (la version installee
est deja 2.1.280 ; seul le PROCESSUS de la session porte encore l'ancienne).

## Ce qui SURVIT (aucune action) — verifie par `ps -o sess=`, chacun a sa propre session

| quoi | pid au moment du releve | session |
|---|---|---|
| orchestrateur (`launch.sh --quiet` + `orchestrator.py`) | 3998179 / 3998198 | 3998179 |
| constructeur d'APK (`.auto_build_apk.pid`) | 1686415 | 1686415 |
| publieur de builds (`.auto_push_builds.pid`) | 3990441 | 3990441 |
| veille Linear (`.linear_watch.pid`) | 2798050 | 2798050 |

Aucun d'eux n'est fils de la session du superviseur : ils ont ete lances avec `setsid`.

## Ce qui MEURT (a relancer)

1. **La veille de fond du superviseur** (Monitor sur `scratchpad/veille.sh`) : elle vit DANS
   la session. C'est elle qui annonce les retours de l'owner, les nouveaux builds publies et
   la mort des demons. **A re-armer en premier.** Le script est jetable : le rescript si le
   scratchpad a disparu (il surveille `owner_feedback` dans le backlog, `TAG:` dans
   `.published_build_info.txt`, l'age de `logs/linear_sync.txt`, et l'etat `/proc/<pid>/stat`
   des deux demons d'APK).
2. `self_heal.pid` (1612340) est **MORT depuis longtemps**, bien avant ce redemarrage.
   Ce n'est pas une consequence du restart — a traiter separement, ne pas l'imputer au restart.

## A verifier apres, dans cet ordre

```sh
ps -eo pid,sess,cmd | grep -E '[o]rchestrator.py|[a]uto_build_apk|[a]uto_push_builds|[l]inear_watch'
tail -6 .autoport/logs/orchestrator.log        # la banniere doit dire modele=claude-opus-5-5
./.autoport/autoport status
```

Si l'orchestrateur a disparu malgre tout :
`setsid nohup bash ./launch.sh --quiet </dev/null >> .autoport/logs/watch-launch.log 2>&1 &`
(ne JAMAIS le relancer pendant une ecriture du backlog).
