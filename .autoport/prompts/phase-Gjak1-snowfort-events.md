## WORK ECONOMY (manager/worker delegation)
MANAGER: plan, decide, VERIFY subagent claims yourself. Delegate to autoport-researcher (state/event
code scans, x86-oracle diffs), autoport-implementer (edits to spec), autoport-tester (device runs,
navs, captures). Parallelize.

# Phase Gjak1-snowfort-events — Snowy Mountain fort: frozen enemies + untriggered cutscenes (jak1)

## Owner bug report (2026-07-07, device play-test — HIS eye is the gate)
In Snowy Mountain ("montagne enneigée"), you can open the FORTIFIED CASTLE gate; entering the fort,
the GROUND ENEMIES ARE IMMOBILE — as if waiting for an event (cutscene) that never fired. Broader
impression: SOME CUTSCENES DON'T TRIGGER correctly elsewhere too. Original PS2/x86 behavior: entering
triggers the encounter normally (enemies active).

## Diagnosis leads (use the accumulated jak1 arm64 knowledge FIRST)
1. **x86-first oracle** (mandatory method): drive the same beat on our-x86 vs original-x86 — both
   must behave identically (our-x86 == original). If our-x86 is fine and only arm64 freezes, it's a
   translation-layer bug; localize with state dumps (actor states, task/event flags, spool status),
   NOT screenshots.
2. Known suspicious classes for "waiting on an event that never fired":
   * enter-state / SUSPEND-vs-RETURN handling — G1/G2 history: compile-time pop-RA could NOT
     distinguish RETURN from SUSPEND states; the kernel-side cinematic fix was deferred. A stuck
     `process` waiting on a state transition freezes actors exactly like this.
   * spool/cutscene streaming (spool-joint blockers from F1d; loader af-spike from Gcine-cut).
   * event dispatch (send-event/process-event paths through mips2c or FFI trampolines).
   * bug class #14 stale-icache is in jak1 too (klink.cpp:623, phase Gjak1-icache-flush) — if that
     phase has landed, retest this bug AFTER it; if not landed, consider whether stale TOP_LEVEL
     execution could corrupt an actor's initial state (less likely for a clean deterministic freeze,
     but cheap to rule out).
3. Repro: device eae4df44, warp/nav to Snowy Mountain fort (open gate, enter), observe enemy AI.
   Also collect the owner's "some cutscenes don't trigger" — test 2-3 known cutscene triggers
   (village sage huts, level-entry cinematics) on device vs x86 oracle.

## Mandate
Reproduce -> localize (name the stuck state/process + why arm64 diverges) -> fix in the TRANSLATION
LAYER ONLY (arm64 codegen / mips2c / kernel glue / pc layer) — engine goal_src UNTOUCHED, our-x86 ==
original-x86. Fix must make fort enemies behave EXACTLY like the x86 oracle, and any cutscene-trigger
divergence found must be fixed or precisely documented for its own phase.

## Verify (device eae4df44)
Fort entry: enemies active/aggro like the x86 oracle (video/screencaps, mCurrentFocus=jak1, crash-free
window). Cutscene triggers tested fire correctly. x86 link finish: logo; full consistent build;
deploy_verify PASS. No regression on the surrounding gameplay (snowy level smoke).

## Report (`.autoport/reports/Gjak1-snowfort-events/report.txt`) `RESULT: SNOWFORT EVENTS <verdict>`
the named root cause (stuck state/event + arm64 divergence mechanism + bug class), the fix (file:line),
device before/after evidence, cutscene-trigger audit results, x86 oracle parity.

## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; .autoport/gold READ-ONLY; full
consistent builds; state dumps over screenshots for divergence work.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.
