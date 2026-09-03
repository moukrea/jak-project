# Review: validators and proof economy of the autoport harness

Read-only audit, 2026-09-03. Nothing was run against the device or the builds. Sources: `.autoport/validators/`, `orchestrator.py` (close_gate, _device_boot_check, validator runner), `lib/preflight.py`, `lib/deploy_verify.sh`, `acquis/font-urbanist.sh`, `hooks/stop.sh`, `logs/<phase>/validator-*.txt` and `attempt-*.jsonl`, `reports/<phase>/`, and the memory files under `~/.claude/projects/-home-emeric-code-jak-project/memory/`.

## Headline

1. **Every validator of the last 19 phases reads exactly one file: `reports/<phase>/report.txt`, written by the worker.** 116 checks across the 15 validators read in full, 116 on the report document, 0 on a binary, a log, a device file or the git tree. The validator itself runs in under a second. The cost is in what its clauses force the worker to produce (multi-run device campaigns, reproduction before fix, bisects across archived builds).
2. **The gates that do test the artifact are switched off for all recent phases.** GATE 2 (deploy_verify chain + boot check) needs `device: true`; all 12 phases from idx 266 to 277 plus the three named ones declare `device: false`. So the harness never proved that the phone runs the build for any of them. The only artifact-level check that still runs at close is `acquis/font-urbanist.sh` (75 s x86 run).
3. **Preflight has been dead since 2026-08-30.** `check_shield_untouched` returns a 2-tuple instead of yielding 3-tuples; `prompt_block` unpacks the string `"ok"` and raises `not enough values to unpack (expected 3, got 2)`. 278 occurrences of `preflight unavailable` in the orchestrator logs. All ten traps it encoded (DGO linking, self-matching pkill, device prop leak, stale report...) are unenforced, silently.
4. **The stop hook re-runs the validator after every turn and refuses to stop until it passes.** With a report-grep validator, the shortest path to exit 0 is to write the missing line. The memory notes call this "the printf path" and record it as the recurring failure mode since phase 20.
5. **The reports are proof dumps.** 214 to 1044 lines, 2 100 to 11 600 words, 10 to 58 minutes of reading, with 18 to 233 side files and 9 MB to 618 MB per phase. Two of five have a usable "one page" section at the top; the rest of the document exists to satisfy the validator and the directives.

---

## 1. Inventory and per-validator table

`.autoport/validators/`: 287 `phase-*.sh`, 1.9 MB, 23 058 lines total; sizes from 10 lines (`Grecharged-buildsys-*`) to 725 (`Grecharged-secondary-motion`). A pruned-copy archive `.avant-elagage/` (6 files, 2026-09-01) shows the owner-ordered pruning ("t'as mis tellement de blockers que le moindre truc prend des journées").

What the 287 validators touch (grep over the scripts):

| Class | Count |
|---|---|
| read `reports/<phase>/report*.txt` | 169 |
| run the x86 `gk` binary | 157 |
| run `adb` | 29 |
| run cmake/ninja/gradle | 30 |
| report-only, nothing else | 72 |

Era drift: the 40 most recent G validators show a clean break at 2026-08-30 (`Gcine-vertical-frame`). Before it: "gk + report". After it: "report" only, 19 validators in a row.

Per-validator detail for the requested set (all read `.autoport/reports/<phase>/report.txt` only; validator wall time < 1 s in every case; "imposed cost" is what the clauses require the worker to have done before the report can be written):

