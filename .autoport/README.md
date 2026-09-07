# Autoport — Claude Code ou Codex, de bout en bout

Le même backlog, les mêmes preuves et les mêmes reprises servent aux deux CLI.
La sélection est **par processus** : argument `--backend`, puis variable
`AUTOPORT_BACKEND`, puis `claude` par défaut. Aucun changement de profil Claude,
de transcript, de mémoire, de jeton owner-ok ou de backlog n'est nécessaire.

## Démarrer et reprendre

```bash
# Codex interactif + veille et orchestrateur en arrière-plan, dans un seul terminal
./run-codex.sh
# Reprendre une session précise
./run-codex.sh --resume <UUID-CODEX>

# Retour intégral à Claude Code, après arrêt du précédent orchestrateur
./.autoport/supervisor.sh --backend claude
./launch.sh --backend claude

# Vérification sans worker, sans preuve, sans sélection d'item
./launch.sh --backend codex --check
# Afficher le lancement du superviseur sans le démarrer
./.autoport/supervisor.sh --backend codex --check
# Reprendre un superviseur Codex précis (pas le dernier worker)
./.autoport/supervisor.sh --backend codex --resume <UUID-CODEX>
# Reprendre l'ancien superviseur Claude
./.autoport/supervisor.sh --backend claude --resume fc2d3cfc-f35f-4d52-b8cc-b3f3b2f92028
```

Un seul orchestrateur par dépôt, **toutes CLI confondues**, grâce au même flock.
`run-codex.sh` ouvre le superviseur Codex au premier plan avec le clavier et
l'interface interactive. La veille attend l'UUID de cette session puis entretient
l'orchestrateur en arrière-plan. Ses sorties vont dans
`logs/supervisor-watch.log`, sans polluer l'interface. `--interval 60` change sa
période ; les autres arguments sont transmis au superviseur.
Quitter Codex arrête la veille créée par ce lanceur. Un orchestrateur déjà lancé
continue son essai ; il peut être arrêté séparément par son PID exact.
Pour la veille seule, l'entrée avancée reste
`supervisor.sh --backend codex --watch --maintain --notify-supervisor`.
Ctrl+C / SIGTERM annule l'essai sans brûler de retry, sauvegarde le travail et
rend la main. Arrêter aussi l'éventuelle veille `--maintain` avant de changer de
CLI, sinon elle peut relancer son backend. Ne jamais tuer par motif.
Les superviseurs interactifs ne doivent pas modifier le backlog simultanément.

La veille est un processus externe, pas un cron caché dans la conversation.
Elle imprime les changements sans appel LLM et possède son propre curseur :
elle ne consomme pas celui de `autoport status --changed`. `--once` fait un tour,
`--interval 60` change la période. Sans `--maintain`, elle observe seulement.
Une erreur du lanceur suspend les relances automatiques de cette veille ; un
orchestrateur vivant en attente de quota n'est jamais remplacé.
`--notify-supervisor` utilise `codex queue` pour remettre les changements au chat
superviseur exact, dont le hook enregistre l'UUID. `--session <UUID>` permet de
le choisir explicitement. La veille mémorise le dernier digest remis : aucun
appel de modèle si le statut reste identique. Les ETA et arbitrages sont faits
par le superviseur, à partir des traces mesurées. Sans cette option, la veille
imprime seulement dans son terminal. Claude conserve son cron natif.
La remise dépend de la disponibilité du thread dans Codex ; un échec est affiché
et retenté au prochain passage, sans lancer une seconde session superviseur.

## Architecture actuelle

| Composant | Responsabilité |
|---|---|
| `autoport`, `lib/backlog.py`, `backlog.yaml` | Statuts, priorité, dépendances, retours verbatim et validation owner |
| `orchestrator.py` | Sélection, essais, signaux, watchdogs, checkpoints, validation après sortie |
| `lib/cli_backend.py` | Commandes CLI, paramètres, authentification Codex, événements JSONL Codex |
| `lib/directives.py`, `prompts/`, `reports/<id>/handoff.md` | Contrat borné, tâche et reprise entre essais/CLI |
| `validators/generic.sh`, `lib/proof_run.sh` | Production et contrôle programmatique des preuves |
| `phase_claim.sh` | Détenteur vivant identifié par PID/starttime/comm Claude ou Codex |
| `hooks/`, `codex/hook.py` | Gardes partagées, adaptation des événements et patches Codex |
| `auto_build_apk.sh`, `auto_push_builds.sh` | Build/livraison indépendants de la CLI ; lancement inchangé |
| `supervisor.sh`, `SUPERVISOR_PROMPT.md`, `watch.py` | Dialogue owner, contrat commun et veille externe |

