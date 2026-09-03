# Autoport harness — mechanics audit (read-only, 2026-09-03)

Scope: `.autoport/orchestrator.py`, hooks, `phase_claim.sh`, `launch.sh`, `supervisor.sh`, `lib/{directives,preflight,ratchet}.py`, `lib/notify.sh`, `auto_build_apk.sh`, `auto_push_builds.sh`, `.claude/agents/*.md`, `model-profiles.json`, `apply-model-profile.sh`, `tools/harness_smoke.sh`, `tests/`, plus `state.json`, `milestones.yaml`, `DIRECTIVES.md` and the logs as evidence. Nothing was edited or launched; one offline reproduction of the preflight crash was run in-process with the Shield check stubbed.

All line numbers refer to the working-tree files on branch `physics-keira-clean` at commit `049204c570`.

---

## 1. As-is architecture

**Processes.** (1) `launch.sh` → `python -u orchestrator.py --quiet | tee logs/orchestrator.log`, one instance guarded by `flock` on `.autoport/.orchestrator.lock` (orchestrator.py:1834). (2) Per attempt, one `claude -p` worker (stream-json, `--dangerously-skip-permissions`, `--max-turns` from the phase, prompt on stdin) whose Task-tool subagents run `.claude/agents/autoport-{researcher,implementer,tester}.md`. (3) Two independent daemons under `systemd --user`: `auto_build_apk.sh` (PID 3508720, full arm64 build + gradle whenever HEAD or 4 Keira files change, then installs on the Redmi) and `auto_push_builds.sh` (PID 2263082, uploads APK/HD zip to the `jak-builds` GitHub release). (4) Claude Code hooks from `.claude/settings.local.json`: SessionStart (`session-start.sh` claims the phase via `phase_claim.sh`, injects a banner), PreToolUse (`pre-tool.sh`, a no-op), Stop (`stop.sh` re-runs the phase validator and refuses the stop if it fails), SessionEnd (`session-end.sh` releases the claim, dumps state).

**Files and owners.** `milestones.yaml` (278 phases, positional list) is edited by the supervisor/operator sessions, read once at orchestrator start (main:1882) and re-read on disk by the hooks and by close_gate for two fields. `state.json` is written only by the orchestrator (`current_phase_idx`, `retries`, `fingerprints`, `completed`, `blocked`, `validator_passed`, `parked`, `rate_interrupts`). `owner-ok/<pid>` tokens are touched by the operator. `DIRECTIVES.md` (156 KB) + the SPEC it names are inlined into every worker prompt by `lib/directives.py`. `.scope_stamp` mtime aborts the running attempt. Each attempt writes `logs/<pid>/attempt-NN.jsonl` and `validator-NN.txt`. Git: the orchestrator commits `git add -A` after every failed attempt (WIP checkpoint) and on pass/awaiting-owner, then pushes `HEAD`.

**One attempt, selection → commit.** `main` takes `phases[state.current_phase_idx]`; skips completed, exits on blocked, skips parked, re-parks owner_verify phases that already validated (1896-1955). `wait_for_quota` probes the OAuth usage endpoint (only pauses at 100 %). `run_phase` assembles `ultrathink + directives block (167 KB) + preflight block (always empty, see B1) + delegation/build/proof preambles + prompts/phase-<x>.md + last 4 KB of the previous validator output`, spawns claude, and reads its stdout with `select` on a 5 s tick, running four watchdogs: post-result idle 45 s, scope stamp change, 45 min without an artifact-fingerprint change, 30 min of total silence. After exit: fatal-config and no-start detection (zero tokens), the 529-storm heuristic, then the phase validator is run as ground truth. On validator exit 0, `close_gate` runs: GATE 1 real code change since the supervisor anchor, GATE 2 `deploy_verify.sh` + `_device_boot_check` (device phases), GATE 4 every `acquis/*.sh`, GATE 3 owner token. Outcomes: `pass` → completed + commit + push; `awaiting-owner` → commit, `validator_passed`, park, advance; `fail` → WIP commit, fingerprint, stuck check (3 identical), retry after 30 s; `stuck`/`blocked` → exit 0. At the end of the list, "reprise" moves the cursor to the first open phase and exits; someone must relaunch.

---

## 2. Bugs found

