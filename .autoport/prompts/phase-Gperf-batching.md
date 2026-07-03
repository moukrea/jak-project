# Phase Gperf-batching — cut GL draw-call submission cost so the device can reach 60fps

## Why (owner-agreed next big effort, 2026-07-03)
The device is DRAW-CALL-SUBMISSION BOUND, not fill-rate bound (proven by the render-scale diagnostic,
commit 57bb5c51d): Geyser Rock ≈ 571 draws ≈ 20ms of GL-thread submission (buckets_ms) vs 0.07ms for
the upscale blit; fps stayed pinned at 30 from 640x480 down to 160x120. 60fps needs the frame inside
16.6ms — the lever is REDUCING/CHEAPENING draw submission, not resolution. The Android renderer takes
the no-multidraw path (one glDrawElements per draw, no_multidraw=true) with per-draw state churn.
A real 60fps also amplifies everything else (dynamic render scale gets headroom, camera k=1).

## Mandate (renderer/GLES only; engine goal_src + gold + IGenX86_64 untouched)
1. PROFILE FIRST (don't guess): break buckets_ms down — how much is glDrawElements count itself vs
   per-draw state changes (program/texture/uniform binds) vs buffer uploads? Which renderer families
   dominate (tfrag/tie/merc/sprite/shrub)? Get a per-family draws + ms table on Geyser Rock.
2. BATCH: attack the dominant cost with the appropriate GLES3 techniques, e.g.:
   - restore/emulate multidraw: merge per-fragment draws that share program+texture+state into single
     glDrawElements calls (index-buffer concatenation — the desktop multidraw path does exactly this);
   - reduce redundant state changes (sort/bucket draws by program+texture, cache GL state, skip
     redundant binds);
   - uniform buffers / instancing where the pattern fits (GLES3 has UBOs + instancing).
   Start with the family that buys the most ms; iterate family by family.
3. MEASURE after each family: fps + buckets_ms on Geyser Rock AND a heavy scene (village1). Target:
   a sustained fps clearly above 30 (ideally 55-60 at 640x480; report honestly what's reached).
   NO visual regressions: screencap-compare each family before/after (identical rendering), 0 flicker
   (screenrecord), all prior fixes intact (collision/jungle/blueeco/speed/camera/dynamic-scale).
4. This is a BIG effort — deliver INCREMENTALLY: even 30→45fps is a win worth landing. If a family
   can't batch without visual damage, skip it honestly and report why.

## Verify
Device eae4df44: before/after fps + buckets_ms table (per family batched); sustained-run stability
(no crash, 0 flicker, visuals identical via screencaps); dynamic render scale still converges;
x86 desktop build unaffected (its multidraw path untouched or still works; link finish: logo).
Full CONSISTENT build, deploy_verify PASS.

## Report (`.autoport/reports/Gperf-batching/report.txt`) with `RESULT: DRAW BATCHING FPS <before>-><after>`
the profile table (per-family draws/ms), what was batched + how, the honest fps gained, visual-parity
proof, prior fixes intact, x86 ok.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.
