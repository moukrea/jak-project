# Autoport harness: throughput and failure-pattern review (May 18 to Sep 3, 2026)

Sources: `git log --all` (14 415 unique commits, 4 778 tagged `[autoport/…]`), 573 surviving `attempt-NN.jsonl` logs, `orchestrator.log` (covers Aug 2 onward only, no timestamps), `state.json`, `milestones.yaml` (278 phases), `owner-ok/`, `acquis/`, `reports/` (9.1 GB, 5 488 files, 91 phases). Read-only; nothing was modified.

## 0. Headline

- Phases closed per week fell from 22 to 46 in June to 5, 3 and 0 in the last four weeks. The August 10 to 23 fortnight closed 0 phases while producing 645 commits on one phase (Keira breast physics).
- The attempt logs under-report August by roughly 7x: the orchestrator launched 854 worker sessions since Aug 2 but only 116 log files survive, because every rate-limit restart re-launches "attempt 1" and overwrites `attempt-01.jsonl`. `state.json` records 660 rate-interrupts in total, 450 of them on two phases.
- A broken quota probe (374 `AttributeError: 'NoneType'.replace`, 1 105 HTTP 429 on the probe) makes the orchestrator "proceed optimistically", get refused at the door, sleep 5 minutes and retry: 234 door refusals, 230 of them on `Ghd-skin-origin-stretch`, which is a measured 19.7 h gap between its attempt 1 and attempt 2.
- The supervisor role has effectively disappeared. `SUPERVISOR_JOURNAL.md` stopped on 2026-06-18. `[autoport/supervisor]` commits (1 201 between May and July) stop on Aug 1. The `[keira-physique]` supervisor stream (211 commits) stops on Aug 28. Since then workers author their own follow-up phases, prompts, validators and directives inside their attempts.
- Validators are satisfied by report files written by the same worker. In the last 60 attempts, 36 passed the validator, yet 41 of the 221 "completed" phases have a last commit that says `NOT done` / `AWAITING OWNER PLAY-TEST`, and 39 of the 96 owner-ok tokens were written by the supervisor rather than the owner (31 are empty files).
- `.autoport/` now holds 942 top-level one-off scripts (145 832 lines, 8 MB), 433 of them created in August. `DIRECTIVES.md` (created Aug 11) is 160 KB and is inlined into every worker prompt: 736 launches since Aug 2 at up to 167 285 characters each, versus 10 539 characters at the start of August.

## 1. Weekly time series

Autoport-tagged commits, all branches. "worker" = `[autoport/<phase>]`, "sup" = `[autoport/supervisor]`. The `[keira-physique]` supervisor stream (Aug 10 to 28) is not autoport-tagged and is shown separately. "done" = completed phases whose last commit falls in that week (state.json has no completion timestamps). "owner-ok" = tokens by file mtime. Weeks of May 25 and Jun 1 had zero commits (harness paused). The last row covers Aug 31 to Sep 3 only.

