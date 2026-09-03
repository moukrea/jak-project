# Worker context audit — autoport harness (phase Gcutscene-npc-flicker-2, 2026-09-03)

Read-only audit. Nothing edited, no build, no orchestrator run. The assembled directives block is
saved at `scratchpad/assembled-directives.txt` (167,285 chars, version `vd9e8b66782`, serial 9).

## 1. What the worker receives, by source

Tokens at 3.5 chars/token (lead's convention; real French-with-accents tokenization is worse).

| Source | Chars | ~Tokens | Phase-specific? | Notes |
|---|---:|---:|---|---|
| `lib/directives.py block()` header + echo rule | 1,200 | 340 | no | version line, subagent rule |
| **DIRECTIVES.md** (inlined whole) | ~155,000 | **~44,300** | **no — about Keira breast physics** | 67 H2 sections, 66 dated 2026-08-11..08-28, 1 dated 09-02 |
| SPEC-keira-physique.md (inlined, designated by DIRECTIVES) | ~10,800 | ~3,100 | **no — Keira physics** | 8 sections, test-room, collisions |
| Preflight block | 0 | 0 | — | **crashes** (`ValueError` in `prompt_block`: `check_shield_untouched` yields bare strings `"ok"` / `"[SHIELD-GUARD ok] …"` instead of 3-tuples). If it worked it would inject **144 `METRIC-FRAME` WARNs about `phys-room.gc` / `physics_room_table.py`** = 39,347 chars ≈ 11.2K tokens of Keira-room noise into the NPC-flicker prompt |
| WORK ECONOMY / BUILD & DELIVERY / PROOF ECONOMY preamble (orchestrator.py:1267-1330) | 3,604 | ~1,030 | no | hard-coded, English |
| Phase prompt `prompts/phase-Gcutscene-npc-flicker.md` | 2,174 | ~620 | **yes** | 37 lines |
| Previous validator tail (attempt 2) | 71 + wrapper | ~80 | yes | `[Gcnf ok] …` — i.e. the previous attempt **passed** its validator; the retry exists because the owner said it is not fixed |
| `hooks/session-start.sh` output | ~1,400 | ~400 | 1 line (phase id/name/validator) | rest is stale boilerplate: "you are **Opus 4.7**", "x86 emitter under `goalc/emitter/`… mirror it for AArch64" (phase-A era) |
| `/home/emeric/code/CLAUDE.md` (parent dir, auto-loaded) | 2,771 | ~790 | no — **about snag/cairn/jaunt** | tells the worker to read `~/code/task-list.json`, `progress.md`, run `cargo build`, commit in conventional-commit English — none exists/applies here |
| MEMORY.md (auto-memory index) | 24,968 of 79,376 bytes loaded | ~7,100 | no | truncated at ~25 KB: **97 of 412 lines / 82 of 372 entries load; 290 entries (78%) are cut off** |
| Skills + deferred tool listing (system prompt) | ~13,000 | ~3,700 | no | Atlassian/Gmail/Chrome MCP, 20 skills — irrelevant to a headless worker |
| Agent definitions (3 × ~2 KB) | 6,067 | ~1,700 | no | only descriptions in the manager's prompt; the full body goes to each subagent, and each subagent is ordered to **re-read DIRECTIVES.md in full** (+~45K tokens per subagent launch) |
| **Total at turn 0** | ~220,000 | **~63,000** | **≈700 tokens (~1.1%) are about the phase** | |

Measured effect (logs/Gcutscene-npc-flicker-2/attempt-01.jsonl): 463 turns, 82 min, **$142**, 209 M
cache-read input tokens (≈452K tokens re-read per turn), 725 Bash calls, 3 subagents (each 4–11 K-char
prompt, each carrying the DIRECTIVES version line as ordered). Attempt 2 (in flight): 169 Bash calls,
0 subagents, worker `cat`s DIRECTIVES.md twice and MEMORY.md once on top of the inlined copy.

Generic vs phase-specific: **~99% generic or wrong-phase.** The largest single block (DIRECTIVES +
SPEC ≈ 47K tokens, 75% of the context) is entirely about Keira's breast/hair physics
(`keira|poitrine|sein|mèche|chestL`: 193 hits; `cinémat|PNJ|flicker`: 1 hit).

## 2. DIRECTIVES.md — full read, classification

2,296 lines, 67 H2 sections. Git history: 71 edits, 24 on 2026-08-11 alone; last non-physics edit
2026-09-02 (one 8-line section appended). It is a **dated journal of the Keira physics phase**
(`Grecharged-secondary-motion`), not a standing-orders document.

### (a) Still-relevant standing orders (7 sections, ~12% of text)
- `## RÈGLES QUI NE SE NÉGOCIENT JAMAIS` (8 rules): no comment-as-proof, no false green, no visual
  proof, no silent de-scope, gates frozen, no force-push / rm -rf / pkill-by-pattern. **Rules 4, 6, 7
  are physics-specific** ("chaînes viennent du rig", "rien ne traverse le mesh", "une mesure par chaîne").
- `## RÈGLE DE REPRISE` (owner feedback reopens the phase), `## RÈGLE DE NON-DESTRUCTION` (fix at the
  producer), `## DEUX APPAREILS` (Redmi vs Honor), `## PREUVES PROGRAMMATIQUES` (09-02), `## RAPPORT`
  (echo the version), the lock-PID convention (08-14 07:10).
- ~60 of the 67 sections could be dropped from every non-physics phase with zero loss.

### (b) Stale / obsolete (≥ 52 sections)
- **The `PÉRIMÈTRE ACTIF` block itself** names `Phase : Grecharged-secondary-motion`, branch
  `physics-keira-clean`, "KEIRA SEULE… aucun autre modèle ne reçoit de données", "CONTRAT UNIQUE:
  SPEC-keira-physique.md". The worker for a cutscene-NPC phase is told its scope is Keira's breasts.
- 13 "PASSE DE L'OWNER" sections (08-11/12) with per-build tuning numbers (`raideur 2.60 → 3.30`,
  `lBoob 656→676`), all superseded the same day; an explicitly `[RETIRE 03:40]` section is still in
  the file; `## ÉTAT MESURÉ … 2026-08-11 10:00` ("806 lignes compilent") is a snapshot.
- Sections 08-19 → 08-23 are a running argument about §22/§33 of `SPEC-breast-softbody.md`
  (a file that is *not* the inlined SPEC) — 10 sections that each "retract" or "correct" the previous.
- `## 2026-08-14 07:30 — PLUS AUCUNE PHYSIQUE SUR KEIRA SAUF LES SEINS` replaced "tous les
  précédents", then `# DIRECTIVE OWNER 2026-08-28 — LA CIBLE … C'EST LE MOTEUR` replaced it again;
  both stay in the file, in reverse chronological order for the first half and chronological for
  the second (the file was appended at both ends).
- session-start.sh: "Opus 4.7"; the active profile is `fable51-high` (`claude-fable-5-1[1m]`).

### (c) Contradictions (each pair is live in the same prompt)
1. **"Aucun APK ne repart tant que `ROOM-GRAVSAG` n'est pas non nul"** (l.1768) vs **"Aucune
   condition de qualité ne retient un build"** (l.1788, same day, self-retraction left in place).
2. **"RÈGLE DE CONSERVATION: si le plancher casse, le point est retiré"** (l.1986) vs
   **"Un plancher qui casse n'est plus un motif de retrait… ELLE REMPLACE LA RÈGLE DE CONSERVATION"** (l.715-719).
3. **Rule 5 "Gates gelées. N'ajoute, ne modifie… aucune gate"** (l.1362) and implementer/researcher
   HARD LOCK on `.autoport/validators/**` vs **"Toute gate qui contredit une ligne de la SPEC est
   fausse par construction: on corrige la gate"** (l.966) and phase prompt (b) "poser une garde de
   NON-REGRESSION qui échoue si le symptôme revient" — the worker must add a guard it is forbidden to add.
4. **"INTERDIT… toute nouvelle gate, tout réglage de stiffness/damping/gravity"** (l.1059, 08-13)
   vs **"Réappliquer la calibration §24… ne plus jamais la retirer"** (l.961, 08-14) and the 08-11
   sections that each demand a new `ROOM-*` measurement.
5. **"Une seule chose simulée: chestL/chestR… Le reste vient après, sur son ordre, jamais par
   initiative"** (l.825-833) vs **"Sortir de la mono-chaîne dès qu'une famille est stable: instancier
   une deuxième famille (cheveux ou oreille)"** (l.2143) and SPEC §1 "Oreilles · cheveux · mèches ·
   seins · lunettes… un élément déclaré mais inerte est un échec".
6. **"CONTRAT UNIQUE: SPEC-keira-physique.md"** (l.1328, the inlined one) vs **"SPEC-breast-softbody.md
   AUTORITAIRE… À LA LETTRE"** (l.974) vs **"LA SPEC EST LA SEULE REFERENCE. TOUT CE QUI PRECEDE NE
   COMPTE PLUS"** (l.621) — and PITFALLS `gate-must-quote-the-spec` says SPEC-keira-physique.md was
   "MON resume numerote… absent du disque": the harness inlines as *the contract* the document the
   pitfall register calls a fabrication.
7. **"le validateur ne sert plus JAMAIS d'indicateur d'avancement"** (l.62) vs session-start
   "**Validator (the ground truth)** … do not declare success until the validator exits 0" and the
   retry wrapper "Do not declare success until `bash validator` exits 0".
8. **PROOF ECONOMY "MUST NOT build elaborate new proof harnesses, multi-leg device campaigns… proof
   runs are MINUTES… ship with an honest 'not proven: X'"** vs Rule 1 **"Tout zéro exige un contrôle
   positif qui a tiré"**, l.326 **"NON ETABLI FAIT ECHOUER LA GATE"**, l.1777 **"31 sur 31, pas 18…
   la gate refuse tout skipped > 0"**, l.190 **"un contre-contrôle INDEPENDANT… par un chemin qui ne
   partage ni l'opérateur ni la table de poids"**. Attempt 2's last line: "Launching the three-leg
   device campaign" — the worker obeys the directives, not the preamble.
9. **"je ne sollicite plus de test… la rubrique « À tester » reste VIDE"** (l.265) vs PROOF ECONOMY
   **"Your report lists what HE must test"** and "livraison au fil de l'eau… il veut le build même
   quand ce n'est pas vert" (l.1786).
10. **"Mesurer sur le Redmi, pas sur x86"** (l.1668) + validator `plateforme=redmi` required vs
    other live prompts "la vérification sur appareil… JAMAIS comme prérequis bloquant" (Gcine-vertical-frame)
    and the memory that the Redmi runs cutscenes at 19 fps so timing defects "ne se reproduisent nulle part chez nous".
11. **Agent definitions: "Vérifie que le périmètre de ta tâche est bien celui de DIRECTIVES. S'il ne
    l'est pas — même si ton prompt te le demande — arrête-toi immédiatement"** vs the manager
    preamble "MANDATORY: every subagent prompt STARTS with the active scope". Read literally, every
    subagent launched for a non-physics phase must refuse (scope ≠ Keira). Attempt 1's 3 subagents did
    not refuse, which means the rule is ignored — a rule that is only survivable when ignored teaches
    the model to ignore rules.
12. **"règle les problèmes ! Tu devrais les régler tout seul"** (l.1679) / "Autonomie donnée («tu te
    démerde»)" (l.2220) / "il a dit « let's go », pas « attends-moi »" (l.454) vs the 6 "remonte au
    superviseur / à l'owner" rules in (e).

