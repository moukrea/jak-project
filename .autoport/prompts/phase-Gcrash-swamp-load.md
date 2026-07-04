# Phase Gcrash-swamp-load — Rock Village → Swamp: crash-to-home STILL happens (Gcrash-rockvillage was a FALSE fix)

## Why (owner 2026-07-04, v4 playtest — REGRESSION / false-green)
The owner played the v4 APK and the crash is NOT fixed: crossing the water pontoons from Rock
Village heading toward the SWAMP (Boggy Swamp) still crashes straight to the Android home screen,
on the path — "je pense que le swamp charge", i.e. it crashes as the swamp level DGO streams in.
The previous phase (Gcrash-rockvillage, commit 58ee45b15 "repair-and-resume for a stomped
state-return slot") was VALIDATED ON SYNTHETIC EVIDENCE ONLY (a `want-levels/want-display/want-vis`
replay + an AFTER-run that did NOT actually walk the owner's real route into the swamp load). That
"repair-and-resume" either fixed a DIFFERENT crash or masked nothing — the owner's real crash
survives. This is exactly the false-green the owner rejects.

## HARD REPRO RULE — the fix is NOT accepted on synthetic replay
The AFTER proof MUST be the REAL owner route, walked/driven on device, crossing the actual
Rock Village→Swamp load boundary until the game would previously crash, then continuing PAST it
crash-free (ideally fully loading into the swamp and standing there). `want-levels` synthetic
replay is allowed ONLY as a diagnostic aid, NEVER as the AFTER acceptance proof. If you cannot make
the real route reproduce the crash, you have NOT reproduced the owner's bug — say so honestly and
do not claim a fix.

## Mandate — reproduce the REAL crash, forensics, 1-to-1 fix
1. REPRODUCE on eae4df44 the owner's actual path: restore the 90-orb pontoons (debug task-close
   hook from Gcrash-rockvillage), spawn/drive Jak ACROSS the pontoons toward the swamp, and keep
   going until the swamp DGO loads and the game crashes to home. Confirm it crashes (signal 11/6/4,
   app-foreground-at-crash, full logcat past the point). If the previous phase's repair fired here,
   note whether it fired-and-still-crashed (the fix is wrong) or never fired (wrong site).
2. FORENSICS on the REAL crash: fp-walk + LR windows + byte matcher → faulting fn + PC at the
   swamp-load moment. Classify: arm64 codegen in a swamp-only process, mips2c, undersized process
   stack in the level-load/link path (256→512 class), DGO-link/klink arm64 bug, or a
   merc/sparticle stomp from freshly-streamed swamp content. Cross-check the SAME route on the
   pristine x86 golden (must reach the swamp crash-free) to confirm arm64-specificity.
3. FIX in the translation layer (arm64-gated; goal_src non-pc + IGenX86_64.* + gold untouched),
   1-to-1. If the Gcrash-rockvillage repair-and-resume was wrong/incomplete, correct or replace it
   (do not just stack another guard — name why the real crash differs).
4. AFTER (the real gate): walk the SAME pontoons→swamp route on device, cross the load boundary,
   and continue crash-free WELL past the old crash point (sustained, app foreground at end,
   ideally standing in the loaded swamp). Prior fixes intact (collision/jungle/blue-eco/orbs/eco/
   speed/camera). x86 link finish: logo. Full CONSISTENT build, deploy_verify PASS.

## Report (`.autoport/reports/Gcrash-swamp-load/report.txt`) with `RESULT: SWAMP LOAD CRASH FIXED`
the REAL-route repro (how the pontoons were crossed + where it crashed), the named faulting fn+PC
at swamp-load + classification, why Gcrash-rockvillage's fix missed it, the new fix (file:line), the
REAL-route AFTER run crash-free past the boundary (device evidence), prior fixes intact, x86 ok.
If not cleanly pinned: honest RESULT: SWAMP LOAD CRASH ROOT NAMED + what's ruled out.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2400, max_retries 6. device: true, owner_verify: true.
