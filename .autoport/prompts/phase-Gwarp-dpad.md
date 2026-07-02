# Phase Gwarp-dpad — teleporter (warp) selection: analog stick acts as D-pad, like in the options menus

## Why (owner 2026-07-02)
The in-game teleporters (warp screens) select their destination with the D-PAD. On Android the analog
stick doesn't drive that selection (it works in the options menus because those already map stick→D-pad
there). The owner wants: while a teleporter/warp selection UI is active, the analog stick behaves as the
D-pad — same context switch the options menus use — so you can pick a warp destination with the stick.

## Mandate (Android input mapping / context switch; runtime glue + pc/)
1. Find how the OPTIONS menus make the stick act as the D-pad on Android (the existing stick→D-pad
   mapping / menu-context input path). Identify the warp/teleporter selection UI state.
2. When the warp selection UI is active, apply the SAME stick→D-pad mapping (up/down/left/right analog
   → D-pad directions with the menu-style repeat/threshold), so the stick navigates the warp choices.
   Restore normal stick behavior when the warp UI closes. Touch + D-pad keep working.
3. Runtime glue / pc/ only; engine goal_src untouched (gold oracle clean).

## Verify (device eae4df44)
Reach a teleporter/warp selection UI; inject analog-stick directions (adb input / the pad path) and
confirm the stick now moves the warp selection (like the D-pad), and normal stick control returns after
the warp UI closes. Options-menu stick→D-pad still works. x86 builds + boots. Full CONSISTENT build,
deploy_verify PASS.

## Report (`.autoport/reports/Gwarp-dpad/report.txt`) with `RESULT: WARP STICK ACTS AS DPAD`
where the options stick→D-pad mapping lives; the warp-UI-active detection; the stick→D-pad applied
during warp + restored after; verification that the stick drives warp selection; engine goal_src
untouched; x86 link finish: logo.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 1800, max_retries 5. device: true, owner_verify: true.
