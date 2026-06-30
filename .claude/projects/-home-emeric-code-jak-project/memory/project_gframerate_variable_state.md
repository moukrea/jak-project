---
name: project_gframerate_variable_state
description: Gframerate-variable PASS — free fps + constant real-time speed; the Redmi renders UNCAPPED (SwapInterval doesn't FIFO-block).
metadata:
  type: project
---

Gframerate-variable PASS (2026-06-30, commit 03facb4a1): replaced the 30/60 vblank
LOCK with the engine's native variable-fps math. Device-verified state-anchored:
game-units/real-sec = 60.0/60.0/60.0 (windowed) across 59.7/31.6/22.7 fps regimes
(spread 0.08%), fps free-fluctuating, 0 flicker, 0 crash, deploy_verify PASS.

NON-OBVIOUS DEVICE FACTS (matter for any future fps/timing work on eae4df44):
- The Redmi's `SDL_GL_SetSwapInterval(1)` reports "ok" but does NOT FIFO-block
  (mailbox/queue swap). So the GL loop free-runs ABOVE the 60Hz panel (~73fps at
  light load). This is WHY the predecessor added the (bad) lock. dumpsys: active
  mode 60Hz, peak 90Hz (`mDefaultPeakRefreshRate=90`); `get_refresh_rate()` can
  return the 90 peak — cap against `Gfx::g_global_settings.target_fps` (60), NOT
  the refresh.
- The EE GOAL loop is NOT 1:1-gated by the GL present: `android_gfx::vsync()`'s
  `frame_idx > frame_idx_of_input_data` barrier returns EARLY once the GL is one
  chain ahead, so a fast EE SPINS and over-advances the game clock. To cap the
  game frame rate you MUST pace `vsync()` (the EE-thread syncv barrier), NOT the
  GL-thread present loop. EINTR-robust (SIGILL crash-repair handler fires signals).
- `__send-gfx-dma-chain` (a35_send_gfx_dma_chain) is the clean ONCE-per-frame
  EE-thread signal. The timer reads (timer-count/timer-reset) fire several times
  per frame at irregular >3ms gaps and DOUBLE-COUNT if used for frame detection.
- The engine integer time-ratio (`floor(timer-count/ticks-per-frame)+1`, snap
  <1.3) can't represent fractional fps -> needs explicit error-feedback in
  a35 (desired+=real_dt*target-fps; emit k=round(deficit); band-middle clock) to
  track real time. Per-frame k/dt is noisy (quantization); judge on WINDOWED
  (~1s) game-units, the perceived speed.
- `drawable.gc:1197` run-time read is `#if PC_PORT 0` (no a35 call on Android).
- `__read-ee-timer` is used ONLY by the frame clock (get-bus-clock/256), so a35
  may be frame-quantized safely (the full `get-bus-clock` is unused).

Fix is libgk-side; the reset-gfx target-fps=refresh goal_src change is Android-
gated + a NO-OP on the 60Hz Redmi (resolves to 60). See [[feedback_state_dumps_x86_first_not_screenshots]],
[[feedback_device_ground_truth_no_mixing]], [[project_grender_audit_state]].
