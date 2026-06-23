# Phase Gtouch-controls — complete the Android on-screen touch controls (full button set + PS icons + show-on-touch/10s-fade)

## The ask (owner, 2026-06-23) — needed to actually play/test on device
The in-game touch overlay is incomplete. The owner wants:
1. **The FULL control set** — all buttons, not the current partial set.
2. **Proper PlayStation icons, not letters** (the current overlay draws "X"/"O"/"[]"/"/\\").
3. **Appear only on screen touch, then fade out after 10 seconds with no touches** (currently always visible).
This is custom Android code; the owner needs it to test controls. (Native gamepad support is a
SEPARATE later phase — do not do it here.)

## What exists (enhance it, don't rewrite from scratch)
`android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java` (E2 phase) already:
- sits atop the SDLSurface, maps hit-zones → `NativeGk.onPadButton(sdl_button, pressed)` (the same
  path a real gamepad uses via SDL_EVENT_GAMEPAD_BUTTON), and logs an `overlay-map:` line.
- has only: ×○□△, d-pad(4), START — drawn as ASCII letters, ALWAYS visible.
Missing: **L1/R1/L2/R2, L3/R3, SELECT/BACK**, **the analog STICKS** (left = movement — without it
Jak can't move properly; right = camera), **PS icons**, and the **show-on-touch + 10s-fade** behavior.

## Mandate (android-only; goal_src 1-to-1; this is allowed runtime/platform glue)
1. **Full control set** mapped to the correct SDL gamepad buttons/axes:
   - face ×○□△ (SOUTH/EAST/WEST/NORTH), d-pad (UP/DOWN/LEFT/RIGHT), START, SELECT/BACK,
   - shoulders L1/R1 (LEFT/RIGHT_SHOULDER) and triggers L2/R2 (LEFT/RIGHT_TRIGGER axes), L3/R3
     (LEFT/RIGHT_STICK click),
   - **a virtual LEFT analog stick** (movement) and **RIGHT analog stick** (camera) that inject the
     LEFTX/LEFTY/RIGHTX/RIGHTY axes (use the existing axis-injection path — see
     `android/android_input_audio.cpp` "Sticks: a deflected injected axis wins"; add a
     `NativeGk.onPadAxis(sdl_axis, value)` JNI if one isn't already exposed).
2. **PlayStation icons** drawn as vector glyphs (△ ○ ✕ □ shapes; d-pad arrows; L1/R1/L2/R2 labels;
   stick rings), not ASCII letters. Tasteful, semi-transparent, sized for a phone in landscape.
3. **Visibility behavior:** hidden by default; **any screen touch shows it**; **after 10 s with no
   touch it fades out** (smooth alpha fade). A touch while faded brings it back. Touches on a control
   still actuate it (and reset the 10s timer); touches elsewhere just wake/refresh the overlay and
   pass through to the game.
4. Keep the existing same-behavior contract: each control's injected event is byte-equivalent to a
   real gamepad's, and the `overlay-map:` log enumerates EVERY control (name → sdl button/axis →
   cx,cy,size) for verification.

## Validator (`phase-Gtouch-controls.sh`) PASS requires
1. `.autoport/reports/Gtouch-controls/controls.txt`: the `overlay-map:` line enumerates the FULL set
   (face×4, dpad×4, START, SELECT, L1,R1,L2,R2,L3,R3, left-stick, right-stick) with each control's
   SDL button/axis; a per-control **actuation test** — a synthetic touch at each control's coords
   produces the correct `onPadButton`/`onPadAxis` (button bit / axis value) reaching native; and a
   **visibility test** — overlay hidden→(touch)→visible→(10s idle)→faded→(touch)→visible (cite the
   alpha/visibility state + timestamps). With `RESULT: TOUCH CONTROLS COMPLETE (full set, icons, show-on-touch+10s-fade)`.
2. Real `android/**` code change; goal_src 1-to-1 (zero edits). Fix-summary
   `.autoport/reports/Gtouch-controls-fix-summary.md` ≥60 lines; temp instrumentation removed.
3. Builds (`cmake --build build-android --target gk` + gradle assemble), installs, boots to gameplay
   crash-free; `deploy_verify.sh eae4df44` PASS. x86 desktop unaffected (`link finish: logo`).
4. NOTE: the ICON look/feel + analog feel are owner-eye-final — make them clean; the validator gates
   the FUNCTIONAL contract (full mapping + actuation + fade behavior + builds/deploys).

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. `.autoport/gold` READ-ONLY. Keep device awake/unlocked. After any
failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind (one or two
overlay screencaps for the report are fine).

## Max settings
`max_turns: 1600`, `max_retries: 3`.
