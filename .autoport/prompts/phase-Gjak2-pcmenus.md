# Phase Gjak2-pcmenus — backport jak1's PC/Android options system to jak2

## Owner request (2026-07-08, live jak2 menu test)
jak2's Graphic Options are bare vs everything we built for jak1:
 * ASPECT RATIO stuck in 4:3 — no "Fit to screen" like jak1 (owner: "l'option Fit to screen du 1
   était parfaite"); changing aspect keeps the image contained in the 4:3 box.
 * "Window Size" offers NO choices (jak1 got a whole resolution system — Gres-picker).
 * "Display Mode" offers NO choices and shows garbage "UNKNOWN ID 999187".
 * Backport the jak1 tweaks: DYNAMIC RENDER SCALE (Gdynamic-renderscale), conditional/hidden menus
   (live-length machinery), resolution picker, fit-to-screen aspect handling, touch nav —
   the whole jak1 pc/progress system adapted to jak2's menu (goal_src/jak2/pc/ only; engine untouched).

## Mandate
Port the jak1 pc-menu feature set to jak2, game-gated, persisted like jak1's pc-settings. Fit-to-
screen fills the device screen (no 4:3 pillarbox unless chosen). Same touch/pad nav quality as jak1.
Reuse the jak1 implementations (they are the spec); adapt to jak2's progress menu structure.

## Verify (device eae4df44): fit-to-screen fills the screen; aspect changes apply live; Window Size/
Display Mode either offer real choices or are hidden (no garbage IDs); dynamic render scale works;
persists across relaunch; screencaps; mCurrentFocus=jak2; x86 jak2 unbroken; deploy_verify PASS.
## Report (.autoport/reports/Gjak2-pcmenus/report.txt) `RESULT: JAK2 PC MENUS <what-lands>`
## Locks: ANDROID_SERIAL=eae4df44; engine goal_src untouched (pc/ only); gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.
