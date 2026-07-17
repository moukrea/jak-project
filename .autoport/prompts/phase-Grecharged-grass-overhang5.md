## WORK ECONOMY: MANAGER verifies via the OWNER'S REAL INSTALL FLOW, not adb-push or offline metrics.

# Phase Grecharged-grass-overhang5 — ROUND 5. overhang4 "objective PASS" was a FALSE PASS on the owner's device.

## Owner play-test on the SHIPPED jak-builds build (2026-07-14, verbatim)
"j'ai désactivé le pre-computed grass et c'est toujours autant claqué !" — overhang is STILL broken,
precompute ON or OFF, exactly as his prior rounds (clip-through, diagonal bands, brutal transition).

## Why round 4 falsely "passed"
The offline/Redmi banding detector + geometric counters said bands->0, clip->0. The OWNER's device shows
NO improvement. So the metric measured something that does not correspond to the rendered result on a
real install — OR the fix never manifests through the real asset pipeline (slim APK + external archive),
only through the worker's adb-pushed test bake. Distrust every offline/Redmi number.

## Mandate
FIRST reproduce the owner's flow (slim APK + external jak1_assets.zip extracted to the external root, NO
adb asset push) and CAPTURE the overhang zone — confirm the defect is present exactly as the owner sees
it. THEN find why overhang4's changes don't manifest through that pipeline (grassbake read path? enhanced
overlay path? toggle/settings seeding? shader actually compiled into the shipped libgk?). Fix, and PROVE
it via the same real-install flow with before/after captures. Edge stack LOCKED, OFF==stock.
Max: max_turns 3000, max_retries 6.

## SUPERVISOR HANDOFF (2026-07-14 11:50 — attempt 3 interrupted for the fable profile switch, NOT a failure)
Attempt 3 state, PRESERVED in the supervisor WIP snapshot commit: a fix landed in GrassBakeCore.cpp/.h +
grass.vert; the external jak1_assets.zip was rebuilt and its grassbake sha VERIFIED matching the fix; the
real-flow proof (slim APK install + boot + before/after captures) was in flight when interrupted.
ATTEMPT 4: resume from that commit — do NOT re-diagnose from scratch. Also: attempts 1-2 burned most of
their budget on warp/foreground logistics (warp_ok=0 loops with the game NOT foregrounded — see
diag/goverhang5_diag.txt); reuse the working capture harness from attempt 3's before/ + after/ runs and
verify mCurrentFocus before every capture. Finish the real-flow proof, write the honest report, validator.
