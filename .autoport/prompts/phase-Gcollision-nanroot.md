# Phase Gcollision-nanroot — DIRECT collision fix: find WHY arm64 makes a NaN in collision (drop the replay approach)

## Why this phase exists (supervisor 2026-06-28)
The input-replay approach went in CIRCLES for days (determinism → live-capture → real-input-capture; owner
re-captures recorded neutral; v1 replay desyncs and doesn't reach the glitch spots). ABANDON input-replay.
Go direct at the bug. The FCVTZS fix (Gcollision-systemic) was a FALSE GREEN ("different glitches, not
fixed") — it matched the float→int CONVERSION but did not fix the in-game collision. Prior forensics
(Gledge INVESTIGATION.md) already established the smoking gun: **a NaN reaches collision** — vftoi0's
diverging inputs were ALL NaN (exp=0xFF), 74948× in a Geyser drive. So the conversion was a SYMPTOM; the
ROOT is the NaN itself: an arm64 op UPSTREAM produces a NaN where x86 produces a finite value, which then
cascades (e.g. `vector-reflect-flat!` needs a UNIT normal; a NaN/degenerate normal → reflection explodes →
"ça projette" / clip / under-map).

## Mandate — find + fix the NaN ROOT, x86-first, translation layer, goal_src 1-to-1
1. Reach collision autonomously (NO owner, NO input-replay): warp to Geyser (`debug.opengoal.f1.warp 1`)
   + drive Jak into terrain with a simple cpad_inject/scripted nudge — the bug is SYSTEMIC so ANY collision
   exhibits it. (Also reproduce on x86 with the same warp+nudge for the oracle.)
2. Instrument the collision / collision-reaction math to catch the **FIRST NaN (or first x86-vs-arm64
   divergence)** and its ORIGIN: walk back from vftoi0 / `vector-reflect-flat!` / the spatial-hash to the
   op that first produces NaN on arm64 while x86 is finite. Prime suspects: a vector **normalize / divide /
   rsqrt** of a degenerate (near-zero) vector (0/0=NaN on arm64 vs finite/handled on x86), a VU0 op, or an
   uninit lane. Dump the inputs+output of that op on both backends at the same logical point.
3. RE-EXAMINE the FCVTZS fix: is it correct, incomplete, or HARMFUL (it changed glitches without fixing)?
   Keep it only if it genuinely matches x86; otherwise revert/narrow it. The real fix is the NaN source.
4. Fix the root op (mips2c / goalc arm64) so arm64 == x86 (no spurious NaN; finite collision values).
   goal_src 1-to-1.

## Validator (`phase-Gcollision-nanroot.sh`) PASS requires
1. `.autoport/reports/Gcollision-nanroot/report.txt` with `RESULT: ARM COLLISION NAN ROOT FIXED`:
   the FIRST NaN/divergence in the collision path NAMED with its origin op (input+output x86 vs arm64,
   showing x86 finite / arm64 NaN BEFORE); AFTER the fix, that op is finite on arm64 == x86 and the
   collision math no longer feeds NaN (sweep/drive: arm64 == x86, 0 NaN). The FCVTZS re-examination
   documented (kept/narrowed/reverted with reason).
2. goal_src 1-to-1 (or documented pristine revert); real translation-layer change; fix-summary
   `.autoport/reports/Gcollision-nanroot-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.
3. NOT done on the validator alone — the OWNER play-tests the fixed build (their eye = the gate; the last
   collision "fix" false-greened). Supervisor coordinates the owner play-test after the validator passes.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake.
## Max: max_turns 1800, max_retries 5.