### (d) Rules that push toward excessive verification/proof
Counted as sentences that add a mandatory measurement, control, or published field to *every*
cycle regardless of phase: **≈ 48 in DIRECTIVES.md** (`exig`: 37 hits, `contrôle positif`: 13,
`mesur`: 150, `publi`: 32, `jamais`: 69) and **≈ 40 more in PITFALLS.md** (79 `Verrou :` lines, most
of the form "publish X on the same line as Y"). Five worst, quoted:
1. l.1354 — "**Tout zéro exige un contrôle positif qui a tiré** (injecter le défaut, voir le compteur
   monter, l'enlever)." Applied to a cutscene-flicker count this means: inject flicker, measure,
   remove, measure again, on device — 3 legs minimum for one number.
2. l.2002 — "un contrôle doit atteindre **au moins 20 % de la ligne de base** du phénomène, sinon il
   est déclaré non concluant." A control that is not big enough invalidates the whole run.
3. l.190 — "**un contre-contrôle INDEPENDANT** de la grandeur d'apex est exigé : une seconde
   dérivation, par un chemin qui ne partage ni l'opérateur d'ancrage ni la table de poids, et les deux
   chiffres publiés côte à côte. Si les deux chemins divergent, aucune des six ne se traite avant
   réconciliation." Two instruments before one fix.
