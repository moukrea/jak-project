# Gcollision-arm — working notes (investigation log)

## Defect (owner, 2026-06-24, Geyser Rock, arm64-only — NOT in x86 original)
1. Jak clips THROUGH the tall wall right of the Geyser steps and falls into the map.
2. Jumping near certain walls leaves Jak stuck CROUCHED (accroupi).
Owner read: arm64 float/decimal/codegen mishandling diverging from x86.

## Collision path (Researcher A, verified)
- Player root = `collide-shape-moving`; per frame: `integrate-and-collide!`
  (collide-shape.gc:872) → `step-collison!` (777) → per-cache-prim
  `collide-with-collide-cache-prim-{sphere,mesh}` → **mips2c leaf
  `moving-sphere-triangle-intersect` (collide_func.cpp:266..)** which returns the
  swept hit fraction `u` (miss sentinel -1e8) + the wall NORMAL (vf16).
- Wall push-out applied in GOAL `target-collision-reaction` (collide-reaction-target.gc:119):
  uses best-u to advance trans; deep-penetration 3-unit normal shove; wall-vs-ground
  decision `(< (fabs surface-angle) wall-angle)` (line 152).
- Stuck-crouch latch: `can-exit-duck?` (target-util.gc:619) = a HEAD-SPHERE probe
  (body-radius spheres above Jak) through `fill-and-probe-using-spheres` → the SAME
  leaf. `target.gc:1187`: `(if (and (not (can-exit-duck?)) (can-duck?)) (go target-duck-stance))`.
  → BOTH owner bugs bottom out in the same leaf.

## Two confirmed arm64-vs-x86 translation-layer divergences
### (a) FMA contraction (build-flag fact)
- build-android = NDK clang `-ffp-contract=on` (AArch64 has fmadd → fuses `a*b±c`).
- build-x86 = GCC `-mavx` (NO `-mfma`) → cannot emit FMA → no contraction.
- The mips2c VU0 ops `vmadd`/`vmsub`/`vopmsub` (cross product) are single-statement
  `acc ± a*b` (mips2c_private.h:1019-1068, 1535) → contract on arm64, not x86.

### (b) goalc arm64 float `<` / `<=` NaN codegen (IR.cpp:1664-1693)
- Float compare lowers to FCMP + a hardcoded FP cond code: LT→MI, LEQ→LS, GEQ→GE, GT→GT.
- On a NaN operand (FCMP unordered: N0 Z0 C1 V1) vs x86 unsigned jumps (UCOMISS NaN: CF1 ZF1):
  - `<`  (MI vs jb) : arm64 #f, x86 #t  → **DIVERGES**
  - `<=` (LS vs jbe): arm64 #f, x86 #t  → **DIVERGES**
  - `>=` (GE vs jae): both #f → match.   `>` (GT vs ja): both #f → match.
- Deploying this fix needs a FULL consistent CGO rebuild (collision GOAL is in
  ENGINE/GAME.CGO; standalone boot-CGO rebuild SIGILLs). Risky; only pursue with
  evidence that NaN actually occurs in collision.

## Off-device leaf differential (DEFINITIVE, ran on the real device hardware)
Harness: `fma_leaf_proof.cpp` runs the VERBATIM body of the leaf (mips2c_private.h
inline VU0 ops) over 60000 randomized TILTED-wall grazing + moving-sphere configs,
fixed-seed (identical inputs across builds), compiled 3 ways and run on device + x86.

IMPORTANT harness bug found+fixed: drawing multiple RNG `fr()` inside one
function-argument list is UNSEQUENCED in C++ → clang and gcc draw DIFFERENT inputs,
faking a 12.8% "divergence". Fixed by sequencing every `fr()` into a named local.

Clean results:
- **arm64 FMA-off == x86 oracle: BIT-IDENTICAL** (0 / 60000 differences). So
  `-ffp-contract=off` makes the arm64 collision leaf bit-match x86.
- **arm64 FMA-on vs FMA-off: 0 HIT↔MISS verdict flips** (even at tunneling move
  speeds ±90000). FMA only perturbs the hit-FRACTION `u` (push-out distance) on
  1601–2422 / 60000 configs — never flips whether a collision is detected.
- The leaf is otherwise platform-clean: vdiv/vrsqrt/vmini/vmax are plain IEEE C++;
  the only `#ifdef __aarch64__` blocks in mips2c are no-op OOB tripwires.

### Conclusion of the off-device phase
FMA contraction is a REAL arm64-vs-x86 collision divergence (push-out distance), and
`-ffp-contract=off` provably makes the leaf bit-identical to x86 — a correct 1-to-1
fidelity fix. BUT FMA does NOT flip the leaf's hit/miss, so it is **not** the cause
of the wall CLIP-THROUGH (a tunnel = a miss where x86 hits). The clip cause must be
UPSTREAM of the leaf: the goalc-compiled GOAL physics (target velocity/position
integration, the reaction's NaN-sensitive `<`/`<=` compares) or the collide-cache
fill. → Requires REAL-GAME x86-vs-device collision-state capture to localize.

## Next: real-game instrumentation (this build)
Gated diagnostic (env OG_COLL_LOG / prop debug.opengoal.coll.log), TEMPORARY:
- `gcoll_trans_log()` (kmachine.cpp + kboot.cpp): player trans every ~0.25s →
  GCOLL-TRANS — an objective clip/fall-through detector (Y drop).
- leaf logger (collide_func.cpp): player-radius (9011.2 / 2867.2) queries → GCOLL-LEAF
  (return u, normal, center, NaN flag) + GCOLL-SUM (calls/hits/nan counts). Tests
  whether NaN occurs in real collision and what the wall queries resolve to.
Run on device (Geyser drive to the wall) AND x86 (warp + teleport), compare.
