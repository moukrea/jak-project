# Tests du harnais

```bash
cd /home/emeric/code/jak-project
python3 -m pytest .autoport/tests/harness/ -q
```

Trois secondes, aucun build, aucun `adb`, aucun `gk`. Chaque test qui écrit le
fait dans un `tmp_path` : la fixture `sandbox` (voir `conftest.py`) repointe
`STATE_PATH`, `BACKLOG_PATH`, `LOG_ROOT`, `REPORTS_DIR` et le reste vers un
dossier jetable. **Aucun test ne touche l'état réel.**

Ce que chaque fichier tient :

| Fichier | Ce qu'il empêche de revenir |
|---|---|
| `test_preflight.py` | un check qui rend autre chose qu'un triplet `(sev, code, msg)` — la panne silencieuse de quatre jours (278 « preflight unavailable ») ; et le plafond de 5 constats dans le prompt |
| `test_state.py` | la mise à jour perdue entre deux orchestrateurs, et un numéro d'essai qui recule et écrase un journal |
| `test_forensics.py` | « 529 » compté dans une sortie d'outil, donc nos propres kills (exit 143) requalifiés en panne d'infra ; et le retour de la sonde de quota |
| `test_attempt.py` | un signal, un changement de périmètre ou un refus de l'API qui brûlent un essai ; le handoff absent ; le chien de garde qui mesure le démon de build |
| `test_selection.py` | le curseur positionnel, et un item que l'owner a validé qui ne se ferme jamais |
| `test_loop.py` | `git add -A` qui avale les écritures du superviseur ; un tour complet de boucle |
| `test_proof_busy.py` | la garde du runner qui confond un compilateur avec un prompt qui en parle ; et son propre verdict qui dépendait des processus RÉELS de la machine |

`lib/backlog.py` appartient à un autre chantier : `test_selection.py` code
contre un faux qui implémente l'API de `INTERFACES-2026-09-03.md` §5. Ce faux
est donc aussi l'énoncé exécutable de ce que l'orchestrateur attend de lui.

## Les échecs que la suite porte sciemment

`ECHECS-ATTENDUS.yaml` liste les tests qui échouent pour une raison écrite. Ils ne sont ni
désactivés, ni `xfail`, ni sautés : ils tournent, ils échouent, et chaque entrée nomme QUI doit
trancher. Au 2026-09-12 il y en a deux, la même cause vue sous deux angles — trois items portent
un budget au-dessus du défaut sans la note « budget : », et seul l'owner peut l'écrire.

Ce fichier ne sert pas à se donner du vert. `lib/census/harness-test-suite-is-not-a-signal.sh`
compte comme DÉFAUT tout échec absent du registre, toute entrée qui ne rougit plus (une dispense
périmée n'est pas un acquis) et toute entrée qui rougit pour une autre raison que sa `signature`.
Il publie `test_suite_defects` dans la preuve de l'item du même nom, après avoir lancé la suite
DEUX fois : une fois avec un `ninja` factice vivant, une fois sans. Les deux verdicts doivent être
identiques — c'est ce qui interdit à un test de dépendre de ce que la machine fait au même moment.