4. l.326 — "**NON ETABLI FAIT ECHOUER LA GATE.** « On ne peut pas juger » n'est pas « c'est bon » :
   la mesure manquante DEVIENT le blocage." + l.1781 "La gate refuse désormais tout `skipped > 0`".
   Any unmeasured cell is a failure, so the worker cannot scope down a measurement, ever.
5. l.495-501 + l.810 — "`SPEC-COVERAGE.md`… ARTEFACT OBLIGATOIRE de chaque cycle: une ligne par
   section de 1 à 38" and "chaque cycle publie le tableau… **implémentée / mesurée / écart**" — a
   38-row conformance table per cycle, for a spec that has nothing to do with 90% of phases.
Runners-up: "toute longueur publiée porte sa valeur brute ET sa conversion", "toute ligne du
registre porte la citation VERBATIM en anglais et son numéro de ligne", "toute ligne gauche/droite
publie l'écart au miroir", "publier LES TROIS grandeurs (borne, moyenne, part)", "le nombre
d'échantillons de la trace ET celui utilisé", "Livrer les quatre nombres avant de choisir".

### (e) Rules that push toward asking/blocking instead of acting (9)
- l.225 "deux cycles consécutifs sans changement de statut d'une section se remontent au superviseur… au lieu d'enchaîner un troisième"
- l.223 "un cycle qui touche à l'instrument NOMME la section dont il débloque le verdict, avant de commencer"
- l.1362 rule 5 "Si une gate te semble fausse, tu le rapportes ; c'est le superviseur qui tranche"
- l.452 "remonté à l'owner comme une question ouverte sur sa spec"
- l.833 "Le reste du personnage vient après, sur son ordre à lui, jamais par initiative"
- l.1338 "Aucun autre modèle ne reçoit de données"
- agents ×3: "STOP and report the discrepancy instead of improvising"; "arrête-toi immédiatement et rapporte le hors-périmètre"
- session-start doublon branch: "Tu n'édites rien… tu t'arrêtes"
- PITFALLS `human-gate-counted-as-a-retryable-failure`, `green-validator-is-not-conformance`
Counter-signals exist (l.1679, l.2220, l.454, "no silent de-scope") — so the worker receives both
"decide yourself" and "escalate after two cycles" with no rule saying which wins for which case.