Cycle : `open` → `in-progress` → worker → validateur lancé par l'orchestrateur →
`to-test` / `validated` / nouvel essai / `blocked`. Les compteurs vivent dans
`state.json`, les statuts dans le backlog. `milestones.yaml` et les anciens
journaux ne sont plus le pilote. Le hook Stop Claude est consultatif ; Codex
laisse la validation post-session à l'orchestrateur pour éviter une double course.
Un succès déclaré par l'agent ne ferme jamais une tâche à lui seul.

Les essais interrompus par signal, changement de périmètre ou refus API ne
consomment pas de retry. Les journaux bruts sont conservés dans
`logs/<id>/attempt-NNN.jsonl` avec le backend, la commande et les événements natifs.
Codex : `thread.started`, `item.*`, `turn.completed`, `turn.failed`, `error`.
Les appels d'outil sont dédupliqués entre début/fin, les tokens lus au bilan du
turn. Un texte d'outil contenant « 429 » n'est pas un refus API.
Le reset n'est utilisé que s'il est fourni ; sinon attente bornée, sans sonde de
quota Anthropic ni déduction d'un quota Codex. Les erreurs auth/modèle sont signalées.

## Configuration des CLI

Claude garde `model-profiles.json` et `apply-model-profile.sh`. Les workers chargent
`settings.json` par le lien local existant, ou explicitement si ce lien est absent.
Codex lit uniquement `codex/profiles.json`. Modèles vides : modèle de la CLI locale,
sous-agents hérités. Pour les figer, remplir `manager_model` et `worker_model`.
Les efforts sont séparés : manager/recherche high, implémentation/test medium.
Les rôles sont transmis aux sous-agents **natifs Codex**, sans `claude -p`.

Le profil Codex autonome utilise `danger-full-access` et aucune demande interactive,
comme le mode Claude historique : builds hors dépôt, git et appareils nécessitent
ces accès. `workspace-write` est disponible pour les sessions restreintes, mais
peut empêcher les builds, commits ou installations du projet. Ce réglage ne
modifie aucune politique imposée par l'environnement ou l'administrateur.

Les hooks sont injectés par `-c` pour cette invocation ; rien n'est écrit dans
`~/.codex` ni `.codex`. `--dangerously-bypass-hook-trust` active les hooks en mode
non interactif : les sources de hooks chargées par la CLI doivent être connues
et revues, y compris les hooks personnels/plugins éventuels. Cela ne désactive
pas les gardes de commandes. Version inspectée et vérifiée : Codex CLI 0.153.4.
Authentification : `codex login`, réutilisée par `codex exec`, sans lecture/copie
des secrets par le harnais. La CLI reste responsable de leur stockage.

Codex n'a pas de `--max-turns` équivalent : `max_turns` borne ici les appels
outils observés du manager, en complément des watchdogs de silence/progrès ;
ce n'est pas un plafond global de tokens ni de sous-agents. Les hooks d'outils
sont des gardes contre les erreurs usuelles, pas une frontière de sécurité.

## Contexte du superviseur et validation

`codex/HANDOFF.md` résume les priorités retrouvées dans la session Claude active
le 7 septembre. Le transcript reste intact. L'état courant vient toujours des
fichiers du harnais, jamais de cette note datée.

```bash
python3 -m pytest .autoport/tests/harness/ -q
bash .autoport/tests/harness/test_pretool_guard.sh
```

Les tests utilisent des dépôts/CLI factices en dossiers temporaires. Le migrateur
écrit désormais les prompts à côté de son `--out` : tester une migration ne
réécrit plus les prompts de production.

Références officielles utilisées pour l'adaptateur :
[exec et JSONL](https://learn.chatgpt.com/docs/non-interactive-mode),
[hooks](https://learn.chatgpt.com/docs/hooks),
[sous-agents](https://learn.chatgpt.com/docs/agent-configuration/subagents).