| week (Mon) | autoport commits | worker | sup | keira-physique | distinct phases | "cycle N" | AWAITING OWNER | NOT done | done | owner-ok |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-05-18 | 507 | 425 | 67 | 0 | 89 | 0 | 0 | 0 | 46 | 0 |
| 2026-06-08 | 619 | 369 | 250 | 0 | 41 | 0 | 0 | 0 | 35 | 0 |
| 2026-06-15 | 313 | 259 | 51 | 0 | 26 | 0 | 0 | 0 | 22 | 0 |
| 2026-06-22 | 437 | 287 | 150 | 0 | 38 | 0 | 0 | 0 | 35 | 0 |
| 2026-06-29 | 359 | 239 | 120 | 0 | 28 | 0 | 55 (15 %) | 50 | 26 | 23 |
| 2026-07-06 | 420 | 282 | 138 | 0 | 16 | 0 | 43 (10 %) | 37 | 8 | 8 |
| 2026-07-13 | 492 | 300 | 192 | 0 | 25 | 0 | 50 (10 %) | 44 | 25 | 24 |
| 2026-07-20 | 375 | 203 | 172 | 0 | 7 | 0 | 44 (12 %) | 44 | 6 | 6 |
| 2026-07-27 | 167 | 99 | 68 | 0 | 5 | 0 | 17 (10 %) | 17 | 1 | 1 |
| 2026-08-03 | 179 | 179 | 0 | 0 | 11 | 39 | 34 (19 %) | 34 | 7 | 6 |
| 2026-08-10 | 256 | 256 | 0 | 124 | 2 | 3 | 6 (2 %) | 6 | 0 | 0 |
| 2026-08-17 | 389 | 389 | 0 | 76 | 1 | 205 | 0 (0 %) | 0 | 0 | 0 |
| 2026-08-24 | 176 | 176 | 0 | 11 | 24 | 45 | 31 (18 %) | 31 | 5 | 16 |
| 2026-08-31 | 89 | 89 | 0 | 0 | 23 | 12 | 25 (28 %) | 36 | 3 | 8 |

Reading: the "cycle N" commit style appears on Aug 3 and peaks at 205 commits in one week on one phase (`Grecharged-secondary-motion`, cycles c100 to c148). "AWAITING OWNER PLAY-TEST" appears in subjects from Jun 29 (owner_verify gate introduced) and its share of commits is at its highest now (28 %). The owner-ok token wave of Aug 24 to 30 (16 tokens) closed phases mostly opened the same week, i.e. small regressions, not the backlog.

Monthly cost from the surviving attempt logs (August and September are under-counted because of the overwrite):

| month | attempts (surviving logs) | API hours | cost USD | output Mtok | cache-read Mtok |
|---|---|---|---|---|---|
| 2026-05 | 89 | 45.8 | 925 | 5.8 | 1 354 |
| 2026-06 | 153 | 177.7 | 3 778 | 23.8 | 3 506 |
| 2026-07 | 215 | 180.0 | 4 853 | 16.0 | 2 403 |
| 2026-08 | 89 | 66.4 | 2 449 | 8.4 | 2 153 |
| 2026-09 (3 days) | 27 | 24.8 | 950 | 3.2 | 1 156 |

Models by month (attempt logs): May opus-4-7; June opus-4-8 (117) + fable-5 (19); July fable-5 (128) + opus-4-8 (64) + opus-5 (23); August opus-5 (74); September fable-5-1 (12) + opus-5 (15). The current profile is `fable51-high` with `--max-turns 3000`.

## 2. Per-phase table, G* phases

189 G phases have attempt logs: 438.8 h of wall-clock and 10 928 USD in the surviving logs. Retries in `state.json` and rate-interrupts show where the logs were overwritten (e.g. secondary-motion: 18 log files, 4 retries, 220 rate-interrupts, 810 commits over 22 days).

Top 20 by wall-clock in surviving logs:

