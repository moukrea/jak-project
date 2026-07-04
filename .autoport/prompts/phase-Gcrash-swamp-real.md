# Phase Gcrash-swamp-real — Rock Village→Swamp crash STILL happens in real play (2nd false-green REOPEN)

## Why (owner 2026-07-05, v5 play-test) — the drive-hook repro is NOT faithful
The owner played v5 (which SHIPS the Gcrash-swamp-load fix 543b7739b) and the crash is "exactement
pareil" — crossing the pontoons toward the swamp STILL crashes to home. So the fix did NOT fix the
owner's crash. The supervisor's "independent A/B" used `debug.opengoal.target.drive` (a hook that
force-MOVES Jak's world position) — that reproduced SOME crash the fix cured, but NOT the owner's
real gameplay crash. The position-drive hook is therefore NOT a faithful repro; its crash and the
owner's crash are different. The part-group cleanup fix (543b7739b) stays in the tree (harmless) but
does NOT solve this.

## HARD RULE — reproduce with REAL controller input through the actual walk (no position-drive)
`debug.opengoal.target.drive` is BANNED as the repro/AFTER path (it forces position and diverges from
real physics/streaming — it fabricated the last false-green). Reproduce ONLY by:
  (a) REAL input: restore the 90-orb pontoons (task.close 33), then move Jak with actual pad/stick
      INPUT injection (the cpad/HID path, as in Ginput-replay), walking/jumping the pontoons the way
      the player does, until the swamp loads and it crashes; OR
  (b) the OWNER's save: if a faithful headless walk can't reproduce it, build an instrumented
      crash-capture build (tombstone + fp-walk + focus at fault, auto-saved) and have the OWNER walk
      the route to trigger it (he offered — he just needs 90 orbs; provide a debug orb-grant or a
      prepared save at the pontoons). Then do the forensics on HIS captured crash.
The AFTER proof must be the SAME faithful path (real input walk, or owner re-walk) crash-free past
the boundary — never a target.drive run.

## Mandate
1. Reproduce the REAL crash per the rule above. Capture signal (11/6/4), app-foreground-at-crash,
   full logcat past the point. Confirm it differs from the drive-hook crash (compare PC/fn).
2. Forensics: fp-walk + LR + byte-match → faulting fn/PC at the swamp-load moment. Classify
   (arm64 codegen / mips2c / stack / DGO-link / stomp). x86 golden same real route = crash-free.
3. FIX in the translation layer (arm64-gated; goal_src non-pc + IGenX86_64 + gold untouched), 1-to-1.
4. AFTER: the SAME faithful path (real-input walk or owner re-walk), crash-free well past the
   boundary, sustained. Prior fixes intact. x86 link finish: logo. Full CONSISTENT build,
   deploy_verify PASS.

## Report (`.autoport/reports/Gcrash-swamp-real/report.txt`) with `RESULT: SWAMP CRASH FIXED (REAL INPUT)`
the faithful repro method (real input walk or owner capture — NOT target.drive), the named faulting
fn/PC, why it differs from the drive-hook crash that 543b7739b cured, the fix (file:line), the
faithful AFTER run crash-free, prior fixes intact, x86 ok. Honest RESULT: SWAMP CRASH ROOT NAMED +
ruled-out is acceptable if a faithful repro can't be achieved headless (then hand off to the owner).

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; target.drive BANNED as proof; .autoport/gold READ-ONLY.
## Max: max_turns 2600, max_retries 6. device: true, owner_verify: true.
