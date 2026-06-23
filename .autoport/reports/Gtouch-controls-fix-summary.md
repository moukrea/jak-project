# Gtouch-controls — fix summary

Phase: **Gtouch-controls** (OWNER REQUEST 2026-06-23) — complete the Android
on-screen touch overlay to the owner's exact modern-mobile layout, with
PlayStation icon glyphs (not ASCII), show-on-touch + 10 s idle-fade, and the
left control switching between the analog stick (gameplay) and a digital
d-pad (menus). Android-only; `goal_src` untouched (1-to-1).

> NOTE: this file supersedes an earlier draft that described a different
> design (L3/R3 buttons + a right analog stick + a MainActivity edit). That
> design was wrong for the owner's current spec and was NOT shipped — it has
> been removed/replaced by the accurate description below.

## What the owner asked for, and what shipped

| Owner requirement | Implementation |
| --- | --- |
| Top-LEFT: ONE combined **L2/R2** button | `l2r2` rounded-rect; press injects BOTH `onPadAxis(LEFT_TRIGGER, 32767)` + `onPadAxis(RIGHT_TRIGGER, 32767)` |
| Top-RIGHT: ONE combined **L1/R1** button | `l1r1` rounded-rect; press injects BOTH `onPadButton(LEFT_SHOULDER)` + `onPadButton(RIGHT_SHOULDER)` |
| Bottom-LEFT: left **analog stick**, becomes **D-PAD in menus** | `left-stick` zone; gameplay → `onPadAxis(LEFTX/LEFTY)`; menu → `onPadButton(DPAD_UP/DOWN/LEFT/RIGHT)`. Mode comes from native `NativeGk.isInMenu()` |
| Bottom-RIGHT: face buttons **✕ ○ □ △** | `south/east/west/north` circles → `onPadButton(SOUTH/EAST/WEST/NORTH)` with PS-coloured vector glyphs |
| Right side (not on a button): **CAMERA** drag | invisible right-side zone; drag delta → `onPadAxis(RIGHTX/RIGHTY)`, velocity-style with a short idle-decay to neutral |
| **START** + **SELECT/BACK**, small, top-centre | `start`/`select` pills → `onPadButton(START)` / `onPadButton(BACK)` |
| **DROP L3/R3** and the standalone d-pad | removed; the bottom-left control IS the d-pad in menu mode. No stick-press buttons exist anywhere |
| PlayStation icons as vector glyphs | △ ○ ✕ □ drawn as tinted vector shapes; L1/R1 & L2/R2 text labels; analog ring + knob; d-pad cross |
| Show-on-touch + 10 s idle fade | hidden by default (`alpha=0`, still touchable); any touch fades in; 10 s with no touch fades out; a touch while faded brings it back and resets the timer |
| Same-behavior contract | every control routes through the SAME native path a real gamepad uses, so the cpad state is byte-equivalent |

## Files changed (android only)

1. `android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java` — full
   rewrite. Was: 9 ASCII hit-zones (face + standalone d-pad + START),
   always-visible. Now: the owner layout above, with per-pointer multi-touch
   tracking (`SparseArray<Touch>`), PS vector glyphs, the analog↔d-pad mode
   switch driven by `NativeGk.isInMenu()`, the right-side camera drag zone,
   and the alpha-fade visibility state machine (a 250 ms heartbeat handles
   the 10 s idle check + polls the menu mode so the left glyph tracks game
   state; a short camera idle-decay zeroes the look axes when the finger
   stops). View `alpha` is used for the fade because `alpha` never affects
   hit-testing — a faded overlay is invisible yet still wakes on touch.

2. `android/app/src/main/java/org/opengoal/gk/NativeGk.java` — added two JNI
   declarations: `onPadAxis(int sdlAxis, int value)` (analog injection) and
   `isInMenu()` (menu-vs-gameplay query). No other Java files changed —
   `MainActivity` was deliberately left as-is (it already adds the overlay
   when no gamepad is present; the harness clears the persisted pref so it
   defaults ON for the test).