| phase | attempts (logs) | retries (state) | rate-interrupts | hours | tool calls | cost USD | family size | first | last | status |
|---|---|---|---|---|---|---|---|---|---|---|
| Grecharged-pbr-realtime-fusion | 36 | 1 | 1 | 32.5 | 7 343 | 719 | 1 | 07-23 | 07-28 | todo |
| Gjak2-render | 3 | 3 | 18 | 19.4 | 3 384 | 329 | 1 | 07-06 | 07-07 | done+ok |
| Gd1-cutscene-clock | 1 | 1 | 0 | 14.1 | 223 | 27 | 1 | 06-20 | 06-21 | done |
| Grecharged-grass-poc | 16 | 16 | 0 | 13.0 | 1 816 | 324 | 1 | 07-11 | 07-12 | done+ok |
| Grecharged-mesh-browser | 16 | 16 | 86 | 12.8 | 1 651 | 288 | 1 | 07-30 | 07-31 | done+ok |
| Grecharged-secondary-motion | 18 | 4 | 220 | 11.4 | 3 064 | 426 | 1 | 08-27 | 08-28 | todo (validator passed) |
| Ginput-replay-liverecord | 1 | 1 | 0 | 10.0 | 225 | 49 | 1 | 06-27 | 06-28 | done |
| Ghd-skin-origin-stretch | 8 | 8 | 230 | 9.7 | 1 410 | 203 | 1 | 09-01 | 09-03 | todo |
| Grecharged-ambient-occlusion | 6 | 2 | 5 | 8.2 | 721 | 58 | 1 | 07-15 | 07-16 | done+ok |
| Grecharged-directional-ambient | 10 | 10 | 2 | 8.1 | 1 428 | 174 | 1 | 07-20 | 07-20 | done+ok |
| Gcollision-wallslide | 2 | 2 | 0 | 8.0 | 1 261 | 164 | 1 | 06-25 | 06-25 | done |
| Grecharged-managed-assets-merge | 5 | 5 | 0 | 6.5 | 611 | 74 | 1 | 08-26 | 08-26 | done+ok |
| Grecharged-lightprobes | 13 | 13 | 0 | 6.3 | 1 443 | 246 | 1 | 07-21 | 07-22 | done+ok |
| Gmatch-original | 4 | 4 | 0 | 5.9 | 940 | 80 | 1 | 06-18 | 06-19 | done |
| Grecharged-hd-models4 | 5 | 0 | 1 | 4.5 | 807 | 80 | 5 | 08-05 | 08-05 | done+ok |
| Gcollectible-state | 1 | 1 | 0 | 4.4 | 897 | 60 | 1 | 06-25 | 06-26 | done |
| Gcrash-mouche2 | 2 | 2 | 0 | 4.2 | 775 | 94 | 3 | 06-24 | 06-24 | done |
| Gecho-pool | 3 | 3 | 0 | 4.1 | 937 | 110 | 1 | 06-26 | 06-26 | blocked |
| Grecharged-grass-overhang7 | 5 | 5 | 1 | 4.1 | 812 | 103 | 7 | 07-14 | 07-15 | done+ok (token says PARKED, NOT a pass) |
| Gmenu-ui-placement | 3 | 3 | 0 | 3.9 | 557 | 39 | 1 | 06-19 | 06-19 | done |

Top by commits (better proxy for the overwritten phases):

| phase | commits | span | retries | rate-interrupts | status |
|---|---|---|---|---|---|
| Grecharged-secondary-motion | 810 | Aug 5 to Aug 28 (22 d) | 4 | 220 | todo |
| Grecharged-grass-poc | 141 | Jul 10 to 13 | 16 | 0 | done |
| Grecharged-pbr-realtime-fusion | 105 | Jul 23 to 28 | 1 | 1 | todo |
| Grecharged-ambient-occlusion | 72 | Jul 11 to 16 | 2 | 5 | done |
| Grecharged-lightprobes | 52 | Jul 21 to 22 | 13 | 0 | done |
| Gcine-cut | 48 | Jun 19 to Sep 2 (75 d) | 2 | 0 | todo |
| Grecharged-mesh-browser | 47 | Jul 28 to 31 | 16 | 86 | done |
| Gjak2-render | 46 | Jul 6 to 7 | 3 | 18 | done |

Reopened families (phase X, X2, X-2 …), 11 families among G phases:

| family | members | hours in logs |
|---|---|---|
| Grecharged-grass-overhang | 7 (overhang … overhang7) | 10.7 |
| Grecharged-hd-models | 5 | 18.1 |
| Grecharged-foliage-wind | 3 (wind, wind2, wind3) | 5.2 |
| Gcrash-mouche | 3 | 6.8 |
| Gcine-crash | 2 | 2.3 |
| Gcutscene-npc-flicker | 2 | 4.6 |
| Gjak1-crate-collision | 2 | 6.8 |
| Gcutscene-skip-polish | 2 (plus Gcutscene-skip-all sharing the prompt) | 2.9 |
| Gsubtitle-style | 2 | 3.0 |
| Gfixed-tick-anim-interp | 2 | n/a (the -2 has no log yet) |
| Gperf-particles | 2 | 0.7 |

