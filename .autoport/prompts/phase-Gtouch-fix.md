# Phase Gtouch-fix — touch menus: ON/OFF toggles and SLIDERS must be tappable (they aren't)

## Why (owner 2026-07-02, on his phone with the final APK)
The touch menus work for the MAIN items (rows enter submenus fine), but the SUB-ELEMENTS are broken:
ON/OFF toggles are NOT clickable, and SLIDERS are even worse — not clickable at all. Also (supervisor
note from the final-APK verification): on the save-file screen a tap only FOCUSES the row ("CONTINUE
WITHOUT SAVING") without ACTIVATING it. So the Gtouch-menus tap layer only drives one row/option type;
the other option types (on-off, slider/percent, save-file rows) don't respond to tap.

## Mandate (extend the Gtouch-menus tap layer to ALL option types)
1. ON/OFF toggles: a tap on the row (or its value area) TOGGLES the value (same as highlight+confirm/
   left-right). One tap = flip.
2. SLIDERS / percent carousels (Render Scale, Min Render Scale, Min Target FPS, resolution carousel...):
   make them tap-drivable — either tap-position-on-the-bar sets the value proportionally, or tap on the
   LEFT half steps down / RIGHT half steps up (pick the more robust given the menu draw layout; the
   left/right-half stepping matches the existing carousel semantics and is likely safer). Repeated taps
   keep stepping.
3. SAVE-FILE screen (and any other screen whose rows only focus on tap): a tap on the focused row
   ACTIVATES it (tap once = focus+activate, or second tap on the focused row activates — prefer
   focus+activate in one tap like the main menus).
4. Sweep ALL menu screens/option types for tap-dead elements (aspect-ratio carousel, resolution list,
   Advanced settings submenu, yes/no dialogs) — make the whole menu tree tap-complete. D-pad/gamepad
   stay working.

## Verify (device eae4df44 — real adb input tap only)
With real `adb input tap`: toggle FPS Counter ON→OFF→ON by tap alone; step RENDER SCALE (or MIN RENDER
SCALE) down/up by tap alone (value visibly changes + logged); change an aspect-ratio/resolution carousel
by tap; activate a save-file row by tap. Screencaps before/after each. No D-pad input in the whole
sequence. x86 builds + boots. Full CONSISTENT build, deploy_verify PASS.

## Report (`.autoport/reports/Gtouch-fix/report.txt`) with `RESULT: ALL MENU ELEMENTS TAPPABLE`
per-type tap handling (toggle/slider/save-row/carousel), the adb-tap verification for EACH type with
values changing, no-D-pad confirmation, D-pad still works, x86 link finish: logo.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