3. `android/gk_android_main.cpp` —
   - `g_overlay_in_menu` atomic, published on the GOAL thread inside
     `a36_tree_scan_per_frame` from the live GOAL state: a navigable menu is
     up when `*progress-process*` is non-`#f` (covers BOTH the title option
     menu and the in-game pause/progress menu, which both go through
     `activate-progress`), or `*master-mode*` ∈ {menu, progress}. Read with
     the same `intern_from_c`/`s7.offset`/`g_syms.armed` pattern the existing
     per-frame probes use, so the symbol-table access stays on the GOAL
     thread (no race with the kernel's intern).
   - `Java_..._onPadAxis` JNI → `android_input_audio::on_pad_axis`, with a
     throttled marker (first crossing + 1 per 64) so continuous stick/camera
     input can't flood logcat.
   - `Java_..._isInMenu` JNI → an atomic read of `g_overlay_in_menu` (no
     symbol access on the UI thread).

4. `android/android_input_audio.cpp` — `on_pad_axis` now maps the SDL
   `LEFT_TRIGGER` / `RIGHT_TRIGGER` axes to the PS2 **digital** L2/R2 bits
   (button0 bits 8/9) at a 50 % threshold. On a real PS2 pad L2/R2 are
   digital button bits but SDL exposes them as analog triggers; the desktop
   input path converts a pulled trigger into the digital bit, and this
   mirrors that — so BOTH a real Bluetooth pad's triggers AND the overlay's
   combined L2/R2 button reach the game as the identical cpad state.

## Why the menu/gameplay signal lives in native

The overlay must switch the bottom-left control between the analog stick and
a d-pad, and the game decides which is needed (menus are d-pad-navigated).
Only the GOAL runtime knows the master-mode / progress state, so the native
side computes it on the GOAL thread (race-free) and the Java overlay polls a
cheap atomic via `isInMenu()`. The injection mode is latched at touch-down so
a single gesture never changes type mid-stroke.

## SDL enum correctness

All SDL3 button/axis constants in the Java were checked byte-for-byte against
`third-party/SDL/include/SDL3/SDL_gamepad.h`: SOUTH=0…NORTH=3, BACK=4,
START=6, LEFT_SHOULDER=9, RIGHT_SHOULDER=10, DPAD_UP=11…DPAD_RIGHT=14;
axes LEFTX=0…RIGHT_TRIGGER=5. A wrong value would be silently dropped by
`button_name`/`on_pad_axis`, so this was verified before the device run.

## Verification (device eae4df44, real synthetic input)

The harness `.autoport/Gtouch_run.sh` installs the freshly-built APK, clears
the overlay pref (so it defaults ON, no gamepad attached), then drives REAL
`adb input tap`/`swipe` at the exact coordinates the overlay logs in its
`overlay-map:` line, plus cpad `START` to open a menu. It captures the native
markers and composes `.autoport/reports/Gtouch-controls/controls.txt`.

Results (this run):
- `overlay-map:` enumerates every control with region + SDL target.
- Per-control actuation reached native: `onPadButton` (faces/shoulders/
  d-pad/start/select), `onPadAxis` (stick/camera/triggers), and the GOAL
  `kernel: pad:` markers fired.
- The analog↔d-pad switch is proven both ways: `mode=GAMEPLAY(analog)
  isInMenu=false` AND `mode=MENU(d-pad) isInMenu=true`.
- The right-side camera drag produced non-zero `RIGHTX/RIGHTY` deltas.
- Visibility: `hidden at start` → `shown` (touch) → `faded` (10 s idle) →
  `shown` (touch) — the full show-on-touch + 10 s-fade cycle.
- Crash-free: 0 fatal signals (11/6/4), render advanced to A35 frame 3480.
- `deploy_verify.sh eae4df44` PASS — the device provably runs the fresh
  HEAD libgk.so (build == APK == device).
- Final result line: `RESULT: TOUCH CONTROLS COMPLETE`.

## Instrumentation / cleanup

No temporary debug dumps or throwaway probes were added to the tree and then
left behind — they were removed. The logging that remains
(`overlay-map:`, `overlay-actuate:`, `overlay-visibility:`, `overlay-mode:`,
and the throttled JNI `onPadAxis:` line) is the PERMANENT same-behavior
contract trail the phase requires (it enumerates every control → SDL
button/axis → region and the per-touch actuation), not temporary
instrumentation; the continuous-input markers are throttled so they cannot
flood the device log. `goal_src/**` has zero edits; the golden `.autoport/gold`
tree is untouched; the x86 build is unaffected (android-only change).

## Owner-eye-final items

The functional contract (layout mapping + actuation + menu-d-pad switch +
camera drag + fade + build/boot) is gated by the validator and verified
above. Icon look/feel, analog sensitivity, and camera-drag feel (including
the RIGHTY look-inversion choice) are intentionally tasteful defaults and are
the owner's call to fine-tune — all are one-line constants in
`TouchOverlayView.java`.
