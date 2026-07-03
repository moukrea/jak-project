# Phase Geco-spheres — eco spheres/clusters render badly on Android (green/blue/red, all builds ever)

## Why (owner 2026-07-03)
The GREEN eco spheres are not rendered properly, and the owner believes BLUE and RED eco have the same
issue (the two he has seen so far; probably yellow too). This has NEVER rendered correctly on the
Android builds (not a regression — a long-standing gap). Likely cause family: the Android renderer is a
CURATED SUBSET of the desktop renderer (see Gwater memory: renderer-family fixes need the 3-part
pattern — mips2c kSet un-noop + CMakeLists TUs + bucket/GLES registration), and the eco collectable
visual (glow/orb/generic effect) probably uses a renderer family or effect path that is degraded,
partially wired, or noop'd on Android.

## Mandate — oracle-diff, then wire the missing family (the established renderer method)
1. ORACLE: capture the SAME eco sphere (green, in an open scene e.g. Geyser/jungle) on the pristine x86
   golden and on the device — screencaps side by side. Characterize the delta precisely (missing glow?
   flat/untextured? wrong blend? missing inner sphere/particles?).
2. LOCALIZE: which renderer family/effect draws the eco collectable on desktop (generic? sprite glow?
   merc envmap? sparticle cluster?) — find it in the desktop renderer, then check its Android status:
   noop'd mips2c builder (kSet allowlist), missing TU in the Android CMakeLists, unregistered bucket, or
   GLES-incompatible feature (e.g. primitive restart, blend mode).
3. FIX with the 3-part renderer-family pattern where applicable (un-noop the mips2c builders + compile
   the TUs into the Android build + register the bucket/GLES path). Verify green, blue, red (and yellow
   if reachable) all render like the x86 oracle.
4. NO regressions: fps not measurably worse (this adds draws — note the cost honestly, esp. after/with
   the batching work), 0 flicker, prior fixes intact.

## Verify (device eae4df44)
Side-by-side screencaps device-vs-golden for green/blue/red eco spheres — visually matching. fps cost
noted. 0 flicker. Prior fixes intact. x86 unchanged (link finish: logo). Full CONSISTENT build,
deploy_verify PASS.

## Report (`.autoport/reports/Geco-spheres/report.txt`) with `RESULT: ECO SPHERES RENDER LIKE ORIGINAL`
the characterized delta, the named missing/degraded renderer family + its Android gap (kSet/TU/bucket),
the 3-part fix, per-color screencap proof vs golden, fps cost, x86 ok.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2200, max_retries 5. device: true, owner_verify: true.
