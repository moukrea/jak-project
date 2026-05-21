# Phase E2 — UX: optional touch overlay (no-gamepad fallback)

## Status

**Authored 2026-05-21 by the supervisor**, replacing the May-21
placeholder. Same-behavior contract: the touch overlay must produce
**the exact same JNI events** as a connected gamepad would, so the
GOAL kernel's CPad layer sees identical input regardless of source.

## Bucket

E — UX corrections (REDESIGN.md §8).

## Goal (concrete, device-verifiable)

1. APK contains an opt-in touch overlay (settings flag, default
   **on** when no gamepad is connected, **off** otherwise — same
   default the desktop build uses for keyboard fallback).
2. When the overlay is visible, tapping a virtual face button
   generates a `Java_org_opengoal_gk_NativeGk_onPadButton` JNI
   callback that's byte-equivalent to the call shape a real gamepad
   button would make (same `sdl_button` enum value, same `pressed`
   semantics).
3. With a Bluetooth gamepad connected (E1 prerequisite still
   holds), the overlay auto-hides — observable via a logcat line
   `gamepad detected: hiding touch overlay`.
4. Trace-diff against the desktop x86_64 oracle: a recorded session
   that uses overlay-driven inputs must produce an event subsequence
   identical (within tolerance) to a desktop session driven by
   keyboard inputs mapped to the same buttons.

## Hard rules — same-behavior contract

- Shim governance from E1 applies: every function in `android/*.cpp`
  carries a `SHIM_KIND:` tag.
- `goalc/` codegen + classifier byte-identical to A5 close.
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-identical to A5 baseline.
- No new `abort()` / `__attribute__((weak))` / `*_stubs.cpp` files.
- Desktop x86 `build-x86/game/gk` still reaches `link finish: logo`.

## What's likely needed

- A small overlay view in `android/app/src/main/java/org/opengoal/gk/`
  rendering 4 face buttons + d-pad in a corner. Use a transparent
  `View` over the SDL surface; intercept `MotionEvent.ACTION_DOWN`
  and `ACTION_UP` per hitbox.
- The hit-zone → button mapping should mirror the desktop default
  keyboard layout (in `game/system/hid/input_bindings.cpp`):
  `KEYBOARD_A → SDL_GAMEPAD_BUTTON_X` etc. The validator records
  the mapping table in `.autoport/reports/E2-overlay-map.json`.
- Detecting "gamepad connected" is just listening for
  `SDL_EVENT_GAMEPAD_ADDED` / `_REMOVED` from the SDL thread and
  toggling overlay visibility through a `runOnUiThread` lambda.

## e2_run.sh

Extends E1's run script:
- After build + install + launch, send `adb shell input tap X Y`
  events at known overlay hit-zone coordinates to simulate taps.
- Capture logcat to `.autoport/reports/E2-boot.log`.
- Optionally: take a screencap when overlay is visible (compare
  against a checked-in `E2-overlay-reference.png` via phash).

## Reality check toolkit

- `adb shell input tap <x> <y>` to drive synthetic taps at overlay
  hitboxes (no manual operator presence needed).
- `nm --defined-only` on libgk.so for `NativeGk_onPadButton`,
  `SDL_EVENT_GAMEPAD_ADDED`.
- `.autoport/lib/trace_diff.py` against desktop oracle with
  keyboard-driven session as reference.
- Shim-tag scan, codegen-lock diff, x86+arm64 CGO baseline.

## Cost expectation

Lighter than E1. Java-side UI work + reusing the E1 input-routing
plumbing. ~1 hour / $10-20.
