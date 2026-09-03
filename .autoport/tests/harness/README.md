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

`lib/backlog.py` appartient à un autre chantier : `test_selection.py` code
contre un faux qui implémente l'API de `INTERFACES-2026-09-03.md` §5. Ce faux
est donc aussi l'énoncé exécutable de ce que l'orchestrateur attend de lui.
