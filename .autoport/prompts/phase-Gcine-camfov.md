# Phase Gcine-camfov — fix D1: the new-game cinematic cutscene camera projects at 4:3 (1.333) instead of the panel's 2.222 (wrong FOV/aspect → pulled-back framing). Single arm64 defect. Objective gate via the Gcine-audit camera-diff tooling. NO grind.

## The bug (objectively measured by Gcine-audit, 2026-06-17)
The Gcine-audit phase (`.autoport/reports/Gcine-audit/divergences.md`, commit c7f501029) diffed the device cinematic vs the x86 original and found **D1 (HIGH)**: at matched-pose held beats the device camera is at the **identical world position** as the oracle (`pose_dist=0.0`) but the **projection matrix rows are scaled by exactly 5/3** — horizontal `c0.x ×0.80`, vertical `c1.y ×1.333`, z-depth + position untouched. That is the **2.222 (widescreen) ↔ 1.333 (4:3) aspect ratio**. So the cutscene `math-camera` computes its FOV/aspect at 4:3 on arm64 instead of the panel's 2.222, turning the intended tight close-ups into pulled-back wide shots (oracle M2 = tight pink-halo villain; device = wide Lurker battlefield). Plays correct on x86 ⇒ arm64-specific.

Evidence: `arm64-cam.log` (frames f5506, f8801) vs `x86-cam-shots.log` (f4140, f6900); `beat-diffs/beat-compare.txt`; stills under `device-shots/` vs `x86-shots/`. This is the #1 issue and **confounds** the apparent water/green-glow badness (D3/C4) — fixing it is a prerequisite to re-measuring those.

## Fix direction (from the audit)
The GLOBAL `*video-parms*` aspect float is CORRECT (2.222) — the menu analysis already established that. So the cutscene camera is NOT reading that correct float: it either reads a stale/default aspect (the known Android `aspect4x3` boot default — PC window-size override stubbed, see [[project_aspect_ratio_root_cause]]) or applies the aspect to the wrong projection axis. Localize where the cutscene / `math-camera` derives its horizontal-vs-vertical FOV/projection on arm64 (math-camera.gc / cam projection / the cutscene camera setup) and make it use the correct 2.222 aspect. The 5/3 signature is your fingerprint. Check the arm64 class (field-offset reading the wrong aspect field? float path? a 4:3 default the cutscene path uses that x86 overrides but arm64 doesn't?). Oracle-diff vs x86 to name it.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. adb `/home/emeric/Android/platform-tools/adb`. No `goalc/emitter/IGenX86_64.*`. If the fix is in boot-CGO GOAL, a standalone CGO push SIGILLs the device ([[feedback_game_cgo_rebuild_unsafe]]) — do a FULL consistent rebuild, or prefer a libgk.so/mips2c-boundary fix. Regen+sync affected CGO/DGOs ([[feedback_stale_asset_dgos]]). Oracle repo + `.autoport/gold/` READ-ONLY. NO screenshot/video grind. Don't touch the parked menu, D2 cadence, or D3 lighting (separate phases). Optional: quiet the mis-gated `GINTRO-CHAINWALK` logcat flood (android_gfx.cpp, ANRs ~frame 15200) so long captures are clean — logging-only, fine.

## Verify — reuse the Gcine-audit tooling (objective, no eyeballing)
1. CLEAN rebuild + deploy + `.autoport/lib/deploy_verify.sh eae4df44` PASS.
2. Re-capture the device cutscene camera with the SAME instrumentation the audit used: `.autoport/gcine_audit_device.sh` (NEW GAME via cpad_inject, `OG_GCINE_CAM`/`debug.opengoal.gcine.cam`), and diff the matched beats vs the oracle `x86-cam-shots.log` using `.autoport/lib/gcine_diff.py` / `gcine_beat_match.py`.
3. Write `.autoport/reports/Gd1/projection-match.txt`: for beats M1 (misty-rel ~900) and M2 (~4200), the device projection rows (`c0.x`, `c1.y`, `c2.x`) BEFORE (the audit's 0.80/1.333 scaling) and AFTER your fix — AFTER must MATCH the oracle within ~5% (scaling ≈ 1.0), with a `RESULT: D1 RESOLVED` verdict. pose_dist must stay 0.0 (don't move the camera, only fix its projection).
4. Regression: the cinematic still plays through crash-free — a fresh long routed-logcat with 0 sig 11/6/4, highest frame ≥ 10500, foreground=org.opengoal.gk.jak1 at end (don't regress Gcine-crash3).

## Validator (`phase-Gcine-camfov.sh`)
PASS requires: `.autoport/reports/Gd1/projection-match.txt` with before/after matched-beat projection numbers + `RESULT: D1 RESOLVED` + a re-captured device camera log artifact present; a `Gcine-camfov-fix-summary.md` (≥60 lines) naming the arm64 cutscene FOV/aspect mechanism + the 5/3 oracle-diff + the fix; a real code change under goal_src/** or game/**; x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; a fresh long routed-logcat with 0 sig 11/6/4, frame ≥ 10500, foreground=org.opengoal.gk.jak1. Owner eye-confirms the cinematic framing now fills the screen.

## Max settings
`max_turns: 1500`, `max_retries: 3`.

## Strategic note
The fix is data-defined: the projection must stop scaling by 5/3. Use the audit's matched-beat camera numbers as the exact before/after target (c0.x 0.23225→0.29031, c1.y −0.32267→−0.24200 at M1). The whole verify loop reuses the audit tooling — no new gate to invent.
