# Phase Gtouch-menus — make the in-game menus fully touch-browsable (no D-pad needed)

## Why (owner 2026-07-02)
On Android the menus require the D-pad. The owner wants them fully TOUCH-browsable: TAP a menu entry to
enter its submenu / reveal its sub-options, and TAP a sub-option to select it directly — all by touch,
without needing the D-pad. Applies to the options menus (and the progress/pause menu tree).

## Mandate (Android touch input → menu navigation; goal_src pc/ + android touch glue)
1. Map touch taps on menu rows to the same actions the D-pad/confirm produce: tapping a row focuses +
   activates it (enter submenu / open its carousel of sub-options); tapping a sub-option selects it
   (equivalent to highlight + confirm). Left/right carousel options: tapping the option (or a tap on
   its left/right area) cycles/selects. A tap on "Back" / outside goes back.
2. Hit-testing: map the touch (x,y) to the on-screen menu row/option rectangles (the menu already knows
   each row's screen position for drawing — reuse that layout to know what was tapped). Works with the
   touch overlay already present on Android.
3. Keep D-pad + gamepad working (touch is additive). Keep it in pc/ + android touch glue; engine
   goal_src untouched (gold oracle clean).

## Verify (device eae4df44 — real touch via adb input tap)
Using REAL `adb -s eae4df44 shell input tap X Y` events (not cpad_inject): open the options menu, TAP
"Graphic Options" → it enters; TAP a row (e.g. FPS Counter) → it toggles/opens; TAP a carousel option →
it changes; TAP Back → it exits. Confirm each tap drives the menu WITHOUT any D-pad input. D-pad still
works too. x86 builds + boots. Full CONSISTENT build, deploy_verify PASS.

## Report (`.autoport/reports/Gtouch-menus/report.txt`) with `RESULT: MENUS TOUCH-BROWSABLE`
the tap→action mapping + hit-testing approach; adb-input-tap verification (tap enters submenu / selects
sub-option, no D-pad); D-pad+gamepad still work; engine goal_src untouched; x86 link finish: logo.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