**B1. Preflight is dead on every attempt (confirmed).** `lib/preflight.py:355-366` `check_shield_untouched` *returns* a 2-tuple `("ok", msg)` instead of *yielding* 3-tuples; `run()` (:387) does `findings.extend(fn())`, which appends the two strings as separate entries. `prompt_block` (:420) then unpacks `"ok"` as `sev, code, msg` → `ValueError: not enough values to unpack (expected 3, got 2)`. The orchestrator swallows it (orchestrator.py:1356-1357), so no finding has ever been injected and the supervisor findings are never printed either (the `split` call sits after the raising call in the same `try`). Log: 278 occurrences of `preflight unavailable`. Reproduced offline. Second-order problem once fixed: the same run yields 147 raw findings, 145 of them `METRIC-FRAME` warnings (preflight.py:227-248, keyed on `phys-room.gc`), which the file's own rule calls "a flood is a brake" (:55, :137).

**B2. Infinite no-start loop, cause unrecoverable.** orchestrator.py:1652-1662: exit≠0 with zero tokens and zero tool calls → sleep 300 s and retry forever; the fatal detector (:1627-1644) only matches three strings. Observed 230 consecutive iterations (≈19 h) in `logs/orchestrator-20260831T130651.log` on phase Ghd-skin-origin-stretch while the active profile was `claude-opus-5[1m]`. Why claude exited 1 cannot be recovered: `attempt_log.open("w")` (:1422) overwrote `attempt-01.jsonl` on each iteration, and `--quiet` drops claude's non-JSON stderr (:1563-1565).

**B3. Attempt logs are overwritten when retries are reset.** The OPEN-DEFECTS exemption sets `retries[pid] = 0` (:2064); the next attempt is numbered 1 again and `attempt-01.jsonl` / `validator-01.txt` are opened with `"w"` (:1245-1246, :1422, :1715). Evidence: Grecharged-secondary-motion has 117 fingerprints in state.json, 18 attempt logs on disk, `retries = 4`.

**B4. The 529-storm heuristic relabels our own kills as infra outages.** :1692-1710 counts `overloaded` and `\b529\b` anywhere in the attempt JSONL, tool outputs included (orchestrator.py itself contains 6 such literals, so a worker that reads the harness source pre-loads the counter). Any non-zero exit with ≥3 hits, including exit 143 from the watchdogs (:1490-1539) or from an operator SIGTERM (:248-260), becomes "infra outage": validator skipped, WIP not committed, 10-min sleep. Log: 58 storms, the large majority `exit 143`; 5 are immediately preceded by our own `no ARTIFACT progress` / `forcing close` line.

**B5. Every operator relaunch burns a retry and a fingerprint.** `_sig` (:248-260) only sets HALT and kills the child; `run_phase` continues: validator runs (:1715), `retries[pid] = attempt` (:1721), fingerprint appended (:1786), WIP committed (:1778). Evidence (phase-claim.log + per-run logs of 2026-09-02): Gcine-cut attempts 1 and 2 lasted 56 s and 61 s, both counted and both failed on a pre-existing dirty golden the worker never touched; the phase has `max_retries: 3`, so the next failure blocks it and the orchestrator exits at that cursor (:1905-1915). Across the claim log, 373 of 597 worker sessions lasted under 3 minutes.

**B6. Lost update on state.json across overlapping orchestrators (observed today 02:13).** `logs/orchestrator-20260903T020515.log` shows the old run receiving a signal, then running the Gcine-cut validator until 02:15 (`validator-03.txt`: `[Gcine-cut ok]`), while `orchestrator-20260903T021319.log` shows a new run starting 02:13:18 and rewriting state.json at 02:13:19. The old run's result was never recorded: state still has Gcine-cut `retries = 2`, not in `validator_passed`, not parked. The single-instance flock (:1834-1855) did not prevent the overlap and the mechanism is not provable from the logs, but the lock file is *tracked in git* (`git ls-files .autoport/.orchestrator.lock`, committed by every WIP checkpoint), so any checkout/stash/reset replaces its inode and voids the lock; and HALT never shortens the post-kill tail (validator + gates can take 5+ minutes).

