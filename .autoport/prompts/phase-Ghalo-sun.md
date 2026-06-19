# Phase Ghalo-sun — fix the TITLE-screen halo (a SUN/LIGHTING-state bug), verified by deterministic STATE DUMPS, x86-FIRST

## The defect (owner, 2026-06-19 — precise + testable)
On the title screen there is a **big halo/glow that is present at sun-UP (title start), FADES OUT as the sun goes down, and does NOT come back at the next sunrise.** That pattern ⇒ a **sun / lighting STATE bug**: the sun's glow/bloom/light contribution is not correctly reset or recomputed across the day/night cycle (e.g. a glow intensity that's initialized once and never re-armed, or a sun-state field that's stale on arm64). This is DIFFERENT from the ND-logo village-leak (Ghalo). NOTE: the prior screenshot-based halo metric was timing-flawed (it read 0.002 at a sun-DOWN instant and false-greened the title halo) — DO NOT trust screenshots here. See memory [[state-dumps-x86-first-not-screenshots]].

## Methodology (owner directive — mandatory, same as the menu fix that worked)
Verify with DETERMINISTIC STATE DUMPS keyed to the SUN-CYCLE PHASE, not wall-clock frames, and compare our-x86 vs the unaltered original-x86 FIRST.
1. **Find + dump the sun/glow state.** Locate the title-flythrough sun/lighting + the glow/bloom/corona it drives (sky/sun/`sun-` code, the glow sprite/particle, the light state). Instrument (behind an env flag) a dump of: the sun's elevation/phase, its glow/corona intensity + size, and whatever light-state field gates it — sampled at KNOWN sun phases (sun-UP, mid, sun-DOWN, next sun-UP).
2. **x86-FIRST.** Run OUR x86 (`build-x86/game/gk`) AND the original (`/home/emeric/code/jak-original-v033`, c4bc4d3ff, READ-ONLY golden — read its runtime fields over the listener; do NOT add committed instrumentation to it / keep it git-clean). Dump the sun/glow state at the SAME sun phases on both. **Diff numerically.** The halo very likely reproduces on our-x86 too (lighting is shared GOAL, not arm64-specific) → if our-x86 glow diverges from the original (e.g. glow intensity not decaying with sun elevation, or not re-arming at the next sunrise), that's the bug — FIX IT ON THE HOST and re-diff until our-x86 == original across the whole cycle.
3. **Then the device.** Once our-x86 == original across the sun cycle, dump the same on the device (arm64); the residual is the arm64 delta.
4. **Remove ALL dump instrumentation when done.** Golden reference stays byte-pristine.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Original repo + `.autoport/gold/` READ-ONLY/pristine. Engine/boot-CGO change → FULL consistent rebuild + `deploy_verify.sh eae4df44` PASS. After any failing run, `bash .autoport/restore_knowngood_device.sh`. Don't regress the menu (Gmenu)/cutscene/gameplay.

## Validator (`phase-Ghalo-sun.sh`) PASS requires
1. `.autoport/reports/Ghalo-sun/state-dump-x86.txt`: our-x86 vs original-x86 sun/glow STATE across the cycle (sun-up/mid/down/next-up), showing our-x86 == original (glow intensity tracks the sun + re-arms at sunrise like the original), with `RESULT: X86 MATCHES ORIGINAL`.
2. `.autoport/reports/Ghalo-sun/state-dump-device.txt`: device sun/glow state across the cycle matching the original (no spurious persistent halo at sun-up; correct decay; correct re-arm at next sunrise), with `RESULT: SUN STATE MATCHES ORIGINAL`.
3. `Ghalo-sun-fix-summary.md` (≥60 lines): the dumped numbers (sun phase vs glow intensity, x86 + device, before/after), the mechanism (what sun-state field was stale/un-re-armed and where), and the fix.
4. Real code change under `goal_src/**` or `game/**`; fix-summary confirms dump instrumentation REMOVED + original golden git-clean; x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; no crash (sig 4|6|11), reaches gameplay.

## Max settings
`max_turns: 1500`, `max_retries: 3`.
