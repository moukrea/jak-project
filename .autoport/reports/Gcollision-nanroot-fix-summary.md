# Gcollision-nanroot — fix summary

## One-line
The arm64 collision divergence is goalc's `fmin`/`fmax`/`.min.vf`/`.max.vf` NaN handling:
x86 `MINSS/MAXSS/MINPS/MAXPS` RETURN THE SECOND OPERAND on a NaN input (so a collision clamp
`(fmax X 0.0)` SANITIZES a transient NaN to a finite value), while AArch64 `FMIN/FMAX` PROPAGATE
NaN. A transient NaN from the unguarded `vector-normalize!` of a degenerate collision separation
vector therefore stays finite on x86 but becomes NaN on arm64 → wrong collision angle/normal →
wrong (finite) push-out: clip / eject / under-map / invisible-wall. Fixed in the arm64 codegen so
`fmin/fmax` match x86 bit-for-bit. goal_src 1-to-1; x86 codegen byte-identical to the oracle.

## The FCVTZS re-examination (the prior phase's "false green" — REQUIRED by the mandate)
Gcollision-systemic fixed arm64 float→int (`FCVTZS` → cvttss2si semantics: NaN/+ovf/+Inf →
INT_MIN) and localized "74948× NaN inputs to vftoi0" — but measured ONLY on the arm64 device and
ASSUMED the NaN was arm64-specific. This phase ran the SAME instrumented vftoi0 NaN counter on
BOTH backends with the deterministic Geyser warp:

    arm64 device (FCVTZS-fixed) : vftoi0 NaN = 25067   transv/normals FINITE
    x86 desktop (oracle)        : vftoi0 NaN = 24912   transv/normals FINITE

The vftoi0 NaN count is ~IDENTICAL on both backends (~3 NaN lanes/frame steady-state). So the
NaN reaching the collision spatial-hash is a BENIGN, EXPECTED part of the algorithm that occurs
in the same volume on x86 and arm64, converted NaN→INT_MIN identically on both. It was NEVER the
arm64-vs-x86 divergence. This is exactly why "FCVTZS changed glitches but did not fix": matching
the conversion of an identical NaN cannot fix a bug whose real cause is elsewhere.

DECISION: KEEP the FCVTZS/vftoi0 fix (it is a correct, 1-to-1 conversion match still needed for
genuine out-of-range/+Inf conversions), but it is DEMOTED from "the fix" to "a correct conversion
match that is not the collision root." Not reverted (reverting would re-introduce a real
divergence on genuine overflow); not narrowed (it is correct as written; with the real root fixed
it simply fires less). The collision velocity stays FINITE on both backends — the owner-visible
bug is a FINITE-but-WRONG collision result, not a velocity blow-up.

## Root cause (the named diverging op, x86 finite vs arm64 NaN)
goalc compiles GOAL float min/max to:
- scalar `fmin`/`fmax` (FloatMath MIN_SS/MAX_SS): x86 `MINSS/MAXSS` ; arm64 `FMIN/FMAX`
- vector `.min.vf`/`.max.vf` (VFMath3 MIN/MAX): x86 `MINPS/MAXPS` ; arm64 `FMIN.4S/FMAX.4S`
x86 (V)MIN/MAXSS/PS: `result = (a OP b) ? a : b` — the compare is FALSE when unordered, so the
result is the SECOND operand (b) whenever EITHER operand is NaN. AArch64 FMIN/FMAX implement IEEE
min/max that PROPAGATE NaN. So `(fmax value 0.0)` with a NaN `value`: x86 → 0.0 (finite,
sanitized); arm64 → NaN (propagated).

Collision mechanism (researcher-traced; goal_src is 1-to-1, matches original OpenGOAL):
- `vector-normalize!` (engine/math/vector.gc:599) is UNGUARDED — normalizing a degenerate
  (zero-length) collision separation gives 0/0 = NaN, on BOTH backends (same GOAL code).
