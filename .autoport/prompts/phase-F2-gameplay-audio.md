# Phase F2 — Gameplay: audio output

## Status

**Authored 2026-05-22 by the supervisor**, replacing the May-21
placeholder. Same-behavior contract: audio triggers at identical
points in the game-state trace as the desktop build. SDL3's AAudio
backend handles the platform layer; the GOAL `ssound` RPC layer
already cross-compiles.

## Bucket

F — Stretch gameplay (REDESIGN.md §8).

## Goal (concrete, device-verifiable)

1. SDL3 audio device opens with the AAudio backend (default on
   recent Android NDKs) — logcat: `SDL_audio: opened device ... aaudio`.
2. The `ssound` IOP RPC subsystem drives audio commands the same
   way it does on desktop — same `PlayVag` / `LoadSingle` /
   `PauseStream` event sequence in the trace.
3. **Trigger parity**: during a recorded Geyser Rock playthrough,
   audio trigger events in logcat occur at the **same trace
   timestamps (frame-aligned)** as the desktop oracle reference,
   within a 2-frame tolerance.
4. Audio actually plays — recorded via `adb shell screenrecord
   --time-limit 30 --bit-rate ...` with audio capture, then either
   a manual listen-back (acknowledged in the validator) OR an FFT
   spectrum diff against a desktop reference recording.

## Hard rules — same-behavior contract

- Shim governance from E1: any audio-related shim is
  `PLATFORM_FEATURE` (AAudio init) or `PS2_HW_EMULATION` (SPU
  voice-allocation simulation).
- Codegen + classifier byte-identical to A5 close.
- x86 + arm64 CGOs byte-identical to A2 / A5 baselines.
- No new `abort()` / `__attribute__((weak))` / `*_stubs.cpp`.
- Desktop smoke still works.

## What's likely needed

- `android_input_audio::init()` already calls `SDL_INIT_AUDIO`; D4
  added a callback that fires regularly (visible in D4-boot.log as
  `SDL_audio: callback fired, 960 samples`). What's missing is
  routing the IOP `ssound` RPC commands into actual SDL audio
  device writes.
- The desktop equivalent is in
  `game/overlord/jak1/ssound.cpp` + `game/overlord/common/ssound.cpp`.
  These already cross-compile (part of `android_arm64_kernel`).
  The piece to wire is the SDL3 audio sink that consumes the
  decoded VAG / Wave streams.
- Look at how the desktop build's audio sink works
  (`game/system/audio/sdl_audio_sink.cpp` or similar) and mirror it.

## f2_run.sh

- Build + install + launch
- Drive a recorded session that triggers known audio events
  (title music, footstep SFX, jump SFX)
- Capture logcat into `.autoport/reports/F2-boot.log`
- Optionally: `screenrecord` with audio for manual review

## Reality check toolkit

- Logcat audio-trigger event extraction + frame-aligned diff
  against the desktop oracle reference
- SDL audio device probe (`SDL_GetAudioDeviceFormat`)
- Shim governance, codegen-lock, CGO baseline checks

## Cost expectation

Medium. SDL3 audio sink wiring + alignment. ~1-2 hours / $20-30.
