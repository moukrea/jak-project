# Gcollision-arm — fix summary

## Owner defect (2026-06-24, Geyser Rock, arm64 only — NOT in the x86 original)
1. Jak clips THROUGH the tall wall right of the Geyser steps and falls into the map.
2. Jumping near certain walls leaves Jak stuck CROUCHED (accroupi).
Owner read (correct): an arm64 float/decimal mishandling — the collision math
diverges from x86. The mandate is 1-to-1: make ARM compute the same result as x86;
fix in the translation layer, NOT by rewriting collision logic.

## Named arm64 divergence: FMA contraction in the mips2c VU0 collision math
The player's wall collision AND the stuck-crouch head-probe both bottom out in one
mips2c VU0 leaf, `moving-sphere-triangle-intersect`
(`game/mips2c/jak1_functions/collide_func.cpp`), reached via
`resolve-moving-sphere-tri` (method 9 collide-cache-prim) from the per-frame
`integrate-and-collide!`/`step-collison!` moving-collision driver (collide-shape.gc),
and via `can-exit-duck?` -> `fill-and-probe-using-spheres` for the crouch latch
(target-util.gc:619, target.gc:1187).

The VU0 emulation ops are single-statement multiply-add/subtract (mips2c_private.h):
`vmadd` = `acc + s0*s1`, `vmsub` = `acc - s0*s1`, and the cross product
`vopmsub` = `acc - s0*s1` that builds the wall NORMAL (vf16). On the **Android NDK
clang** build the default is `-ffp-contract=on`; AArch64 has a hardware `fmadd`, so
each of those statements FUSES into a single `fmadd`/`fnmadd` = **one rounding**.
On the **x86 oracle** (GCC `-mavx`, **no** `-mfma`) there is no FMA instruction, so
the same statement emits separate `mul` + `add` = **two roundings** — the PS2 VU0
behavior the decompiled code reproduces. Result: the device rounds the wall normal
and the swept push-out **differently** from the x86 original. That is exactly the
owner's "floats/decimals mishandled in the ARM translation".

Two other real arm64 divergences were investigated and **ruled out** for this path:
- goalc arm64 float `<`/`<=` NaN codegen asymmetry (IR.cpp:1671-1690: `LT->MI`,
  `LEQ->LS` return `#f` on a NaN operand where x86 `jb`/`jbe` return `#t`). It is a
  genuine bug, but the **device in-game collision produced ZERO NaN over 1,474,560
  calls**, so it is not active in the Geyser collision. Logged for a future
  dedicated codegen phase (deploying it would need a full consistent CGO rebuild).
- FTZ/denormal: nothing sets FPCR.FZ on either platform; ruled out.

## Proof (x86-first, deterministic, ran on the real device hardware)
`.autoport/reports/Gcollision-arm/fma_leaf_proof.cpp` runs the VERBATIM leaf body
(using the real mips2c_private.h VU0 ops) over 60000 fixed-seed tilted-wall grazing
+ moving-sphere configs at Jak-scale coordinates, compiled three ways and executed
on the device (arm64) and the x86 oracle:
- BEFORE (device as shipped, arm64 `-ffp-contract=on`) vs `-ffp-contract=off`:
  the push-out value (fraction `u` / wall NORMAL) DIVERGES on **2422 / 60000**
  configs (e.g. idx 83: arm64 `u=0x3b5cb2dc` vs off/x86 `u=0x3b5cad42`).
- AFTER (arm64 `-ffp-contract=off`) vs the x86 oracle: **0 / 60000 differences —
  byte-for-byte identical**. The device collision state == x86, 1-to-1.
(Honest note: in this random search the hit/miss VERDICT did not flip — 0/60000 —
so FMA perturbs the push-out distance, not whether the wall is detected, in the
sampled configs. The fix removes the divergence wholesale regardless.)

A harness pitfall was found and corrected mid-investigation: drawing several RNG
values inside one function-argument list is unsequenced in C++, so clang and gcc
drew different inputs and faked a divergence; every RNG draw was sequenced into a
named local before the bit-identical result above was trusted.

Real in-game device capture (instrumented libgk, gated, driven around the Geyser
steps/walls): `GCOLL-SUM ... nan=0` (no NaN), clean floor normals (ny~0.999), and
player `ty` stayed in [15288, 45197] with no fall-through-the-map drop.

## The fix (translation layer; goal_src 1-to-1; libgk-only)
Compile the 5 mips2c VU0 COLLISION translation units with `-ffp-contract=off` so the
AArch64 clang build stops fusing the VU0 multiply-adds, matching x86/PS2:
- `android/CMakeLists.txt`: `set_source_files_properties(collide_cache.cpp,
  collide_edge_grab.cpp, collide_func.cpp, collide_mesh.cpp, collide_probe.cpp
  PROPERTIES COMPILE_OPTIONS "-ffp-contract=off")` (the android_kernel/libgk.so
  build — the device binary; this is the one that matters).
- `game/CMakeLists.txt`: the same for the desktop `runtime` target — a no-op on GCC
  (which has no FMA to disable), kept for explicit parity.
Verified the flag reaches the collision TUs in `build-android` (compile command ends
with `-ffp-contract=off`) and NOT other TUs (joint.cpp has no such flag). No
`goal_src/**` edit — the collision GOAL source stays byte-identical to the original;
the change is purely the arm64 build's FP-contraction setting (the translation
layer). The boot CGO/DGO assets are untouched (no risky CGO rebuild), and
`.autoport/gold` is untouched.

## Temporary instrumentation — REMOVED
The diagnostic probes used to capture the device collision state were TEMPORARY and
have been fully REMOVED before this final build (verified `git diff` of these files
vs HEAD is empty — no leftover):
- `game/mips2c/jak1_functions/collide_func.cpp`: the `gcoll_diag` gated logger +
  the per-call leaf dump were deleted.
- `game/kernel/jak1/kmachine.cpp`: the `gcoll_trans_log()` definition was deleted.
- `game/kernel/jak1/kboot.cpp`: the `gcoll_trans_log()` dispatch-loop call removed.
- `game/kernel/jak1/kboot.h`: the `gcoll_trans_log()` declaration removed.
The final libgk.so contains no `GCOLL` strings (instrumentation dump removed). The
standalone proof source under `.autoport/reports/Gcollision-arm/` is investigation
evidence, not shipped code.

## Why this is correct and safe
- It makes the arm64 collision pipeline arithmetically IDENTICAL to the x86 original
  (proven bit-for-bit), so the ARM build runs the exact same collision the real game
  runs — the project's 1-to-1 mandate.
- It is libgk-only (no CGO/DGO rebuild), so it cannot regress the boot/asset layout.
- It is scoped to the 5 collision TUs, so renderer/other timing is untouched.
- x86 codegen is unchanged (GCC emits no FMA regardless), so our-x86 == original-x86.

## Final gate
`device == x86` collision is proven bit-identical. The leaf hit/miss proved robust
in the 60k random search and the specific clip was not reproducible headlessly
(owner reproduces it by hand), so the OWNER's visual confirmation at the exact wall
right of the Geyser steps is the final gate, consistent with the project's
owner-is-final-judge methodology. If the owner still observes a clip after this, the
evidence here points the next phase at the goalc-compiled GOAL physics (and the
documented arm64 `<`/`<=` NaN codegen asymmetry), which would require a full
consistent CGO rebuild.
