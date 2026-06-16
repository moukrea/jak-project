# Phase Gnewgame-crash — fix the crash when starting a NEW GAME (overwrite save → intro cinematic). DATA/forensics-driven, deploy-verified, NO screenshot grind.

## The bug (owner, 2026-06-16)
On the device: at the menu, **NEW GAME → overwrite current save → should play the intro cinematic, but it CRASHES.** This blocks actually starting the game. The cinematic plays fine on desktop/x86, so this is an **arm64 codegen/runtime bug** in the new-game / cinematic path. (The menu is visually bunched right now — PARKED separately — but it is FUNCTIONAL: NEW GAME can be selected.)

## Reproduce the crash (you need to reach NEW GAME)
The menu requires navigating to NEW GAME → confirm overwrite. Autonomous input has been a gap (F1d), BUT there is a **`cpad_inject`** file in the app data dir (`/data/data/org.opengoal.gk.jak1/files/cpad_inject`, from the F1d input work) — **investigate whether it drives the cpad** (file-based controller injection). If it works, use it to navigate menu → NEW GAME → confirm, autonomously. If it does NOT reach the cpad, FLAG that the OWNER must navigate to NEW GAME while you capture (the owner is available). ANDROID_SERIAL=eae4df44 ONLY; adb `/home/emeric/Android/platform-tools/adb`; verify `mCurrentFocus=org.opengoal.gk.jak1`.

## Mandate
1. **Capture the crash forensics.** Reproduce (via cpad_inject or owner), capturing a FRESH `adb logcat` through the crash → `.autoport/reports/Gnewgame/crash-logcat.log`. Extract: the signal (sig11/SIGILL/SIGSEGV), the fault address, and the backtrace. Use the crash-forensics method ([[feedback-a34-crash-forensics-loop]]): fp-walk + 24-word LR windows + byte-matcher to NAME the crashing function + the exact instruction. Check `/data/tombstones` (run-as) too.
2. **Localize the new-game/cinematic path** in code: the menu NEW GAME selection (`engine/ui/progress/progress.gc` ~1163 "start a new game"), the save overwrite, and the intro-cinematic trigger (the scene/process that plays it). Pin where the crash occurs relative to this path.
3. **Oracle-diff vs x86.** Start a new game on `build-x86/game/gk` — it plays the cinematic without crashing. Diff the arm64 vs x86 behavior at the crash site to pin the arm64 mechanism (a known bug class: idiv/mod, float-compare, field-offset, 128-bit cc, regalloc-across-BLR, mips2c noop, etc. — name which).
4. **Fix the arm64 mechanism.** If it's a goalc/codegen change, regen+sync the affected CGO/DGOs; if engine C++ (libgk.so), clean-rebuild. (Per [[feedback-game-cgo-rebuild-unsafe]], boot-CGO changes need a FULL consistent rebuild.)
5. **Verify.** CLEAN rebuild + deploy + run `.autoport/lib/deploy_verify.sh eae4df44` (device must provably run the fresh HEAD build). Then reproduce NEW GAME → the **cinematic now plays, no crash** (via cpad_inject or owner). Regression: title/intro still boot crash-free.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. No standalone boot-CGO push (full consistent rebuild). Oracle repo + `.autoport/gold/` read-only. NO screenshot/video grind (it filled the disk). Don't un-park / touch the menu placement (separate task).

## Validator (`phase-Gnewgame-crash.sh`)
PASS requires: `.autoport/reports/Gnewgame/crash-logcat.log` + a `Gnewgame-crash-fix-summary.md` (≥60 lines) naming the crashing function + the arm64 mechanism + the oracle-diff + the fix; a real code change; x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASSES (fresh HEAD on device); a fresh device run reaching/attempting NEW GAME shows **NO sig=11 at the cinematic** (the crash signature is gone) and boot stays crash-free (frame≥300). The "cinematic actually plays" is OWNER-verified by eye (via cpad_inject if it works, else owner navigates).

## Max settings
`max_turns: 1200`, `max_retries: 3`.

## Strategic note
First get the crash NAMED (forensics) — that's 80% of the fix. The cinematic works on x86, so it's an arm64 mechanism in a code path that only the new-game flow exercises. cpad_inject (if functional) makes the whole loop autonomous; otherwise loop the owner in for the repro + final eye-check.