**B7. `.gitignore:97` is corrupted** (`_new-all-types.gc.autoport/state.json` on one line), so `state.json`, `.orchestrator.lock`, ten `.phase-claim.*` files, `.last_apk_build_sha`, `.last_owner_notify.json`, `.directives_issued`, `.scope_stamp` are tracked and re-committed by `git add -A` (:848) in every WIP checkpoint. 2067 files are tracked under `.autoport`, 28 of them `.bak*`.

**B8. Hooks and orchestrator disagree on which phase is running.** `session-start.sh:56-59` and `stop.sh:45-47` resolve the phase from `state.current_phase_idx` against the *on-disk* `milestones.yaml`, while the orchestrator uses the list loaded at startup (:1882-1883) and already exports `AUTOPORT_PHASE_ID`. Phases are inserted mid-list while a run is alive (the `-2` phases were inserted at indices 109-113 at 2026-09-02 00:55 during the run that lasted 09-01 17:05 → 09-02 02:05). In that window the Stop hook runs another phase's validator and holds the worker hostage on it, and the banner names the wrong phase. `stop.sh:39-43` also releases the hostage only for `completed`, not for `parked`/`validator_passed`.

**B9. Owner-confirmed parked phases never complete.** In `main`, the parked skip (:1926-1930) runs *before* the owner-token check (:1932-1940). Nine parked phases currently have an `owner-ok` token and are still not in `completed` (Gcine-vertical-frame, Gloading-screen, Gmemory-ceiling-and-crash, Gprecompute-deterministic-bake, Gplayability-input-and-loadgate, Grecharged-hd-eye-scale, Gjak1-crate-collision-2, Gsubtitle-style-2, Grecharged-hud-jak1). They inflate the "validated but not done" backlog (27 phases) forever.

**B10. The artifact-progress watchdog measures the wrong process.** `_progress_fingerprint` (:1192-1229) includes the APK mtime and `.autoport/tmp/*`, both rewritten by `auto_build_apk.sh` every cycle, so an idle worker looks alive; a worker doing 45 min of reading/analysis with subagents (no tree change) is killed (13 kills logged), then retried with only 4 KB of validator tail as memory (:1361-1370).

**B11. Rate probing is non-functional but still runs.** 1105 failed probes vs 39 successes in the log: 723 × `429 Retry-After=0` (the usage endpoint throttles us; :373-385 then breaks immediately), 374 × `AttributeError: 'NoneType'` from `_parse_rate_payload` (:327-342, `resets_at` null). `wait_for_quota` then "proceeds optimistically" (:765-769), so the pre-phase gate is a no-op, while `maybe_probe_inline` (:1568) is called synchronously from the read loop and can block it up to `PROBE_DEADLINE_SEC` (30 s).

**B12. GATE 4 runs the x86 game for every close, and fails closed on harness state.** For non-device phases `acq_serial` is empty (:1138-1141) so `acquis/font-urbanist.sh` takes the x86 leg (:75-88): launches `build/game/gk` for 75 s with `out/jak1/iso`. That directory is rewritten in ARM64 by the build daemon for minutes after every commit (see D4), so a close that lands in that window fails "un acquis n'est plus tenu" for a reason unrelated to the phase. Unlike GATE 2, the acquis serial does not re-read `device_serial` from disk.

**B13. Keira-specific escape hatches are applied to every phase.** `spec_sections_remaining` (:999-1029) reads the breast-spec ledger `SPEC-COVERAGE.md` (772 KB) and the OPEN-DEFECTS rule (:1732-1754, :2061-2066) triggers on any validator whose single FAIL line contains `OPEN-DEFECTS`.

**B14. Event processing lags behind the pipe.** `select` watches the raw fd but `readline` on the text wrapper over-reads into a private buffer (:1471, :1544); lines already buffered are only processed when new bytes arrive, so `result_seen` and `last_event_at` lag and the 45 s post-result close fires late. Minor, but it is the loop every watchdog depends on.

**B15. Duplicate-worker refusal is not understood by the orchestrator.** `session-start.sh:37-53` tells a duplicate worker to stop, but the orchestrator still runs the validator, counts the attempt, fingerprints and commits WIP for it.

**B16. `session-end.sh:17-26` appends the entire state.json (38 KB) at every session end** → `logs/session-end.log` is 52 MB and growing.

