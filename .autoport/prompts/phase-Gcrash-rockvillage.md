# Phase Gcrash-rockvillage — Rock Village: crash-to-home past the pontoons (after the buzzer crate)

## Why (owner 2026-07-03, playing the batched build on the connected device's twin path)
In ROCK VILLAGE (village2), after paying 90 orbs to the soldier/warrior to restore the pontoon
bridges, the path continues to a spot with a CRATE holding a scout fly (buzzer). Breaking the crate
works fine — but WALKING FURTHER past it crashes the game straight to the Android home screen.
For the NEXT pre-version (v4) — NOT the v3 eco/orb build. Hypothesis space: this is on the route
toward the Boggy Swamp / next-level boundary, so prime suspects are level streaming/load of the
adjacent level on arm64 (DGO load path), an undersized process stack in a border-area process
(the 256→512 class: jungle hopper a7c90ef2b, blue-eco launcher), an arm64 codegen divergence in a
process that only spawns there, or a merc/sparticle stomp from newly-streamed content. Do NOT
assume — reproduce and let forensics name it.

## Mandate — reproduce, forensics, 1-to-1 fix (the established method)
1. REPRODUCE on eae4df44: get Jak to the crash spot. The area is gated on the 90-orb payment —
   check goal_src for village2 continue points (village2-*, swamp-* names) and warp
   (debug.opengoal.level.warp) to the nearest point PAST the pontoons; if none lands there, set the
   game-progress flag for the payment via the debug/listener path or a prepared save, then walk the
   route (stick/cpad injection): pontoons → buzzer crate → onward until the crash. Capture: signal
   (sig 11/6/4, NOT background sig9), app-foreground-at-crash, full logcat, and capture WELL PAST
   the crash point (crash-capture-window rule). Cross-check the same route on the pristine x86
   golden (must be crash-free there).
2. FORENSICS: fp-walk + LR windows + byte matcher → name the faulting function + PC. Classify:
   arm64 codegen / mips2c / stack-size (check "enough stack") / DGO-streaming / renderer-stomp.
3. FIX in the translation layer (arm64-gated; goal_src non-pc + IGenX86_64.* + gold untouched),
   1-to-1. Re-verify: the full route (pontoons → crate → beyond, sustained past the old crash
   point) runs crash-free on device; prior fixes intact (collision/jungle/blue-eco/speed/camera/
   orbs); x86 link finish: logo. Full CONSISTENT build, deploy_verify PASS.
4. WRITE THE REPORT EARLY: as soon as the fix is device-verified, write report.txt from the
   evidence at hand, then keep refining. Do not leave it for last (storm-kill lesson).

## Report (`.autoport/reports/Gcrash-rockvillage/report.txt`) with `RESULT: ROCK VILLAGE PONTOON CRASH FIXED`
the repro route (how the 90-orb gate was crossed), the named faulting fn+PC + classification, the
fix (file:line), the crash-free AFTER run past the old crash point, prior fixes intact, x86 ok.
If not cleanly pinned: honest RESULT: ROCK VILLAGE CRASH ROOT NAMED + what's ruled out.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2200, max_retries 5. device: true, owner_verify: true.
