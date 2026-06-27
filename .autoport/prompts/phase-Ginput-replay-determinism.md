# Phase Ginput-replay-determinism — make replay FAITHFULLY reproduce a real-gameplay recording

## The defect (owner verification, 2026-06-27)
Replaying a recorded REAL-gameplay demo does NOT reproduce the playthrough: on the device the owner sees
Jak performing the recorded moves but **at a completely different place / pointing the wrong direction
from the first seconds**. So the Ginput-replay harness records inputs faithfully (the scripted self-test
proved pad-state byte-identity) BUT the GAME trajectory diverges immediately — there is hidden
**non-determinism** the harness does not capture/restore. This **BLOCKS** the owner-demo collision diff
(Gcollision-replay-diff) and any x86-vs-arm64 state comparison: you cannot compare two runs on the same
input if the same input doesn't even reproduce on the SAME backend.

## Prime suspects (confirm/refute with data — don't assume)
1. **Tick-index desync (most likely):** the harness indexes inputs on its OWN monotonic counter
   incremented per controller-0 READ. That read also happens during boot / loading / cinematics / menus,
   whose duration in those reads VARIES run-to-run. So a gameplay input recorded at index N is replayed
   at a different GAME moment → "moves at the wrong place from the start". Fix: index record+replay by the
   **deterministic game-LOGIC frame** (the kernel update frame that advances only when game logic ticks),
   NOT the raw controller-read counter; or anchor the start on a game event so gameplay inputs align.
2. **Unrestored RNG:** the harness reseeds only `extra_random_generator`/pc-rand. The GOAL gameplay
   `rand-vu` seed and any other RNG source used by spawn/camera/physics may be uncaptured → divergence.
3. **Start-state / camera / spawn:** if recording starts from new-game, the spawn orientation / camera
   angle / initial state may be set with uncaptured variance; movement is camera-relative so a small
   initial camera delta → "wrong direction".

## Method (mandatory) — same-backend record-vs-replay state diff
1. Add a full game-state dump per game-logic frame (Jak position/velocity/orientation, camera angle/pos,
   the rng state, control state). RECORD a short real-gameplay clip (~30–60s, from new-game) WITH this
   dump → the record-trace.
2. REPLAY that demo on the SAME backend WITH the same dump → the replay-trace.
3. Diff record-trace vs replay-trace at matching game-logic frames. The **FIRST diverging frame + field**
   is the first non-determinism source. Fix it (capture+restore the seed/state, or fix the tick index).
4. Repeat until the record-trace and replay-trace are **bit-identical over the whole clip** on the same
   backend (this is the real determinism gate the scripted self-test never exercised).
5. Then verify with a LONGER real-gameplay clip (≥3–4 min) including movement, jumps, camera — replay
   must still match record. Document every non-determinism source found + how it is now captured/restored.

## Outcome / 1-to-1
Fix in the harness/runtime (translation/host layer + the deterministic-frame indexing); `goal_src`
1-to-1. If the fix changes the demo FORMAT (e.g. capturing more start-state), say so — the existing
`.autoport/demos/*.inputs` may then need re-recording (owner-in-the-loop) before the collision diff.

## Validator (`phase-Ginput-replay-determinism.sh`) PASS requires
1. `.autoport/reports/Ginput-replay-determinism/report.txt` with
   `RESULT: REPLAY REPRODUCES REAL GAMEPLAY (RECORD==REPLAY)`: a REAL-gameplay clip (NOT scripted),
   record-trace vs same-backend replay-trace **bit-identical** over the clip (state keyed by game-logic
   frame: Jak pos/orientation/camera), with the BEFORE divergence (first frame/field) and the
   non-determinism sources named + fixed. Both a short and a longer (≥3 min) clip.
2. goal_src 1-to-1; real host/runtime change; fix-summary
   `.autoport/reports/Ginput-replay-determinism-fix-summary.md` ≥60 lines; temp dump removed;
   `.autoport/gold` pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake.
## Max: max_turns 1800, max_retries 5.
