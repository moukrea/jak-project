# Phase A39 — capture run: the fix is in, photograph the boot

## Where we are

A38 root-caused and FIXED the last named blocker (commit 6355ed1fe): `setup-blerc-chains-for-one-fragment` was noop-bound, returned 0 into `(-> global-buf base)`, and the DMA cursor swept all of GOAL memory at 152 KB/frame — the single mechanism behind every residual crash, the font SIGILL, and l0-tfrag's death (tris pinned ≤82 by swept refs). The blerc pair is now bound REAL. The tripwire (property-gated `debug.opengoal.a38.tripwire`, OFF by default) proved the walk and was disarmed. A38's three attempts all failed ONLY the screencap gate: the device keyguard was up (user asleep). Read `.autoport/reports/A38-fix-summary.md` for the full evidence chain.

## Mandate (narrow — this is a capture phase, not a fix phase)

1. Verify the committed state builds clean: `bash .autoport/lib/d3_build.sh` (libgk.so), APK assemble + install (`adb install -r -g`, pre-approved). CGOs in APK assets must match `out/jak1-arm64/iso/` (sync if stale).
2. Confirm keyguard is DOWN (`dumpsys window` → `mDreamingLockscreen=false`); if locked, wait/poll — do NOT burn the attempt; log progress to the report meanwhile.
3. Final boot(s), tripwire OFF: routed logcat → `.autoport/reports/A39-routed-logcat-runN.log`. Expect: GK-DIAG 0, single PID, `A35-RENDER frame=N` ≥ 300, **tris JUMP to tens-of-thousands sustained** (l0-tfrag alive), no font SIGILL.
4. Screencaps at 5/10/15/20/24/28/32/45/60 s → `.autoport/reports/A39-device-*.png` with `mCurrentFocus` before AND after each tick → `A39-focus-runN.txt`. Reversible disables (xiaoji ×2, sshxmobile, ghplus) and RE-ENABLE after. If a tick is polluted (camera app/accessibility/home), note and rely on clean ticks.
5. **A39-fix-summary.md** (≥80 lines): boot metrics vs A38 baselines, frame inventory (which tick shows what), reference the A38 evidence chain. Honest verdict: real content (name the scene) or precise residual (e.g., geometry present but textures wrong → name the texture stage).

## Rules

Locks and anti-cheat identical to A38 (x86 boots; qemu ≥ 675; no fake frames; supervisor re-captures independently; preserve all fixes). `export ANDROID_SERIAL=eae4df44` only.

## Validator

A38's gates with A39 names (report ≥ 80, ≥1 A39-device-*.png, frame ≥ 300 + tris > 0 in newest A39 logcat, nm renderer syms, gk_log_pipe, no forbidden edits).

## Max settings

`max_turns: 800`, `max_retries: 3`. This should take ~30-60 minutes of real work.