**B17. Build daemon hazards (auto_build_apk.sh).** The dirty-tree guard lists only three Keira files (:338-341); any other half-edited source is built and installed. "Patience" (:296-298) deliberately builds *during* the worker's gk run (672 occurrences). The trigger includes `HEAD` (:262-264), so every WIP checkpoint after every failed attempt launches a full arm64 build + `gradle clean` + assemble (454 builds total; 8 in the four hours before this audit). The daemon also commits (:348-351), making it a second committer racing the orchestrator's `git add -A` (`auto-checkpoint commit failed` seen once).

**B18. Publisher orders contradict each other.** auto_push_builds.sh:19-20 and :109 ("publish even when not green") vs :79-84 (skip when HEAD is a WIP checkpoint). Since HEAD is a WIP checkpoint most of the time, the owner effectively only gets builds after a validator pass, which is the opposite of the 2026-08-11 order the file quotes.

**B19. Two drivers of the same phone with no shared lock (plausible race, not proven).** `_device_boot_check` (:906-996) force-stops/launches the Redmi three times; the daemon's `reconcilier_telephone` (:133-246) installs and launches it with a 10-min wait, deferring only on `.deploy-in-progress` (which the gate never writes) or a foreground window under 25 min. An `adb install -r` landing during the boot check yields "app did NOT reach in-game" for the wrong reason.

---

## 3. Dead, disabled or stale code and config that still costs attention or tokens

- **Rate-limit machinery (~350 lines, output-only).** Thresholds at 999/100 (orchestrator.py:104-106); `fetch_rate_status` :345-408, `PrettyState.probes/kill_pending` :442-446, `_current_pct` :499-529, `maybe_probe_inline` :670-736, `wait_for_quota` :756-808, rate_limit_event branch :577-595, the kill block :1572-1584, cache seeding :1414-1418. Only effect: console lines; see B11.
- **`NOTIFY_SCRIPT`** :232 unused; `notify()` :815-825 prints only. **`lib/notify.sh`** dead at line 2 (69 lines kept).
- **`hooks/pre-tool.sh`** dead at line 2 but still registered (`.claude/settings.local.json:15-25`): one bash spawn per Bash/Edit/Write call for nothing.
- **`hooks/session-start.sh:75`** "you are Opus 4.7 at max effort"; **:76-84** AArch64 emitter instructions (mirror `goalc/emitter/IGen*`, regalloc, asm trampoline) from the May emitter buckets, injected into every current phase (cutscenes, fonts, PBR).
- **`launch.sh:58-59`** banner hardcodes "Model: claude-opus-4-8[1m] / Effort: max".
- **orchestrator.py:5-15, :26** docstring names Opus 4.7/4.8 and profile `opus48-xhigh` (active: `fable51-high`); **:1264** "the fable manager must delegate to opus-4-8 subagents".
- **`model-profiles.json`**: 7 profiles, 6 inactive; `fable51-high._note` is the `fable5-high` note verbatim (dated 07-29, talks about fable-5); `opus5-xhigh` carries a stray `effort` key; `opus-xhigh._note` says opus-4-8 but pins opus-5.
- **`.claude/agents/*.md` frontmatter `effort: xhigh`** (all three) while the active profile says high/medium/medium; `apply-model-profile.sh` was not run after the flip, so the preamble (orchestrator.py:1272-1277) announces one effort and the agent files enforce another.
- **`supervisor.sh`**: journal header with buckets A-F (:34-41), bootstrap text "Reset state.json / Rewrite milestones.yaml to bucket A-F" (:61-68), destructive if someone follows it; **`SUPERVISOR_PROMPT.md`** (434 lines, 2026-05-20) still cites `--model claude-opus-4-7` and a north star ("boots on the Redmi, reaches Geyser Rock") achieved months ago; **`REDESIGN.md`** 2026-05-20.
- **`.bak*` files**: `orchestrator.py.bak.090830` and `.bak.133529` (97 KB each), `milestones.yaml.bak.115010` (175 KB), 5 `state.json.bak*`, 14 `*.bak-shield` that contain the forbidden Shield address (excluded from `shield_guard.sh` only by its `\.bak` filter at :16), 28 tracked in git.
- **Campaign residue at `.autoport/` root**: 1093 entries, 624 `.sh` and 318 `.py` one-off scripts (`ajp_*`, `ao_*`, `gcine_*`, `gmam_*`, `gsr_*`…), 19 GB on disk. `shield_guard.sh:15-16` greps the whole repo for the address at every attempt; preflight's `check_self_matching_kills`/`check_device_prop_leak` glob all of them.
- **`tools/harness_smoke.sh`** is the gate of one phase (Grecharged-buildsys-firstboot), not a harness test. **`tests/`** contains only `tests/emitter` (May, emitter differential). There is no test of the harness; `py_compile` passes, `pyflakes` is not installed.
- **`.phase-claim.TEST-claim-phase`** (2026-08-12 test residue) and nine stale claim files, all tracked.
- **`state.json`** historical keys `supervisor_rollback` (May), `rate_interrupts` (Grecharged-mesh-browser 86, Gperf-particles 68…), `stuck_reasons`.
- **`milestones.yaml`**: 15 blocked `A*` emitter phases from May still in the list; `close_gate(phase, validator_log)` never uses `validator_log` (:1032).
- **`directives.py:11-12` docstring** claims the phase prompt is hashed; `version()` (:68-75) deliberately does not.

