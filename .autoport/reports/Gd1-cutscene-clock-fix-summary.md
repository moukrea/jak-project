# Gd1-cutscene-clock — fix summary

**Phase:** Gd1-cutscene-clock (Grender-audit D1, fix #1 — HIGH, low-risk).
**Date:** 2026-06-20. **Device:** Redmi Note 9 Pro `eae4df44`, arm64, `org.opengoal.gk.jak1`.
**Goal:** make cinematics play at REAL-TIME on device by decoupling the cutscene/spool
clock from the render-vsync cadence. No x86/desktop behavior change.

## The defect (deterministically diagnosed)

The owner's "fluid but ~2× time" complaint in cinematics is the **cutscene running in
slow-motion**. The game-LOGIC clock is fine on arm64 (Grender-audit proved
`base-frame-counter` advances at real-time; the `time-ratio` catch-up works). The real
culprit is the **IOP/overlord VBlank clock** that paces every spooled cutscene.

Mechanism, by file:

1. The jak1 overlord `VBlank_Handler` (`game/overlord/jak1/srpc.cpp:446`) advances the
   fake-VAG stream clock once per call:
   `gFakeVAGClock += (s32)(1024 / Gfx::g_global_settings.target_fps)`
   (`srpc.cpp:469-471`). With `target_fps == 60` (`game/graphics/gfx.h:87`) the increment
   is `1024/60 ≈ 17` units per vblank. `info.strpos = GetVAGStreamPos()` (`srpc.cpp:482`,
   returns `gFakeVAGClock`) is then DMA'd to the EE in the `SoundIopInfo` block
   (`srpc.cpp:511-516`). The EE cutscene/scene-player logic polls `strpos` to pace every
   spooled animation. So the increment is **rate-normalized**: the clock advances at
   `(1024/target_fps) × vblank_rate` units/sec, which equals real-time `1024 units/sec`
   **only when `vblank_rate == 60`**.

2. The handler runs on the IOP kernel's vblank check
   (`game/system/IOP_Kernel.cpp:413-416`): `if (vblank_handler && vblank_recieved) {
   vblank_handler(); vblank_recieved=false; }`. `vblank_recieved` is a single
   `std::atomic_bool` set by `IOP_Kernel::signal_vblank()` (`IOP_Kernel.h:206`). So the
   handler runs at the rate the bool is **set** (the consume side runs ≥1 kHz when idle —
   `nextWakeup()` caps the iop-runner sleep at 1 ms — so the set rate is the binding rate).

3. **The bug was in where the bool is set.** On Android, `android/android_gfx.cpp::vsync()`
   fired the IOP vblank exactly **once per `vsync()` call**, and `vsync()` blocks on the
   render swap chain — so it was fired **once per RENDERED+swapped frame**. On the Adreno
   618 the render rate collapses on heavy content (new-game cutscene ≈ 15 fps, village
   flythrough ≈ 20 fps). So the vblank — and `gFakeVAGClock` — ticked at the render rate
   (~15 Hz), not 60 Hz. The cutscene clock advanced at `15 × (1024/60) ≈ 0.25×` real-time
   (≈4× slow-motion), while staying fluid because the camera/joints interpolate per
   game-frame. x86/desktop holds 60 fps, so its `Gfx::vsync()` fires the same callback at a
   flat 60 Hz and cinematics play at 1×.

This is also the prime suspect for the deferred `Gcine-cut` "device glides where x86 cuts":
a hard scene cut smeared over a 0.25×-rate timeline reads as a glide.

## The fix (Android-runtime only)

Decouple the IOP vblank SET rate from the render-swap cadence and drive it on a **wall-clock
60 Hz** schedule, exactly reproducing the desktop's 60 Hz display loop. The CONSUME side
(`IOP_Kernel::dispatch`) is shared, platform-identical code; only the SET rate diverged on
Android, so restoring a 60 Hz set rate makes Android match desktop.

Files changed (both under `android/**`; x86/`#else`/desktop untouched):

- `android/android_gfx.cpp`
  - Added a dedicated wall-clock 60 Hz pacer thread `iop_vblank_pacer_loop()` that calls the
    registered vsync callback (`signal_vblank()`) every 16667 µs, using
    `condition_variable::wait_until` for clean, jitter-resistant timing and a resync guard if
    it ever falls behind (no zero-sleep bursting — `signal_vblank` coalesces a backlog into
    one handler run anyway).
  - Rewrote `set_vsync_callback()` to start the pacer when a callback is registered and
    stop+join it when cleared (`nullptr`), with the start/stop done outside the pacer mutex
    to avoid a join/lock deadlock. The callback is copied under the mutex so the pacer can
    never race a concurrent re-assignment.
  - Removed the per-`vsync()` `fire_iop_vblank()` calls (both the pre-renderer-ready spin and
    the post-ready path). `vsync()` is now purely the game-chain frame-pacing barrier (it
    still blocks on the swap so each game chain maps to one rendered frame); it no longer
    fires the vblank at all. The pre-ready dispatcher HOLD is preserved (it still throttles
    the GOAL dispatcher until the renderer is up); the overlord/fake-VAG clock is kept
    real-time during that window by the pacer thread instead.
- `android/android_runtime_full.cpp`
  - The `register_vsync_callback` lambda now also calls `iop->signal_run_iop()` after
    `signal_vblank()`. The iop-runner otherwise sleeps up to ~1 ms in `wait_run_iop`
    (`IOP_Kernel::nextWakeup` caps the idle wait at 1 ms); waking it guarantees a 60 Hz
    vblank edge is consumed promptly instead of being coalesced away by the one-shot bool
    under scheduler jitter. The wake is a cheap lock+notify and cannot over-fire the handler
    (the bool is one-shot per dispatch).

Safety: `signal_vblank()` only stores an atomic bool and `signal_run_iop()` is a lock+notify,
so both are safe to call from the new thread. Firing the overlord vblank at 60 Hz is the
correct PS2 behavior (hardware vblank is 60 Hz NTSC regardless of EE frame rate) and is
audio-safe: every per-call quantity (`gFakeVAGClock`, `gFrameNum`, `gMusicFade`) is sized for
a 60 Hz vblank, so 60 Hz produces correct-speed audio; the previous ~15 Hz firing is what
desynced/slowed it.

## Verification (deterministic, NOT screenshots)

Metric source is the PRE-EXISTING `A42-STRCLK vblank=<gFrameNum> ...` log line
(`srpc.cpp:484-491`, prints every 300 VBlank_Handler runs) cross-checked against the
`A35-RENDER frame=... tris=...` renderer line (`android/android_gfx.cpp:523`). `gFrameNum` is
the pure vblank-handler counter, so vblank Hz = 300 / Δwall-clock between two `A42-STRCLK`
lines, and render Hz = Δframe / Δt. **No temporary instrumentation / debug dumps were added**
for this measurement — the existing always-on diagnostics are sufficient, so there is nothing
to remove from the source, and the original golden `jak-original-v033` was never touched. The
one-off helper script `.autoport/gd1_clock_measure.sh` lives only under `.autoport/` (no
engine/source change) and leaves no leftover instrumentation in any built TU.

BEFORE (pre-fix code, existing same-day device logs):
- Light beat (`Gspark-enterstate/clean-run.txt`, 06-19): `A42-STRCLK` vblank 1→901 over
  15.047 s = **59.81 Hz** while render held 60 fps → vblank Hz == render Hz (coupled).
- Cutscene (`Gcine-cut/device-killdiag-full.log`, 06-20): render frame 1200→1500 over
  19.96 s = **15.0 fps**; pre-fix the vblank fires once per vsync, so vblank ≈ **15 Hz** =
  0.25× real-time. This is the slow-motion the owner saw.

AFTER (fixed build, fresh device capture): see
`.autoport/reports/Gd1-cutscene-clock/clock-rate.txt`. Expectation/criterion: at the same
heavy beat the `A42-STRCLK` vblank rate is ~60 Hz **while** `A35-RENDER` render rate stays
~15–20 fps — i.e. the vblank/cutscene clock is now decoupled from render and runs at
real-time. The one-shot `Gd1-VBLANK ... paced at wall-clock 60 Hz` log line confirms the
pacer is live.

Regression checks: x86 desktop smoke still reaches `link finish: logo` (Android-only TU
change); `deploy_verify.sh eae4df44` PASS (device runs fresh HEAD libgk); device reaches
gameplay with no new sig 4/6/11.
