# Phase Glauncher-collection — per-game APK OR collection launcher, by build-time assets

## Why (owner 2026-06-30, REVISED)
OpenGOAL can compile Jak 1/2/3/X. The FINAL behavior depends on how many games' assets are provided
at BUILD time:
- **Exactly ONE game provided → NO launcher, NO collection.** The APK boots STRAIGHT into that game,
  named + iconed per game:
    - Jak 1 only → app label "Jak & Daxter"
    - Jak 2 only → "Jak II"
    - Jak 3 only → "Jak 3"
    - Jak X only → "Jak X"   (Jak X may be incomplete upstream — handle gracefully, don't block on it)
  Each single-game build uses ITS OWN launcher icon.
- **MORE THAN ONE game provided → COLLECTION mode.** App label = **"Jak and Daxter: The Recharged
  Jak-pot"** (owner is designing the icon — use a placeholder if none yet, wired so the real icon
  drops in). The app boots to a SELECTION MENU listing the included games; pick one → launch it.
  Start SIMPLE: selectable TEXT entries, usable by TOUCH and/or GAMEPAD. (FUTURE/backlog, not now:
  background image, per-game logos, the selected game's Jak idle-cycling render in the menu.)

## Mandate (build/packaging + runtime; jak1 stays fully playable)
1. BUILD-TIME GAME DETECTION: the set of games = which per-game asset bundles are present in the APK
   at build time. Define the manifest/detection + the mode switch (1 game = direct; >1 = collection).
2. SINGLE-GAME: boot straight into the game; set the app label + icon per the table above. No menu.
3. COLLECTION: app label "Jak and Daxter: The Recharged Jak-pot"; a boot selection menu (text,
   touch+gamepad) → launch the chosen game.
4. Only jak1 assets exist now, so the deliverable to verify is the SINGLE-GAME Jak 1 path: boots
   straight into "Jak & Daxter" (its icon), all current fixes intact. Implement the collection
   mode + detection so that ADDING a 2nd game's assets would switch to collection (document/verify
   the mechanism even though only jak1 is built now — e.g. a dry-run/2-game manifest test).

## Honest scope
Biggest item; collection mode (multi-game coexistence in one APK) may be large. If full multi-game
coexistence can't land cleanly in one phase, deliver: (a) the SINGLE-game Jak1 direct-boot + correct
name/icon (must work), and (b) the detection + collection-menu mechanism proven by a manifest/dry-run,
with a documented STEP-1 for true multi-game asset coexistence. No false-green; owner play-tests.

## Verify (device, actual screen)
jak1-only build → APK boots STRAIGHT into Jak & Daxter (no launcher), label "Jak & Daxter" + its icon,
game plays (all fixes intact). The 1-vs-collection detection is asset-driven (documented; a 2-game
manifest dry-run shows collection mode + the selection menu + touch/gamepad select). Full CONSISTENT
build, deploy_verify PASS, screencaps.

## Report (`.autoport/reports/Glauncher-collection/report.txt`) with `RESULT: PER-GAME OR COLLECTION BY BUILD ASSETS` (or `RESULT: LAUNCHER STEP-1`)
single-game direct-boot + per-game name/icon table; the asset-driven 1-vs-collection detection; the
collection menu (text, touch+gamepad) shown via build or dry-run; jak1 plays; what remains for full
multi-game coexistence + the future rich menu; x86/build status.

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; keep jak1 fixes intact; .autoport/gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.