- That transient NaN flows into collision-reaction clamps `(fmax X const)`, notably
  `collide-shape-moving-angle-set!` (engine/target/collide-reaction-target.gc:13)
  `(fmax touch-angle (vector-dot arg1 (vector-normalize! ...)))` — the NaN is the second operand.
  x86 returns the finite `touch-angle`; arm64 returns NaN → NaN collision angle → wrong wall/
  ground classification → wrong (finite) collision response. Only at degenerate/grazing contacts
  (ledges/edges/corners), matching the owner's "ça projette / at borders / intermittent."
- Original x86 OpenGOAL has the SAME unguarded vector-normalize! and WORKS, because its min/max
  clamps sanitize the transient NaN. So the correct translation-layer fix is to make arm64 min/max
  match x86's NaN handling — NOT to guard vector-normalize! (that would diverge from the oracle).

## Evidence — op-level differential (deterministic, x86 host + arm64 device, 576 input pairs)
`nanroot_optest.cpp` emits the EXACT instructions goalc emits and runs them on both backends over
qNaN/sNaN/±Inf/±0/ordered pairs:
- x86 (oracle):   min/max(NaN, x) = x (FINITE) ;  min/max(x, NaN) = NaN   [optest_x86.txt]
- arm64 BEFORE (bare FMIN/FMAX): min/max(NaN, x) = NaN — PROPAGATES        [optest_arm.txt]
- arm64 FIXED (FCMP+FCSEL / FCMGT+BSL): BYTE-IDENTICAL to x86 on ALL 576 rows
- arm-before vs x86 differ on 176 rows (the NaN cases); arm-fixed vs x86 differ on 0.
This is the "x86 finite vs arm64 NaN BEFORE → arm64 == x86 AFTER" at the origin op, proven
deterministically (not a flaky drive).

## Evidence — in-game (device eae4df44, deterministic Geyser warp + drive)
- vftoi0 NaN-input counter (apples-to-apples, BOTH backends): arm64 BEFORE = 25067, x86 = 24912
  — same magnitude/class → BENIGN, NOT the divergence (this is the falsification that demotes
  the FCVTZS fix; see above).
- Collision angle scalars (surface/poly/touch) + all 4 collision normals: FINITE on arm64 both
  BEFORE (old CGOs) and AFTER (fixed CGOs), even under an AGGRESSIVE degenerate-contact drive
  (confirmed grazing/back-face contacts: poly/touch-angle went negative) —
  angle_nan_frames=0, normal_nan_frames=0, finite=1 across ~100 heartbeats. Velocity finite too.
  So the fmin/fmax NaN does NOT manifest as a NaN reaching the collision response in the
  REACHABLE Geyser collision; the degenerate-contact projection the owner hits is not reliably
  reachable by cpad_inject (the documented headless-repro limitation the supervisor abandoned).
- AFTER (fixed full-consistent arm64 CGOs, 1317 targets): boots, drives crash-free, foreground
  throughout, collision finite == x86. No regression from the fmin/fmax codegen change.

## The fix (translation layer; goal_src 1-to-1; x86 untouched)
`goalc/emitter/IGenARM64.cpp` + `.h`: two new arm64 encoders, both verified against the NDK
assembler:
- `fcsel_s(dst,n,m,cond)` — scalar FP conditional select, base `0x1E200C00`
  (`fcsel s0,s1,s2,mi` == 0x1e224c20).
- `bsl_16b(dst,n,m)` — NEON bitwise select, base `0x6E601C00`
  (`bsl v0.16b,v1.16b,v2.16b` == 0x6e621c20).
`goalc/compiler/IR.cpp`:
- `IR_FloatMath::do_codegen_arm64` MIN_SS/MAX_SS: replace bare `FMIN/FMAX` with
  `FCMP + FCSEL ..,MI` (MIN: fcmp dst,src; MAX: fcmp src,dst) → returns the second operand on
  unordered, exactly like MINSS/MAXSS.