### (f) Duplicated content
- **DIRECTIVES ↔ PITFALLS**: 22 of the 68 `GUARD` entries point *into* DIRECTIVES.md as their marker
  (`GUARD comment-not-proof .autoport/DIRECTIVES.md …`, `tabula-rasa-inventory`, `target-is-response`,
  `invented-owner-approval`, `gate-vetoes-the-owner`, `truncated-series`, `deploy-lock-needs-pid`,
  `wired-but-disarmed`, `wrong-yardstick`, `bone-without-reskin`, `engine-units-are-not-mm`,
  `spec-line-quoted-from-memory`, `instrument-fix-stops-at-the-verdict-line`,
  `measurement-axis-is-not-the-spec-axis`, `asymmetry-line-must-carry-its-pose`,
  `priority-built-on-a-single-extremum`, `my-engine-limit-presented-as-a-spec-property`,
  `green-validator-is-not-conformance`, `a-channel-for-a-response-is-a-mirror`,
  `hardcoded-preset-value-is-a-mirror`, `INVENTAIRE AVANT DE RASER`, `4096 u = 1 m`). Each is the
  same story told twice, once as a dated section and once as a GUARD.
- **DIRECTIVES ↔ preamble**: "livraison au fil de l'eau" (l.1784, l.267, l.727) ≈ BUILD & DELIVERY;
  "Aucune preuve visuelle" (rule 2) ≈ PROOF ECONOMY "visual-measurement campaign (permanently banned)"
  ≈ 09-02 section ≈ Gfont prompt "REGLE OWNER 2026-09-02" ≈ validator comment ≈ MEMORY line 1 of
  "Owner rules". Five copies of one rule.