---

## 4. Design defects that plausibly cause the owner's symptoms

**D1. Every phase runs under the Keira physics contract (misreads tasks).** `directives.block(pid)` (lib/directives.py:93-128) inlines all of `DIRECTIVES.md` (156 KB, 67 dated arbitration sections about breast/hair physics) plus `SPEC-keira-physique.md` into every worker prompt: 167 285 chars (~45 k tokens) per attempt, same version `vd9e8b66782` for all phases. The active scope section (`DIRECTIVES.md:1284-1341`) states "Phase: Grecharged-secondary-motion", "KEIRA SEULE — aucun autre modèle ne reçoit de données", "CONTRAT UNIQUE: SPEC-keira-physique.md". The three agent definitions (`.claude/agents/*.md:10-16`) order subagents to re-read that file first and to "stop immediately" if their task's scope is not the DIRECTIVES scope. A cutscene, font or PBR phase therefore starts with a 45 k-token contract that contradicts its prompt, and its subagents are told to refuse it. Log: `directives … 167285 chars` on 736 attempts. The mechanism (serial-based invalidation) is right; the payload is not phase-scoped.

**D2. Reopening a phase means cloning it with a `-2` suffix (backlog tangle).** A parked/validated phase cannot be reopened in place: the top-of-loop shortcut (:1932-1955) re-parks it on sight. So owner feedback produces a new entry inserted mid-list with the *same* prompt file (4 prompts shared by 2-3 phases; `phase-Gcutscene-skip-all.md` by three) and sometimes the same validator (`Gcutscene-npc-flicker-2` shares `validators/phase-Gcutscene-npc-flicker.sh`, which reads `reports/Gcutscene-npc-flicker/report.txt`, :4). The feedback itself lives only in the YAML `name:` field, which `run_phase` never puts in the prompt (:1359-1360); it reaches the worker only through the index-based session-start banner (B8). 137 of 288 validators reference a report directory of another phase id.

**D3. Positional cursor over a mutable list, and exit-and-hope.** `current_phase_idx` indexes a YAML list that is edited while the orchestrator runs; the same index meant Gcine-cut at 2026-09-02 18:18 ("fin de liste — reprise … Gcine-cut (index 109)") and Gcutscene-npc-flicker-2 at 02:13. "Reprise" (:2135-2148) sets the cursor then `return 0`; a blocked phase at the cursor also exits (:1905-1915), and three blocked phases sit ahead of it (indices 148, 161, 232). Result: 251 launches in total, 60 in the last ten days, each relaunch itself costing a retry (B5). Answering "what is next and why" requires reading four state sets (completed/parked/blocked/validator_passed) against the list; nothing prints that.

**D4. The harness sabotages its own verification through the build daemon.** Failed attempt → WIP commit (:1778) → `auto_build_apk.sh` sees HEAD change (:262-264) → full arm64 build that rewrites `out/jak1/iso` in ARM64 for minutes + `gradle clean` + assemble (≈1 h of CPU beside the worker), "pendant un gk" after 25 min (:296) → x86 validators and the acquis x86 leg (B12) fail on a foreign ISO → another WIP commit. The memory note `feedback_deploy_lock_checked_only_at_cycle_top` records exactly this false red. Last night: builds at 23:11, 23:30, 23:41, 23:56, 00:35, 01:02, 01:29, 03:00.