Attempts per G phase: 103 phases needed 1 attempt, 42 needed 2, 25 needed 3, 19 needed 4 or more (max 36).

Secondary-motion commit cadence is uniform across all 24 hours of the day (23 to 49 commits per hour-of-day bucket), i.e. a continuous unattended loop for three weeks.

## 3. Attempt failure taxonomy (last 60 attempts by mtime, Aug 28 22:39 to Sep 3 03:23)

Classification from the validator tail plus the result event:

| outcome | count | notes |
|---|---|---|
| validator PASS | 36 | includes 4 that passed only after a close-gate retry |
| validator FAIL: no report / marker missing | 12 | 9 of them had zero Edit/Write to code; the worker ran out (killed or turn-limited) before writing `report.txt` |
| validator FAIL: device-run evidence missing or refused | 3 | e.g. `[Ghso FAIL] la preuve APRES correction doit etre prise sur l'APPAREIL` |
| close-gate: stale / missing APK | 2 | `libgk.so (23:07) is OLDER than newest source (23:11)`, `no app-jak1-debug.apk` |
| close-gate: device not connected | 2 | `device eae4df44 is NOT connected (adb sees: none)` |
| validator FAIL: golden tree dirtied | 2 | Gcine-cut, 7 tool calls each, 1 minute |
| validator FAIL: other | 2 | owner-feedback gate (`l'ICONE du bouton n'est pas centree`), `deploy_verify FAIL` inside validator |
| killed / still running | 1 | Gcutscene-npc-flicker-2 attempt 2 (in flight at snapshot) |

Result events in the same 60: 41 `success/completed`, 3 `success/api_error`, 16 with no result event at all (worker killed by the orchestrator: owner signal, 45-minute no-artifact watchdog, or forced close). Wall-clock of the 60: 64.9 h, median 0.99 h, max 4.8 h. Only 7 of the 60 carry a cost field (335 USD); by tokens the 60 consumed 6.6 M output and 2 042 M cache-read tokens.

Orchestrator-level ends since Aug 2 (854 launches): exit 0 = 282, exit 143 = 62 (40 owner SIGTERM "Received signal", 10 "no ARTIFACT progress for 45 min", 5 "claude emitted result but hasn't exited (45s idle); forcing close", 13 after a 429 on the probe), exit 1 = 14, exit -9 = 2, `error_max_turns` = 2 in all 573 logs. No claim conflicts were logged (the `.phase-claim.*` file was created 32 times and deleted 45 times for secondary-motion without a conflict message). API 529 storms: 12 waits of 10 minutes.

Rate-limit machinery, all phases: 660 rate-interrupts recorded in `state.json` (secondary-motion 220, Ghd-skin-origin-stretch 230, mesh-browser 86, perf-particles 68, jak2-render 18). Of the 468 "Retrying after session reset" lines since Aug 2, 224 + 123 say `(session ?)`, meaning the probe had no data. The `Ghd-skin` case is the NO-START path: `claude exited 1 with ZERO work done — hard rate limit at the door. Backing off 5 min` 230 times in a row (attempt 1 ended 09-01 09:11, attempt 2 started 09-02 04:51). Secondary-motion had 97 mid-work kills with a real percentage: each one discards the worker's context and relaunches with the full 160 KB directive block.

Share of an attempt spent in proof/verification: tool-call timestamps are not in the stream, so the proxy is tool-call index. Workers edit mostly through Bash (13 899 Bash calls vs 194 Edit calls in the last 60), so code writes were detected in both Edit/Write and Bash (`sed -i`, `cat >`, `tee`, `git apply` on game/, goal_src/, android/, common/). Result on the last 60:

