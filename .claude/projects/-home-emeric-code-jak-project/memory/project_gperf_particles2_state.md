---
name: project_gperf_particles2_state
description: Gperf-particles2 outcome + the Redmi-can't-oracle-device-specific-GPU-bugs fact and the perf-validation confound recipe
metadata:
  type: project
---

Gperf-particles2 PASS (commit 5457889fd, 2026-07-05): REDO after the v5 double false-green.
KEPT 5 image-invariant perf features (sprite-lean, state-cache, sprite-instance,
shrub-static-idx, 2d-NEON) default-ON w/ live kill switch `=1`; DROPPED 3 that corrupt the
image, default-OFF, opt-in `'2'` = known-bad control (overlap, tod-pingpong, tod-skip).
Gain: v4 32->clean 37 fps / render_ms 28.4->25.8 (+9%) in the night Rock Village fire zone.
sprite-instance = the glbuild win (-21ms/60f); 2d-NEON = -11ms/60f GOAL-thread sparticle CPU
(the owner's CPU-bound bottleneck). 2d-NEON bit-exactness is now GUARDED by -ffp-contract=off
on sparticle.cpp in BOTH game/ and android/ CMakeLists.

KEY DURABLE FACTS (reusable for any future perf/rendering validation):
- The Redmi (eae4df44, Adreno 618) does NOT reproduce the owner's DEVICE-SPECIFIC GPU bugs:
  the v5 geometry pop (GOAL/GL overlap live-EE race) and TOD ping-pong flicker do NOT show
  on the Redmi (his newer GPU does). Same class as the Snapdragon-only swamp crash
  [[feedback_signal9_not_a_crash]]. So the Redmi is NOT a reliable oracle for device-specific
  GPU-timing/driver bugs — the owner is ground truth. Validate device-INDEPENDENT questions
  (image-invariance vs v4) on the Redmi; don't expect it to reproduce his corruption.
- CONFOUND #1 dynamic resolution: the GOAL dyn-rs auto-scaler (pckernel-common.gc,
  `dynamic-render-scale?`) changes internal res every ~0.5-1s -> global transient that the
  pop detector flags as "pop", different per boot. PIN it before ANY pixel comparison:
  `run-as org.opengoal.gk.jak1 sed -i s/#t/#f/ files/.config/OpenGOAL/jak1/settings/pc-settings.gc`
  on `(dynamic-render-scale? ...)`. RESTORE to #t after (it's the owner's setting).
- CONFOUND #2 fire-particle animation: fire flame animates with VARIABLE magnitude; a naive
  clean-vs-clean parity floor under-samples it and fakes DIFFERS. The floor MUST include a
  SAME-config v4-vs-v4 pair. (Night parity read cross 2.226 vs clean-floor 0.776 = "DIFFERS"
  but v4-vs-v4 = 1.97 == cross -> it was fire animation, not a feature.)
- The moving-video POP detector (tools/detect.py) fires ~84 FALSE positives on NORMAL LOD/
  culling pop during camera pans through foliage — an absolute pop count is meaningless; only
  clean-vs-v4 DELTA at matched conditions + eye-on-worst-frame is trustworthy. detect.py IS
  sensitive though: validated on synthetic injected defects (pop 0->320, flicker flip_rate
  0->1.0). Its flip_rate (not saw_energy) is the real flicker discriminator (clean ~0.1, real ~1.0).
- tod_fast_maybe (kboot/kmachine, env OG_TOD_FAST / prop debug.opengoal.tod.fast=1 -> 18000)
  ADVANCES the clock ~60x (day->night in ~24s) WITHOUT pinning = natural-TOD capture lever.
- x86 CGO restore after arm64-goalc contamination [[feedback_arm64_diag_overwrite_kernel_cgo]]:
  `(build-game)` alone does NOT repackage CGOs (mtime skip); need
  `build-x86/goalc/goalc --game jak1 --cmd '(make-group "iso" :force #t)'`.

DEFERRED: the GOAL/GL overlap (the big fps lever, ~+7.7fps in the prior report) is a real
race but SAFE-ABLE via a game-thread snapshot of the bounded live-EE set the renderer reads
(TextureUploadHandler upload.page, TextureAnimator upload->data, Merc2 bones + mod/frag). It
stays OFF here (unverifiable on the Redmi = would risk another false-green); it is the natural
next perf phase. See [[project_pcompare_gate]] and [[feedback_objective_frame_comparison]].