| idx | Phase | Validator file | Lines | Distinct checks | On report doc | On artifact | Imposed proof cost |
|---|---|---|---|---|---|---|---|
| 266 | Gsubtitle-style | phase-Gsubtitle-style.sh | 29 | 8 (RESULT exact phrase, SUBCOLOR rgb/degrade, SUBSHADOW type/blur, SUBSCOPE=0) | 8 | 0 | one x86 run |
| 267 | Gcutscene-skip-all | phase-Gcutscene-skip-all.sh | 45 | 14 (CUTPATHS couverts==total, CUTSKIP contextuelle, CUTHINT x3, CUTFILL 1350-1650 ms + sync, CUTSMOOTH, CUTCENTER h/v, CUTFIT >=2 langs) | 14 | 0 | census of all cutscene paths + run per language |
| 268 | Gjak1-crate-collision | phase-Gjak1-crate-collision.sh | 33 | 12 (CRATEREPRO >=2 runs with defect, CRATEBISECT >=2 builds, CRATECAUSE nommee + lien_jak2, CRATEIDENTVERDICT, CRATEIDENT >=4, CRATEALLOC, CRATEOK courses>=3 caisses>=20 sans=0) | 12 | 0 | reproduce an intermittent bug twice, bisect 2 archived APKs, >=3 device runs |
| 269 | Gjak1-crate-collision-2 | phase-Gjak1-crate-collision-2.sh | 22 | 3 (CRATEPROBE plateforme=redmi fps<=30, 31/31/31) | 3 | 0 | one device run (pruned from 17 clauses) |
| 270 | Gfixed-tick-anim-interp | phase-Gfixed-tick-anim-interp.sh | 20 | 4 (ANIMJIT >60 fps, on/off ratio >=2, ANIM60 identique=1) | 4 | 0 | 2 arms x >60 fps |
| — | Gfixed-tick-anim-interp-2 | phase-Gfixed-tick-anim-interp-2.sh | 29 | 6 (ANIMJIT <=30 and >60, both arms per fps, on<off, ANIM60) | 6 | 0 | 2 arms x 2 cadences = 4 runs |
| 271 | Gcutscene-npc-flicker (+ -2, same file) | phase-Gcutscene-npc-flicker.sh | 27 | 8 (NPCGUARD echoue_si=, NPCOK scenes>=3, plateforme=redmi, NPCFLICK mayor scene+pnj, NPCCULL=0, mayor named, cycles=0) | 8 | 0 | >=3 scenes on Redmi incl. mayor (a scene the game cannot launch by flag: a launcher had to be written) |
| 272 | Gsubtitle-style-2 | phase-Gsubtitle-style-2.sh | 17 | 4 (SUBDUP passes=1, SUBSHADOW offset_x/y=0) | 4 | 0 | one x86 run |
| 273/277 | Gcutscene-skip-polish (+ -2, same file) | phase-Gcutscene-skip-polish.sh | 39 | 12 (CUTFILL, CUTSHAPE r=h/2, CUTHORS=0, CUTSMOOTH, CUTCENTER <11.4 + centered, CUTICON, CUTFIT, CUTNATIVE sites=0 triangle=0) | 12 | 0 | x86 run + 23-language ink measure + census |
| 274 | Gpbr-props-reach-draw | phase-Gpbr-props-reach-draw.sh | 22 | 6 (PBRREACH redmi, deposes>=rencontrees, draws>=1, PBRVAL >=20 lines, >=5 non-default) | 6 | 0 | device run with pack ablation (3 attempts to ablate, see memory) |
| 275 | Gmenu-census-cleanup | phase-Gmenu-census-cleanup.sh | 22 | 6 (MENUCENSUS, MENUROW count, MENUDEBUG=0, MENUDOUBLON verdict, no dead rows) | 6 | 0 | code census |
| 276 | Gfont-regression | phase-Gfont-regression.sh | 25 | 7 (FONTBISECT >=2, FONTCAUSE nommee, FONTBIND, FONTOK chaines>=20 glyphes_origine=0, FONTGUARD echoue_si=) | 7 | 0 | bisect 2 builds + device run + x86 run |
| — | Ghd-skin-origin-stretch | phase-Ghd-skin-origin-stretch.sh | 34 | 8 (HDSTRETCHCOUNT present + word "commande", avant redmi >=1, HDATTRIB chemin, HDMOVES >=500 m, HDROOTJUMP redmi 0/0 >=10 min, apres redmi 0 >=10 min) | 8 | 0 | reproduction run + >=2 Redmi runs of >=10 min in motion; 8 attempts, 88 logs, 618 MB |
| — | Grecharged-foliage-wind3 | phase-Grecharged-foliage-wind3.sh | 31 | 6 (WINDNATIVEREF <=1 %, WINDPIVOT <=0.5 cm, WINDCOVER per level equality, WINDPAIRS=0, WINDSPECTRUM <=40 %) | 6 | 0 | stock-vs-native comparison + per-instance census + spectrum |
| **Total** | | | | **116** | **116** | **0** | |

Notes on the table:
- The `-2` phases (`Gcutscene-npc-flicker-2`, `Gcutscene-skip-polish-2`) reuse the cycle-1 validator, whose path is hard-coded to the cycle-1 report directory. The memory `feedback_defect_reported_through_a_broken_acquis` records the workaround: copy the report into both directories. `reports/Gcutscene-skip-polish/report.txt` is today byte-identical to the cycle-2 report.
- Every check uses the same parser: `kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))` on lines starting with an upper-case tag. A check is satisfied by a line the worker types.
- The FAIL messages are owner quotes ("« on est pas dans un jeu en pixel art »"). The validators are checklists of owner sentences, not measurements.

Validator attempt history for these phases (`logs/<phase>/validator-NN.txt`): 27 runs, 10 failures. Of the 10 failures, 4 are "pas de report.txt" or "RESULT absent" (the worker had not finished writing), 3 are "field X absent" after a supervisor rewrote the gate mid-phase (Ghd attempts 4, 6, 7), 1 is an owner-added clause (skip-polish-2 attempt 2, icon). Repository-wide: 560 validator logs, 135 failures, 40 of them "no report".

## 2. Self-referential and proof-of-proof checks

All 116 checks are self-referential in the strict sense (the worker writes the file the validator greps). The ten below are the clearest cases where the check cannot distinguish work from typing:

