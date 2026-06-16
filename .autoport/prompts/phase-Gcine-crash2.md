# Phase Gcine-crash2 — the new-game intro cinematic STILL crashes mid-playback (kicks to phone home). Find + fix the NEXT crash. DATA/forensics, deploy-verified, NO grind.

## The bug (owner, 2026-06-16)
The prior fix (66ef643c4, target-racer-h GOAL-ptr hi32) eliminated the ~75s crash, so the cinematic now plays FURTHER — but it **STILL crashes during playback and returns to the Android home screen** (app death). So there is a LATER crash point in the cinematic. The cinematic plays fine on x86 → arm64-specific. Likely the **same bug class recurring** (GOAL-pointer high-32-bit inconsistency / mips2c call contract) at a later scene, or a new arm64 codegen/runtime defect in a later cinematic code path.

## Reproduce (autonomous — cpad_inject works)
`cpad_inject` (headless cpad injection, confirmed working) can navigate the menu → NEW GAME → confirm overwrite, then let the cinematic PLAY THROUGH until it crashes. ANDROID_SERIAL=eae4df44 ONLY; adb `/home/emeric/Android/platform-tools/adb`; verify `mCurrentFocus=org.opengoal.gk.jak1`. Capture a FRESH `adb logcat` spanning the full cinematic until the crash → `.autoport/reports/Gcine2/crash-logcat.log`. (App-death-to-home = a native crash, sig11/SIGILL/SIGABRT — confirm which.)

## Mandate
1. **Capture the LATER crash forensics.** Let the cinematic play to the crash; capture the signal + fault address + backtrace. Use the crash-forensics method ([[feedback-a34-crash-forensics-loop]]): fp-walk + 24-word LR windows + byte-matcher to NAME the crashing function + the scene/cinematic stage where it dies. Note how far into the cinematic it gets (which scene). Check `/data/tombstones` (run-as).
2. **Localize the cinematic stage + code path** at the crash (which intro scene/process; the joint/anim/scene-player/camera code it runs). Pin the failing instruction + the GOAL function.
3. **Oracle-diff vs x86.** The full cinematic plays on `build-x86/game/gk` (start a new game there). Diff arm64-vs-x86 at the crash site → name the arm64 mechanism (GOAL-ptr hi32 again? a different class — idiv/mod, float-compare, field-offset, 128-bit, regalloc-across-BLR, mips2c noop?).
4. **Fix the arm64 mechanism.** goalc/codegen → regen+sync affected CGO/DGOs; engine C++ → clean-rebuild. Boot-CGO change → FULL consistent rebuild ([[feedback-game-cgo-rebuild-unsafe]]).
5. **Verify.** CLEAN rebuild + deploy + `.autoport/lib/deploy_verify.sh eae4df44` PASS. Then reproduce NEW GAME (cpad_inject) → the cinematic **plays FULLY through to gameplay, no crash, no return-to-home**. Regression: title/intro still crash-free.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. No standalone boot-CGO push. Oracle repo + `.autoport/gold/` read-only. NO screenshot/video grind (it filled the disk). Don't touch the parked menu placement. (Cinematic camera/cadence/pose-glitch + water/green-glow are SEPARATE tasks — fix only the CRASH here.)

## Validator (`phase-Gcine-crash2.sh`)
PASS requires: `.autoport/reports/Gcine2/crash-logcat.log` + a `Gcine2-crash-fix-summary.md` (≥60 lines) naming the crash function + scene + arm64 mechanism + oracle-diff + fix; a real code change; x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; a fresh NEW-GAME run (cpad_inject) with **0 sig=11/SIGILL/SIGABRT through the full cinematic** and boot/run sustained (frame well past the prior crash point, e.g. ≥ 9000). "Cinematic plays fully through" is OWNER eye-confirmed.

## Max settings
`max_turns: 1500`, `max_retries: 3`.

## Strategic note
Name the new crash first (forensics + how far the cinematic got). It's likely the same GOAL-ptr-hi32 / mips2c-contract class recurring in a later scene — check that pattern before assuming a new one. The whole loop is autonomous via cpad_inject; owner eye-confirms the full play-through.
