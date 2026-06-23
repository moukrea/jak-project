# Gcrash-mouche — OWNER VERIFICATION REQUESTED

**Deployed build:** HEAD `4def0ff50` libgk.so (arm64), package `org.opengoal.gk.jak1`,
device `eae4df44` (Redmi Note 9 Pro). Provably on-device via `deploy_verify.sh`.

## What to do
1. Launch the game, start a NEW GAME, and play to **Geyser Rock** (the first level).
2. Break the **red crates** that release the Precursor scout-flies (mécamouches), and
   **collect a scout fly** (a "buzzer").
3. Report what happens at the moment of collecting the fly:
   - Does the game **crash to the home screen**? (the original bug)
   - Does the game **freeze / hang** (frozen image, must force-close)?
   - Or does it **collect the fly and keep playing** (the desired outcome)?

If convenient, repeat for **5 scout flies** and report whether ANY collect crashes/hangs.

## Why owner verification is required (honest status)
The scout-fly collect crash was **reproduced deterministically on-device** and proven to
be an **arm64-specific** translation defect (the identical collect runs **crash-free on
desktop x86**, reaching the 7-fly milestone reward — so the game logic is fine; only the
arm64 build diverges).

The crash is the buzzer **entering its `pickup` state**: `enter-state` reads a state
`code` pointer of 0 and jumps to EE+0 (`sig=4` SIGILL). A fault-handler repair for that
SIGILL is now in the build, but the underlying cause is a **concurrent / SP-relative
corruption of the live GOAL process stack** during the collect (it follows the stack
across every heap; it is NOT the previously-suspected manipy "fly-to-HUD" HUD-merc draw,
which was tested 8× on-device and is crash-free). Because that stack corruption defeats a
clean repaired resume, I could **not** programmatically produce ≥5 crash-free collects
honestly — so the real-world behavior on the deployed build needs your eye.

**Expectation to set:** with the partial fixes, the collect may still **freeze** rather
than collect cleanly. If it does, that is the documented residual — a focused follow-up
phase is recommended to catch the exact arm64 stack-stomp writer (thread-filtered
mprotect / hardware data-watchpoint on the buzzer process stack during the collect).

A gated repro hook is retained for that follow-up (off by default; no effect on normal
play): `adb shell setprop debug.opengoal.f1.warp 1` + `setprop debug.opengoal.mouche.buzz 1`
spawns + collects a real buzzer in Geyser Rock for deterministic re-reproduction.
