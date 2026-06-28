# Gcollision-nanroot — investigation log (manager notes)

## Mandate
Find the arm64 op that produces a NaN in collision where x86 is finite (the supervisor's
hypothesis: a NaN reaches collision on arm64 → clip/eject/under-map). Re-examine the FCVTZS
(float→int) fix from Gcollision-systemic, which the owner reported "changed glitches but did
not fix." goal_src 1-to-1; fix in the arm64 translation layer; owner play-test = final gate.

## KEY FALSIFICATION (this phase): the vftoi0 NaN is NOT the divergence
Prior phases (Gledge-glitch, Gcollision-systemic) localized "74948× NaN inputs to vftoi0"
during a Geyser collision drive — measured ONLY on the arm64 device, and ASSUMED the NaN was
arm64-specific. This phase measured the SAME instrumented counter on BOTH backends:

| backend | vftoi0 NaN-input count | transv / normals | how driven |
|---------|------------------------|------------------|-----------|
| arm64 device (FCVTZS-fixed CGOs) | **25067** (idle 286 → driving) | FINITE throughout | warp + cpad_inject wall drive ~90s |
| x86 desktop (oracle)             | **24912** (~3/frame steady)  | FINITE throughout | warp + settle ~150s |

→ The vftoi0 NaN is a BENIGN, EXPECTED part of the collision algorithm that occurs in nearly
identical volume on BOTH backends (a degenerate/padding lane quantized then discarded, mapped
NaN→INT_MIN identically by cvttss2si on x86 and by the FCVTZS fix on arm64). It is NOT the
arm64-vs-x86 divergence. The Gledge "74948×" was real but never arm64-specific.

→ The FCVTZS/vftoi0 fix (Gcollision-systemic) is therefore a SYMPTOM fix: arithmetically
correct (arm64 float→int now matches x86 cvttss2si bit-for-bit for genuine out-of-range
inputs) but NOT the collision root, because both backends already see the same NaN and convert
it identically. This is exactly why the owner saw "changed glitches, not fixed." KEPT (it is a
real 1-to-1 conversion correctness fix, still needed for genuine +ovf/+Inf), but demoted from
"the fix" to "a correct conversion match."

Also measured: collision VELOCITY (control transv) stays FINITE on both backends — no NaN
explosion. So the owner-visible bug is a FINITE-but-WRONG collision result on arm64, not a
velocity blow-up.

## The actual divergence: goalc fmin/fmax/.min.vf/.max.vf NaN handling (op-level PROVEN)
GOAL `fmin`/`fmax` (FloatMath MIN_SS/MAX_SS) and `.min.vf`/`.max.vf` (VFMath3) compile to:
  x86  : MINSS/MAXSS, MINPS/MAXPS  — on a NaN operand, RETURN THE SECOND OPERAND (the compare
         is unordered=false), i.e. a clamp `(fmax X 0.0)` SANITIZES a transient NaN X → 0.0.
  arm64: FMIN/FMAX, FMIN.4S/FMAX.4S — IEEE FMIN/FMAX PROPAGATE NaN.
Op-level differential (nanroot_optest.cpp, exact emitted instructions, run on x86 host + the
arm64 device, 576 input pairs incl. qNaN/sNaN/±Inf/±0/ordered):
  - x86 (oracle): min/max(NaN, x) = x (finite); min/max(x, NaN) = NaN.   [optest_x86.txt]
  - arm-BEFORE (bare FMIN/FMAX): min/max(NaN, x) = NaN — PROPAGATES.       [optest_arm.txt]
  - arm-FIXED (FCMP+FCSEL / FCMGT+BSL): byte-identical to x86 on ALL 576 rows.
  - arm-before vs x86 differ on 176 rows (the NaN cases); arm-fixed vs x86 differ on 0.
This is the "x86 finite vs arm64 NaN" origin op, proven deterministically (not a flaky drive).

