# Interfaces partagées — remise d'équerre du 2026-09-03

Contrat entre les quatre chantiers parallèles. **Personne ne modifie un fichier qui n'est pas
dans sa colonne.** Si tu as besoin d'un changement chez un autre, tu le demandes au lead.

| Chantier | Fichiers qu'il possède (et lui seul) |
|---|---|
| A — contrat | `DIRECTIVES.md`, `lib/directives.py`, `hooks/session-start.sh`, `<repo>/CLAUDE.md`, `~/.claude/projects/-home-emeric-code-jak-project/memory/**`, `.claude/agents/*.md`, `archive/journal-*.md` |
| B — orchestrateur | `orchestrator.py`, `lib/preflight.py`, `hooks/session-end.sh`, `tests/harness/**` |
| C — preuve | `lib/proof_run.sh`, `lib/device_teardown.sh`, `validators/generic.sh`, `hooks/stop.sh`, `hooks/pre-tool.sh`, `acquis/*.sh` |
| D — backlog | `backlog.yaml`, `lib/backlog.py`, `autoport` (CLI), `tools/migrate_backlog.py` |
| lead | `auto_build_apk.sh`, `auto_push_builds.sh`, `supervisor.sh`, `SUPERVISOR_PROMPT.md`, `.gitignore`, `archive/**`, intégration finale |

Chemins relatifs à `/home/emeric/code/jak-project/.autoport/` sauf mention contraire.

---

## 1. `backlog.yaml` — la seule vérité du travail (chantier D)

```yaml
version: 1
items:
  - id: cutscene-npc-flicker          # kebab-case, stable, sans préfixe G
    feature: "Les PNJ clignotent pendant les cinématiques"   # l'unité que l'OWNER valide
    status: open                      # open|in-progress|to-test|validated|blocked|archived
    priority: 20                      # entier, petit = urgent ; ordre de sélection
    owner_feedback:                   # les mots de l'owner, datés, JAMAIS réécrits
      - {date: "2026-08-31", text: "le problème des PNJ ... est revenu"}
      - {date: "2026-09-03", text: "bah non c'est toujours pété"}
    gate: {key: flicker_episodes, op: "==", value: 0}   # critère machine, cf. §2
    device: true                      # la preuve doit être prise sur l'appareil
    device_serial: eae4df44           # défaut si absent : eae4df44 (Redmi). JAMAIS la SHIELD.
    game: jak1
    max_turns: 1200
    max_retries: 6
    depends_on: []                    # liste d'ids
    history: [Gcutscene-npc-flicker, Gcutscene-npc-flicker-2]  # anciens ids de phase
    prompt: prompts/item-cutscene-npc-flicker.md   # généré depuis l'item, régénéré à chaque réouverture
    owner_ok: null                    # ou {date, text, build_sha}
```

Sémantique des statuts :
- `open` : à faire. L'orchestrateur peut le prendre.
- `in-progress` : un worker le tient (posé par l'orchestrateur, effacé à la fin de l'essai).
- `to-test` : le harnais a livré, l'owner doit regarder. **N'apparaît jamais dans « en cours ».**
- `validated` : l'owner a dit oui. `owner_ok` porte sa phrase. Ne se re-liste JAMAIS.
- `blocked` : bloqué, `block_reason` obligatoire, avec ce qu'on attend pour débloquer.
- `archived` : hors sujet ou obsolète, gardé pour l'historique.

## 2. `gate:` — le critère machine

`{key, op, value}` où `op` ∈ `== != < <= > >=`. `key` est le nom d'un champ `KEY=VALEUR`
présent dans `proof.txt` (§3). Le moteur DOIT émettre ce champ ; ce n'est jamais le worker
qui le tape. Un item `device: true` sans `gate` est refusé par `autoport lint`.

## 3. `reports/<item-id>/proof.txt` — écrit par la machine (chantier C)

Produit uniquement par `lib/proof_run.sh`, jamais à la main, jamais par le worker.

```
source=x86                  # ou: device
serial=eae4df44             # présent seulement si source=device
binary=/chemin/du/binaire/juge
sha=1a2b3c4d5e6f7a8b        # 16 premiers hex de sha256sum du binaire
started_at=2026-09-03T08:12:44Z
duration_s=63
crash=0
frames=1842
FEATURE cutscene-npc-flicker armed=1 hits=37
flicker_episodes=0          # les KEY=VALEUR emises par le moteur, recopiees telles quelles
```