| metric | value |
|---|---|
| attempts with at least one detected code write | 49 / 60 |
| share of calls before the FIRST code write (investigation) | median 47 % |
| share of calls after the LAST code write | median 5 %, mean 11 %, p75 16 % |
| calls that write code | 436 / 15 300 (2.9 %) |

The "after last edit" number is small because edit and proof interleave in short cycles (edit, build, campaign, measure, edit). The category mix says where the calls go: read/search 9 078 (59 %), analysis in python/awk 1 670 (11 %), build 1 207 (8 %), git 744 (5 %), adb/device 664 (4 %), x86 runs and campaigns 633 (4 %), edits 436 (3 %). Time-weighted over long tool calls only (heartbeats of 30 s or more, 27 h out of 65 h wall): waiting on logs with tail/cat 10.7 h, runs/campaigns 8.0 h, builds 4.7 h, analysis 1.4 h, adb 1.2 h. So roughly half of an attempt is orientation before touching code, and most of the wall-clock after that is waiting on builds and device campaigns, not on writing code. Across all 573 logs, attempts with zero Edit/Write to code rose from 18 % (June) and 22 % (July) to 56 % (August) and 59 % (September): the recent phases are measurement and report phases, not code phases.

## 4. Self-sabotage and churn indicators

Reverts and retractions (autoport-tagged subjects):

| indicator | count | by month |
|---|---|---|
| `WIP checkpoint — attempt N (validator FAILED; auto-versioned for rollback/bisect, NOT a pass)` | 713 | Jun 184, Jul 256, Aug 263, Sep 10 |
| git `Revert "…"` commits | 26 | all May 23 (A6, A10, A15 emitter phases, each reverted 2 or 3 times) |
| revert-like subjects excluding WIP checkpoints (revert/annul/retir/rollback/restore/desarm) | 302 | May 19, Jun 103, Jul 63, Aug 113, Sep 4 |
| strict self-retraction subjects | 151 | May 18, Jun 67, Jul 28, Aug 36, Sep 2 |

The August retractions are mostly the worker retracting its own previous cycle inside secondary-motion, verbatim: `cycle 126 : JE RETIRE LA CIBLE QUE J'AI NOMMEE AU CYCLE 125`, `cycle 125 (suite) : JE RETIRE MA PROPRE PREUVE DE P1 — ELLE COMPARAIT DEUX BINAIRES`, `cycle 117 (bloc C): … JE RETIRE LA RETROGRADATION QUE J'EN AVAIS TIREE`, `cycle 116 (fin): JE RETIRE LE « PROCHAIN CHANTIER » QUE JE VENAIS D'ANNONCER — IL ACHETE 0,03 mm LA OU IL EN MANQUE 12,9`, `cycle 112b: JE RETIRE MA SATURATION D'IL Y A UNE HEURE`. The supervisor stream does the same: `je retire ma priorite de 18:25: le contre-controle que j ai exige l a refutee`, `je corrige ma directive du 23:00`, `ma directive de 03:10 s appuyait sur une serie tronquee: retiree`, `j ai invente deux validations, et toute ma methode reposait dessus`.