Mechanism in collision (researcher-traced, goal_src is 1-to-1 / matches original OpenGOAL):
  - `vector-normalize!` (engine/math/vector.gc:599) is UNGUARDED: normalizing a degenerate
    (zero-length) collision separation vector = 0/0 = NaN, on BOTH backends (same GOAL code).
  - That transient NaN flows into collision-reaction clamps of the form `(fmax X const)`,
    notably `collide-shape-moving-angle-set!` (collide-reaction-target.gc:13)
    `(fmax touch-angle (vector-dot arg1 (vector-normalize! ...)))` — the dot is the SECOND
    operand. x86 MAXSS returns the finite first operand `touch-angle`; arm64 FMAX returns NaN.
  - → arm64 writes a NaN collision angle → wrong wall/ground classification → wrong (finite,
    or rejected-cell) collision response: clip / eject / under-map / invisible-wall. Only at
    degenerate/grazing contacts (ledges/edges/corners) — matches the owner's "ça projette /
    at borders / intermittent." x86 never reaches the NaN branch (its clamp sanitizes).
Original x86 OpenGOAL has the SAME unguarded vector-normalize! and works — because its min/max
clamps sanitize the transient NaN. So the correct 1-to-1 translation-layer fix is to make
arm64 min/max match x86's NaN handling — NOT to guard vector-normalize! (which would diverge
from the goal_src oracle).

## Ruled out
- vftoi0 / FCVTZS float→int conversion: identical NaN volume on both backends (above). Not it.
- Integer codegen (modulo, idiv, shifts, vector int compares/packs, ptr indexing): all
  bit-identical x86/arm64 in collision. The ONE real integer divergence found — IMUL_32 lacks
  arm64 32-bit truncation+sign-extension (IR.cpp:1166, mul_x full-64) — does NOT fire in the
  collision broad-phase (operands are power-of-2 → SHL, or small bounded tri/prim/vert counts
  < 2^31). Noted as a separate backend bug, OUT OF SCOPE here.
- FMA/fused-multiply-add: none emitted by the arm64 backend. Approximate reciprocals: none.
  Scalar/vector div & sqrt: full-precision IEEE on both → identical Inf/NaN. So fmin/fmax NaN
  handling is the ONLY remaining float codegen divergence.

## The fix (translation layer; goal_src 1-to-1; x86 untouched)
goalc arm64 codegen, IR_FloatMath::do_codegen_arm64 (MIN_SS/MAX_SS) and
IR_VFMath3Asm::do_codegen_arm64 (MIN/MAX) now emulate the x86 "return operand-2 on unordered":
  - scalar MIN: FCMP dst,src ; FCSEL dst,dst,src,MI
  - scalar MAX: FCMP src,dst ; FCSEL dst,dst,src,MI
  - vector MIN: FCMGT v0,src2,src1 ; BSL v0,src1,src2 ; MOV dst,v0
  - vector MAX: FCMGT v0,src1,src2 ; BSL v0,src1,src2 ; MOV dst,v0
New encoders fcsel_s (0x1E200C00) and bsl_16b (0x6E601C00) added to IGenARM64; all encodings
verified against the NDK assembler. x86 do_codegen_x86 untouched (our-x86 == original-x86).

## Evidence ledger (artifacts in this dir)
- optest_x86.txt / optest_arm.txt : op-level differential (arm-fixed == x86, 576/576).
- dev_before.log : arm64 in-game, vftoi0 25067, transv finite, 0 FIRST-NONFINITE.
- x86_nanbase.log : x86 in-game, vftoi0 24912, transv finite (falsifies the vftoi0 discriminator).
- dev_angle_before.log : arm64 aggressive drive, angle/normal NaN tripwire (in progress).
- dev_after.log : arm64 with the fmin/fmax fix (full build) — pending.

## Honesty / scope
The op-level fmin/fmax divergence is PROVEN (x86 finite vs arm64 NaN, fixed → arm64==x86) and
is the only remaining float codegen divergence (by elimination). The exact in-game projection
occurs only at degenerate contacts; headless cpad_inject drives may not reach them (the
supervisor abandoned drive/replay repro for this reason). The OWNER play-test is the final gate.
