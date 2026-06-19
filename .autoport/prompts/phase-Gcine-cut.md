# Phase Gcine-cut — fix the cinematic camera CUTS, verified by deterministic camera STATE DUMPS, x86-FIRST

## The defect (owner, 2026-06-19 — precise)
In the new-game cinematic the camera does NOT change PLAN with a hard CUT where it should — **instead of cutting to the next camera target/plan, the camera MOVES/interpolates toward the next target.** So discrete shot changes come out as continuous pans/zooms (wrong framing + wrong pacing). The owner notes this **may also reproduce on our altered x86 build** (the cut logic is shared GOAL, not necessarily arm64-specific) — so it should be cheap to find on the host vs the original. See memory [[state-dumps-x86-first-not-screenshots]], [[cinematic-audit-findings]] (Gcine-audit camera-DATA tooling is the model — extend it).

## Methodology (owner directive — mandatory)
Verify with DETERMINISTIC camera-plan STATE DUMPS compared NUMERICALLY, x86-FIRST. Do NOT use screenshot diffs.
1. **Dump the camera-PLAN transition state, not pixels.** Locate the cutscene/scene-player camera-plan logic (the camera-plan list, the per-plan duration, the cut-vs-interpolate decision — `process-drawable`/`cam`/`scene`/`camera-teleport`/`tracking`-style fields). Instrument (behind an env flag) a per-frame dump of: the active camera-plan index, the plan's target, and the transition TYPE — was this frame a CUT (instantaneous jump to the new plan's pos/rot) or an INTERPOLATION (the pos/rot moved continuously from the previous plan). The Gcine-audit camera-pos/projection dump (`gcine_diff.py`) already captures per-frame camera DATA — extend it to also record "did the camera position JUMP (cut) or move smoothly (interp) at each plan boundary."
2. **x86-FIRST.** Run OUR x86 (`build-x86/game/gk`) AND the original (`/home/emeric/code/jak-original-v033`, READ-ONLY golden, read fields over the listener, keep it git-clean). Dump the camera-plan transition sequence on BOTH through the new-game cinematic. **Diff numerically:** at each plan boundary, does the original CUT (camera pos jumps) where our build INTERPOLATES (camera pos moves)? That divergence is the bug. If our-x86 already diverges from the original (interpolates where the original cuts), FIX IT ON THE HOST and re-diff until the cut/interp pattern matches the original.
3. **Then the device.** Once our-x86 cut/interp pattern == original, dump the same on the device; fix the residual arm64 delta (if any).
4. **Remove ALL dump instrumentation when done.** Golden reference stays byte-pristine.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Original repo + `.autoport/gold/` READ-ONLY/pristine. Don't regress Gcine-camfov (cutscene FOV), Gnewgame/Gcine-crash (no crash), menu, halo. FULL consistent rebuild + `deploy_verify.sh eae4df44` PASS for any boot-CGO change. After any failing run, `bash .autoport/restore_knowngood_device.sh`.

## Validator (`phase-Gcine-cut.sh`) PASS requires
1. `.autoport/reports/Gcine-cut/state-dump-x86.txt`: our-x86 vs original-x86 camera-plan transition sequence through the cinematic (per plan boundary: CUT vs INTERP, plan index, target), showing our-x86's cut/interp pattern == the original's, with `RESULT: X86 MATCHES ORIGINAL`.
2. `.autoport/reports/Gcine-cut/state-dump-device.txt`: device camera-plan transition sequence matching the original (cuts where the original cuts), with `RESULT: CAMERA CUTS MATCH ORIGINAL`.
3. `Gcine-cut-fix-summary.md` (≥60 lines): the per-boundary cut/interp data (x86 + device, before/after), the mechanism (which plan-transition field/branch made it interpolate instead of cut, and where — x86-level or arm64), and the fix.
4. Real code change under `goal_src/**` or `game/**`; fix-summary confirms dumps REMOVED + original golden git-clean; x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; cinematic still plays crash-free (frame ≥ 10500, foreground=jak1, 0 sig 4|6|11).

## Max settings
`max_turns: 1500`, `max_retries: 3`.
