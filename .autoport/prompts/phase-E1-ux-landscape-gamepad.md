# Phase E1 — UX: landscape rendering + Bluetooth gamepad routing

## Status

**Authored 2026-05-21 by the supervisor**, replacing the May-21
placeholder. E1 enforces the lock-in goal:

> ARM+Android APK reaches title screen on the user's Redmi Note 9
> Pro **rendering the same graphics and executing the same logic as
> the working x86_64 port**.

E1's specific slice of that goal: render in **landscape**, route a
**real Bluetooth gamepad** the way the desktop x86_64 build does. No
mocks, no fake input events, no log-string-only checks. The validator
runs on-device and compares the runtime trace against the desktop
oracle.

## Bucket

E — UX corrections (REDESIGN.md §8).

## Goal (concrete, device-verifiable)

1. The APK launches in **landscape** orientation. Verified via
   `adb shell dumpsys window | grep mCurrentRotation` reporting
   90° or 270°, and via SDL window size on-device having
   `width > height`.
2. SDL3's gamepad subsystem comes up: logcat contains
   `SDL_GAMEPAD: opened` or `SDL_Init: gamepad subsystem OK` and
   when a real Bluetooth pad is connected the `SDL_EVENT_GAMEPAD_ADDED`
   event fires.
3. Pressing a face button on the connected pad produces a
   `Java_org_opengoal_gk_NativeGk_onPadButton` JNI callback (logged
   in the existing handler in `android/gk_android_main.cpp`) AND
   the corresponding GOAL kernel pad-state byte changes — observable
   either via the existing kernel `cpad_info` instrumentation or by
   a small `pad-state poll` log line we add to `kmachine`/CPad layer.
4. Trace-diff against the desktop x86_64 oracle
   (`.autoport/oracle/jak1-desktop-trace.txt`) up to the title-screen
   milestone — the on-device event sequence is a subsequence of the
   oracle within tolerance.

## Hard rules — same-behavior contract

E1 introduces the **shim governance** rule that applies to every
later phase too. Any function added or modified in
`android/android_runtime_compat.cpp`, `android/android_runtime_full.cpp`,
or any `android/*_stubs.cpp` MUST carry a header comment of the form:

```
// SHIM_KIND: BIONIC_ADAPTER     — bridge between glibc and Bionic APIs
// SHIM_KIND: PS2_HW_EMULATION   — substitutes PS2-specific hardware
// SHIM_KIND: PLATFORM_FEATURE   — Android-platform-only wiring (JNI, SurfaceView)
// SHIM_KIND: OPTIONAL_OFF       — desktop feature genuinely unavailable on phone (Discord, ImGui)
// Why: <one-line specific reason; reference the desktop equivalent>
```

Any function without one of those four kinds is a **DODGE shim**
that routes around real bytecode and is **forbidden** at E1 and
beyond. The validator scans for untagged shims and fails.

Other invariants:

- `goalc/` codegen + `.autoport/lib/classify_ir_arm64.py` remain
  byte-identical to A5 close.
- x86 CGOs remain byte-identical to A2 baseline.
- arm64 CGOs remain byte-identical to A5 baseline (E1 must not
  re-emit bytecode).
- No new `abort()` / `std::abort()` / `__attribute__((weak))` in
  `.cpp` / `.h` / `.s`.
- Desktop x86 `build-x86/game/gk` still reaches
  `link finish: logo`.

## What's likely needed

The Android side already initializes SDL3 (`gk_android_main.cpp::gk_sdl_main`
calls `android_input_audio::init()` which is meant to bring up
`SDL_INIT_AUDIO | SDL_INIT_JOYSTICK | SDL_INIT_GAMEPAD`). Probably
incomplete pieces:

- `AndroidManifest.xml` may already declare landscape; verify and
  add `<uses-feature android:name="android.hardware.gamepad" />` +
  intent filters for HID input devices if missing.
- `MainActivity.java` should set
  `setRequestedOrientation(SCREEN_ORIENTATION_LANDSCAPE)` and
  declare `INPUT_FEATURE_GAMEPAD` in the activity config.
- `android_input_audio::poll()` (or wherever the SDL event pump
  lives on the SDL thread) needs to handle `SDL_EVENT_GAMEPAD_ADDED`,
  open the device with `SDL_OpenGamepad`, then dispatch
  `SDL_EVENT_GAMEPAD_BUTTON_DOWN/UP` into
  `Java_org_opengoal_gk_NativeGk_onPadButton` (which already exists
  in `android/gk_android_main.cpp`).
- The desktop builds (`game/system/hid/sdl_util.cpp` etc.) already
  do this; the Android side should mirror the same call sequence.

If a real device test reveals the desktop's gamepad code path uses
features that don't exist in the Android SDL3 build, fix the SDL3
build flags rather than adding a shim — keep the call sequence
identical.

## e1_run.sh

The existing `.autoport/lib/d4_run.sh` does build → install → launch
→ 60 s logcat capture. E1 adds `.autoport/lib/e1_run.sh` (or extends
d4_run) to also:

- Wait for the user (`adb shell input keyevent KEYCODE_BACK` may
  trigger a known pad-event so the validator can probe synthetically)
  — OR, document that the test requires the user to press a button
  on the connected Bluetooth pad during the capture window. The
  validator will fail-with-clear-message if no pad event fires.

## Reality check toolkit

- `adb shell dumpsys window` → landscape orientation.
- `adb shell input keyevent`-driven synthetic gamepad event OR
  manual press during capture window.
- `.autoport/lib/trace_diff.py` against the desktop oracle through
  the title-screen milestone.
- `nm --defined-only` on libgk.so to confirm `SDL_OpenGamepad`
  reference is satisfied (linked, not stubbed).
- Codegen-lock diff (same set as A5 close).
- Shim-tag scan: every function in `android_runtime_compat.cpp` and
  `android_runtime_full.cpp` must carry a `SHIM_KIND:` header (the
  rule begins at E1; D4's existing shims will need retroactive
  tagging as part of E1 — most are `BIONIC_ADAPTER` or
  `PS2_HW_EMULATION`).

## Cost expectation

Lighter than A5. SDL gamepad wiring is well-trodden territory in
the OpenGOAL codebase. Probably 1-2 hours / $15-25 of claude
budget. The shim-tagging pass for retroactive labelling of D4's
shims may add another hour.
