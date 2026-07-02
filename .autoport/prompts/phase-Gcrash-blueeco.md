# Phase Gcrash-blueeco — Forbidden Jungle blue-eco vent/fountain = instant crash-to-home

## Why (owner 2026-07-02, on his PERSONAL phone with the final complete APK)
In Forbidden Jungle, the BLUE ECO VENT/FOUNTAIN ("la fontaine d'eco bleue") causes an INSTANT crash to
the Android home screen. Everything else in the owner's playthrough was great ("le jeu est méga beau,
tout tourne bien"). This is a hard gameplay blocker in jungle. NOTE the history: a blue-eco PORTAL
crash was fixed long ago (arm64 divergence class); the jungle STACK crash (hopper, PROCESS_STACK_SAVE
256→512) was fixed in a7c90ef2b. This is a NEW/remaining crash tied to the blue-eco vent interaction
(likely the vent's particle/eco-collection/charge process on arm64).

## Mandate — reproduce, forensics, 1-to-1 fix (the established method)
1. REPRODUCE on eae4df44: warp to jungle (debug.opengoal.level.warp=jungle-start), drive Jak to the
   blue-eco vent (stick injection / cpad) and trigger it (stand in the fountain, collect blue eco).
   Capture the crash: signal (sig 11/6/4, NOT background sig9), app-foreground-at-crash, full logcat.
   Capture well PAST the crash point (crash-capture-window rule).
2. FORENSICS: fp-walk + LR windows + byte matcher → name the faulting function + PC. Classify:
   arm64 codegen / mips2c (sparticle? eco-collection? sound?) / stack-size (check "enough stack" —
   another undersized thread?) / renderer. Compare the same interaction on the x86 golden (loads fine?).
3. FIX in the translation layer (arm64-gated; goal_src non-pc + IGenX86_64.* + gold untouched),
   1-to-1. Re-verify: the vent interaction runs crash-free on device (sustained, well past the
   trigger), collision/jungle/speed/camera fixes intact, x86 link finish: logo.

## Report (`.autoport/reports/Gcrash-blueeco/report.txt`) with `RESULT: BLUE ECO VENT CRASH FIXED`
the repro (vent triggered), the named faulting fn+PC + classification, the fix (file:line), the
crash-free AFTER run past the trigger, x86 ok. If not cleanly pinned: honest RESULT: BLUE ECO CRASH
ROOT NAMED + what's ruled out.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2200, max_retries 5. device: true, owner_verify: true.

## SUPERVISOR NOTE (2026-07-02, during the Anthropic 529 storm) — WRITE THE REPORT FIRST
Prior attempts have ALREADY implemented + checkpoint-committed the fix (the 512 stack-class fix for the
blue-eco launcher) and ran crash-free AFTER runs — but the API storm keeps killing the session BEFORE
report.txt gets written (the finish line). On THIS attempt: (1) FIRST, reconstruct + WRITE
.autoport/reports/Gcrash-blueeco/report.txt from the existing evidence (git log/checkpoints, prior
attempt artifacts under .autoport/reports/Gcrash-blueeco/, the AFTER-run logs) — land the report EARLY;
(2) THEN re-verify anything missing (deploy_verify, a fresh AFTER run if evidence is stale) and update
the report. Do not leave the report for last.
