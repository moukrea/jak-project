# Ginput-replay-realinput — fix summary

## Owner defect (2026-06-28)
Under the deterministic Geyser warp anchor, a LIVE input record captured ALL-NEUTRAL across two
owner re-captures: `collision-glitch-v2.inputs` (0/71354 non-neutral) and
`collision-glitch-v2-raw.inputs` (0/335077). The prior Ginput-replay-liverecord phase
false-greened: it verified only the headless `cpad_inject` channel (which writes the `g_inject_*`
atomics directly), never the owner's REAL touch-overlay / Bluetooth-gamepad input. The supervisor
confirmed `adb`-input real touch is 0% captured under the warp.

`goal_src` is left byte-identical. The fix is entirely host/runtime (the Android Java input glue).
No goalc / emitter / IGenX86_64 / C++ runtime change. No `.autoport/gold` change.

## What the on-device investigation established (eae4df44, fresh HEAD libgk db51bdc5)
1. **The merge + record + replay path is SOUND.** REAL `adb shell input` touch (swipe/tap on the
   in-game overlay), recorded under the warp with the overlay PRESENT, captured **75.3%
   (1664/2211)** and, on a second run, **65.5% (543/829)** non-neutral — the stick deflections
   track the driven swipes. So the warp does NOT suppress the merge; the prior phase's framing
   ("the warp overwrites the pad before the tap") is REFUTED — there is no such drive (the
   `mouche_fx_run` hook spawns buzzers, it never touches the pad).
2. **The drop is BEFORE the merge, in Android touch delivery.** The record tap
   (`CPadGetData` -> `pad_replay::on_cpad_read`) records exactly what
   `android_input_audio::get_cpad_state()` returns, which composes the touch/gamepad producers
   (`g_overlay_button0` / `g_stick_*`) OR the injector (`g_inject_*`). All-neutral therefore means
   the owner's active input source never reached `on_pad_button` / `on_pad_axis`.
3. **Reproduced the all-neutral with REAL touch.** With the touch overlay in its DISABLED state
   (PREF_TOUCH_OVERLAY_ENABLED=false — exactly what a gamepad-present-at-first-launch leaves
   behind), warp + record + `adb shell input` touch produced **overlay-actuate = 0** and a
   recorded demo of **0/602 non-neutral** — ALL-NEUTRAL, reproducing the owner's 0/71354.
4. **Root cause.** The touch overlay is REMOVED from touch hit-testing in two real conditions:
   (a) it is never added when a gamepad is present at startup (`setupTouchOverlay` early-returns
   on `!enabled`), and (b) the gamepad auto-hide sets it to `View.GONE`, which removes it from
   hit-testing entirely (alpha-0 stays touchable, but GONE does not). The owner records with a
   Bluetooth gamepad (two 8Bitdo SF30 Pro, a Switch "Pro Controller" and a Sony "Wireless
   Controller" are paired). When that pad is bonded-but-not-delivering Android input events (a
   common Switch Pro / DualShock Bluetooth quirk) AND the overlay has been removed, there is NO
   input path at all and the record is SILENTLY all-neutral.

## The fix (host/runtime; goal_src 1-to-1)
`android/app/src/main/java/org/opengoal/gk/MainActivity.java`:
- `isInputRecordArmed()` (new): reads `getprop debug.opengoal.pad_replay` (the harness selector,
  set by `adb setprop` BEFORE launch — `onCreate` runs before native reads it, so Java reads the
  property directly). Returns true for `record`/`replay`.
- `setupTouchOverlay()`: when a record/replay is armed, FORCE the overlay ON even if the
  gamepad/user default disabled it — a record must never be silently input-less. Marker:
  "FORCING the overlay ON ... record_armed=true".
- `pollGamepadCount()`: while a record/replay is armed, do NOT `View.GONE` the overlay on
  gamepad-detect — keep it touch-capable (GONE would re-introduce the exact drop). Non-record
  behaviour is unchanged (overlay still hides for a clean gamepad UX).

`android/app/src/main/java/org/opengoal/gk/TouchOverlayView.java`:
- `setPersistentVisible(boolean)` (new) + a `persistentVisible` guard in the idle-fade heartbeat:
  while a record/replay is armed, keep the controls VISIBLE (skip the 10s idle fade) so the owner
  SEES and uses the touch controls to record, even if their gamepad is silent.

These touch nothing in the capture path: the merge (`get_cpad_state`), the record tap
(`on_cpad_read`), the logic-frame index, the warp anchor, the timestep force and the RNG reseed
are all UNCHANGED. The change is purely *which Java input source is alive during a record*, so
determinism is unaffected.

## Verification (device eae4df44, fresh HEAD libgk, deploy_verify PASS)
- BEFORE (overlay pref OFF, current code): warp + record + `adb input` touch -> **0/602
  non-neutral** (overlay-actuate 0). All-neutral reproduced.
- AFTER (overlay pref OFF, fixed code): the fix forces the overlay touch-capable
  ("FORCING the overlay ON", "record_armed=true", "PERSISTENT") -> `adb input` touch ->
  **REAL INPUT CAPTURED: 1802/2330 (77.3%)**, overlay-actuate 346, anchor at logic frame 603.
- Verified with REAL `adb shell input swipe`/`adb shell input tap` events — explicitly NOT
  `cpad_inject` (the inject property is the neutral token "none"; the injector is not used).
- DETERMINISM (record == replay): device pad_replay SELFTEST -> `PAD DIFF: 0/120`,
  `FIRST DIVERGENCE: none — bit-identical (record == replay)`, `DETERMINISM 0/120`, SELFTEST PASS.
  The captured REAL demo replays: `REPLAY <- pad_demo.inputs (v2, 2330 logic frames)` + anchor 603.
- x86 smoke: `link finish: logo` present (no x86/codegen change — the fix is Android-Java only).
- libgk.so sha UNCHANGED across the rebuild (db51bdc5…) — confirms the change is Java/dex only.

## Gamepad note (shares the proven merge)
The Bluetooth-gamepad path (Android event -> SDL -> `android_renderer.cpp` poll loop ->
`process_sdl_event` -> `on_pad_button`/`on_pad_axis`) reaches the SAME `g_overlay_button0` /
`g_stick_*` merge that the proven touch capture exercises. A physical pad cannot be driven
headlessly (the paired controllers are bonded-but-disconnected; `adb input gamepad` does not route
through SDL), so the merge is proven via REAL adb-input touch and the fix guarantees the owner can
always record via touch even when their pad is silent. A follow-up improvement for HIDAPI-routed
pads (declare `BLUETOOTH_CONNECT` so SDL HIDAPI can enumerate Switch Pro / DualShock controllers)
is recommended but was deliberately NOT applied here: it is unverifiable without a physical pad and
could regress the working Android SOURCE_GAMEPAD path. It belongs in its own phase with a pad in
hand.

## Temp instrumentation — REMOVED before close
No temporary diagnostics were added to the runtime tree. The MainActivity / TouchOverlayView log
lines are PERMANENT, informative markers that are part of the fix (they name the guaranteed-input
behaviour), not throwaway dumps. All investigation scripts (repro_*.sh, exp_*.sh, before_off.sh,
after_verify.sh, analyze_inputs.py, probe_gamepad.sh) live under
`.autoport/reports/Ginput-replay-realinput/` — they are harness, not runtime, and were removed
from any runtime path (none was ever added). `git diff` of `game/`, `goalc/` and `goal_src/` is
empty; only the two Android Java files changed. `.autoport/gold` is untouched (pristine). No
leftover diagnostic code remains in `game/` or `android/` C++.
