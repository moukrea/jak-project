# Phase Ginput-replay-realinput — capture the owner's REAL input (touch/gamepad) under the anchor, not just the headless injector

## The defect (supervisor-confirmed, 2026-06-28)
The v2 warp-anchored record drops the OWNER'S REAL input. Two owner re-captures (~20 min then ~2.5 h of
real play) recorded ALL-NEUTRAL (0 non-neutral across 333k frames). Ginput-replay-liverecord FALSE-GREENED:
it verified capture of the **headless cpad_inject path** (which survives the warp), NOT the owner's real
**touch-overlay / Bluetooth-gamepad merge** (`android_input_audio::get_cpad_state`). Supervisor reproduced
it autonomously: arm `debug.opengoal.f1.warp 1` + `debug.opengoal.pad_replay record`, send REAL Android
touch via `adb shell input swipe/tap` on the in-game overlay → the recorded `files/pad_demo.inputs` is
0% non-neutral. So under the warp anchor the live touch/gamepad merge never reaches the pad_replay tap;
only cpad_inject does.

## Lead
The f1.warp path (`(start 'play game-start)` + the Gcrash-mouche3 drive hook, kmachine.cpp:~931, and/or
the OG_F1_WARP machinery) likely overwrites the consumed pad with neutral AFTER the touch/gamepad merge
but BEFORE the pad_replay tap — or the tap/record under the warp reads a buffer that the real merge does
not feed (while cpad_inject writes a buffer it does). v1 (no warp) captured the owner's touch fine (61%
non-neutral), so the merge itself works; the WARP is what suppresses it. Find where the real merged input
is lost under the warp and ensure it reaches the pad_replay record tap, while keeping the deterministic
anchor + logic-frame index + rng reseed (determinism MUST still hold).

## Method (mandatory) — fix REAL input capture, verify with REAL input (adb input), NOT cpad_inject
1. Reproduce with REAL touch: arm warp+record, `adb shell input swipe`/`tap` on the overlay in-game,
   confirm the demo is all-neutral (the supervisor's repro).
2. Trace the consumed pad from `android_input_audio::get_cpad_state` (touch+gamepad merge) through
   CPadGetData to the pad_replay tap, under the warp. Find where the real merge is dropped/overwritten.
3. Fix so the real touch/gamepad merge reaches the record tap under the warp anchor (don't let the warp
   drive/flag neutralize it). Keep determinism (anchor, logic-frame index, rng reseed) intact.
4. VERIFY with REAL input, autonomously (NO owner, NO cpad_inject): arm warp+record, drive a known
   varied sequence via `adb shell input` (swipes for the stick + taps for buttons), confirm the demo is
   substantially NON-NEUTRAL; then REPLAY it and confirm record==replay bit-identical (determinism holds).
   Also confirm a real Bluetooth/SDL gamepad path is captured if feasible (or document the touch proof +
   that gamepad shares the same merge).

## Validator (`phase-Ginput-replay-realinput.sh`) PASS requires
1. `.autoport/reports/Ginput-replay-realinput/report.txt` with `RESULT: REAL INPUT CAPTURED UNDER ANCHOR`:
   the BEFORE (real touch all-neutral) reproduced; the drop point named; AFTER, a record driven by
   `adb shell input` (REAL Android touch, explicitly NOT cpad_inject) is non-neutral with
   `REAL INPUT CAPTURED: <N>/<M>` (M≥60, N≥M/3) AND replay==record bit-identical. The report must state
   the verification used `adb input` real touch events, not the headless injector.
2. goal_src 1-to-1; real host/runtime change; fix-summary
   `.autoport/reports/Ginput-replay-realinput-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake.
## Max: max_turns 1600, max_retries 5.
