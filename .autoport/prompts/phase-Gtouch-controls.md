# Phase Gtouch-controls — complete the Android on-screen touch controls (owner-specified layout)

## The ask (owner, 2026-06-23) — needed to actually play/test on device
Complete the in-game touch overlay with PlayStation icons (not letters), a specific modern-mobile
layout, and show-on-touch + 10s-idle-fade. This is custom Android code; the owner needs it to test.
(Native physical-gamepad support is a SEPARATE later phase — do not do it here.)

## What exists (enhance it)
`android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java` (E2 phase) sits atop the SDLSurface,
maps hit-zones → `NativeGk.onPadButton(sdl_button, pressed)` (the SAME path a real gamepad uses via
SDL_EVENT_GAMEPAD_BUTTON), and logs an `overlay-map:` line. It currently has only ×○□△ + d-pad +
START as ASCII letters, always-visible. Rework it to the owner's exact layout below. For analog you
need axis injection — add a `NativeGk.onPadAxis(sdl_axis, value)` JNI if not present, feeding the
existing axis path (`android/android_input_audio.cpp` "Sticks: a deflected injected axis wins").

## Exact layout (owner-specified — follow precisely)
- **Top-LEFT:** ONE combined **L2/R2** button (L2 and R2 do the same thing in-game → single button;
  inject BOTH LEFT_TRIGGER + RIGHT_TRIGGER, or whichever the game reads).
- **Top-RIGHT:** ONE combined **L1/R1** button (single button; inject LEFT_SHOULDER + RIGHT_SHOULDER).
- **Bottom-LEFT:** the **left analog stick** (movement) — a virtual joystick injecting LEFTX/LEFTY.
  **Context switch:** when the game is in a MENU it must become a **D-PAD** (digital UP/DOWN/LEFT/RIGHT)
  because menus require the d-pad; in gameplay it is the analog stick. (Detect menu vs gameplay from
  the game's master-mode / progress state — the native side knows it; signal the overlay via JNI.)
- **Bottom-RIGHT:** the **face buttons ✕ ○ □ △** (SOUTH/EAST/WEST/NORTH).
- **Right side of the screen (any area NOT on a button):** the **CAMERA** — a touch-DRAG zone (swipe
  to look), injecting RIGHTX/RIGHTY from the drag delta, like modern mobile games. NOT a visible
  joystick. Button touches in that region still actuate the button; non-button drags pan the camera.
- **START** and **SELECT/BACK**: keep, small (e.g. top-center).
- **DROP L3/R3** (unused) and the standalone d-pad (the d-pad only exists as the menu mode of the
  left control).

## Other requirements
- **PlayStation icons** as vector glyphs (△ ○ ✕ □ shapes; L1/R1 & L2/R2 text labels; stick ring),
  not ASCII. Tasteful, semi-transparent, landscape-sized.
- **Visibility:** hidden by default; any screen touch shows it; after **10 s** with no touch it fades
  out (smooth alpha). A touch while faded brings it back and resets the timer. Control touches still
  actuate AND reset the timer.
- Keep the same-behavior contract: each control's injected event is byte-equivalent to a real
  gamepad's; the `overlay-map:` log enumerates EVERY control (name → sdl button/axis → region).

## Validator (`phase-Gtouch-controls.sh`) PASS requires
1. `.autoport/reports/Gtouch-controls/controls.txt`: the `overlay-map:` enumerates the set —
   face×4 (bottom-right), combined **l1r1** (top-right), combined **l2r2** (top-left), START, SELECT,
   left-stick (bottom-left), **menu-dpad** (left control's menu mode), right **camera** drag zone —
   and explicitly has **NO l3/r3 and NO standalone d-pad button**. Plus a per-control **actuation
   test** (touch at each control → correct `onPadButton`/`onPadAxis` reaching native, incl. the
   left-stick→d-pad menu switch and the right-side camera drag → RIGHTX/RIGHTY), and a **visibility
   test** (hidden→touch→visible→10s idle→faded→touch→visible). With
   `RESULT: TOUCH CONTROLS COMPLETE (owner layout, icons, show-on-touch+10s-fade)`.
2. Real `android/**` change; goal_src 1-to-1 (zero edits). Fix-summary
   `.autoport/reports/Gtouch-controls-fix-summary.md` ≥60 lines; temp instrumentation removed.
3. Builds (`cmake --build build-android --target gk` + gradle assemble), installs, boots to gameplay
   crash-free; `deploy_verify.sh eae4df44` PASS; x86 unaffected (`link finish: logo`).
4. Icon look/feel + analog/camera feel are owner-eye-final — make them clean; the validator gates the
   FUNCTIONAL contract (layout mapping + actuation + menu-d-pad switch + camera drag + fade + build).

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. `.autoport/gold` READ-ONLY. Keep device awake/unlocked. After any
failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind (1-2 overlay
screencaps for the report are fine).

## Max settings
`max_turns: 1600`, `max_retries: 3`.
