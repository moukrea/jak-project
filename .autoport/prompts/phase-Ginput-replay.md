# Phase Ginput-replay — faithful input record/replay harness (owner-records-once → infinite deterministic replay) + x86-vs-arm64 frame-by-frame state diff

## Why (owner directive, 2026-06-25)
The two remaining CRASH bugs (`Gportal-crash`, `Gcrash-mouche3`) are **navigation-gated**: they only
fire after Jak is driven to a specific in-level spot (break the fly-crate→collect the buzzer; charge
the blue-eco portal). The worker cannot drive that reliably, so attempts run long and die mid-attempt
before converging. Owner's fix: **boot the game, wait idle, let the OWNER perform the actions, and
RECORD every input from the first one until the crash → a demo that reproduces the crash infinitely,
which the worker can then replay autonomously to instrument/fix/verify.** Owner's hard requirement:
**"faut être SÛR que tu enregistres VRAIMENT TOUS les inputs"** — zero dropped inputs, or the replay
diverges and the crash won't reproduce.

Owner's second directive: **"tu devrais pouvoir tout comparer programmatiquement... tu as la référence
(x86) et le build Android et comparer les valeurs... Ça doit être identique!"** — replaying the SAME
demo on x86 and arm64 and diffing the per-frame state trace localizes ANY divergence (crash OR state
bug) to the exact first frame/value that differs. This harness is the foundation for that too.

## Mandate — build a deterministic record/replay harness on the HOST pad layer (1-to-1, goal_src untouched)
Tap the host-side pad buffer at the point AFTER touch+gamepad merge, i.e. **exactly the pad state the
game consumes each frame** (leads: `android/android_input_audio.cpp` injection path; the PC `newpad`/
`Pad::GetState` layer feeding `game/kernel/jak1/kmachine.cpp` cpad). Do NOT modify goal_src or the
game's pad-reading logic — record/replay the host buffer the game reads. (If OpenGOAL's original
attract-demo infrastructure is reused, that is original game code, not a modification — but host-side
tap is cleaner and keeps goal_src byte-identical; prefer it.)

### Record (faithfulness is everything)
- Capture the **FULL pad state every game frame** — all button bits + both analog sticks + both analog
  triggers + the game frame index — as **absolute state per frame, NOT events/deltas** (so no edge can
  be missed). One fixed-size record per frame.
- **Idle-until-first-input:** start the recording (frame 0) at the **first non-neutral pad state**
  (owner's "j'attends le premier input en idle"). Stamp frame 0 with a **start-state fingerprint**:
  rng seed, the kernel frame counter, current level/continue-point, and Jak's position — the
  precondition replay must restore.
- **Flush every frame** to the demo file so a crash loses NOTHING — the crash frame MUST be in the log.
- Demo file: `.autoport/demos/<name>.inputs` (pull from device after the owner run).

### Replay (deterministic)
- A replay mode (boot flag / env / demo-file presence) that, instead of live input, **forces the
  recorded pad state each frame from frame 0**, one recorded frame per game frame (frame-locked).
- **Restore the start-state fingerprint** (re-seed rng to the recorded seed, same continue-point) so
  the run is deterministic. Reuse OpenGOAL's deterministic-frame / demo machinery if present.
- Works on **both** `build-x86` desktop gk AND the Android arm64 device build.

### State-trace hook (powers the x86-vs-arm64 diff)
- During replay, optionally dump a compact **per-frame state vector** (Jak pos/vel/control-state,
  target/process state, the handful of globals relevant to the bug under test) to a trace file.
- Replaying one demo on x86 vs arm64 and diffing the two traces yields the **first divergent frame** —
  the programmatic root-cause localizer the owner asked for.

## Self-verification — PROVE all-input capture, autonomously (NO owner needed to build/verify)
1. **All-input fidelity:** programmatically inject a known scripted button+stick sequence (via the
   existing cpad_inject path) while recording; replay the recording; assert the **replayed per-frame
   pad state is BYTE-IDENTICAL to the recorded one across EVERY frame** (`PAD DIFF: 0/<N>` frames
   mismatched). This is the owner's "tous les inputs" guarantee.
2. **Determinism:** replay the same demo twice; assert the two per-frame **state traces are identical**.
3. **Faithful reproduction:** assert the record-run state trace == the replay-run state trace.
4. **Cross-backend:** replay the same scripted demo on x86 and arm64; produce both state traces and
   document the diff mechanism (first-divergence-frame report). (A trivial scripted demo may show 0
   divergence — that's fine; the point is the pipeline works end-to-end on both.)

## Validator (`phase-Ginput-replay.sh`) PASS requires
1. `.autoport/reports/Ginput-replay/replay.txt` with `RESULT: INPUT RECORD/REPLAY FAITHFUL + DETERMINISTIC`,
   containing: `PAD DIFF: 0/<N>` (all-input fidelity), the determinism proof (2 replays identical),
   the faithful-reproduction proof, and the cross-backend (x86+arm64) replay evidence + first-divergence
   diff mechanism. A self-test demo artifact `.autoport/demos/selftest.inputs` exists and is non-trivial.
2. Real `android/**` or `game/**` host-pad-layer change; **goal_src 1-to-1** (zero edits, or a documented
   pristine revert). Fix-summary `.autoport/reports/Ginput-replay-fix-summary.md` ≥60 lines describing the
   record format, the merge/tap point, the flush-per-frame guarantee, the determinism mechanism, and how
   the crash phases + x86-vs-arm64 diff consume it. Temp instrumentation removed; `.autoport/gold` clean.
3. x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS (device runs fresh HEAD with the harness).

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY. Keep device
awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1600`, `max_retries: 4`.