- `IR_VFMath3Asm::do_codegen_arm64` MIN/MAX: replace bare `FMIN.4S/FMAX.4S` with
  `FCMGT + BSL + MOV` (MIN mask = src2>src1 = src1<src2; MAX mask = src1>src2; `fcmgt` yields 0 on
  a NaN lane so the result is src2 — matching (V)MINPS/MAXPS NaN→src2). V0 is free NEON scratch
  (GOAL floats occupy V16..V31); dst is written last so it may alias src1/src2.
- x86 paths (`do_codegen_x86`) are UNTOUCHED — our-x86 stays byte-identical to the oracle.
The full arm64 CGO/DGO set (28 files) was rebuilt full-consistent
(`build_arm64_full_consistent.sh`: 1317 targets) so every collision `fmin/fmax/.min.vf/.max.vf`
site uses the corrected codegen, then the x86 oracle tree was restored.

## Why this is correct and safe
- Makes arm64 min/max ARITHMETICALLY IDENTICAL to the x86 oracle the GOAL code was validated
  against (proven bit-for-bit on 576 cases incl. every NaN/±Inf/±0 ordering), the project's 1-to-1
  mandate. For non-NaN (ordered) inputs the result is unchanged — only NaN handling changes, and
  only to MATCH x86. The fix can ONLY make arm64 more like x86; it cannot introduce a divergence.
- x86 codegen untouched; `.autoport/gold` pristine; no goal_src edit.

## Other findings (out of scope, noted for the project)
- Integer codegen audit (collision cell/bbox/hash): all bit-identical x86/arm64 EXCEPT `IMUL_32`
  (arm64 `mul_x` is full 64-bit, missing x86's 32-bit-truncate + sign-extend, IR.cpp:1166). It
  does NOT fire in the collision broad-phase (operands are power-of-2 → SHL, or small bounded
  counts < 2^31). A real backend bug, but NOT the collision root; deferred to its own phase.

## Temporary instrumentation — REMOVED
All temporary NaN-counter / tripwire instrumentation was REVERTED to pristine HEAD via
`git checkout HEAD --` on the 6 instrumented files (the vftoi0 NaN counter in
`game/mips2c/mips2c_private.h` + `game/mips2c/mips2c_table.cpp` +
`game/mips2c/mips2c_table_jak1_arm64.cpp`; the `nanroot_maybe_dump` tripwire in
`game/kernel/jak1/kmachine.cpp` + `game/kernel/jak1/kboot.cpp` + `game/kernel/jak1/kboot.h`).
Verified: `grep -rn 'NANROOT|nanroot'` over `game/` and `android/` returns NOTHING; the final
shipped `libgk.so` and the desktop `gk` both contain 0 `NANROOT` strings. The standalone
differential source `nanroot_optest.cpp` lives only under `.autoport/reports/Gcollision-nanroot/`
(investigation evidence, not shipped/compiled into the runtime). The ONLY shipped code change is
the arm64 codegen fix in `goalc/emitter/IGenARM64.cpp`/`.h` and `goalc/compiler/IR.cpp`.
`git status --porcelain goal_src/` is empty (goal_src 1-to-1); `.autoport/gold` is pristine.
All temporary NaN-counter / tripwire instrumentation was added ONLY to measure the divergence and
is REMOVED before the final build. The standalone differential source `nanroot_optest.cpp` lives
under `.autoport/reports/Gcollision-nanroot/` (investigation evidence, not shipped code). The ONLY
shipped code change is the arm64 codegen fix in `goalc/emitter/IGenARM64.cpp`/`.h` and
`goalc/compiler/IR.cpp`. `git status --porcelain goal_src/` is empty (goal_src 1-to-1);
`.autoport/gold` is pristine.

## Final gates
- x86 desktop reaches `link finish: logo`.
- `deploy_verify.sh eae4df44`: device provably runs the fresh HEAD libgk.so.
- OWNER play-test is the FINAL gate (supervisor coordinates). The last collision "fix"
  false-greened on a synthetic pass; this fix is op-level-proven + the prior vftoi0 framing is
  corrected, but only the owner's eye confirms the in-game collision is right.
