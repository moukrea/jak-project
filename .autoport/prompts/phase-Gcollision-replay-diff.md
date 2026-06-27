# Phase Gcollision-replay-diff — diagnose the REAL arm64 collision divergence from the owner's recorded glitch playthrough

## Why (owner directive 2026-06-27)
The prior Gcollision-systemic "fix" (arm64 FCVTZS→cvttss2si codegen, 38285/75000 unit-sweep → 0) was a
FALSE GREEN: it changed behavior but did NOT fix in-game collision — owner reports "DIFFERENT glitches,
but not fixed." The synthetic ≥3-scenario check missed the real defect. Owner's mandated method (use it):
**replay the OWNER's real recorded glitch playthrough on x86 vs arm64 with collision dumps, compare,
find what actually diverges.**

## The artifact
`.autoport/demos/collision-glitch.inputs` — the owner played ~8 min on the CURRENT arm64 build
deliberately triggering every collision glitch they could (clip-through walls, jumps under map, eject /
stuck-crouch near objects, invisible walls / must-jump on flat ground, blue-eco zone cliff-eject).
28229 logic ticks, 61% non-neutral, seed=181478213, deterministic-replayable via the Ginput-replay harness.

## Method (mandatory — owner's plan; NO synthetic scenarios, NO unit-sweep-only pass)
1. **Add a collision-state dump hook keyed by the harness LOGIC TICK** (not render frame), on BOTH x86 and
   arm64. Dump the collision state that matters for these glitches: Jak/target position+velocity, the
   collide-cache/mesh/edge query results (hit normals, penetration depth, the spatial-hash/bbox
   quantized coords, the resulting push-out/impulse), and the control/movement state. Same fields, same
   order, both backends. (Reuse/adapt the Gcollision-systemic dump if still in git history.)
2. **Replay the OWNER demo on x86** (`OG_PAD_REPLAY_REPLAY=.autoport/demos/collision-glitch.inputs` on
   `build-x86/game/gk`) → the x86 oracle collision trace (correct).
3. **Replay the SAME demo on the arm64 device** (`debug.opengoal.pad_replay=replay`, the demo pushed to
   the app files dir) → the arm64 collision trace (glitchy).
4. **Compare the two traces at matching LOGIC TICKS.** The FIRST tick whose collision value diverges is
   the glitch ONSET (after it the paths legitimately diverge because the bug moved Jak). Trace that first
   divergent value back to the arm64 op that produced it — that is the REAL root. (It may NOT be the
   FCVTZS path; re-examine. Could be a different VU0 op, a float compare, an FMA TU, a denorm/FTZ, a
   mips2c quantization, or the FCVTZS fix itself being wrong — let the data decide.)
5. **Regression-check** the FCVTZS fix + the earlier per-site fixes: if the FCVTZS change is wrong/harmful
   (owner saw "different glitches" appear with it), correct or revert it; keep whatever genuinely matches x86.
6. **Fix the real root** in the translation layer (mips2c / goalc arm64 codegen), goal_src 1-to-1.
7. **Verify by re-replay:** the owner demo replayed on the FIXED arm64 build produces a collision trace
   that MATCHES the x86 oracle (same fields, matching at the logic ticks that previously diverged — or
   matching far longer before any divergence). Document the first-divergence tick BEFORE vs AFTER.

## Validator (`phase-Gcollision-replay-diff.sh`) PASS requires
1. `.autoport/reports/Gcollision-replay-diff/report.txt` with `RESULT: ARM COLLISION MATCHES X86 ON OWNER DEMO`:
   uses `.autoport/demos/collision-glitch.inputs` replayed on BOTH x86 and arm64 with per-logic-tick
   collision dumps; names the FIRST divergent logic tick + the root op BEFORE; shows AFTER the fix the
   arm64 trace matches the x86 oracle (first-divergence tick pushed out massively / to none). The
   regression-check of FCVTZS + per-site fixes documented.
2. goal_src 1-to-1 (or documented pristine revert); real translation-layer change; fix-summary
   `.autoport/reports/Gcollision-replay-diff-fix-summary.md` ≥60 lines; temp instrumentation (the dump
   hook) removed; `.autoport/gold` pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.
3. NOTE: passing the validator is NOT done — the OWNER re-plays to confirm collision feels right
   (final ground truth). Do not declare fixed on the trace alone (the last attempt false-greened).

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`.
## Max: max_turns 1800, max_retries 5.
