# Phase 23 — Touch input → GOAL pad mapping + audio output

## Goal

The game runs and renders, but it has no way to receive controller input
(the d-pad/ABXY overlay is silent) and no audio comes out. Both are
mostly plumbing on top of phases 18+22 — SDL3 already abstracts the
backend, we just need to (a) bridge our TouchControlsView events into
SDL controller events that the GOAL kernel reads, and (b) ensure
SDL_audio (or a thin layer) actually opens the device.

After this phase, tapping d-pad-right in the overlay moves the in-game
character (or at least logs the pad event reaching the kernel), and
audio is heard from the speaker (or at minimum: SDL reports a working
audio device).

## Concrete deliverables

1. **TouchControlsView → SDL gamepad event bridge.**
   - The existing `TouchControlsView` (Java) draws on-screen d-pad/ABXY
     hitboxes. Wire each hitbox press/release to a native call:
     `NativeGk.onPadButton(int button, boolean pressed)`.
   - Mapping (use SDL3's standard enum):
     - d-pad up/down/left/right → `SDL_GAMEPAD_BUTTON_DPAD_*`
     - A/B/X/Y → `SDL_GAMEPAD_BUTTON_SOUTH/EAST/WEST/NORTH`
     (jak1 uses Sony layout: ✕→south, ◯→east, □→west, △→north)
   - Native impl in `android/gk_android_main.cpp`: maintain a
     `SDL_VirtualJoystick` (one created at SDL_Init time, kept alive)
     and call `SDL_SetJoystickVirtualAxis`/`SDL_SetJoystickVirtualButton`
     for each event.
   - Log every pad event: `kernel: pad: dpad_right pressed` /
     `kernel: pad: dpad_right released`. Each event must be observable
     in logcat with the button name in lowercase.

2. **Audio open + first sample submission.**
   - SDL3 has Android audio backends (OpenSL ES and AAudio). Prefer
     AAudio when the device supports it (API 26+ — your Redmi has it).
   - In `gk_sdl_main`, after `SDL_Init`, request audio init:
     `SDL_InitSubSystem(SDL_INIT_AUDIO)` and log
     `SDL_audio: opened device='<name>' freq=<hz> channels=<n>` using
     the actual device info from `SDL_GetCurrentAudioDriver`.
   - The runtime's audio code (in `game/sound/` or
     `game/system/sound_player`) is wired to SDL — verify it actually
     submits samples by adding (or finding) a log at the SDL audio
     callback entry: `SDL_audio: callback fired, NN samples`.
     This log must appear within 30s of `state=title`.

3. **Bridge audio to OpenAL Soft if/when the runtime requires it.**
   - If the existing runtime uses OpenAL Soft directly (check
     `game/sound/`), cross-build OpenAL Soft for arm64 with
     `-DALSOFT_BACKEND_OPENSL=ON` and link it into libgk.so.
   - Otherwise, SDL3's own audio subsystem is sufficient.

4. **Optional but recommended**:
   - Keep the screen on while the activity is foregrounded:
     `getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)`.
   - Disable the haptic feedback on touch (already off by default on
     a SurfaceView, but explicit is safer).

## Don't

- Do **not** invent your own SDL gamepad enum. Use SDL3's
  `SDL_GAMEPAD_BUTTON_*` — the GOAL kernel was already wired to
  receive these on desktop.
- Do **not** poll input from the runtime thread. SDL events are
  pushed; the kernel pulls them via the existing event-pump call
  on its main loop.
- Do **not** disable hardware key events from the system (volume
  rocker, etc.). The game should ignore them at the runtime layer.

## Pitfalls

- AAudio prefers low-latency stream sizes. SDL3 picks a reasonable
  default but you may need to set `SDL_AUDIO_BUFFER_SIZE` env var
  if the engine submits in larger chunks.
- Toybox doesn't ship `aplay`; for an audio sanity ping use SDL's
  own `SDL_PlayAudio` test pattern, NOT a shell `aplay` from adb.
- On retail MIUI, "system sounds" volume and "media" volume are
  separate sliders. If audio plays but is inaudible, check the
  media slider in the notification shade. (Out of scope for the
  validator, but worth a logged warning if the stream volume is 0.)

## Validator

```
.autoport/validators/phase-23-input-audio.sh
```

The validator drives the runtime via `adb shell input tap <x> <y>`
on the dpad-right hitbox coordinates, then asserts a
`kernel: pad: dpad_right` event appears in logcat within 5 seconds.
Repeats for A and Y buttons. Then asserts the audio callback fires
at least 10 times in 10 seconds.

## Success

Tapping the d-pad-right overlay moves the in-game cursor / character
(visible on screen) and logcat shows `kernel: pad: dpad_right pressed`.
Audio is audible from the device speaker on the title screen.
