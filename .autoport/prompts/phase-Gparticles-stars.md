# Phase Gparticles-stars — particles "not working" + no stars at night (title) — verify on fresh HEAD, fix the TRANSLATION layer

## The defect (owner, 2026-06-21)
On the title screen the owner reports **particles don't appear to work** and **no stars are
visible at night**. A prior phase (`Gd2`) claimed it re-enabled `sp-process-block-3d` and measured
a BUILDER COUNT — but the owner saw nothing. That was a **proxy false-green** ([[proxy-dumps-false-green]],
[[merc-census-blind-to-invisibility]]): "the builder ran" ≠ "particles are emitted, alive, and
on-screen."

## Re-baseline FIRST (the sun was already fixed on HEAD — likely the same story)
The sun "halo" turned out to be a STALE/MIXED DEPLOYMENT: on a correctly-deployed fresh HEAD the
sun already matched the original ([[gsun-halo]] / [[deploy-landing-guard]]). The FFI xmm fix
([[arm64-ffi-xmm8-15-trampoline]]) + the Gd2 builder un-noop are in HEAD. So **deploy fresh HEAD
(deploy_verify) and re-measure before concluding** — particles/stars may already render on HEAD.

## Methodology — DETERMINISTIC counts of ACTUAL output, x86-FIRST, NEVER pixels
Dump the metric that reflects the defect — **the number of particles actually EMITTED, ALIVE, and
SUBMITTED-VISIBLE** (post enable-mask/cull, on-screen), and for stars the **star sprites actually
drawn at night** — NOT builder invocations. Compare on **original-x86 (.autoport/gold)**,
**our-x86 (HEAD)**, **device**.

1. Particles: dump live `sparticle` count + the per-frame emitted/drawn 2D+3D particle counts
   (sprite-2d / sp-process-block / the actual draw submission), title beat, 3-way.
2. Stars: find the night-sky star element (sky star sprites / `*night*` sparticle), dump the drawn
   star count at a NIGHT beat, 3-way.
3. **our-x86 vs original-x86 FIRST** — must be identical (1-to-1; if not, a source hack diverged →
   revert to pristine). **Device vs original** — the divergence (device count = 0 / far below
   original) localizes the layer: arm64 mips2c builder still noop'd (un-noop in
   `mips2c_table_jak1_arm64.cpp`), an arm64 codegen drop, or a GLES sprite draw gap. Fix THERE.
4. `goal_src/**` stays 1-to-1 (revert-to-pristine only if a prior hack diverged it).

## Validator (`phase-Gparticles-stars.sh`) PASS requires
1. `.autoport/reports/Gparticles-stars/parts.txt`: per-frame ACTUAL emitted/visible particle count
   AND night star count for original-x86, our-x86, device — our-x86 == original-x86 (1-to-1), a
   calibrated BEFORE where device count ≈ 0 (or << original), and an AFTER where device counts
   match the original (within tolerance). With `RESULT: PARTICLES+STARS RENDER MATCHING ORIGINAL
   (device, 1-to-1 source)`. Counts must be ACTUAL emitted/drawn, NOT builder invocations.
2. our-x86 == original-x86 explicitly; any `goal_src/**` edit must be a documented pristine revert
   (else the fix is in `goalc/**`/`game/graphics/**`/`game/mips2c/**`/`android/**`).
3. Fix-summary `.autoport/reports/Gparticles-stars-fix-summary.md` ≥60 lines; temp instrumentation
   removed; `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