Usage : `lib/proof_run.sh <item-id> <x86|device> [--timeout N] [--off]`
- `--off` : même run avec la feature désarmée, écrit `proof-off.txt` (contrôle d'ablation).
- Nettoie toujours les `debug.opengoal.*` de l'appareil en `trap EXIT`.
- Refuse de démarrer si un build est en cours (`.deploy-in-progress` avec PID vivant, ou
  `gradle`/`ninja`/`goalc` en cours) : il attend, il ne meurt pas.

## 4. `validators/generic.sh` — le seul validateur (chantier C)

Lit `$AUTOPORT_PHASE_ID` (= l'id d'item), charge l'item via `lib/backlog.py`, juge
`reports/<id>/proof.txt`. ≤ 40 lignes. Ne lit JAMAIS `report.txt`. Vérifie dans l'ordre :
fraîcheur (aucune source moteur plus récente que le proof), identité (sha du binaire),
`crash=0`, `frames` ≥ seuil, `FEATURE <id> armed=1 hits>0`, puis le `gate:` de l'item,
puis l'ablation si `proof-off.txt` existe. Sortie 0 = vert, 1 = rouge avec une ligne
`[<id> FAIL] <raison>`.

## 5. `lib/backlog.py` — API Python (chantier D)

```python
load(path=None) -> Backlog          # défaut .autoport/backlog.yaml
Backlog.items           -> list[dict]
Backlog.get(item_id)    -> dict | None
Backlog.next_open()     -> dict | None    # premier `open` sans dépendance non-validée, par priority
Backlog.set_status(item_id, status, **fields) -> None   # écriture ATOMIQUE (tmp+rename), relit avant d'écrire
Backlog.status_report(changed_only=False) -> str        # le texte 3 blocs, français
Backlog.lint() -> list[str]                             # incohérences
```

CLI `./.autoport/autoport` : `status [--changed] [--json]`, `next`, `show <id>`,
`set <id> <status> [--reason ...]`, `ok <id> "phrase de l'owner"`, `lint`.

`status` imprime exactement trois blocs, en français, sans jargon :
`## En cours` (une ligne), `## À tester` (feature + build + où regarder), `## Bloqué`
(pourquoi + ce qu'on attend de l'owner). Un bloc vide est omis.

## 6. Ce que l'orchestrateur attend (chantier B)

- Sélection : `backlog.next_open()`. Plus de `current_phase_idx`, plus de `milestones.yaml`.
- `AUTOPORT_PHASE_ID` = l'id d'item. Validateur = `validators/generic.sh` pour tous.
- `state.json` ne garde plus que : `retries`, `fingerprints`, `attempt_seq`, `rate_interrupts`,
  `last_update`. Les statuts vivent dans `backlog.yaml`.
- Le prompt du worker = `directives.block(item_id)` + le prompt de l'item + `handoff.md`.

## 7. Règles communes à tous les chantiers

1. **Ne lis pas `DIRECTIVES.md`** pour te guider : il est en cours de remplacement et son
   contenu actuel est le défaut principal qu'on corrige.
2. **Aucun build, aucun `adb`, aucun lancement de `gk`, `gradle`, `ninja`, `goalc`,
   `orchestrator.py` ou `launch.sh`.** Le harnais est gelé. Tu écris du code et tu le testes
   avec des tests unitaires et des faux fichiers, rien d'autre.
3. **Jamais `pkill -f` / `pgrep -f` sans crochet** (`pgrep -f '[o]rchestrator'`) : ça se
   matche soi-même.
4. Appareils : Redmi `eae4df44` uniquement. La SHIELD (192.168.1.32) est **interdite**,
   l'owner l'a répété six fois.
5. Tu ne commites pas. Le lead commite à la fin de chaque chantier.
6. Plafonds durs, à faire ÉCHOUER bruyamment quand ils sont dépassés : contrat ≤ 12 Ko,
   validateur ≤ 40 lignes, preflight ≤ 5 constats injectés, rapport owner ≤ 40 lignes.