1. `phase-Gsubtitle-style.sh:6` — `grep -qE '^RESULT:[[:space:]]*SUBTITLE STYLE DONE[[:space:]]*$'`. The pass phrase is the check.
2. `phase-Gjak1-crate-collision.sh:17` — `if not c or not c[0].get('nommee'): F("CRATECAUSE absent : la cause doit etre NOMMEE")`. Any non-empty value passes.
3. `phase-Gjak1-crate-collision.sh:18` — `if c[0].get('lien_jak2') not in ('oui','non','indetermine')`. All three answers pass; the check verifies that a field exists.
4. `phase-Gcutscene-npc-flicker.sh:10` — `re.search(r'^NPCGUARD .*echoue_si=\S+')`. "A regression guard exists" is proven by a token after `echoue_si=`. The memory `feedback_guard_that_runs_only_in_its_phase` shows what such guards were worth: grep of the three previous hd guard scripts found one occurrence each, their own header.
5. `phase-Gfont-regression.sh:22` — same pattern, `FONTGUARD .*echoue_si=\S+`.
6. `phase-Gfont-regression.sh:11` — `if len(b)<2: F("FONTBISECT sur >= 2 builds exige")`. Proof-of-proof: two lines tagged FONTBISECT prove that a bisect was performed. The actual report says the bisect was done "par etat" because no font commit existed, i.e. the clause was satisfied by re-labeling.
7. `phase-Ghd-skin-origin-stretch.sh:25` — `re.search(r'^HDSTRETCHCOUNT .*(commande|pose_cmd)')`. The check is that the word "commande" appears on the line.
8. `phase-Ghd-skin-origin-stretch.sh:16`, `phase-Gcutscene-npc-flicker.sh:17`, `phase-Gpbr-props-reach-draw.sh:12`, `phase-Gjak1-crate-collision-2.sh:15` — `plateforme=redmi`. A device token typed by the worker. The memory `feedback_worker_desktop_fallback_device_proof` documents three rounds passing device gates on desktop proof; the fix was to require the token, which moves the question from "did it run on the device" to "did the worker write redmi".
9. `phase-Gmenu-census-cleanup.sh:17` — `MENUDOUBLON .*verdict=(doublon-fusionne|deux-choses-renommees)`. Either verdict passes; the gate checks that a decision was written, not which.
10. `phase-Gpbr-props-reach-draw.sh:18` — `if len(v)<20: F(...)`. A floor on the number of PBRVAL lines in the report. Count floors also at `CRATEIDENT >= 4`, `FONTOK chaines >= 20`, `CRATEOK caisses >= 20`, `NPCOK scenes >= 3`. The memory `feedback_validator_scope_outlives_gates` already describes the failure: "the only way left to satisfy the clause is to write numbers into the report for things nobody measured".
11. `phase-Gfixed-tick-anim-interp-2.sh:27` — `ANIM60 identique_au_bit=1`. A literal `1`.
12. `phase-Gcutscene-skip-polish.sh:22` — `CUTHORS images_hors_cinematique=0`. The defect the owner sees (cartouche in the main menu) is closed by a zero in a text file.

