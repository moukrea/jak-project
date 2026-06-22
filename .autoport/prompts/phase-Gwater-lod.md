# Phase Gwater-lod — near-camera water chunks render as plain blue squares — find the LOD/draw divergence (x86-first, no pixels)

## The defect (owner, 2026-06-21)
On the title flyover, when the camera flies close to the water, the **chunks closest to the camera
render as plain blue squares** — as if the detailed water surface isn't drawn and a flat-blue
fallback shows instead. Farther water looks fine.

## Re-baseline on the fresh consolidated HEAD FIRST
The device now persistently runs a fresh consistent HEAD set ([[consolidate-fresh-head-known-good]]).
Several "defects" (sun/rays/particles/menu) were stale-deployment artifacts already correct on HEAD.
**Deploy/confirm fresh HEAD and re-measure the water before assuming a code bug** — it may already
render. If it still shows blue squares on the fresh consolidated build, it's a real translation gap.

## Likely area (confirm, don't assume)
The ocean/water renderer is a known Android curated-subset risk ([[gwater-state]]): ocean mips2c
builders can be noop'd and/or the ocean renderer TU not compiled into the Android build — the
"renderer-family 3-part pattern" (mips2c kSet un-noop + CMakeLists TU + register bucket / GLES
primitive-restart gate). The near-camera "blue squares" are consistent with the **near (high-detail)
ocean LOD draw missing** while the far/flat tier still draws.

## Methodology — deterministic LOD/DRAW dump, x86-FIRST, NEVER pixels
Dump the metric that reflects the defect: for the water chunks **near the camera**, the **selected
LOD tier and whether the detailed-water draw is actually submitted** (draw-call / vertex count per
near-chunk), vs the flat-fallback. Compare on **original-x86 (.autoport/gold)**, **our-x86 (HEAD)**,
**device**.
1. our-x86 vs original-x86 FIRST (must be 1-to-1; if our-x86 diverges, a source hack did it → revert
   to pristine).
2. device vs original: if near-chunk detailed draws are MISSING on device (count 0 / wrong LOD) while
   present on x86 → the ocean renderer/LOD path is the gap. Fix in the translation layer
   (`game/graphics/**` ocean renderer + `game/mips2c/**` builders + CMakeLists TU + bucket/GLES gate),
   NOT in goal_src.
3. End state: device near-camera water draws the detailed surface matching the original (no flat-blue
   fallback); our-x86 == original-x86.

## Validator (`phase-Gwater-lod.sh`) PASS requires
1. `.autoport/reports/Gwater-lod/water.txt`: per-near-chunk LOD + detailed-water draw/vertex counts
   for original-x86, our-x86, device — our-x86 == original-x86 (1-to-1), a calibrated BEFORE where
   device near-chunks draw flat/0 detailed, and an AFTER where device near-chunks draw the detailed
   surface matching the original. With `RESULT: NEAR-CAMERA WATER RENDERS MATCHING ORIGINAL (device, 1-to-1 source)`.
2. our-x86 == original-x86 explicitly; any `goal_src/**` edit must be a documented pristine revert
   (else fix is in `game/graphics/**`/`game/mips2c/**`/CMakeLists/`android/**`).
3. Fix-summary `.autoport/reports/Gwater-lod-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh` (now restores the fresh
HEAD set). NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
