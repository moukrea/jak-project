# Phase Gcine-crash3 — RESIDUAL new-game cinematic crash: it now survives the Gol/Maia close-up cut (Gcine-crash2) and the NaN pose-blink (Gcine-pose) but STILL crashes a bit later IN THE SAME Gol/Maia portal scene (returns to Android home). Verify on a LONG run, then fix. DATA/forensics, deploy-verified, NO grind.

## The bug (owner, 2026-06-16, eyes on device)
The new-game intro cinematic gets FURTHER than before but **still crashes**. Owner pinpoint: it now gets PAST the Gol/Maia portal villain close-up cut (the Gcine-crash2 fix) and past the pose-blink (the Gcine-pose libgk.so NaN-bone guard, 60ba2f477) — but it **crashes a few beats LATER in that same pinkish-halo Gol/Maia portal scene**, kicking back to the phone home screen (app death = native crash sig 11/6/4). Plays correct on x86 ⇒ arm64-specific.

CRITICAL CONTEXT — why this wasn't caught: Gcine-crash2 and Gcine-pose both "passed" on logs that only reached ~frame 9420-9960 (right at `GAMEPLAY: enter misty`, the Gol/Maia scene edge). The crash is JUST PAST that capture window. **This phase's run MUST capture far longer** — past the entire Gol/Maia scene into sustained, confirmed gameplay — and prove the app is still foreground/alive at the end (no return-to-home).

## Reproduce (autonomous — cpad_inject works) — LONG capture is mandatory
`cpad_inject` (headless cpad injection, confirmed working) navigates the menu → NEW GAME → confirm overwrite, then lets the cinematic PLAY THROUGH. ANDROID_SERIAL=eae4df44 ONLY; adb `/home/emeric/Android/platform-tools/adb`; verify `mCurrentFocus=org.opengoal.gk.jak1` BEFORE trusting any frame ([[feedback_device_screencap_foreground_check]]). Capture a FRESH `adb logcat` spanning the FULL cinematic AND well into gameplay (do NOT cut the capture at frame ~9960 — run it long, e.g. several minutes past `enter misty`) → `.autoport/reports/Gcine3/crash-logcat.log` for the repro. At end-of-run, record `mCurrentFocus` to `.autoport/reports/Gcine3/foreground-at-end.txt` (this is the owner's actual symptom: if it = com.miui.home the app died = crash; if = org.opengoal.gk.jak1 it survived). `-a` on every routed-logcat grep ([[feedback_grep_a_routed_logcat]]).

## Mandate
1. **Reproduce on the CURRENT (pose-fixed) HEAD with a LONG capture.** First confirm the build on the device is HEAD (`deploy_verify.sh eae4df44`). Then run NEW GAME and let it play far past the Gol/Maia scene into gameplay. Two outcomes:
   - **It still crashes** → capture the signal + fault address + backtrace + the frame/scene it died at. Use the crash-forensics toolkit ([[feedback_a34_crash_forensics_loop]]: fp-walk + 24-word LR windows + byte matcher) to NAME the crashing function + the Gol/Maia scene stage. Check `/data/tombstones` (run-as).
   - **It does NOT crash** (the 60ba2f477 NaN-bone guard already fixed it) → prove it with the long clean run (foreground alive + frame well past 9960) and document that determination with the evidence. That is a valid PASS — the owner needs the long-window proof either way.
2. **If it crashes: localize + oracle-diff vs x86.** Which Gol/Maia-scene code path (the worker's Gcine-pose forensics already mapped the area: align-joint streaming, `cspace<-parented-transformq-joint!`, merc skeleton, the `l0-pris-merc` prismatic-merc envmap draw flagged in Gcine-crash2). Diff arm64-vs-x86 at the fault → name the arm64 class (GOAL-ptr hi32? mips2c noop? idiv/mod? float-compare? field-offset? 128-bit cc? regalloc-across-BLR? a NaN still escaping the pose-guard into the renderer/GPU?).
3. **Fix the arm64 mechanism.** goalc/codegen → regen+sync ALL affected CGO/DGOs ([[feedback_stale_asset_dgos]]). Engine C++/mips2c → clean rebuild. Boot-CGO is unsafe to push ([[feedback_game_cgo_rebuild_unsafe]]) — prefer a libgk.so/mips2c-boundary fix like Gcine-pose did. No `goalc/emitter/IGenX86_64.*`.
4. **Verify with the LONG run.** CLEAN rebuild + deploy + `deploy_verify.sh eae4df44` PASS. Then NEW GAME (cpad_inject), long capture: **0 native crash sigs (11/6/4)** across the whole log, highest frame **≥ 10500** (well past enter-misty 9960), and `foreground-at-end.txt` = `org.opengoal.gk.jak1` (NOT com.miui.home). Regression: title/intro still crash-free.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. No standalone boot-CGO push. Oracle repo `/home/emeric/code/jak-original-v033` + `.autoport/gold/` read-only. NO screenshot/video grind (it filled the disk — [[feedback_objective_frame_comparison]]). Don't touch the parked menu, camera/cadence, water, or green-glow (separate phases). CRASH only.

## Validator (`phase-Gcine-crash3.sh`)
PASS requires: `.autoport/reports/Gcine3/crash-logcat.log` + `.autoport/reports/Gcine3/foreground-at-end.txt` (= org.opengoal.gk.jak1) + a `Gcine3-fix-summary.md` (≥60 lines) naming the Gol/Maia scene + the investigation + (the arm64 fix mechanism + oracle-diff IF it reproduced, OR an evidenced "already fixed by 60ba2f477, verified by long run" determination); x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; a fresh long NEW-GAME routed-logcat with **0 sig 11/6/4**, highest frame **≥ 10500**, and app foreground at end. Owner eye-confirms the full play-through to gameplay.

## Max settings
`max_turns: 1500`, `max_retries: 3`.

## Strategic note
The owner already proved the symptom (return-to-home in the Gol/Maia scene), so the long capture + foreground-at-end check is the honest gate — never claim fixed on a log that stops at ~9960 again. The Gcine-pose forensics (merc/joint NaN, align-joint streaming, l0-pris-merc envmap) are your strongest leads. If the pose-guard already fixed it, prove that with the long run and move on.
