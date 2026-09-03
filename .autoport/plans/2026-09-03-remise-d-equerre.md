# Autoport : remise d'équerre

Revue complète du harnais, 3 septembre 2026. Corrigée le même jour sur le point du superviseur : la session est active, voir §1 et étape 6. Rien n'a été modifié : ni code, ni état, ni process. L'orchestrateur, le worker en cours (Gcutscene-npc-flicker-2) et les deux démons de build tournaient pendant la revue et tournent toujours.

Sources : le code du harnais, `state.json` et `milestones.yaml`, 4 778 commits `[autoport/…]`, 573 journaux d'essais, les 1 111 transcripts de sessions Claude Code (dont ta session superviseur de 77 jours, active pendant la revue), tes 1 617 messages depuis mai, les 763 fichiers de mémoire. Les cinq rapports détaillés sont joints dans `.autoport/plans/revue-2026-09-03/`.

---

## 1. Verdict

Le harnais n'est pas cassé à un endroit. Il a été patché en réaction à chaque incident depuis mai, et rien n'a jamais été retiré. Le résultat :

- **Chaque worker reçoit ~63 000 tokens au premier tour, dont ~700 (1 %) parlent de sa phase.** Le reste est surtout le journal daté de la physique de Keira (`DIRECTIVES.md`, 160 Ko, 67 sections dont 11 se rétractent elles-mêmes), injecté tel quel dans toutes les phases, cinématiques et polices comprises. Le bloc « périmètre actif » dit encore « KEIRA SEULE ». Les sous-agents ont l'ordre de s'arrêter si leur tâche n'est pas dans ce périmètre.
- **Les validateurs des 19 dernières phases ne lisent qu'un seul fichier : le rapport écrit par le worker lui-même.** 116 vérifications sur 116 portent sur ce texte, zéro sur un binaire, un log ou l'appareil. Les seules portes qui testent l'artefact réel (`deploy_verify` + boot check) sont désactivées (`device: false`) sur toutes les phases que tu testes en ce moment.
- **Le débit s'est effondré** : 22 à 46 phases closes par semaine en juin, puis 5, 3 et 0 sur les quatre dernières semaines. Du 10 au 23 août, 645 commits sur une seule phase et zéro phase close.
- **Le temps des workers va à la preuve, pas au code.** Sur les trois dernières semaines : 66 % des appels prouvent, mesurent ou analysent, 13 % lisent du code, **1,3 % éditent le jeu** (1,6 h sur 309 h). En août et septembre, 56 à 59 % des essais ne contiennent aucune édition de code.
- **Le superviseur est vivant, mais il travaille sans trace.** C'est ta session interactive de 77 jours, lancée par `supervisor.sh`, et c'est aujourd'hui ton seul canal vers le harnais. Sur la dernière semaine : 120 messages de toi, 335 tours de son propre cron de 30 minutes, 1 138 commandes shell, zéro commit. Elle écrit les prompts, validateurs et jetons par heredoc et ne commite jamais : ses écritures sont absorbées par le commit suivant d'un worker, sous le préfixe de ce worker. Le journal qu'elle devait tenir est mort depuis le 18 juin. Et le prompt de son cron porte un « contexte » figé au 26 août (phase 232) qu'il répète à chaque tour.
- **Le harnais se sabote mécaniquement** : chaque essai raté fait un commit WIP, ce commit déclenche le démon de build (build arm64 complet + `gradle clean`), qui réécrit `out/jak1/iso` en ARM64 pendant que le worker suivant lance un `gk` x86 dessus. Faux rouge, nouveau commit WIP, nouveau build. Huit builds cette nuit entre 23 h et 3 h.
- **Chaque relance manuelle brûle un essai.** Ton Ctrl-C ou `kill` laisse l'orchestrateur exécuter le validateur, compter l'essai et enregistrer une empreinte. 373 des 597 sessions worker ont duré moins de 3 minutes. Une boucle « pas de démarrage » a tourné 230 fois (19,7 h) sur Ghd-skin-origin-stretch le 31 août, sans que la cause soit récupérable.
- **Le backlog n'a plus une seule vérité.** 278 phases dans une liste positionnelle indexée par un curseur qu'on déplace à la main pendant que la liste est éditée. 41 phases « complétées » dont le dernier commit dit « NOT done ». 27 phases validées mais pas closes. 9 phases parquées qui ont ton feu vert et ne fermeront jamais (le saut « parquée » passe avant la lecture du jeton). 39 des 96 jetons `owner-ok` ont été écrits par le superviseur, pas par toi, 31 sont vides. Le fichier de la file « à tester » date du 22 août et parle de la spec des seins.
- **Une phase rouverte est un clone** (`-2`) qui réutilise l'ancien prompt et parfois l'ancien validateur (qui lit le rapport de l'ancienne phase). Ton retour vit dans le champ `name:` du YAML, que le worker ne voit jamais.
- **Le preflight est mort depuis le 30 août** (un `return` au lieu d'un `yield`, 278 occurrences de « preflight unavailable » avalées en silence). La sonde de quota est cassée (1 105 erreurs 429, 374 exceptions), l'orchestrateur « continue avec optimisme ».
- **Ta mémoire de session est illisible** : 763 fichiers, index de 411 lignes tronqué au chargement, 78 % des entrées jamais chargées, et ce qui charge est la physique de Keira.

Et un point hors harnais : **ton mot de passe sudo est en clair dans le transcript du 29 août (20 h 46).** À changer.

---

## 2. Ce qui marche et qu'on garde

- Le validateur exécuté par l'orchestrateur, pas sur parole du worker, avec le JSONL forensique par essai.
- Les commits WIP après chaque essai raté (historique bisectable). On les garde, mais sans les fichiers d'état du harnais dedans et sans déclencher de build.
- Le prompt passé par stdin (le fix E2BIG).
- `.scope_stamp` pour avorter un essai quand le périmètre change (jamais utilisé, mais c'est le bon mécanisme).
- `phase_claim.sh` (un seul worker par phase, vivacité par PID + starttime, jamais de kill par motif).
- Le verrou d'instance unique (à sortir du suivi git).
- Le `close_gate` qui relit `no_code` et `device_serial` sur disque, le boot check route B pour les téléphones qui ne loggent pas.
- Le versionnage des directives par sérial, pas par hash de prose.
- `auto_push_builds.sh` : règle « ancêtre de HEAD », zip HD séparé, notes de release après chaque push.
- `auto_build_apk.sh` : déclencheur par hash de contenu, réconciliation idempotente sur l'appareil.
- Les gardes de portée des hooks sur `AUTOPORT_PHASE_ID`.
- Le jeton `owner-ok` : la seule porte qui ait jamais attrapé un vrai défaut visuel. C'est toi.
- Ta manière de piloter n'a pas changé depuis mai et elle est saine : tu dis « X » une fois dans le chat, tu veux un build, un digest en trois rubriques, une liste exacte de ce qu'il y a à tester, et zéro question déjà répondue.

---

## 3. Les mécanismes qui te mettent à mal

Chaque ligne relie un symptôme que tu as exprimé à sa cause mécanique et à la preuve.

| Ce que tu vois | Cause | Preuve |
|---|---|---|
| « Tu comprends tout de travers » | Le contrat inliné est celui de la physique de Keira ; la phase réelle pèse 1 % du contexte ; la porte et le prompt ne disent pas la même chose (le validateur exige `plateforme=redmi`, `pnj=mayor`, que le prompt ne mentionne pas) | review-context §1, §4 |
| « Tellement de blockers que le moindre truc prend des journées » | ~48 règles de preuve dans DIRECTIVES + ~40 dans PITFALLS + les « How to apply » de 496 mémoires, contredites par le préambule « proof economy » du même prompt ; le worker suit les directives (« three-leg device campaign » au 2e essai de npc-flicker-2) | review-context §2d, §2c-8 |
| « Ton travail est systématiquement détruit » | kill + relance = essai brûlé + contexte perdu ; le watchdog « 45 min sans changement d'artefact » tue les essais d'analyse (13 kills) ; le rejeu ne reçoit que 4 Ko de sortie de validateur | review-mechanics B5, B10, D6 |
| « Ça revient, c'est toujours pété » | Aucune porte artefact sur les phases récentes ; validateur = grep du rapport ; un seul acquis (`font-urbanist`) sur 96 phases validées ; le clone `-2` valide sur le rapport de la phase 1 (npc-flicker-2 est passé vert le 2/09 avec 0 édition de code, ton verdict le 3/09 : « bah non c'est toujours pété ») | review-validators §1-2, review-throughput §5 |
| « Je dois tester quoi ? » / « J'ai déjà validé ça » | L'unité que tu valides est une feature ; l'unité du harnais est un id de phase ; une demande = 2 à 3 phases ; 21 phases parquées ; la file « à tester » n'est pas maintenue | review-sessions L4, E5 |
| « T'es endormi ? » / « Et le cron ? » | Une seule session de 77 jours, 17 000 tours, compactée plusieurs fois ; absente pendant les quotas et quand le PC est éteint pendant que l'orchestrateur continue sur l'ancien périmètre ; 335 tours de cron par semaine contre 120 messages de toi | review-sessions L6, vérifié le 3/09 |
| « La moitié du temps gaspillée en builds » | Chaque WIP commit lance un build arm64 complet + gradle clean ; 454 builds ; « pendant un gk » 672 fois | review-mechanics B17, D4 |
| « Tu touches à la SHIELD » | L'ordre est en prose (mémoire, cron, DIRECTIVES) ; ce que le worker exécute (prompt, `device_serial`, 18 scripts) dit l'adresse de la SHIELD | review-sessions E4 |

---

## 4. Le plan

Principe : **on ne réécrit pas l'orchestrateur, on l'assainit. On remplace ce qui est structurellement faux : le contrat, la preuve, le backlog, le superviseur.** Chaque étape a un critère d'arrêt vérifiable. Aucune étape ne perd d'historique : tout ce qui est retiré est déplacé dans `archive/` et reste dans git.

### Étape 0 : gel et sauvegarde (2 h, à faire en premier, par moi sur ton feu vert)

1. Attendre la fin de l'essai en cours ou l'arrêter proprement via `.scope_stamp` (pas de kill).
2. Arrêter l'orchestrateur et le démon de build. Laisser `auto_push_builds.sh`.
3. Snapshot : tag git `harness-pre-reset-2026-09-03`, copie de `state.json`, `milestones.yaml`, `owner-ok/`, `DIRECTIVES.md`, `PITFALLS.md` dans `.autoport/archive/2026-09-03/`.
4. Réparer `.gitignore` (ligne 97 corrompue) et sortir du suivi : `state.json`, `.orchestrator.lock`, `.phase-claim.*`, `.last_*`, `.scope_stamp`, les 28 `.bak*`.
5. Changer le mot de passe sudo. Optionnel : purger la ligne du transcript.

Critère : `git status` propre, tag posé, orchestrateur à l'arrêt, aucun process `gk` ou `gradle`.

### Étape 1 : le contrat (1 jour)

Objectif : un worker reçoit ≤ 12 000 tokens au premier tour, dont ≥ 3 000 sur sa phase.

1. **`DIRECTIVES.md` → 3 Ko de règles permanentes** : les 8 règles non négociables moins les 3 spécifiques à la physique, reprise, non-destruction, deux appareils (Redmi + Honor, jamais la SHIELD), preuves programmatiques, format de rapport. Tout le reste part dans `archive/journal-keira-physique-2026-08.md`. Toute règle rétractée est supprimée, git garde l'historique.
2. **Périmètre par phase** : `lib/directives.py` inline les règles + un `prompts/SCOPE-<phase>.md` s'il existe. Plafond dur 12 Ko avec erreur bruyante au-delà. La version est calculée par phase.
3. **Sous-agents** : retirer « relis DIRECTIVES.md en entier » et « arrête-toi si le périmètre diffère ». Le périmètre est dans leur prompt.
4. **`session-start.sh`** réécrit en 6 lignes (id, validateur, préfixe de commit, « pas d'humain dans la boucle »). Plus d'« Opus 4.7 » ni d'émetteur AArch64.
5. **`CLAUDE.md` à la racine de jak-project** pour que le worker ne charge plus celui de `~/code` (snag/cairn/jaunt, `cargo build`).
6. **Mémoire** : `MEMORY.md` réécrit en ≤ 120 pointeurs d'une ligne ≤ 120 caractères, règles d'abord, physique en dernier ; les 130 instantanés de phases de juin et les notes physiques vont dans `memory/archive/` hors index. Hook de fin de session qui refuse une ligne d'index > 160 caractères.
7. **Préambule** de l'orchestrateur réduit à une seule politique de preuve avec plafond chiffré (voir étape 2).

Critère : mesure de `block(pid)` ≤ 12 Ko pour trois phases différentes ; un essai de phase courte (Gsubtitle-style-2) démarre et le premier appel outil du worker touche la phase, pas DIRECTIVES.

### Étape 2 : la preuve (2 jours)

Objectif : une porte qui ne peut pas être satisfaite en tapant une ligne, et qui coûte minutes, pas heures.

1. **`lib/proof_run.sh <phase> <x86|device>`** : lance le jeu, attend le compteur de la phase ou un timeout, écrit `reports/<phase>/proof.txt` avec `source=`, `sha=` du binaire, `crash=`, `frames=` et la ligne `FEATURE <phase> armed=1 hits=N` émise par le moteur. Le worker ne tape jamais ces champs. Nettoyage des `debug.opengoal.*` en `trap EXIT`.
2. **Un validateur générique** (≤ 40 lignes, un seul fichier) : fraîcheur (proof plus récent que toute source), identité (sha du binaire), pas de crash, feature active, un critère par phase déclaré dans le backlog (`gate: {key, op, value}`), ablation optionnelle. Le rapport du worker n'est jamais parsé. Les 288 validateurs existants vont dans `archive/validators/` ; les phases encore ouvertes sont migrées une par une vers un `gate:`.
3. **Le hook Stop devient consultatif** : il affiche la sortie du validateur et laisse sortir. Le blocage « continue à travailler » est ce qui a formé le réflexe « j'écris la ligne manquante ».
4. **`device: true` rétabli** pour toute phase que tu dois tester, avec les deux corrections connues : relance après 120 s si gradle ou ninja tourne, et lecture du serial sur disque (`eae4df44`, jamais autre chose).
5. **Acquis** : un script par feature validée par toi (police, herbe, cinématiques, caisses, PNJ), ≤ 90 s chacun, exécuté à chaque fermeture. Aujourd'hui il y en a un.
6. **Règles mécaniques dans `pre-tool.sh`** (mort aujourd'hui) : refuser `pkill -f`/`pgrep -f` sans crochet, `cmake -B`, `adb` sans `-s eae4df44`, toute commande visant l'adresse de la SHIELD, `screencap` et l'écriture de `.png` sous `reports/`. Chaque règle qui devient un hook sort du prompt.
7. **Budget de preuve par essai** dans l'orchestrateur : avertissement à 3 runs, arrêt de l'essai à 45 min cumulées de runs.
8. **Rapport ≤ 40 lignes** pour toi : verdict en une phrase, ce qui a changé, 8 lignes de preuve copiées de `proof.txt`, ce que tu dois regarder, ce qui n'est pas prouvé. Les notes de labo vont dans `reports/<phase>/notes/`, jamais lues par une porte.

Critère : une phase migrée passe vert avec le validateur générique, et le même validateur passe rouge quand on remplace `proof.txt` par un fichier écrit à la main (sha faux).

### Étape 3 : l'orchestrateur (1 jour)

Corrections ciblées, pas de réécriture. Chacune est une référence de ligne dans review-mechanics.

1. Preflight : `check_shield_untouched` en `yield`, test unitaire « chaque check rend des triplets », réduit à 4 checks (GD-LINK, SELF-KILL, DEVICE-PROP-LEAK, REPORT-STALE), plafond 5 lignes injectées.
2. SIGTERM / Ctrl-C : l'essai interrompu n'est ni compté, ni empreinté, ni committé.
3. « Pas de démarrage » : borné à 6 itérations, stderr de claude conservé, dormir jusqu'à l'heure de reset renvoyée par l'erreur.
4. Heuristique 529 : ne lire que les événements `error` de l'API, jamais les sorties d'outils ; un exit 143 est un kill, pas une panne.
5. Journaux jamais écrasés : numéro d'essai monotone, `attempt-NN` jamais ouvert en `w` deux fois.
6. `main` : lecture du jeton `owner-ok` avant le saut « parquée » (les 9 phases bloquées ferment).
7. Hooks : résoudre la phase par `AUTOPORT_PHASE_ID`, jamais par index.
8. Watchdog de progrès : empreinte sans APK ni `tmp/`, et compter les fichiers de `reports/<phase>/notes/` comme du progrès.
9. `state.json` : écriture atomique + numéro de version ; refus d'écrire si la version a bougé.
10. Suppression des ~350 lignes de gestion de quota (seuils à 999) et de `notify.sh`. Le seul comportement voulu : sur 429 au démarrage, attendre le reset.
11. Reprise du contexte : à chaque essai raté, le worker écrit `reports/<phase>/handoff.md` (≤ 30 lignes : ce que j'ai établi, ce que j'ai tenté, ce qui reste) ; l'essai suivant le reçoit à la place des 4 Ko de validateur.
12. `session-end.sh` n'ajoute plus 38 Ko de `state.json` au log (52 Mo aujourd'hui).

Critère : `python -m pytest .autoport/tests/harness/` avec des tests sur preflight, fingerprint, sélection de phase et parsing 529 ; un Ctrl-C pendant un essai laisse `retries` inchangé.

### Étape 4 : le démon de build (½ journée)

1. Déclencheur : jamais sur un commit WIP. Build uniquement sur un commit de passage de validateur, ou sur un fichier `.autoport/.build-request` posé par le worker quand le code est final (ce que le préambule demande déjà).
2. Verrou partagé `.deploy-in-progress` avec PID vivant, lu par `proof_run.sh` et `close_gate` avant tout `gk` ou `adb`.
3. Plus de `gradle clean` par défaut.
4. Push continu vers jak-builds conservé, y compris non vert, comme tu l'as demandé le 11 août et le 1er septembre. Les notes de release sont générées depuis le backlog (section « à tester »).

Critère : un WIP commit ne lance aucun build ; un `gk` x86 lancé pendant une construction attend au lieu de mourir.

### Étape 5 : le backlog (1 jour, migration sans perte)

Nouveau fichier `backlog.yaml`, généré par script depuis `milestones.yaml` + `state.json` + `owner-ok/` + les commits, puis relu par toi.

```yaml
- id: cutscene-npc-flicker
  feature: "PNJ qui clignotent pendant les cinématiques"   # l'unité que TU valides
  status: open | in-progress | to-test | validated | blocked | archived
  owner_feedback:                                           # tes mots, datés, jamais réécrits
    - {date: 2026-08-31, text: "le problème des PNJ qui apparaissent, disparaissent… est revenu"}
    - {date: 2026-09-03, text: "bah non c'est toujours pété"}
  gate: {key: flicker_episodes, op: "==", value: 0}
  device: true
  depends_on: []
  history: [Gcutscene-npc-flicker, Gcutscene-npc-flicker-2]  # anciens ids, pour git log
```

Règles :
- **Une feature = un item.** Rouvrir = passer `validated` → `open` avec un nouveau retour dans `owner_feedback`. Plus de clone `-2`. Le prompt est régénéré depuis l'item (5 rubriques : défaut cité, cause connue, livrable, preuve exigée = le `gate`, hors périmètre).
- **`status` est la seule vérité.** `state.json` ne garde que les compteurs d'essais. Le curseur positionnel disparaît : l'orchestrateur prend le premier `open` sans dépendance ouverte, dans l'ordre de priorité du fichier.
- **Ton feu vert est un fichier que tu produis**, pas une transcription : `owner-ok/<id>` contient ta phrase, la date, et le sha du build testé (le superviseur te propose la commande, tu la valides).
- **Migration** : les 221 phases complétées deviennent `validated` si un jeton cite tes mots, `to-test` si le jeton est vide ou écrit par le superviseur, `archived` pour les 15 phases A* de mai. Les 41 « completed / NOT done » passent en `to-test`. Les 9 parquées avec jeton passent `validated`. Tu reçois la liste et tu tranches ce qui est litigieux.
- **Une commande `autoport status`** qui imprime trois blocs : en cours (une ligne), à tester (feature + build + où regarder), bloqué (pourquoi, ce qu'on attend de toi). C'est cette sortie qui alimente le digest et les notes de release. Le fichier `OWNER-VERIFY-QUEUE.md` disparaît.

Critère : `autoport status` produit la liste ; tu confirmes qu'aucune feature déjà validée n'y apparaît en « à tester ».

### Étape 6 : le superviseur (½ journée)

Le rôle est bon et la session fait le travail de traduction : on la garde. Ce qu'on change, c'est sa trace et son coût.

1. **Une trace propre** : chaque écriture du superviseur (prompt, validateur, backlog, jeton) est committée sur-le-champ sous `[autoport/supervisor]`, et l'orchestrateur ne fait plus `git add -A` (il ne commite que les chemins touchés par le worker). Aujourd'hui ses écritures partent dans les commits des workers et sa piste est invisible dans git.
2. **Un prompt système de 60 lignes** à la place des 434 actuelles (Opus 4.7, Geyser Rock, buckets A-F). Rôle : traduire tes messages en items de backlog, poser tes jetons, arbitrer les blocages, entretenir les acquis. Interdits : éditer le moteur, lancer des campagnes, toucher un appareil.
3. **Le cron** : plus de contexte figé dans le prompt du digest (il cite encore la phase 232 du 26 août). Le digest lit `autoport status --changed` ; s'il ne sort rien, deux lignes ou pas de tour du tout. Trois rubriques, ≤ 12 lignes.
4. **Ordre = fichier.** Un ordre du type « n'y touche plus » devient une règle de hook (étape 2.6) ou un champ de backlog, le jour même, et le superviseur te montre le diff.
5. **La session** : tu peux garder la session longue si elle te convient. Ce qui doit changer, c'est que l'état vive dans les fichiers (`backlog.yaml`, `autoport status`) et non dans le contexte compacté, pour qu'une reprise après quota ou PC éteint reparte de la vérité et non d'un résumé. Je recommande une session par semaine, relancée avec `autoport status` en entrée.

Critère : trois jours de fonctionnement sans que tu aies à demander « tu bosses sur quoi ? », et un `git log` qui montre les écritures du superviseur sous son propre préfixe.

### Étape 7 : nettoyage (½ journée, en dernier, réversible)

- 942 scripts jetables à la racine de `.autoport/` → `archive/scripts/<phase>/` (déplacés, pas supprimés).
- `reports/` (9,1 Go) : garder `report.txt`, `proof.txt`, `notes/` ; les logs bruts > 30 jours vont dans `archive/` compressés.
- `SUPERVISOR_JOURNAL.md`, `REDESIGN.md`, `SUPERVISOR_PROMPT.md`, `SPEC-COVERAGE.md` → `archive/`.
- `model-profiles.json` : garder le profil actif et un seul de secours ; `apply-model-profile.sh` exécuté pour que les agents et l'orchestrateur disent le même effort.
- Branches : `master` et `physics-keira-clean` ont divergé de plusieurs milliers de commits. Décision à prendre : `physics-keira-clean` devient la branche de travail officielle et `master` est archivée sous un autre nom, ou l'inverse. Je recommande la première.

---

## 5. Ordre, effort, risques

| Étape | Effort | Dépend de | Gain attendu |
|---|---|---|---|
| 0 gel | 2 h | rien | plus de perte pendant les travaux |
| 1 contrat | 1 j | 0 | contexte 63 k → ~10 k tokens ; fin des tâches comprises de travers |
| 2 preuve | 2 j | 1 | fin des faux verts par grep ; preuve en minutes |
| 3 orchestrateur | 1 j | 0 | fin des essais brûlés, des boucles de 19 h, des journaux écrasés |
| 4 build | ½ j | 3 | fin des faux rouges x86 et des builds de nuit |
| 5 backlog | 1 j | 0 (migration) | une liste « à tester » vraie ; plus de features re-listées |
| 6 superviseur | ½ j | 5 | un superviseur avec une trace git, un cron qui coûte zéro quand rien ne change |
| 7 nettoyage | ½ j | tout | 19 Go → quelques centaines de Mo ; preflight qui ne scanne plus 942 scripts |

Les étapes 1, 3 et 5 sont indépendantes et peuvent avancer en parallèle. Total : environ 6 jours de travail de harnais, pendant lesquels le harnais ne fait pas de jeu. C'est le prix : trois semaines de physique ont produit zéro phase close, donc six jours d'atelier sont rentabilisés dès la première semaine à 5 phases.

Risques :
- **Casser une phase en cours.** Parade : étape 0 avant tout, tag git, et l'ancien orchestrateur reste lançable depuis le tag.
- **Migration du backlog qui te fait revalider des choses.** Parade : tu relis la liste générée avant qu'elle devienne la vérité ; tout item litigieux reste `to-test` avec ton mot.
- **Le validateur générique trop lâche.** Parade : le `gate:` par phase est obligatoire pour toute phase `device: true`, et la fraîcheur + le sha ferment la voie « j'écris la ligne ».
- **Rechute.** Le harnais a regrossi 48 h après l'élagage du 1er septembre. Parade : plafonds durs (12 Ko de contrat, 40 lignes de validateur, 5 lignes de preflight) qui font échouer le lancement quand ils sont dépassés, pas des consignes.

---

## 6. Ce que je propose maintenant

Rien n'a été touché. Sur ton feu vert, je fais l'étape 0 puis l'étape 1 dans cette session (les deux sont réversibles par le tag), et je te rends un `autoport status` de l'étape 5 en lecture seule pour que tu tranches la migration. Les décisions que tu dois prendre :

1. Rétablir `device: true` sur les phases que tu testes (recommandé : oui).
2. Validateur générique + `gate:` par phase, ou garder un validateur par phase (recommandé : générique, les validateurs par phase regrossissent en 48 h).
3. Branche officielle : `physics-keira-clean` (recommandé) ou `master`.
4. Le mot de passe sudo.
