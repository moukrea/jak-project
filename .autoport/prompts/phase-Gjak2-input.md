## WORK ECONOMY: MANAGER plans/verifies; delegate researcher/implementer/tester. Parallelize.

# Phase Gjak2-input — jak2 gameplay input: Jak doesn't move (owner-blocking)

## Owner report (2026-07-08, Redmi, shipped build)
In-game: ANIMATIONS PLAY but Jak does NOT move — no walk, no jump, nothing responds; plus a slight
CONSTANT SLIDE always in the same direction. The Gjak2-ingame report claimed "input path healthy"
from cpad ZERO-DRIFT dumps — that measured drift, not DELIVERY. Reality: movement input never
reaches the game (and a residual constant analog value causes the slide).

## Diagnosis leads
 1. jak1's touch-overlay->cpad injection path vs jak2's: is the overlay wired to the jak2 runtime
    (game-aware pad glue)? jak1 needed a whole input mandate (F1d) — check what jak1-specific pad
    plumbing was never ported (pc-pad/cpad binds in the jak2 pc-* surface, a17 pad helpers).
 2. The constant slide = a nonzero analog default (uncentered stick value / wrong neutral byte) in
    whatever cpad struct jak2 reads — find the neutral encoding difference jak1 vs jak2.
 3. State-dump the cpad values our-x86 (keyboard/controller works there?) vs device while pressing
    overlay controls: prove where the values die.

## Verify (device eae4df44): Jak walks/jumps/spins via the touch overlay + a bluetooth/usb pad if
available; no idle slide (neutral centered); 2-3 min free movement video, mCurrentFocus=jak2,
crash-free. x86 input unaffected.
## Report .autoport/reports/Gjak2-input/report.txt `RESULT: JAK2 INPUT <verdict>`
## Locks: ANDROID_SERIAL=eae4df44; engine goal_src untouched; gold READ-ONLY; full consistent builds.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.
