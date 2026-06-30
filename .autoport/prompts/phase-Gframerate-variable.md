# Phase Gframerate-variable — free-fluctuating fps + constant game speed (replace the 30/60 lock)

## Why (owner 2026-06-30)
The Android "speed fix" (f4828f9f2) LOCKS the renderer to whole-vblank 30/60 and drives the GOAL
clock off a fake stable grid → fps capped at 30/60, flap-oscillates (~50 avg) at the boundary, and
game speed still varies. The owner is right: OpenGOAL is NOT tied to 60 — the PC port runs correct
speed at any fps (60/120/144). The real Android bug: `target-fps` is hardcoded to 60 (reset-gfx →
set-frame-rate! 60) while the device renders ~45-50fps, so `seconds-per-frame=1/60` is wrong → slow/
variable. The engine's NATIVE variable-fps math (`'custom` mode: seconds-per-frame=ratio/target-fps,
time-adjust-ratio) is already correct — we just never feed Android the right target-fps / real dt.

## Mandate (runtime/pc only; engine goal_src untouched → gold oracle clean)
1. **Android target-fps = real device refresh.** In the Android init/pc path (pc/pckernel-h.gc:329
   reset-gfx, or an Android-gated init in pc/) call `set-frame-rate!` with the real panel refresh via
   `pc-get-active-display-refresh-rate` instead of hardcoded 60 → engine enters `'custom`.
2. **Feed real per-frame dt + REMOVE the lock.** `a35_read_ee_timer` (android/gk_android_main.cpp):
   return the smoothed REAL wall-clock ticks (desktop `ns*3/10`, EMA-smoothed); drop the
   `g_gspeed_clock_active` branch. DELETE the vblank cadence-LOCK + clock-publish block in
   android/android_renderer.cpp (the 30/60 forcing + g_gspeed_clock_*); remove those globals from
   android/android_gfx.{cpp,h}.
   ⚠️ KEEP the flicker fix (8b330f996 "never present an undrawn buffer / hold last good frame") —
   remove ONLY the cadence lock, not the anti-flicker hold. Verify both: free fps AND zero black frames.
3. **Unpin the IOP/cutscene vblank pacer from 60** (android/android_gfx.cpp iop pacer + gfx.h target_fps
   default) → follow the same real refresh, else cutscene/stream timing drifts at non-60 fps.

## Verify (state-anchored — owner's mandate)
- On device, a known action / the in-game clock advances the SAME game-time per REAL second at
  several fps regimes (~30 Geyser, ~50 low-res, ~60 light) — CONSTANT real-time speed. Quantify.
- FPS COUNTER shows the REAL fluctuating fps (not capped 30/60). Game speed smooth (no slow↔fast).
- Cutscenes at correct speed (not slow-mo). ZERO black flicker (screenrecord frame-by-frame).
- x86 unaffected (link finish: logo). Full CONSISTENT build (CGOs+libgk), deploy_verify PASS.

## Report (`.autoport/reports/Gframerate-variable/report.txt`) with `RESULT: VARIABLE FPS + CONSTANT SPEED`
state-anchored game-units/real-sec at ≥3 fps regimes (must be ~equal); fps-counter free; flicker 0;
cutscene-speed ok; x86 link finish: logo; the lock removed + target-fps wired (file:line).

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 1800, max_retries 5. device: true, owner_verify: true.

## OWNER ADD (2026-06-30, during attempt 1) — CAMERA must also be smooth
Beyond movement speed: the owner reports the CAMERA feels choppy / "the view doesn't follow the
framerate, it jumps". This is likely the SAME root (camera advance uses time-adjust-ratio, wrong when
target-fps is hardcoded 60). The owner play-test (final gate) must confirm the CAMERA is smooth — not
just that Jak's movement speed is constant. If the camera still stutters after the fix, the phase is
NOT done (owner withholds the token); investigate camera interpolation / render-vs-camera cadence.
