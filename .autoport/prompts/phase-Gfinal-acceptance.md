# Phase Gfinal-acceptance — one consolidated device run verifying ALL owner-reported defects are fixed on the current HEAD (regression-proof)

## Why
All 9 owner-reported defects were fixed/verified individually this session, and the device was
consolidated onto a fresh HEAD set ([[consolidate-fresh-head-known-good]]). The birds fix
(`sparticle.cpp`, commit 0ce8478fe) is a libgk change that landed AFTER the consolidation. This
phase is a single combined acceptance run on the CURRENT HEAD build to (a) regression-proof the
birds libgk against the other visuals, and (b) produce one trustworthy artifact showing the owner's
complete report is fixed on the exact build they will re-test. NO new fix expected — this is
verification. NO pixels; reuse the deterministic metrics each phase established.

## What to verify (one fresh-HEAD device session; deterministic dumps, no pixels)
Deploy/confirm fresh HEAD (deploy_verify), boot, and over a title beat + into gameplay dump and
check, on device, ALL of:
1. **Boot→gameplay**: reaches frame ≥ 10500, foreground=jak1, **0 sig(4/6/11)/Fatal**.
2. **Sun corona** size == original (24576) — not a 20% glow ([[gsun-halo]]).
3. **Particles**: vproc3d > 0 (e.g. 32..193); **night stars** starc > 0 ([[gparticles-stars]]).
4. **Birds**: bird-bob-func bob-y ADVANCES per frame (Δ≠0; dispatches > 0) ([[gbirds-anim]]).
5. **Menu**: element X/Y SPREAD (PART0=0 / PART1≈−220 / PART2≈+195 @2400x1080), not bunched ([[gmenu-ui-placement-state]]).
6. **Near water**: near-camera ocean chunks draw DETAILED (verts > 0, not flat/0) ([[gwater-state]]).
7. **Cinematic**: the NEW-GAME save→overwrite path completes crash-free to gameplay (the f30-0 /
   merc-trampoline fixes hold) ([[gfix-cinematic-crash]], [[arm64-ffi-xmm8-15-trampoline]]).
- goal_src stays 1-to-1 (no edits); x86 unchanged.

## Validator (`phase-Gfinal-acceptance.sh`) PASS requires
1. `.autoport/reports/Gfinal-acceptance/acceptance.txt`: one device session citing the deterministic
   value for EACH of the 7 checks above (boot→gameplay frame ≥10500 + 0 crash; sun 24576; vproc3d>0
   + starc>0; bird bob Δ≠0; menu PART spread; near-water verts>0; cinematic completes). With
   `RESULT: ALL OWNER DEFECTS VERIFIED FIXED ON CURRENT HEAD (no regression)`.
2. ZERO `goal_src/**` edits (this is verification, not a fix); golden `.autoport/gold` pristine.
3. Fix-summary/report `.autoport/reports/Gfinal-acceptance-fix-summary.md` ≥60 lines summarizing the
   session per defect with the cited numbers; temp instrumentation removed.
4. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After the run, `bash .autoport/restore_knowngood_device.sh` (restores the fresh HEAD set). NO screenshot grind.

## Max settings
`max_turns: 1200`, `max_retries: 3`.