- **DIRECTIVES ↔ agents ↔ memory**: "Redmi eae4df44 / never emulator-5554" (DIRECTIVES l.1870,
  researcher.md, tester.md, `reference_real_device`); "never pkill by pattern" (rule 8, PITFALLS
  `pid-files`, memory `never-pkill-claude`); lock PID (DIRECTIVES 08-14 07:10, PITFALLS
  `deploy-lock-needs-pid`, memory `feedback_lock_pid_from_tool_shell_is_dead`); "4096 u = 1 m"
  (DIRECTIVES l.663, PITFALLS l.411 which itself says "Déjà consigné en mémoire projet, et j'y suis
  retombé").
- **DIRECTIVES ↔ SPEC-keira-physique**: the SPEC's §7 re-states rule 0, rule 1 and the "trois
  questions" verbatim; §5 re-states the "PRÉCISION SUR LA PRIORITÉ D'ANIMATION" section.

## 3. PITFALLS.md and the auto-memory

### PITFALLS.md (67,895 bytes ≈ 19.4K tokens, 68 GUARD entries, last edit 2026-08-23)
- (a) generically useful: ~14 (`pid-files`, `dirty-tree`, `build-identity`, `gate-deadlock`,
  `prompt-via-stdin`, `truncated-listing`, `find-newermt-bare-time`, `regenerable-is-not-unused`,
  `absent-by-wrong-name`, `hyst-substring`, `blocking-gate-must-run-last`,
  `verdict-must-accumulate-not-exit`, `human-gate-counted-as-a-retryable-failure`, `trigger-nobody-calls`).
- (b) Keira-physics-only: ~50 (`meshpen`, `skinpen`, `B0`, `§22`, `chestL`, `lBooc`, `rootdev`,
  `ROOM-*`…). `keira|poitrine|sein|mèche`: 24 hits; cinematics: 0.
- (c) contradicts DIRECTIVES: `gate-must-quote-the-spec` (SPEC-keira-physique.md "absent du disque…
  MON résumé") vs directives.py inlining it as the contract; `green-validator-is-not-conformance` vs
  session-start "ground truth".
- (d) verification-inflating "Verrou :" lines: ~40 (see 2d).
- (f) 22 duplicates of DIRECTIVES sections (list in 2f).
- It is **not** in the worker prompt (only via preflight's `check_guards_still_installed`, which
  currently crashes), so its main cost is when workers/subagents `cat` it (attempt 2 did not; the
  memory index tells them to).

### MEMORY.md (79,376 bytes, 412 lines, 372 entries; 763 memory files, 3.8 MB)
- Truncation: Claude Code loads ~25 KB. The last loaded entry is line 97 ("§11 : le COM est DEJA
  livre…"). **315 lines / 290 entries (78%) never load**, including the entire sections `Solver /
  physics`, `Models / actors`, `Device / harness`, `Build / deploy / staleness`, `arm64 / GOAL classes`,
  `G-phase`, `jak2`, `Recharged gfx` — i.e. every section that is not Keira physics.
- Line length: **191 of 372 entries exceed 200 chars** (mean 205, median 201, max 433). Each entry is a
  mini-memory (quotes, numbers), not a pointer, which is what pushes the useful sections out of the window.
- Index coverage: 763 files, 372 indexed → **391 (51%) unreachable by index**, and of the 372 indexed
  only 82 load → **~89% of memory files are unreachable at session start**. PITFALLS
  `registry-unindexed` already recorded the same defect at 610/335 and the fix (propagate to
  SPEC-COVERAGE) did not address the index.
- Age: 425 of 763 files were written in August; 130 in June are phase-state snapshots (`project_f1d_state`,
  `project_f1e_state`, `project_g1_state`…) that describe long-closed phases and still link each other.
- Sample of 15 files (5 newest, 5 mid, 5 old): 5 current and useful (`bind-rest-length…`,
  `hd-stretch-is-w-lane…`, `defect-reported-through-a-broken-acquis`, `bone-probe…`,
  `redmi-vs-honor…`); 5 Keira-physics (`hair_gradient_needs_geometry`, `attic_gradient_mechanism`,
  `gate_root_vacuous_chord_bound`, `hd_bake_deletes…` (self-marked RESOLVED), `delivery_hd_pack…`); 5
  obsolete phase snapshots from June. Every "feedback" file ends with a **How to apply** that adds a
  publication requirement ("publier les deux… avec la preuve de l'état LIÉ"), so the memory corpus is
  a third copy of the verification-inflation in (2d).
- Top-of-index entries are the newest physics discoveries, not the rules; a worker on a non-physics
  phase gets 7K tokens of `w3=0,9982`, `§22 apex ceiling`, `comw=` and none of the build/device pitfalls.

## 4. Phase prompts (current + 7 recent, idx > 240)

| Prompt | Bytes | Task clear? | DoD cheap to check? | Owner-quote/history share | Notes |
|---|---:|---|---|---:|---|
| phase-Gcutscene-npc-flicker.md (current, reused by `-2`) | 2,174 | yes | **no** | ~40% | DoD = 4 marker lines incl. `NPCPRIOR` (archaeology of past fixes) + `NPCGUARD`; but the **validator asks for 3 more things the prompt never states**: `plateforme=redmi`, `scene=*mayor* pnj=mayor`, `NPCCULL dans_frustum_et_culled=0`. Worker learns the real DoD only from the validator script. `hd=<0|1>` asks the worker to decide HD vs visibility before measuring. |
| phase-Gcutscene-skip-all.md (reused by skip-polish-2) | 1,550 | yes | yes | ~20% | best of the set: 5 bullets + 4 markers; but `skip-polish-2` runs on *this* prompt while its actual spec (capsule radius, margins, "n'apparaît pas dans le menu principal") lives only in a commit message and milestones `name` |
| reports/Gfont-regression/owner-defects.txt (used **as** the prompt) | 3,173 | yes | partly | ~45% | a defect report, not a spec; mandate is 4 imperatives; fine |
| phase-Ghd-skin-origin-stretch.md | 4,389 | yes → **then replaced** | yes after §"CADUC" | ~30% | half the file is superseded ("CE QUI PRECEDE EST CADUC") but kept; two marker formats, only one valid |
| phase-Gjak1-crate-collision.md (reused by `-2`) | 5,455 | yes → replaced twice | yes | ~35% | three layers: original, "MANQUE CONSTATE", "CORRECTION DE METHODE… CE QUI PRECEDE EST CADUC"; 8 marker names, 4 obsolete |
| phase-Grecharged-foliage-wind3.md | 1,604 | yes | yes | ~25% | good: D1→D2→D3 order + 4 markers |
| phase-Gfixed-tick-anim-interp.md | 2,086 | yes | yes | ~10% | good: cause named, path to reuse, 4 markers with thresholds |
| phase-Gcine-vertical-frame.md | 4,066 | yes | yes | ~25% | "CINQUIEME fois… LIS-LE EN ENTIER AVANT DE TOUCHER UNE LIGNE" + 7 markers + 30/08 addendum |
| phase-Gloading-screen.md | 18,126 | no single task | no | **~60%** | 6 dated "RETOUR OWNER" layers, 17 numbered sub-defects, no marker/DoD section at all; the archetype of "accumulated retry-history instead of a spec" |

Pattern: prompts are written once as spec+markers (good), then **appended** with owner reactions and
supervisor "CADUC" rewrites instead of being rewritten. Median prompt 3.8 KB, but 11 prompts exceed
23 KB (`Grecharged-grass-poc.md` 94 KB, `pbr-realtime-fusion` 68 KB). Milestones reuse the *same*
prompt file for retry phases (`-2`) while the new requirements live in the milestone `name` string
and the validator — the worker sees the old prompt, the harness grades the new spec.

## 5. lib/directives.py — how the block is built

- `block(pid)` = header (version + echo rule + subagent rule) + **entire** DIRECTIVES.md (`txt.strip()`)
  + entire SPEC named by the first `` `.autoport/prompts/SPEC-*.md` `` occurrence in DIRECTIVES.md.
  Nothing is per-phase; `phase_id` is only read to hash the prompt in `parts()` and then **not used**
  by `version()` (which hashes serial + `## PÉRIMÈTRE ACTIF` section + SPEC). Same version string for
  all 278 phases.
- **No size cap, no section selection, no age filter.** The comment "Only the ACTIVE SCOPE block
  feeds the version" applies to the hash, not to what is inlined.
- The scope stamp (`SCOPE-SERIAL: 9`) lives inside the `PÉRIMÈTRE ACTIF` section, which describes
  `Grecharged-secondary-motion`; bumping it would invalidate attempts of unrelated phases.
- `_spec_path` picks the first backticked `SPEC-*.md` path in the file: today `SPEC-keira-physique.md`;
  `SPEC-breast-softbody.md` (the one 20 sections call "AUTORITAIRE") is not backticked with a path and
  is therefore never inlined. `SPEC-c20-code-changes.md` (21 KB) sits next to it, unreferenced.
- The subagent rule is enforced twice: in the block and in `.claude/agents/*.md` ("Lis
  `.autoport/DIRECTIVES.md`… puis le contrat de périmètre… en entier"). Cost per subagent launch:
  ~50K tokens of reading before the first useful tool call.
- Orchestrator: `instructions = "ultrathink\n\n" + _dblock + _pblock + delegation_preamble + prompt`
  — the phase prompt is the **last** 600 tokens after 50K tokens of physics; the validator tail (if
  any) is appended after it. Prompt travels via stdin (fixed after the E2BIG crash at 106 KB — the
  contract has grown 58% since that fix).

## 6. Ten most impactful context problems, ranked

1. **The "contract" is a 47K-token Keira-physics journal inlined into every phase.** Evidence: 66/67
   sections dated 08-11..08-28 about breasts/hair; `PÉRIMÈTRE ACTIF` = `Grecharged-secondary-motion`;
   193 physics hits vs 1 cutscene hit; 75% of turn-0 context; $142 / 82 min / 209M cached input
   tokens for one attempt. **Fix:** split DIRECTIVES.md into `DIRECTIVES.md` (standing orders only,
   ≤ 3 KB: the 8 rules minus 4/6/7, reprise, non-destruction, deux appareils, preuves programmatiques,
   rapport) and `journal/keira-physics-2026-08.md` (never inlined). `block()` inlines the standing
   orders + a per-phase `SCOPE-<phase>.md` if present; hard cap 12 KB with a loud error above it.

2. **The scope mechanism tells non-physics workers and every subagent that their task is out of
   scope.** Evidence: agents' "arrête-toi immédiatement" + `PÉRIMÈTRE ACTIF` naming another phase;
   one version string for all phases; subagents ordered to re-read 160 KB. **Fix:** make the scope
   per phase (`version(pid)` hashes `SCOPE-<pid>.md` or the phase prompt's first section); replace the
   agents' "re-read DIRECTIVES.md in full" with "the scope block is in your prompt; if absent, stop";
   drop the echo-the-version ritual or move it to a hook that checks the report file.

3. **Verification is mandated by prose in four places and contradicted by the preamble.** Evidence:
   ~48 + ~40 + memory "How to apply" rules vs PROOF ECONOMY "minutes, not hours"; attempt 2 launches a
   "three-leg device campaign" for one counter; rules 1/"20% baseline"/"NON ETABLI fails the gate"
   make scoping down impossible. **Fix:** one short PROOF policy with an explicit cost ceiling per
   phase ("one x86 run + one device run; a positive control only when the validator asks for one");
   delete the physics-era proof rules from the standing orders; put per-phase proof requirements
   **only** in the validator and quote the validator's checks verbatim in the prompt.

4. **The phase prompt and the validator disagree on the definition of done.** Evidence: validator
   requires `plateforme=redmi`, `scene=*mayor* pnj=mayor`, `NPCCULL … =0`; the prompt says none of
   this; the retry's real spec is in the milestone `name` and git commit messages; previous attempt
   passed the validator (`[Gcnf ok]`) and was still reopened. **Fix:** generate the "Preuve exigée"
   section of the prompt *from* the validator (or have the validator print its checklist with
   `--explain` and inline that); on `-2` phases write a new prompt file, never reuse the old one;
   move owner-verify criteria into the validator when the owner names a scene.

5. **Contradictory standing orders (12 live pairs, section 2c).** The worker cannot satisfy "gates
   frozen" and "pose une garde", "aucune condition ne retient un build" and "aucun APK ne repart",
   "validator is ground truth" and "validator never indicates progress". **Fix:** when a rule is
   retracted, delete the old text (git keeps history); a `preflight` check that greps the standing
   orders for known retracted phrases; one owner of each rule (validator, hook, or prose — never two).

6. **Memory index is 78% truncated and 51% incomplete, and what loads is physics.** Evidence:
   25 KB cap, 97/412 lines loaded, 191/372 entries > 200 chars, 763 files / 372 indexed, June
   phase-state snapshots still indexed. **Fix:** rewrite MEMORY.md as ≤ 120 one-line pointers (≤ 120
   chars), rules/pitfalls first, physics last; archive `project_f1*`/`g1` and all `Grecharged-*`
   physics notes into a `memory/archive/` not in the index; enforce the line length with the
   session-end hook.

7. **Preflight is dead, and its live output would be 11K tokens of Keira noise.** Evidence:
   `check_shield_untouched` yields `"ok"` strings → `ValueError` swallowed by the orchestrator; when
   fixed it yields 144 `METRIC-FRAME` WARNs on `phys-room.gc` for a cutscene phase. **Fix:** fix the
   tuple; scope checks to files in the phase's diff (`_active_set()` exists but METRIC-FRAME ignores
   it); cap injected findings at 10 lines; unit-test `prompt_block()` once.

8. **Stale boilerplate from other projects/eras is auto-loaded.** Evidence: `/home/emeric/code/CLAUDE.md`
   (snag/cairn/jaunt, `task-list.json`, `cargo build`), session-start "Opus 4.7… mirror x86 emitter
   for AArch64", `[RETIRE 03:40]` section, 13 "PASSE" sections. **Fix:** add a `CLAUDE.md` at the
   jak-project root that overrides (or move the parent file into `snag/`, `cairn/`, `jaunt/`); rewrite
   session-start.sh to 6 lines (phase id, validator path, commit prefix, "no human in the loop");
   delete retracted sections.

9. **Prompts grow by appending owner reactions ("RETOUR OWNER (4)", "CE QUI PRECEDE EST CADUC").**
   Evidence: Gloading-screen 18 KB / 6 layers / no DoD; crate-collision 3 layers, 4 obsolete markers;
   Ghd-skin half-superseded. **Fix:** prompt template = 5 fixed headings (Défaut cité, Cause connue,
   Livrable, Preuve exigée = validator checks, Hors périmètre) ≤ 2.5 KB; owner quotes go to
   `reports/<phase>/owner-defects.txt` and the prompt links them; each retry regenerates the prompt.

10. **Rules are prose where they should be hooks/checks.** Evidence: "never pkill by pattern",
    "lock with PID", "grep -a on logcat", "adb -s eae4df44", "no `cmake -B`", "commit prefix", "report
    must contain DIRECTIVES vX" are each stated 2–5 times in prose and enforced nowhere except (some)
    in preflight. **Fix:** move them into `hooks/pre-tool.sh` (currently `exit 0` on line 2) as
    PreToolUse Bash checks (block `pkill -f` without bracket, block `cmake -B`, block `adb` without
    `-s`), and into the validator wrapper (commit prefix, version line). Every rule that becomes a
    hook leaves the prompt.

Order-of-magnitude payoff of 1+2+6+8 alone: turn-0 context drops from ~63K to ~10K tokens, of which
~3K are about the phase; subagent launches drop from ~50K to ~5K tokens of preamble.