**D5. Over-verification per close.** One passing attempt runs the phase validator three times (worker, Stop hook, orchestrator), GATE 1 git scans, `deploy_verify.sh`, a boot check up to 3 × 48 s, the acquis x86 run of 75 s (plus 60 s on device), while the PROOF ECONOMY preamble (:1306-1320) tells the worker to prove less. The Stop hook (`stop.sh:59-77`) refuses to let the worker end while the validator fails, which for owner-gated phases (OPEN-DEFECTS style validators that never pass) forces the worker to keep working until `max_turns` (3000 on 71 phases) or a watchdog kill.

**D6. Retries discard context, not just work.** After a watchdog kill or a relaunch, the next attempt gets the phase prompt plus 4 KB of validator tail (:1361-1370) and no digest of what the previous attempt found; combined with B10/B5 this is the "re-discovers everything" loop. The WIP commit preserves the tree but not the reasoning.

**D7. Standing orders are layered by date and never reconciled.** Examples coded side by side: "no pre-emptive stops" (:101-106) vs four watchdogs (:1189, :127-128); "publish even if not green" vs "never publish WIP" (B18); "proof economy" vs five gates; "human gate must not stop the worker" (:1739-1750) vs Stop hook hostage. Each was a reasonable reaction to one incident; together they pull in opposite directions, and the worker reads all of them in the preamble.

**D8. Double workers are guarded at three layers but the state layer is unguarded.** flock (orchestrator), phase claim (hook), PID files (daemons) exist; state.json has no versioning or lock, so overlapping runs silently lose results (B6).

---

## 5. What works well and must be preserved

- **Ground-truth validator run by the orchestrator, not the worker's word** (orchestrator.py:1715-1719), with the per-attempt forensic JSONL written unbuffered (:1550-1552) and `phase_start`/`phase_end` summary records (:1423-1433, :1611-1621).
- **WIP checkpoint commits after failed attempts** (:1777-1780): bisectable history; keep, but exclude harness state files (B7).
- **Prompt over stdin** (:1446-1451) — the E2BIG fix.
- **`.scope_stamp` immediate abort** (:1176-1186, :1500-1508): cheap, precise, one observed use.
- **`phase_claim.sh` liveness by (pid, starttime, comm)** (:87-101), no pattern kills, refuse-don't-kill semantics, separate lock file for the atomic write (:113-116).
- **Single-instance flock** (:1834-1855) — right primitive; needs an untracked lock path and a post-HALT fast exit.
- **`close_gate` re-reads `no_code` and `device_serial` from disk** (:1050-1056, :1094-1101), game-aware deploy gate (:1107-1108), boot-check route B for log-silent phones and reading output not exit codes (:968-990).
- **Intent of not counting infra failures** (no-start, 529) and of not calling OPEN-DEFECTS "stuck" (:2061-2066): keep the intent, fix the detection (B2, B4).
- **`directives.py` serial-based version** (:48-55): deliberate invalidation instead of hashing prose; `.directives_issued` accepting versions issued under the current serial (:80-91).
- **`preflight.py` shape**: cheap checks, `MissingInput` (:38-41), audience split via `SUPERVISOR_CODES` (:398-406), the live-set scoping (:53-67, :135-150). Fix B1 and cap per-code findings.
- **`ratchet.py`**: measured noise bands (:96-99) and "a run that failed its own gates does not set the bar" (:207-211).
- **`auto_push_builds.sh`**: ancestor-of-HEAD rule (:67-78), HD zip as a separate deliverable (:85-92), PID files instead of pattern matches (:25-30), `release_notes.sh` + `owner_testable.py` after each push (:120-130).
- **`auto_build_apk.sh`**: `TMPDIR` + `java.io.tmpdir` (:56-58), content-hash trigger (:262-264), idempotent reconcile that resolves the launcher activity (:222-231) and quotes device stamps (:233-245), the orphan-holder check on `.deploy-in-progress` (:321-329).
- **Hook scope guards on `AUTOPORT_PHASE_ID`** (session-start.sh:14, stop.sh:16) and the `stop_hook_active` loop guard (stop.sh:26-29).
- **`shield_guard.sh`** scanning by value, not by list (:14-16).

