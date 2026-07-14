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