Regressions of validated work are now a phase type: `Gfont-regression` (owner: « t'as complètement niqué la font (Urbanist) »), `Gloadgate-crash-regression`, `Gtouch-longjump-regression`, `Gorb-hud-regression`, and the owner-ok token `Gfont-urbanist` renamed by hand to `Gfont-urbanist.CASSE-2026-09-02`.

One-off scripts at the top level of `.autoport/` (940 tracked, 2 untracked): 942 files, 145 832 lines, 8.0 MB.

| month created | scripts |
|---|---|
| 2026-05 | 2 |
| 2026-06 | 125 |
| 2026-07 | 327 |
| 2026-08 | 433 |
| 2026-09 (3 days) | 63 |

Weekly peak: 132 scripts in the week of Aug 24, 114 in the week of Aug 17. Largest families by prefix: `c1xx_*` cycle scripts 140, `gpbrf*` 52, `physics_*` 48, `probe_*` 47, `grass*` 45, `gda_*` 29, `ao_*` 24. Each phase leaves a new prefix (`ghso`, `ghso4`, `ghso6`, `npcf`, `npcf2`, `npcf3`, `fw3`, `gcs`, `gcs2`), and nothing is ever removed.

Growth of the steering documents (bytes / lines at the last commit of each month; commits touching the file):

| file | May | Jun | Jul | Aug | now (Sep 3) | commits |
|---|---|---|---|---|---|---|
| SUPERVISOR_JOURNAL.md | 92 942 / 2 012 | 266 422 / 5 305 | frozen | frozen | 266 422 / 5 305 (last edit 2026-06-18) | 257 (74 May, 183 Jun, 0 since) |
| DIRECTIVES.md (created Aug 11) | | | | 159 424 / 2 287 | 160 079 / 2 296 | 72 (71 Aug, 1 Sep) |
| PITFALLS.md (created Aug 12) | | | | 67 895 / 814 | frozen since Aug 23 | 55 |
| SPEC-COVERAGE.md (created Aug 20) | | | | 772 117 / 2 168 | frozen since Aug 28 | 149 |
| milestones.yaml | 17 548 / 394 | 109 156 / 993 | 158 266 / 2 362 | 187 692 / 2 803 | 197 095 / 2 956 | 662 |
| orchestrator.py | 51 317 / 1 289 | 67 847 / 1 573 | 78 302 / 1 746 | 98 668 / 2 114 | 101 892 / 2 163 | 80 |

DIRECTIVES.md within August: 98 KB on Aug 16, 147 KB on Aug 23, 159 KB on Aug 30. It is inlined verbatim into every worker prompt: `directives … inlined into the worker prompt (167285 chars)` on the current launches, versus 10 539 characters on the first August launches; 736 inlinings since Aug 2. Its 67 top-level sections are dated diary entries (`## 2026-08-21 20:50 — JE RETIRE MA PRIORITE DE 18:25`), not rules, so every worker re-reads three weeks of retracted arbitration about Keira's breast physics before starting a font or cutscene phase.

## 5. Backlog hygiene

milestones.yaml: 278 phases, 188 of them G*, no duplicate ids. Fields present: id, name, prompt, validator, max_turns, max_retries (all 278), device (120), owner_verify (120, 117 true), device_serial (47), no_code (2). There is no `blocked_by` / `depends_on` field at all, so "todo but blocked" is not representable in the backlog; blocking lives only in `state.json`.

| check | result |
|---|---|
| prompt file shared by several phases | 4 files, 9 phases: `phase-Gcutscene-skip-all.md` (3: skip-all, skip-polish, skip-polish-2), `phase-Gcutscene-npc-flicker.md` (2), `phase-Gsubtitle-style.md` (2), `phase-Gjak1-crate-collision.md` (2) |
| validator shared by several phases | 3: `phase-Gcutscene-npc-flicker.sh`, `phase-Gkeira-hd-detached-parts.sh`, `phase-Gcutscene-skip-all.sh` |
| max_retries >= 60 or max_turns >= 3000 | 79 phases (71 at max_turns 3000, 6 at max_retries 400: managed-assets-merge, memory-ceiling-and-crash, precompute-deterministic-bake, playability-input-and-loadgate, secondary-motion, fixed-tick-interpolation) |
| status per state.json | completed 221, blocked 15 (plus 2 blocked ids not in milestones: Gmenu-pixelmatch, Grefen-english-pristine-frames-audit), parked 20, todo 22 |
| validator_passed but not completed | 27 |
| parked and validator passed (waiting on the owner) | 19 |
| parked AND completed at the same time | Grecharged-hud-jak1 |
| completed phases whose LAST commit says `NOT done` / `AWAITING OWNER PLAY-TEST` | 41 |
| completed phases with at least one AWAITING OWNER commit | 75 |

The shared validator is a concrete false-green: `phase-Gcutscene-npc-flicker.sh` reads `.autoport/reports/Gcutscene-npc-flicker/report.txt` (the phase-1 report path). `Gcutscene-npc-flicker-2` attempt 1 ran 745 tool calls with 0 detected code writes on Sep 2 and passed `[Gcnf ok] 0 clignotement sur >=3 scenes` on Sep 2 03:28, while the owner's verdict of Sep 3 is « bah non c'est toujours pété ». The validator was then hardened by hand at 03:05 on Sep 3 (mayor scene, Redmi platform required).

How a phase becomes owner-validated. `owner-ok/README.txt`: the close-gate (GATE 3) refuses to complete an `owner_verify` phase without a token file `owner-ok/<phase-id>`; the orchestrator parks the phase after validator+gates pass, moves on, and on a later pass through the parked phase, if the token exists, appends it to `completed`. Consistency of that state today:

| check | result |
|---|---|
| owner-ok tokens | 96 (plus README) |
| empty tokens (no rationale) | 31 |
| tokens written by the supervisor, not the owner (`delegate-verified by supervisor`, `supervisor gate-close`, `gate-advance`, `DEPASSEE`, `PARKED … NOT a pass`) | 39 |
| tokens quoting the owner's words (« Cinematiques: C'est valide », « Bon les caisses sont réparées ») | 30 |
| tokens for phases NOT in completed | 15 (Gmemory-ceiling-and-crash, Gprecompute-deterministic-bake, Gfirstperson-hd-hide, Gkeira-visor-deliver, Gplayability-input-and-loadgate, Gcutscene-reframe, Gloading-screen, Gcine-vertical-frame, Gtext-tone, Gkeira-hd-detached-parts, Gandroid-window-size, Grecharged-hd-eye-scale, Gjak1-crate-collision-2, Gsubtitle-style-2, and the renamed Gfont-urbanist.CASSE) |
| completed owner_verify phase with NO token | 1 (Gtouch-longjump-regression) |
| token that explicitly says it is not a pass but the phase is completed | Grecharged-grass-overhang7 (`PARKED 2026-07-15 … NOT a pass`), Grecharged-buildsys-cidocs (`NOT the owner's final subjective sign-off`), Gfixed-tick-interpolation (`VALIDATION FAIBLE`) |

