# Phase F3 — Gameplay: 30 FPS sustained on device

## Status

**Authored 2026-05-22 by the supervisor**, replacing the May-21
placeholder. The Redmi Note 9 Pro can't sustain the PS2-native 60 Hz
under the full renderer load; F3 confirms a stable 30 FPS target
without dropping the same-behavior contract — game logic still
ticks at PS2-equivalent simulation rate, only the render rate
halves.

## Bucket

F — Stretch gameplay (REDESIGN.md §8).

## Goal (concrete, device-verifiable)

1. During a 60-second Geyser Rock gameplay session on device, the
   `android_renderer: sustained swap N` heartbeat increments to at
   least **1800 frames in 60 seconds** = 30 FPS average.
2. **Frame-time histogram**: 95th percentile frame time ≤ 40 ms
   (allows occasional spikes; the average is the 30 FPS target).
3. **Game logic still 60 Hz internal**: the desktop game runs at
   60 Hz simulation; Android must too, or physics/animation will
   feel wrong. Verified by counting GOAL `(set! *display* ...)`
   tick events: should fire 3600 times in 60 sec (60 Hz × 60 s) on
   both desktop and device. If F3 introduces a `tick_rate=30Hz`
   shortcut, that's a behavior divergence and the validator fails.
4. Trace-diff against desktop oracle still passes (no events
   skipped due to frame drops).

## Hard rules — same-behavior contract

- Render rate may be 30 FPS on device, but **simulation rate stays
  60 Hz** identical to desktop. Halving the simulation would be a
  behavior change and is forbidden.
- Shim governance from E1.
- Codegen + classifier byte-identical to A5 close; CGO baselines
  preserved.
- No new `abort()` / `__attribute__((weak))` / `*_stubs.cpp`.
- Desktop smoke still works.

## What's likely needed

- The renderer in `android_renderer.cpp` currently does
  `SDL_Delay(16)` per swap → tries for 60 FPS. On the Redmi Note 9
  Pro the GPU can't keep up; we need either:
  - Conditional swap-interval (skip 1 frame in 2 if frame budget
    blown — but the simulation still ticks 60 Hz).
  - Or `SDL_Delay(33)` for a hard 30 FPS render lock while the
    GOAL runtime sees full 60 Hz internally.
- Use `SDL_GetPerformanceCounter` to measure per-frame budget and
  decide on adaptive skip.
- The desktop builds the same way: `--vsync` plus an optional
  frame-skip flag. Mirror that.

## f3_run.sh

- Build + install + launch
- Drive Geyser Rock gameplay for 60 s
- Pull `.autoport/reports/F3-frame-times.csv` (per-frame
  microsecond delta from `SDL_GetPerformanceCounter`)
- Capture logcat into `.autoport/reports/F3-boot.log`

## Reality check toolkit

- Per-frame CSV → compute average + 95p
- GOAL tick-event count from logcat
- Shim governance, codegen-lock, CGO baseline checks

## Cost expectation

Lighter than F1/F2 (mostly perf tuning + measurement). ~1 hour / $10-20.
