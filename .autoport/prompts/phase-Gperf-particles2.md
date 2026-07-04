# Phase Gperf-particles2 — REDO: the v5 perf changes CORRUPT the image in real play (REOPEN of a false-green)

## Why (owner 2026-07-05, v5 play-test — SEVERE regression)
The Gperf-particles v5 build is "horrible et totalement injouable". In REAL gameplay:
 - elements constantly DISAPPEAR and REAPPEAR (geometry flickers present/invisible at varying
   intensities) — classic symptom of the GOAL/GL frame OVERLAP racing the renderer against the
   DMA-chain build (renderer draws half-built / stale chains);
 - the TEXTURES/palettes cycle and flicker between day / night / sunrise constantly — the TOD
   MEMOIZE + TOD ping-pong (round 3/4) skip/stale the per-tree time-of-day palette upload, so
   trees show mismatched, flickering TOD states.
The worker's own validation MISSED this because it was structurally blind to it: pose-HELD (camera
static → no geometry pop visible) with the time-of-day PINNED to night (→ TOD-cycling bug hidden),
and a "0-flicker" recording that only checked for all-black frames, not geometry pop or palette
cycling. The supervisor shipped it (my failure). A STOPGAP has DEFAULTED ALL Gperf-particles
optimizations OFF (android_opengl_renderer.cpp perf_opt_in lambda + android_gfx.cpp overlap;
opt back in per-feature with the prop = '2'), restoring the v4 renderer. This phase re-does the
perf work CORRECTLY.

## HARD VALIDATION RULE — real moving gameplay, natural TOD, video-inspected (NO pinning)
Every perf feature you re-enable MUST be validated in REAL, MOVING gameplay with the time-of-day
advancing NATURALLY, captured on VIDEO (screenrecord), and inspected frame-by-frame for BOTH:
 (a) geometry POP — anything present in one frame and absent in an adjacent frame (tie/tfrag/shrub/
     merc/sprite), and
 (b) TOD/palette FLICKER — trees/terrain changing brightness/tint between adjacent frames when the
     real clock barely moved.
A pose-held static A/B and a TOD-PINNED capture are FORBIDDEN as the correctness proof (they hid
this bug). You MUST also record a KNOWN-BAD control (the feature re-enabled) and SHOW your inspection
detects the pop/flicker there — if your check can't see the bug on the bad build, the check is
worthless (this is the exact step that was skipped). Only then is a clean capture meaningful.

## Mandate — re-earn each optimization, one at a time, correctness FIRST
For EACH previously-added optimization (sprite-lean, state-cache, sprite-instance, tod-pingpong,
shrub-static-idx, tod-skip/memoize, 2d NEON, GOAL/GL overlap): re-enable it ALONE, prove it is
CORRECT under the real-gameplay video rule above (no pop, no flicker, byte-identical image to
v4-renderer across a moving night+day traversal), THEN measure its fps gain. Keep ONLY the ones
that are BOTH correct AND a real gain. The two known-broken ones need a real fix or must stay off:
 - GOAL/GL OVERLAP: if it races the DMA chain, it needs proper double-buffering / a fence so the
   renderer never reads a chain still being built — or it stays OFF. Correctness beats the fps.
 - TOD MEMOIZE/ping-pong: the skip key is wrong (palettes go stale / mismatched per tree). Fix the
   invalidation (per-tree, keyed on the ACTUAL palette inputs incl. TOD interpolation fraction) so
   the image is byte-identical to the always-upload path while the clock runs — or it stays OFF.
Ship only what's proven. Partial delivery (e.g. only the safe state-cache + sprite-lean) is fine.

## Verify (device eae4df44)
Moving-gameplay video (camera panning + Jak moving + natural day→night) with each kept feature ON,
frame-inspected: 0 geometry pop, 0 TOD flicker, image matches v4-renderer. Per-feature fps gain
numbers. eco bursts + orb HUD intact. 0 all-black flicker. x86 link finish: logo. Full CONSISTENT
build, deploy_verify PASS.

## Report (`.autoport/reports/Gperf-particles2/report.txt`) with `RESULT: PERF CLEAN <before>-><after> FPS`
per-feature correctness verdict (kept/dropped + WHY), the moving-video inspection (incl. the
known-bad control proving the check works), the numeric gain of kept features, eco/orb intact,
x86 ok. If a feature can't be made correct, RESULT may be a smaller gain — that's acceptable;
a CORRECT image is mandatory, fps is secondary.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2600, max_retries 6. device: true, owner_verify: true.