`OWNER-VERIFY-QUEUE.md` was last written on 2026-08-22 04:50 and is entirely about the Keira breast spec (« A tester : rien … une question sur ta spec : le sens de « Global » dans ta section 12 »). It does not mention any of the 19 phases currently parked and waiting for the owner; the live queue exists only as `notify(alert)` lines in the orchestrator log and as free-text values in `state.parked`. `acquis/` holds one guard, `font-urbanist.sh`, created Sep 2 after the font regression; the memory rule that every phase runs `acquis/*.sh` at close-gate therefore covers one acquis out of 96 validated ones.

Reports: 9.1 GB in 91 phase directories, 5 488 files. Heaviest: Gpbr-props-reach-draw 1 860 MB (80 files), Grecharged-directional-ambient 1 163 MB, Grecharged-secondary-motion 838 MB (1 094 files), Grecharged-pbr-realtime-fusion 732 MB (1 001 files), Gloadgate-crash-regression 677 MB, Ghd-skin-origin-stretch 618 MB.

## 6. What the supervisor has been doing

`SUPERVISOR_JOURNAL.md` is dead: 5 305 lines, last heading `## 2026-06-18 ~02:32 — 3rd fix falsified; writer is NOT sparticle; tree reverted`. Its last 300 lines cover Jun 12 to 18: the F1d/F1e/F1f phases (first tiered-architecture pass, the leaky F1d validator satisfied at boot by the title attract, the owner's live crash repros #5 to #9), the Gcine-camfov build that bricked the device, and three falsified fixes for the blendshape DMA stomp. That was the last period with a written supervisor narrative.

Since then the supervisor exists in three forms: `[autoport/supervisor]` commits (1 201, May 18 to Aug 1, none in August), the `[keira-physique]` stream (211 commits, Aug 10 to 28) writing DIRECTIVES.md, PITFALLS.md, SPEC-COVERAGE.md, and the orchestrator's automatic `preflight/SUPERVISOR`.

Last two weeks (Aug 20 to Sep 3): 54 `[keira-physique]` commits. 35 are the empty auto-checkpoint `checkpoint automatique du constructeur: l'arbre compile (551 cibles), etat coherent livrable`. The other 19, all between Aug 20 00:09 and Aug 23 16:18, are arbitration entries on the breast spec: `registre de couverture de la spec: 6 sections tenues sur 38`, one hour later `le registre tue trois de mes propres tenues: 6/38 -> 3/38 sans que la physique bouge`, `rien n est valide: un retour de l owner n est pas une validation`, `j arrete de solliciter des tests tant que la couverture ne le permet pas`, `je retire ma priorite de 18:25`, `arbitrage: un validateur vert n est pas la conformite`, `je corrige ma directive du 23:00: cabler une cle-REPONSE fabrique un miroir`. After Aug 28 there is no supervisor commit at all; the only DIRECTIVES.md edit since is by the `Gfont-regression` worker on Sep 2.

Who authors the backlog now: every prompt file created since Aug 26 was committed from inside a worker attempt of another phase (`[autoport/Gjak1-crate-collision] … -> prompts/phase-Ghd-skin-origin-stretch.md`, `[autoport/Ggrass-crash] … -> prompts/phase-Gcutscene-skip-all.md, phase-Ggrass-density-presets.md, phase-Gsubtitle-style.md`, `[autoport/Gfirstperson-hd-hide] … -> 5 prompts`). Workers also write their own validators (shared ones included) and their own owner-ok rationale text.

The automated preflight is not working: `preflight unavailable: not enough values to unpack (expected 3, got 2)` 278 times, `[PREFLIGHT-ERR] check_guards_still_installed: [Errno 21]` 23 times, and 171 `[PIPEFAIL-GREPQ]` lint warnings re-emitted on every launch for the same 12 validator scripts, never fixed.

Productive? Between Aug 10 and Aug 28 the supervisor and the worker together produced 810 commits, 160 KB of directives, 772 KB of coverage registry and 140 `c1xx_*` scripts on one phase whose spec coverage moved from 6/38 to 3/38 and back to "one section green", with the owner's verdict on Aug 13 recorded as « verdict dur, et il a raison ». Zero phases closed in those two weeks. Since Aug 28 the supervisor is absent and the orchestrator runs without a manager, which is when regressions of validated work (font, load gate, crates, NPC flicker) started to be reported by the owner.

## 7. Where the time goes, in one list

- Rate-limit restarts: 660 recorded, 468 since Aug 2; the two hot phases lost their earlier attempt logs entirely. 234 door refusals at 5-minute sleep each, 230 of them consecutive on one phase (19.7 h measured).
- Broken quota probe: 374 `AttributeError` and 1 105 HTTP 429 on the probe, 373 "proceeding optimistically" launches.
- Prompt weight: 160 KB of dated directives inlined into every one of the 736 launches since Aug 2.
- Investigation before code: median 47 % of tool calls; 56 to 59 % of August and September attempts contain no Edit/Write to code at all.
- Validators satisfied by self-written reports, one of them reading the previous phase's report; 41 "completed" phases whose last commit says `NOT done`; 39 owner-ok tokens written by the supervisor, 31 empty.
- Backlog written by the workers themselves since Aug 26; no supervisor since Aug 28; journal dead since Jun 18; OWNER-VERIFY-QUEUE.md stale since Aug 22 while 19 phases wait on the owner.
- 942 one-off scripts and 9.1 GB of reports that nothing prunes; 713 auto-versioned WIP failure commits in the history.
