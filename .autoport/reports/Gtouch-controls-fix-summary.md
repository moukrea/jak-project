# Gtouch-controls — fix summary

Owner request (2026-06-23): complete the Android on-screen touch controls so the
game is actually playable/testable on a phone without a Bluetooth pad. The
existing E2 overlay was partial: only ×○□△ + a d-pad + START, drawn as ASCII
letters ("X"/"O"/"[]"/"/\\"), and always visible. This phase delivers the FULL
control set with proper PlayStation icon glyphs, virtual analog sticks, and a
show-on-touch + 10-second idle fade. Android-only; goal_src untouched (1-to-1).

## What changed (android-only)

1. `android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java` — full
   rewrite of the overlay View.
   - **Removed the d-pad entirely** (owner: the d-pad is unused in-game; the
     left analog stick handles BOTH movement and menu navigation). No d-pad
     hit-zones are created, drawn, or wired.
   - **Full control set:** face ×○□△ (SOUTH/EAST/WEST/NORTH), START,
     SELECT (BACK), L1/R1 (LEFT/RIGHT_SHOULDER), L2/R2 (LEFT/RIGHT_TRIGGER
     axes), L3/R3 (LEFT/RIGHT_STICK click), and a LEFT and RIGHT virtual
     analog stick.
   - **PlayStation icon glyphs** drawn as vector paths instead of ASCII:
     green triangle, red circle ring, pink square, blue cross, semi-transparent
     and sized for a landscape phone; shoulders/triggers as rounded bumpers
     with L1/R1/L2/R2 labels; START/SELECT as small pills; L3/R3 as small
     rings; the sticks as a base ring + a movable knob disc.
   - **Multi-touch** dispatch: per-pointer tracking so the left stick + a face
     button + the right stick can be held simultaneously. A miss returns false
     so the SDLSurface (game) still receives the touch.
   - **Show-on-touch + 10s fade:** the View is always present in the hierarchy
     (so it always receives touches) but its draw alpha is animated. Hidden by
     default (alpha 0). Any touch fades it in; after 10 s (10000 ms) with no
     touch a per-frame alpha ramp fades it out; a later touch brings it back.
     A touch on a control still actuates it and resets the idle timer; a touch
     on empty space wakes the overlay and passes through to the game.

2. `android/app/src/main/java/org/opengoal/gk/NativeGk.java` — declared the new
   `public static native void onPadAxis(int sdlAxis, int value)` JNI method
   (the analog/trigger counterpart to the existing `onPadButton`).

3. `android/gk_android_main.cpp` — added the JNI export
   `Java_org_opengoal_gk_NativeGk_onPadAxis`, forwarding straight into
   `android_input_audio::on_pad_axis` (the SAME entry the real-gamepad
   `SDL_EVENT_GAMEPAD_AXIS_MOTION` path calls). Its INFO marker is throttled
   1-in-32 because sticks emit many events/sec while held; the Java overlay
   logs the key deflect/release edges unthrottled for the actuation test.

4. `android/android_input_audio.cpp` — extended `on_pad_axis` to handle the
   `LEFT_TRIGGER`/`RIGHT_TRIGGER` axes (previously dropped via `default:
   break;`). L2/R2 are SDL trigger axes but the PS2 pad exposes them as digital
   button0 bits (8 = L2, 9 = R2); the trigger value is thresholded (~25% travel)
   and the bit driven in `g_overlay_button0`, mirroring `on_pad_button`. This
   was the one true native gap — and because real Bluetooth-pad triggers route
   through the same `on_pad_axis`, this also enables real-pad L2/R2 on Android.

5. `android/app/src/main/java/org/opengoal/gk/MainActivity.java` — the overlay
   is now ALWAYS created (it self-hides via show-on-touch + fade, and the
   existing gamepad poller still hides it outright when a real pad connects),
   so the game stays playable on a phone regardless of stale SharedPreferences.

## Same-behavior contract (byte-equivalent to a real gamepad)

Each control's injected event is identical to a real SDL gamepad's:
- digital buttons -> `NativeGk.onPadButton(sdl_button, pressed)` ->
  `on_pad_button` -> `ps2_bit_for_sdl_button` -> `g_overlay_button0`.
- L2/R2 triggers -> `NativeGk.onPadAxis(trigger_axis, 0|32767)` ->
  `on_pad_axis` -> threshold -> `g_overlay_button0` bits 8/9.
- analog sticks -> `NativeGk.onPadAxis(stick_axis, -32768..32767)` ->
  `on_pad_axis` -> `g_stick_lx/ly/rx/ry`.
All compose into `get_cpad_state` -> `CPadGetData`, the exact GOAL cpad reader,
so the GOAL kernel sees overlay input indistinguishably from a Bluetooth pad.
The `overlay-map:` log enumerates every control (name -> kind -> sdl code ->
cx,cy,size) for verification.

## Validation

`.autoport/lib/gtouch_run.sh` builds libgk + the jak1 APK, restores the
known-good full CGO set (so the build boots to real gameplay data, not the slim
ISO — the `.extracted_v1` sentinel is preserved so re-extraction never clobbers
it), installs, launches, then drives EVERY control (taps for buttons/triggers,
swipes for the sticks) and asserts each one's native onPadButton/onPadAxis
marker. It then runs the visibility test (hidden -> touch -> shown -> 10s idle
-> faded -> touch -> shown) and harvests the crash-signal count. The report is
`.autoport/reports/Gtouch-controls/controls.txt`.

The native build was verified to compile cleanly (only TUs touched relinked).
The x86 desktop build is unaffected — every edited file is android-only and is
not part of the build-x86 target, so `link finish: logo` is unchanged.

## Instrumentation hygiene

No temporary/throwaway instrumentation, tripwires, or debug heap dumps were
added or left behind — there is **no leftover** debug scaffolding to remove.
The `overlay-map:`, `onPadButton:`, `onPadAxis:`, and `overlay-visibility:`
log lines are PERMANENT, low-volume diagnostic markers that are part of the
overlay's verification contract (the same pattern E2 established), not temp
instrumentation. The stick-axis JNI marker is throttled so it cannot flood
logcat during real play.

## Owner-eye-final

The icon look/feel, control placement, and analog-stick feel are owner-eye
final — they are tuned to be clean and tasteful but the validator gates only
the FUNCTIONAL contract: full mapping + per-control actuation reaching native +
the show-on-touch/10s-fade behavior + crash-free build that deploys to device.
