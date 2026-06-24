# Phase Gcollision-arm — Jak clips through walls / ends up crouched near walls (arm64 collision divergence, NOT in x86)

## The defect (owner, 2026-06-24, in-game Geyser Rock)
Two collision bugs that **do NOT happen in the original x86 build** → arm64-specific divergences:
1. **Wall clip-through:** to the RIGHT of the Geyser Rock steps (the ones whose edge-grab blue-lock
   was fixed) there is a **taller wall**. Jak can **clip THROUGH it and fall into/through the map.**
2. **Stuck crouched:** jumping near certain walls leaves Jak **crouched** (accroupi) — wrong state.
The owner's read (correct): likely **collision / state variables / floats (decimals) mishandled in the
arm64 translation** — the collision math diverges from x86.

## NON-NEGOTIABLE methodology — make ARM match x86; do NOT rewrite collision logic ([[porting-1to1-fix-in-translation-layers]])
Owner (verbatim intent): "pour corriger ce genre de trucs faut pas faire des implem full custom
sinon... c'est pas l'original qui tourne sous ARM mais une refonte — faut que ce soit EXACTEMENT le
même jeu sur ARM et x86." So: the collision GOAL/mips2c source stays 1-to-1; the bug is that the
arm64 EXECUTION of it computes a different result than x86 (a float-precision / rounding / codegen /
mips2c divergence). FIND that divergence and fix it in the TRANSLATION layer (goalc arm64 codegen,
mips2c, runtime) so arm64 collision == x86. NEVER tweak collision thresholds/logic to paper over it.

## Methodology — deterministic x86-first collision-state diff at the failing spots
1. Reproduce on device: drive Jak to the wall right of the steps (cpad_inject or a debug teleport to
   that position) and into it → capture the clip-through; and the jump-near-wall → crouch.
2. **x86-first:** at the SAME position/input on desktop x86, dump the collision state — the
   collide-cache / collide-shape-prim results, the wall collision plane/normal, the penetration
   resolution, Jak's `control` collision flags + the crouch/`tobot`/state, and the key FLOATS
   (positions, normals, dot products, the `1/det`-style math, time-step). x86 does NOT clip / crouch.
3. **device vs x86:** dump the SAME collision state on device at the same spot. Find the first value
   that DIVERGES (a float computed differently, a sign/compare that flips, a NaN/denormal, an
   mips2c #f-guard or modulo or LDP/bone-style class, an FTZ flush, a 32-vs-64 compare). That
   divergence is why the wall-collision resolves wrong (clip) and the crouch state latches.
4. Fix the named arm64 divergence in the translation layer. Re-verify: device collision state ==
   x86 at those spots → no clip-through, correct (non-crouched) state. x86 unaffected; goal_src 1-to-1.
   (These bugs may be a broad arm64 collision-float class — fixing the root likely helps elsewhere.)

## Validator (`phase-Gcollision-arm.sh`) PASS requires
1. `.autoport/reports/Gcollision-arm/collide.txt`: x86-first collision-state dumps at the wall-right-
   of-steps and the jump-near-wall spots — a calibrated BEFORE where device DIVERGES from x86 (the
   named float/codegen value) and Jak clips/crouches, and an AFTER where device collision state == x86
   and Jak does NOT clip through the wall and is NOT left crouched. With `RESULT: ARM COLLISION MATCHES
   X86 (no wall clip-through, no stuck-crouch)`. Name the arm64 divergence + the fix.
2. our-x86 == original-x86 (1-to-1); any `goal_src/**` edit must be a documented pristine revert (the
   fix should be in `goalc/**`/`game/mips2c/**`/`game/**`/`android/**`). Fix-summary
   `.autoport/reports/Gcollision-arm-fix-summary.md` ≥60 lines naming the divergence; temp
   instrumentation removed; `.autoport/gold` git-clean.
3. x86 `link finish: logo`; device boots to gameplay crash-free; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY. Keep device
awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1600`, `max_retries: 4`.
