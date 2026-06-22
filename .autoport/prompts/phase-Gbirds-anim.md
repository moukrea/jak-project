# Phase Gbirds-anim — birds over the tower are static (not animating) — find the anim-advance divergence (x86-first, no pixels)

## The defect (owner, 2026-06-21)
On the title screen the **birds flying over the tower appear but are frozen** — static objects, no
wing/flight animation. They now render (an improvement) but their animation doesn't advance.

## Re-baseline on the fresh consolidated HEAD FIRST
The device now persistently runs a fresh consistent HEAD set ([[consolidate-fresh-head-known-good]]),
and the last several "defects" (sun/rays/particles/menu/water) were stale-deployment artifacts
already correct on HEAD. **Confirm fresh HEAD and re-measure the birds before assuming a code bug** —
they may already animate. If still frozen on the fresh consolidated build, it's a real bug.

## Methodology — deterministic ANIM-ADVANCE dump, x86-FIRST, NEVER pixels
Dump the metric that reflects the defect: the **bird process's animation frame / joint-mod /
ja-frame-num advancing per game frame** (and the bird process's update being called). Compare on
**original-x86 (.autoport/gold)**, **our-x86 (HEAD)**, **device**.
1. Find the bird element (the title flying-bird process / skelgroup + its `ja` animation channel).
2. Dump its anim frame-num (and skeleton joint motion) across consecutive frames, 3-way.
3. our-x86 vs original-x86 FIRST (1-to-1; if our-x86 frozen too, a source hack/codegen bug → fix in
   the right layer). device vs original: if the device bird anim-frame is STUCK (doesn't advance) while
   x86 advances → an arm64 translation defect (anim clock not advancing, a frozen joint-mod, an
   arm64 float/interp bug in the anim update). Fix in the translation layer (`goalc/**`/`game/**`/
   `game/mips2c/**`/`android/**`), NOT goal_src.
4. End state: device bird anim-frame advances per frame matching the original; our-x86 == original-x86.

## Validator (`phase-Gbirds-anim.sh`) PASS requires
1. `.autoport/reports/Gbirds-anim/birds.txt`: per-frame bird anim-frame/joint advance for original-x86,
   our-x86, device — our-x86 == original-x86 (1-to-1), a calibrated BEFORE where the device anim-frame
   is STUCK (Δ≈0 across frames), and an AFTER where it advances matching the original. With
   `RESULT: BIRDS ANIMATE MATCHING ORIGINAL (device, 1-to-1 source)`.
2. our-x86 == original-x86 explicitly; any `goal_src/**` edit must be a documented pristine revert
   (else fix is in `goalc/**`/`game/**`/`game/mips2c/**`/`android/**`).
3. Fix-summary `.autoport/reports/Gbirds-anim-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh` (now restores fresh HEAD).
NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