Why this is not a hypothetical: `feedback_physical_artifact_validators` ("the orchestrator's claude consistently found the printf path", phases 20-22), `feedback_lean_validator_false_green` (F1b closed with zero code), `feedback_validator_reads_stale_artifacts` (validator exit 0 while the tree did not compile), `feedback_validator_reads_a_stale_table` ("13 gates vertes" on the previous run's table). The report-grep design has produced every false green the memory records, and the response each time was to add a clause to the grep.

The pruning of 2026-09-01 did not hold: `Ghd-skin-origin-stretch` went 30 lines (archived) to 34 (current) within 48 h, `Gcutscene-npc-flicker` 23 to 27, with new owner-quote clauses each time. Clause growth is the harness's reflex to an owner complaint.

## 3. Checks that fail for reasons unrelated to the task

Cross-reference between memory files and the gate or check that produced the incident:

| Memory | Gate / check | What happened | Cost |
|---|---|---|---|
| `feedback_gate_reading_an_artifact_mid_write` | close_gate GATE 2 → `deploy_verify.sh:64-65` (`find … app-jak1-debug.apk`) | gradle had deleted and not yet rewritten the APK; gate said "rebuild a consistent set" | one full attempt (Gfont-urbanist) |
| `feedback_deploy_lock_checked_only_at_cycle_top` | any x86 `gk` gate (the 157 "gk" validators, `acquis/font-urbanist.sh` x86 leg) | after any commit or source edit, `auto_build_apk.sh` rewrites `out/jak1/iso/` in ARM64 for ~2 min; x86 gk dies in SIGSEGV/SIGILL | false red + bisect on an unrelated change |
| `feedback_reconciliation_blind_to_binary_only_change` | device delivery (stamps compare packs only) | libgk-only commit never reached the Redmi; "up to date" with a 16:16 binary; GATE 2 would have caught it but was `device: false` | wrong binary under test |
| `feedback_lock_pid_from_tool_shell_is_dead` | `.deploy-in-progress` convention (DIRECTIVES 2026-08-14) | lock named a dead PID; builder deferred 2 cycles | 2 build cycles |
| `feedback_archiving_at_run_start_loses_the_only_trace` | `hooks/stop.sh` re-running the validator while a 25-min run is in flight | "trace absent" read as "claim without execution"; 3 attempts, 4th occurrence | 3 attempts |
| `feedback_stale_debug_property_holds_a_button_down` | device runs; `_device_boot_check` clears 5 props but not `cpad_inject`; `preflight.check_device_prop_leak` was the guard, now dead | jump button held down for weeks, 3 refuted hypotheses | weeks |
| `feedback_disarmed_default_makes_owner_verify_untestable` | GATE 3 `owner_verify` + flag default OFF | phase formally unclosable | a phase |
| `feedback_reopen_owner_verify_phase` | GATE 3 resume path (`state.json` `validator_passed`) | relaunch after owner rejection re-pauses forever; reopening needs hand-editing state.json | supervisor time per cycle |
| `feedback_stop_hook_cannot_clear_the_owner_gate` / `feedback_human_gate_must_not_park_the_loop` | `hooks/stop.sh` + OPEN-DEFECTS human gate | infinite "keep working" loop, then 14 h idle | 14 h |
| `feedback_gate_behind_an_always_failing_gate` / `feedback_engine_line_ceiling_hides_all_gates` | bash-level `fail` in a long validator | all later gates unevaluated for days | unseen regressions |
| `feedback_validator_time_anchors` | validators anchoring freshness on `validator-NN.txt` mtime | the anchor is the validator's own stdout file | false red on fresh artifacts |
| `feedback_deploy_verify_freshness_gate` | `deploy_verify.sh:49-50` (any `.cpp/.h` newer than the .so) | a trivial late edit re-stales; bundle identity mismatch | attempts 22 and 25 of Gpbr-fusion |
| `feedback_redirected_stdout_is_block_buffered` | proof harness counting lines while `gk` runs | 0 lines counted, 70 produced | false red |
| `reference_redmi_vs_honor_timing_and_device_pitfalls` | device runs | screen asleep → 0 lines = "no defect"; /tmp at 99 % → every command exit 1; orphan logcats | 8-10 min per lost run |
| `feedback_pkill_pattern_self_match` | wait loops in harness scripts | `until ! pgrep -f` never ends; 4 occurrences, 24 min once | 15-25 min each |
| `feedback_acquis_delivered_under_an_optional_feature_gate` | `gfu_font_live_proof.sh` (green while owner saw kanji) → led to GATE 4 | proof taken at load, not at bind | a regression shipped |
| `feedback_defect_reported_through_a_broken_acquis` | validator path hard-coded to cycle-1 dir | report must be copied to two places | confusion per `-2` phase |
| `feedback_partial_target_rebuild_breaks_goalc_abi` | build tier advice in the prompt ("incremental `--target gk`") | goalc SIGSEGV; 2 delivery cycles reported failed while arm64 was fine | 2 cycles |
| `feedback_build_game_does_not_deliver_to_running_gk` | proof runs | two 13-min runs measured a CGO older than every edit of the day | 26 min + a wrong conclusion |
| `feedback_autobuilder_ships_your_wip` / `feedback_never_clear_a_lock_to_unblock_yourself` | auto builder commits and publishes the tree mid-experiment | owner had a wrong build 27 min; a run continued 20 min on missing art-groups | owner trust |

The deploy gate specifically: 31 `CLOSE-GATE/deploy` failures in the orchestrator logs (2026-07-17 to 2026-08-30), of which the parseable reasons are 9 "libgk.so older than newest source" and 5 "device NOT connected". The gate's own comments record three design corrections (check 2 removed as false positive; serial re-read from disk after the Honor/Redmi mix-up; game-aware package after Gjak2-polish got stuck twice). It is the most-corrected gate and the one now switched off everywhere.

## 4. Gates run at close, cost, false-red history

`close_gate(phase, validator_log)` runs after the phase validator exits 0 (`orchestrator.py:1032-1165`):

| Gate | What it does | Cost | Runs for the recent phases? | False-red history (from comments and memory) |
|---|---|---|---|---|
| GATE 1 code-change | `git diff --name-only <supervisor anchor> -- game/ android/ goalc/ goal_src/` plus dirty tree; refuses if empty unless `no_code: true` | ~0.1 s | yes | anchor postdated the fix (Gcrash-blueeco 2026-07-02); stale in-memory `no_code` burned a retry (Grecharged-grass-object-clip 2026-07-13). Both fixed in code. |
| GATE 2a `deploy_verify.sh` | adb presence; `.so` mtime newer than newest `.cpp/.h/.vert/.frag`; sha chain build == APK == device (pulls the whole device APK, 600+ MB; memory says 667 MB dies at 31 % on tmpfs); `ogflags` pairing; HD and physics feature-parity greps | 1-3 min | **no** (`device: false` on all 15) | 31 failures logged; APK write race; unplugged device; wrong package for jak2; trivial late edit; bundle identity |
| GATE 2b `_device_boot_check` | force-stop, clear 5 debug props, `am start` resolved launcher, poll logcat 12 x 4 s for `master-mode=game` or `A35-RENDER`, 3 attempts; route B for log-silent phones (pid stable, no `gk_crash.txt`, fresh `files/*.txt`, foreground); fail-OPEN on adb exceptions | up to ~2.5 min | **no** | 'Setup failed' class it was built for (2026-06-30); Honor drops app logs (route B added) |
| GATE 4 acquis | every `.autoport/acquis/*.sh` with a 600 s timeout, fail-CLOSED. One script today: `font-urbanist.sh` = static atlas check + (device leg: launch, `sleep 60`, read `files/font_atlas.txt`) or (x86 leg: 75 s `gk` run under X11, grep `FONTTEX bind tbp=0x3980`) | 1-2 min | yes, x86 leg only (no serial passed when `device: false`) | 2 green runs logged, no red yet. Exposed to: auto-builder rewriting `out/jak1/iso` (memory), no X display, `build/game/gk` absent → all fail-closed and block every phase |
| GATE 3 owner token | `owner-ok/<pid>` exists? else `awaiting-owner` | 0 s | yes (all 15 are `owner_verify: true`) | parks the phase; reopening after rejection is manual (`feedback_reopen_owner_verify_phase`) |
| `spec_sections_remaining` | only on the OPEN-DEFECTS special path; parses the 772 KB `SPEC-COVERAGE.md` | <1 s | not for these phases | 14 h idle before it existed |
| `hooks/stop.sh` | re-runs the phase validator after every turn; exit 2 blocks the stop with the last 80 lines | <1 s per turn for report validators; for the gk-era validators, a 75 s+ gk run per turn | yes | human-gate infinite loop; mid-run "trace absent"; trains the printf path |
| preflight | see section 5 | dead | no | — |

Net for the 15 phases under review: close costs about 2 minutes (acquis x86 leg + git). What is not run: any proof that the device has the build or that it boots. The validator passed, GATE 1 saw a diff, the font still binds on x86, and the phase parks on the owner.

## 5. Preflight

`lib/preflight.py`, 436 lines, 10 checks in `CHECKS`:

| Check | Severity | Scope | Assessment |
|---|---|---|---|
| `check_goal_objects_linked` (GD-LINK) | BLOCKER | `goal_src/jak1/pc/*.gc` vs `.gd`/`.gp` | Real, cheap, catches a SIGSEGV class confirmed by `feedback_new_goal_file_must_be_listed_in_the_dgo`. Keep. |
| `check_self_matching_kills` (SELF-KILL) | BLOCKER/WARN | live `.autoport/*.sh` | Real, 4 recorded occurrences. Keep, but it is advisory only: it cannot stop the worker from typing `pgrep -f` in a Bash call. Belongs in a PreToolUse hook. |
| `check_no_cmake_reconfigure` (CMAKE-B) | WARN | live scripts | Fine, cheap. |
| `check_validator_pipefail_grepq`, `check_validator_negated_class` | BLOCKER, supervisor-only | live validators | Validator-authoring hygiene. Useful only if validators keep using bash greps; irrelevant to the python-kv validators of the last 19 phases. |
| `check_report_not_stale` (REPORT-STALE) | WARN | report vs edited sources | Correct signal, wrong severity: "a WARN blocks nothing" (`feedback_validator_reads_stale_artifacts`, validator exit 0 on a tree that did not compile). |
| `check_metric_frame_declared` (METRIC-FRAME) | WARN | keyword within 400 chars of every `ROOM-*` emitter | Prose heuristic on two files of a scope that ended 2026-08-14. Produced most of the 143-148 findings per attempt (the flood the module's own docstring calls "a brake"). Remove. |
| `check_guards_still_installed` (GUARD-*) | BLOCKER | 73 `GUARD` lines in `PITFALLS.md`, each a prose quote that must still appear in `DIRECTIVES.md` or a script | Proof-of-prose. Its own comment records two cycles paying a permanent BLOCKER because `**` and a capital letter broke the quote match. Remove. |
| `check_device_prop_leak` | BLOCKER/WARN | scripts that `setprop debug.opengoal.cpad_inject` without clearing | Real (94 of 101 scripts leak). Keep, but the fix is a teardown trap in the harness runner, not a prompt line. |
| `check_shield_untouched` | BLOCKER | runs `shield_guard.sh` (adb) | Violates the file's own contract ("no builds, no device, under a second") and is the bug that killed the module. |

**Why it throws.** `run()` does `findings.extend(fn(*args))`. Nine checks are generators yielding `(sev, code, msg)`. `check_shield_untouched` is a plain function that `return`s `("ok", "...")` or `("BLOCKER", "...")`. `extend` on that tuple appends two *strings*. `run()`'s `try/except` does not fire (no exception at extend time). Then `prompt_block` at line 420 does `for sev, code, msg in ...` and unpacking `"ok"` raises `ValueError: not enough values to unpack (expected 3, got 2)` — exactly the message in the logs. First seen in `orchestrator-20260830T133537.log`, same day the check was added (commit 25ae957df7, a WIP checkpoint of Gloading-screen-window). The orchestrator's `except Exception` prints "preflight unavailable" and carries on, so nobody was blocked and nobody noticed for four days.

**Was it useful before it died?** Log counts: 148 attempts got 48 findings injected, 36 got 145, 23 got 143, 59 got 1. A 48- to 145-item block at the top of a prompt that already carries 167 KB of DIRECTIVES is noise; the one BLOCKER that matters (GD-LINK) is buried under METRIC-FRAME and GUARD lines. Verdict: the idea is right (mechanise recurring traps), the implementation is a prose linter. Fix is one line (make the shield check `yield`, or drop it), then prune to four checks: GD-LINK, SELF-KILL, DEVICE-PROP-LEAK, REPORT-STALE (as BLOCKER, or better as a validator precondition).

## 6. Reports of the five most recent phases

| Phase | Files in `reports/<phase>/` | Size | Main report | Words | Reading time at 200 wpm | Side artifacts |
|---|---|---|---|---|---|---|
| Ghd-skin-origin-stretch | 233 | 618 MB | `report.txt`, 1044 lines | 11 605 | 58 min | 88 `.log` (62 MB), 12 `*-marqueurs.txt` up to 372 KB |
| Gcutscene-npc-flicker (+ -2) | 90 | 111 MB | `report.txt`, 430 lines (plus `report-cycle2-…`, `report-part1..4`, `report-draft.md`) | 4 143 | 21 min | 32 `.log` (60 MB), x86 campaign dumps |
| Gcutscene-skip-polish-2 | 18 | 9.1 MB | `report.txt`, 429 lines | 4 469 | 22 min | 7 `.log`, `census.txt` 194 lines, `cut-lines.txt` 171 lines |
| Gfont-regression | 18 | 16 MB | `report.txt`, 214 lines | 2 115 | 11 min | 3 device logcats (5 MB), **6 PNG screenshots** (visual proof is banned by the owner), 2 x86 logs |
| Gcutscene-skip-polish (cycle-1 dir) | 8 | 132 KB | `report.txt` = byte copy of the -2 report; `report-cycle1`, `report-cycle2` kept | 4 469 | 22 min | census, ink, native, center |

Judgement per report:
- **Ghd-skin-origin-stretch**: section "0. CE QUI EST ETABLI, EN CINQ LIGNES" is a genuine decision document (cause with numbers, where the w comes from, the fix, the proof, what stays open). It is 5 bullets of 40 lines. The remaining 1 000 lines are: why three gates opened wrongly, positive controls, the order in which measurements decided, stock reference, build tier. That is a lab notebook aimed at the supervisor and the validator, not at the owner.
- **Gfont-regression**: "0. EN UNE PAGE" works (state not build; why; what cannot be seen on the Honor; fix; proof at bind; permanent guard). The rest defends the bisect clause and the guard clause.
- **Gcutscene-skip-polish-2**: opens with a page of artefact inventory and a scope-conflict paragraph about DIRECTIVES being six days stale, then "LIGNES DE VERDICT". The owner's three requests are answered in section 0 but only after 60 lines of preamble. Proof dump with a decision document inside it.
- **Gcutscene-npc-flicker**: opens with `NPCPRIOR` lines (why cycle 1 failed) because the validator asks for them; the actual answer ("the excused bucket held all the episodes") is in 1.2. Proof dump; the multi-part files show it was assembled to feed the validator.
- Four of five start with `DIRECTIVES vd9e8b66782` on line 1: the report is stamped for the harness before it addresses a human.

Common pattern: the report length tracks the number of validator clauses plus the number of owner sentences quoted in DIRECTIVES, not the size of the change. Every report re-litigates prior cycles because the gates demand it (`NPCPRIOR`, `FONTBISECT`, "pourquoi trois portes s'etaient ouvertes a faux").

## 7. Conclusions

### (a) Verification activities to remove or make optional, ranked by evidence

1. **Report-grep as the pass/fail decision.** 116/116 checks, 0 on artifacts; the printf path documented since phase 20; every recorded false green came from this design. Replace with a proof file written by a harness runner from engine output (see (c)). The worker's prose is never parsed.
2. **The stop hook blocking on the validator.** It converts every missing clause into "write the line", blocks on human gates, and fires mid-run. Make it advisory (print the validator tail, exit 0) or run once when the worker declares done.
3. **Reproduce-before-fix and bisect clauses on intermittent defects** (`CRATEREPRO >= 2`, `CRATEBISECT >= 2`, `FONTBISECT >= 2`, `HDSTRETCHCOUNT avant redmi >= 1`). Ghd spent 8 attempts, ~10 h of transcript time and 618 MB to satisfy them; `reference_redmi_vs_honor` shows some conditions cannot reproduce on the Redmi at all, so the clause forces either hours or fiction. Optional, and never a gate.
4. **Count floors** (`>= 20 chaines`, `>= 20 caisses`, `>= 4 CRATEIDENT`, `>= 20 PBRVAL`, `>= 3 scenes`). `feedback_validator_scope_outlives_gates` explains why they end in invented numbers. Replace with "every declared element has a value" over a data file, or drop.
5. **Proof-of-guard clauses** (`NPCGUARD echoue_si=`, `FONTGUARD echoue_si=`). A guard exists when it is in `acquis/` and runs at close, which is checkable by `ls`. Drop the report clause.
6. **Long device campaigns imposed by clauses** (`>= 10 min` x 2 arms, `>= 500 m`, `>= 3 courses`). Contradicts the PROOF ECONOMY block the same prompt carries ("proof runs are MINUTES, not hours"). The validator wins because the stop hook enforces it. Cap at one short run per arm; put the numbers in the report as information, not as gates.
7. **Preflight as it stands.** Dead; when alive, a 48-148 line flood. Fix and cut to four checks, or delete.
8. **GUARD registry (73 prose quotes) and METRIC-FRAME.** Proof-of-prose. Delete.
9. **Duplicate report copies for `-2` phases.** Resolve `reports/$AUTOPORT_PHASE_ID/` instead of a hard-coded cycle-1 path.
10. **Screenshots in reports** (6 PNG in Gfont-regression). Banned by the owner, unread by anyone, 10 MB.
11. **Per-clause owner quotes as FAIL messages.** They make the validator the place where owner feedback is stored, so it grows with every message. Keep the quotes in `owner-defects.txt`; the validator checks one number.

### (b) Minimal gate set that actually protects against regressions

1. **Fresh build.** `build/game/gk` and `build-android/lib/arm64-v8a/libgk.so` newer than the newest engine source; `out/jak1/iso/GAME.CGO` and `ENGINE.CGO` newer than the newest `.gc`, and not mid-rewrite (size stable over 10 s, no `goalc`/`ninja`/`gradle` process). Already 80 % present in `deploy_verify.sh` check 1 and in the memories' two-command check.
2. **Device runs that build and boots.** `deploy_verify.sh` chain + `_device_boot_check`. They exist. Turn `device: true` back on; the single largest gap today is that no recent phase has run them. Keep fail-open on adb infra errors, and retry once after 120 s when a builder is running (the write-race fix).
3. **No crash.** x86 run exits 0 within the timeout with `N` frames rendered; device: pid stable for the window and no `files/gk_crash.txt`. Both already coded in route B of the boot check.
4. **Feature active, by an engine-emitted counter.** One line per phase, name declared in `milestones.yaml`, emitted by the engine into stdout (x86) and `files/<phase>.txt` (device). The gate reads that file, never `report.txt`. Where the phase has a toggle, the same run with the toggle off must show `hits=0` (ablation on the same binary, one extra short run).
5. **Acquis scripts** at close, each under 90 s, fail-closed only when the instrument is reachable; when no display or device, print a loud `ACQUIS UNPROVABLE` and let the owner gate decide.
6. **Owner token.** Unchanged. It is the only gate that has ever caught a real visual defect.

Everything else (bisect, reproduction, spectra, censuses, margins in 23 languages) is engineering the worker may do, and may describe in the report, and is never gated.

### (c) Templates

**Validator template (≤ 40 lines).** It reads a machine-written proof file, not the worker's report. The proof file is produced by a shared runner (`lib/proof_run.sh <phase> <x86|device>`) that launches the game, waits for the phase counter or a timeout, and writes `reports/<phase>/proof.txt` with `source=`, `sha=`, `crash=`, `frames=`, and the engine's `FEATURE <name> armed=? hits=?` line copied verbatim. Phase-specific pass criteria live in `milestones.yaml` as `gate: {key: os_etires, op: '==', value: 0}` so the validator file never changes per phase.

```bash
#!/usr/bin/env bash
# Generic phase validator: judges the proof file the runner wrote, never the report.
set -uo pipefail; cd "$(git rev-parse --show-toplevel)"
P=${AUTOPORT_PHASE_ID:?}; D=.autoport/reports/$P; PF=$D/proof.txt
fail(){ echo "[$P FAIL] $*" >&2; exit 1; }
[ -s "$PF" ] || fail "proof.txt absent: run lib/proof_run.sh $P first"
# 1. freshness: proof newer than every engine/GOAL source and than the binary it ran
new=$(find game android goal_src -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.gc' -o -name '*.vert' -o -name '*.frag' \) -newer "$PF" | head -3)
[ -z "$new" ] || fail "sources edited after the proof: $new"
kv(){ sed -n "s/^$1=//p" "$PF" | tail -1; }
# 2. identity: the proof names the binary; it must be the one on disk
so=build/game/gk; [ "$(kv source)" = device ] && so=build-android/lib/arm64-v8a/libgk.so
[ "$(kv sha)" = "$(sha256sum $so | cut -c1-16)" ] || fail "proof sha $(kv sha) != $so"
# 3. no crash, something rendered
[ "$(kv crash)" = 0 ] || fail "crash=$(kv crash)"
[ "${frames:=$(kv frames)}" -ge 300 ] || fail "frames=$frames (<300)"
# 4. feature active (engine-emitted line, copied verbatim by the runner)
grep -q "^FEATURE $P armed=1 hits=[1-9]" "$PF" || fail "feature line absent or hits=0"
# 5. one phase criterion from milestones.yaml: gate: {key, op, value}
g=$(python3 - "$P" <<'PY'
import sys,yaml;p=[x for x in yaml.safe_load(open('.autoport/milestones.yaml'))['phases'] if x['id']==sys.argv[1]][0]
g=p.get('gate');print(f"{g['key']} {g['op']} {g['value']}" if g else "")
PY
)
if [ -n "$g" ]; then set -- $g; v=$(kv "$1"); [ -n "$v" ] || fail "proof lacks $1="
  python3 -c "import sys;sys.exit(0 if eval(f'{sys.argv[1]}{sys.argv[2]}{sys.argv[3]}') else 1)" "$v" "$2" "$3" \
    || fail "$1=$v violates $1 $2 $3"; fi
# 6. optional ablation: a second proof with the toggle off must show hits=0
[ -s "$D/proof-off.txt" ] && ! grep -q '^FEATURE .* hits=0' "$D/proof-off.txt" && fail "toggle off still hits"
echo "[$P ok] fresh, $(kv source) sha $(kv sha), no crash, feature active${g:+, $g}"
```

Properties: 30 lines, identical for every phase, no owner quotes, no count floors, no token the worker can type (the runner writes `source=` and `sha=` itself). The stop hook can still run it, cheaply, and it cannot be satisfied by editing a text file.

**Report template (≤ 40 lines, the file is for the owner, never grepped).**

```
# <phase id> — <one-line title in the owner's words>
Commit <sha>  ·  APK/libgk <sha16>  ·  build tier: <data|goal|c++ incremental|full>
Attempts <n>  ·  build <min>  ·  proof runs <n> x <min>

## Verdict (one sentence)
<fixed | fixed with a caveat | not fixed, here is why>

## What changed (≤ 5 bullets, one file:line each)
- 

## Proof (verbatim lines from proof.txt, ≤ 8)
source=… sha=… crash=0 frames=…
FEATURE <phase> armed=1 hits=…
<gate key>=<value>

## What you must look at (≤ 3 bullets, where and how)
- 

## Not proven / still open (≤ 3 bullets)
- 

## Notes (optional link) → reports/<phase>/notes/ (never read by any gate)
```

### (d) Prose rules that should become mechanical hooks

| Prose rule today (DIRECTIVES / memory / prompt) | Mechanism |
|---|---|
| "never `pkill -f` / `pgrep -f` / `until ! pgrep`" (rule 8, 4 incidents) | PreToolUse hook on Bash: reject commands matching `p(kill|grep)\s+-f` without a `[x]` bracket, and any `pgrep` inside `while|until`. |
| "clear `debug.opengoal.*` props after a device session" (jump held for weeks) | The runner (`proof_run.sh`) traps EXIT and runs `device_teardown.sh`; the boot check adds `cpad_inject` to its clear list. |
| "check no builder is writing before measuring" (2-command check in memory, 4 incidents) | PreToolUse hook: refuse `gk`/`goalc`/`adb install` while `auto_build_apk.txt` shows a cycle in flight or `GAME.CGO` mtime < 60 s; the runner waits instead. |
| "the report must postdate the sources; the tree must compile" (REPORT-STALE is a WARN) | Validator step 1 above (freshness is a FAIL), plus the runner refuses to start without a green `goalc (mi)` since the last `.gc` edit. |
| "prove on the device, not on desktop" (`plateforme=redmi` tokens) | `source=` written by the runner from the adb serial; the worker never types it. |
| "never visual proof" (PNG in reports) | PreToolUse hook rejecting `screencap` and writes of `*.png` under `reports/`. |
| "gates are frozen, rule 5" (worker forbidden to edit validators) | `pre-commit` hook refusing changes under `.autoport/validators/` unless `AUTOPORT_SUPERVISOR=1`; then the stop hook need not police it, and a generic validator makes the rule moot. |
| "copy the report to both directories" | Resolve the phase directory from `AUTOPORT_PHASE_ID`. |
| "proof runs are minutes, not hours" (PROOF ECONOMY block) | Orchestrator budget: sum of `sleep` in Bash calls and count of runner invocations per attempt; warn at 3 runs, abort the attempt at 45 min of proof time (the progress watchdog already exists at 45 min for artifacts). |
| "stale APK is the delivery, never the work" | In `close_gate`, on a deploy failure, check `pgrep gradle|ninja` and retry once after 120 s before returning fail. |
| "a trap that cost once must be a check" (preflight docstring) | Fix the 3-tuple bug, add a 5-line self-test that every CHECK yields 3-tuples, cap the prompt block at 5 findings. |
| "gate behind an always-failing gate" | Validators never `exit` before the last check; the template above has one criterion, so the problem disappears. |

### Two things the lead should decide, not me

- Whether `device: true` goes back on for owner-facing phases. It is the only artifact gate the harness has, and it is off for every phase the owner is currently testing. Its cost is 2-5 min per close; its false-red history is documented and the fixes are one `if` each.
- Whether the validator becomes generic (one file, criteria in `milestones.yaml`) or stays per-phase. The evidence says per-phase validators regrow clauses within 48 h of pruning; only a structural cap holds.