---

## 6. Complexity metrics

**LOC (working tree).**

| File | LOC |
|---|---|
| orchestrator.py | 2163 |
| auto_build_apk.sh | 456 |
| lib/preflight.py | 436 |
| lib/ratchet.py | 220 |
| phase_claim.sh | 147 |
| lib/directives.py | 137 |
| auto_push_builds.sh | 134 |
| launch.sh (repo root) | 106 |
| supervisor.sh | 99 |
| tools/harness_smoke.sh | 94 |
| acquis/font-urbanist.sh | 89 |
| hooks/session-start.sh | 88 |
| hooks/stop.sh | 77 |
| lib/notify.sh | 69 (dead) |
| hooks/pre-tool.sh | 58 (dead) |
| hooks/session-end.sh | 28 |
| apply-model-profile.sh | 27 |
| shield_guard.sh | 26 |

Data the loop reads each attempt: `DIRECTIVES.md` 2296 lines / 156 KB, `SPEC-keira-physique.md` 11 KB, `milestones.yaml` 2956 lines (278 phases), `state.json` 1359 lines, `PITFALLS.md` 814 lines (73 GUARD entries), `SPEC-COVERAGE.md` 772 KB, `SUPERVISOR_PROMPT.md` 434 lines. Inventory: 288 validators, 289 prompts, 408 report dirs, 1093 top-level entries, 2067 tracked files, 19 GB.

**Gates at close.** `close_gate` has 5 checks (code change, deploy_verify, boot check, acquis scripts ×N (N=1 today), owner token); upstream of it the phase validator runs 3× per attempt (worker, Stop hook, orchestrator) and the OPEN-DEFECTS/spec-ledger special case adds a sixth decision.

**Flags and knobs.** 37 module-level constants in orchestrator.py; 1 CLI flag (`--quiet`); 13 recognised per-phase YAML fields (`id, name, prompt, validator, max_turns, max_retries, device, device_serial, owner_verify, no_code, effort, game, device_pkg`); env vars: orchestrator sets 4 (`CLAUDE_EFFORT, CLAUDE_CODE_SUBAGENT_MODEL, AUTOPORT_PHASE_ID, AUTOPORT_PHASE_VALIDATOR`) and reads 2 (`ADB, ANDROID_SERIAL`); hooks/daemons/acquis read 7 more (`CLAUDE_PROJECT_DIR, HOME, TMPDIR, GRADLE_OPTS, DISPLAY, XAUTHORITY, SDL_VIDEODRIVER`) plus `SKIP_DEVICE`; 7 model profiles, 1 active. `max_retries` ranges 3…400 (60 phases at 3, 30 at 60, 6 at 400); `max_turns` 120…4200 (71 phases at 3000).

**Owner standing orders hardcoded in orchestrator.py.** 83 lines mention the owner; about 20 distinct dated policy blocks: rate policy 06-11/06-12 (:101-106, :581), notify drop 06-13 (:824), auto-checkpoint 06-13 (:1772), no-start 06-12 (:1646), close-gate mandate 06-30 (:872), GATE 1/2 hotfix incidents 07-13/07-29/07-09 (:1044-1048, :1088-1093, :1103-1106), build efficiency 08-06 (:1288), proof economy 08-06 (:1306), 45-min watchdog 08-06 (:1189), scope abort (:1176), directive transmission 08-11 (:1322), preflight 08-11 (:1339), single instance 08-11/12 (:1804-1827), OPEN-DEFECTS exemption 08-12 (:2055), human gate 08-23/08-26 (:1724-1754), no-stop-on-owner 08-30 (:2039), parked skip 08-31 (:1920), acquis 09-02 (:1127), reprise 09-02 (:2129).

**Backlog as of state.json (278 phases):** 221 completed, 19 blocked (15 are May-era `A*` emitter phases), 21 parked (9 with an owner-ok token already present, see B9), 27 `validator_passed` but not completed, 22 open and unparked; 5 reopened `-2` clones; cursor at index 109 = Gcutscene-npc-flicker-2 (worker PID 3712298 alive at audit time).
