# Phase Gtitle-tap — title screen: "PRESS START OR TAP SCREEN", and a tap opens the start menu

## Why (owner 2026-07-03, v3 playtest)
On the title screen the prompt says "PRESS START". On a touch device it should say
"PRESS START OR TAP SCREEN" — and tapping the screen must do what START does (open the start menu).

## Mandate
1. TAP = START on the title screen: reuse the existing touch plumbing (NativeGk.onMenuTap →
   menu-touch-drive! from Gtouch-menus/Gtouch-fix) — on the title/attract "press start" state, ANY
   screen tap triggers the START press path (same state transition, same sound). Scope it: only on
   the press-start screen (do NOT make random taps act as START in-game; in-menu tap behavior from
   Gtouch-fix stays as is).
2. TEXT: change the title prompt to the touch-aware wording on the Android build ONLY (desktop
   keeps "PRESS START"). LOCALIZED — at minimum EN "PRESS START OR TAP SCREEN" and FR (e.g.
   "APPUYEZ SUR START OU TOUCHEZ L'ÉCRAN"), and check the string fits/centers at both 4:3 and
   16:9-wide title layouts (Gtitle-pixelmatch placement unregressed). Text lives in the game text
   bank — prefer the pc text-override path; TIT.DGO is safe to rebuild+push if needed.
3. Verify on eae4df44: screencap the new prompt (EN + FR); real `adb input tap` on the title screen
   opens the start menu (screencap sequence); gamepad START still works; in-game taps unchanged
   (still virtual-pad, no phantom START); attract cycle + logo placement unregressed vs golden.
   x86 build boots with its prompt untouched (link finish: logo). Full CONSISTENT build,
   deploy_verify PASS.

## Report (`.autoport/reports/Gtitle-tap/report.txt`) with `RESULT: TITLE TAP OPENS START MENU`
the tap->start wiring (file:line), the localized prompt screencaps (EN+FR), the tap-opens-menu
sequence proof, scoping proof (in-game taps unaffected), title layout unregressed, x86 ok.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched (pc/ ok, TIT.DGO rebuildable); .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
