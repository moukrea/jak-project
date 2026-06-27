# Gcollision-systemic — fix summary

## One-line
The pervasive arm64 collision breakage (clip-through, eject, under-map, invisible
walls, stuck) was a SYSTEMIC float→int conversion divergence: goalc's AArch64
codegen emitted a bare `FCVTZS` for GOAL float→int, which saturates NaN→0 and
+ovf/+Inf→INT_MAX, where the x86 oracle (`cvttss2si`/`cvttps2dq`) maps all
out-of-range/NaN to INT_MIN (0x80000000). Fixed in the arm64 codegen so the
conversion matches x86 bit-for-bit. goal_src untouched; x86 codegen byte-identical.

## The owner defect (2026-06-27)
Collision broken EVERYWHERE on arm64 (x86 fine): clip through walls, jumps under
the map, eject far OR stuck near objects, invisible walls / must-jump on flat
ground, blue-eco zone ejects off the cliff (intermittent). Owner's read — "related
to the ARM conversion" — was correct.

## Why the earlier per-site fixes were symptoms, not the root
Four prior fixes each patched ONE manifestation of the same conversion/float bug
class (collide_cache #f-guard; collide_edge_grab; FMA `-ffp-contract=off`; the
ledge **mips2c `vftoi0`** cvttss2si emulation). The ledge fix was the smoking gun:
it corrected the float→int saturation in exactly ONE mips2c op. But the **same
conversion is wrong pervasively** — the goalc-compiled GOAL collision code in the
boot CGOs (collide-shape/cache/mesh/edge-grab) does its own float→int via the
goalc backend, which was still a bare `FCVTZS`. So collision stayed broken.

## Root cause (named codegen op)
`goalc/emitter/IGenARM64.cpp`:
- scalar `float_to_int32` → `fcvtzs Wd, Sn`
- vector  `ftoi_vf`       → `fcvtzs Vd.4s, Vn.4s`
AArch64 FCVTZS saturates differently from x86 cvttss2si/cvttps2dq:
NaN→0 (x86 0x80000000), +ovf/+Inf→0x7fffffff (x86 0x80000000); -ovf/-Inf→0x80000000
and in-range truncation already match. Collision quantizes triangle/query coords
into the spatial-hash/AABB grid with 58 vector `.ftoi.vf` sites
(collide-cache 51, collide-mesh 4, collide-edge-grab 3 — confirmed by arm64 CGO
disassembly, matched 1:1 by x86 `cvttps2dq`). Collision legitimately produces
NaN/overflow coords (degenerate/grazing/far geometry); x86 maps them to an
out-of-bounds cell (rejected), arm64 mapped NaN→0 / +ovf→INT_MAX (a valid-looking
cell) → wrong collision triangle → wrong push-out / blown-up velocity integrator
→ clip / eject / invisible wall / under-map / stuck.

## Evidence — unit-diff sweep (the Gcollision-arm model, many→0)
- `conv_sweep.cpp`, x86 (GCC oracle) vs arm64 (NDK clang) on device eae4df44, 75000
  collision-realistic inputs:
  - BEFORE (oracle vs bare FCVTZS): **38285 / 75000** divergent (+ovf 21639, NaN
    1110, Inf 612, in-range 0).
  - AFTER  (oracle vs cvttss2si emulation): **0 / 75000**.
- `seq_validate.cpp` (on-device, the EXACT instruction words goalc emits, 200000
  inputs): scalar **0** mismatches vs cvttss2si, vector **0 / 800000 lanes** vs
  cvttps2dq, 77873 differ from bare FCVTZS. RESULT: SEQUENCES == x86.

## Evidence — state-anchored in-game (≥3 scenarios, before→after==x86)
Deterministic warp (f1.warp) + per-logic-tick *target* state dump (control trans=
position, transv=velocity, status, control-state), x86 oracle vs device PRE-FIX vs
device FIXED.
- x86 oracle: settles clean (tr=-5393129,28317,4362849), drives smoothly, velocity
  bounded.
- Scenario 1 (wall / clip / invisible wall): BEFORE position FROZE 579 ticks at an
  invisible wall while velocity shoved; AFTER advances and STOPS cleanly == x86.
- Scenario 2 (eject / launch): BEFORE velocity spiked +17934 then SATURATED at
  tv.y=-163839.97 (= -40·4096, the conversion/fixed-point clamp) and pinned
  forever; AFTER velocity bounded, no spike, no saturation == x86.
- Scenario 3 (edge / off-cliff / stuck): BEFORE stuck with garbage velocity; AFTER
  walks up/over a slope, off a ledge into a BOUNDED controlled fall and recovers
  == x86.
- device FIXED settle = -5392877,28345,4363629 ≈ x86 oracle (sub-percent).

## The fix (translation layer; goal_src 1-to-1)
`goalc/emitter/IGenARM64.cpp` + `.h`: new arm64 encoders `csel`, `movi_4s_lsl24`,
`fcmgt_4s`, `bif_16b` (bases verified against the NDK assembler; `bif` is size=0b11
= 0x6EE01C00, NOT the BIT 0x6EA01C00 — caught and fixed during validation).
`goalc/compiler/IR.cpp`:
- `IR_FloatToInt::do_codegen_arm64` (scalar): FCVTZS Wd,Sn; movz INT_MIN; movz/movk
  INT_MAX; cmp; csel(eq→INT_MIN for +ovf/+Inf); fcmp Sn,Sn; csel(vs→INT_MIN for
  NaN); sxtw.
- `IR_VFMath2Asm` FTOI (vector): movi 2^31; fcmgt keep-mask (built from Vn BEFORE
  the FCVTZS so it is correct in-place dst==src); FCVTZS .4s; movi INT_MIN; bif
  (override only the +ovf/+Inf/NaN lanes to INT_MIN).
- Scratch: X16/X17 (documented-free GPR) and V0–V2 (free NEON; GOAL floats live in
  V16–V31). No regalloc/temp change, so x86 register allocation is unperturbed and
  the x86 codegen path is byte-for-byte untouched (our-x86 == original-x86).
- The FIXED arm64 CGO/DGO set (all 28) was rebuilt full-consistent
  (`build_arm64_full_consistent.sh`) and deployed; the x86 oracle tree
  (`out/jak1/iso`) was restored and reaches `link finish: logo`.

## Why this is correct and safe
- Makes the arm64 collision conversion arithmetically IDENTICAL to the x86 oracle
  the GOAL code was validated against (proven bit-for-bit), the project's 1-to-1
  mandate. In-range conversions are unchanged (only NaN/overflow lanes are fixed),
  so non-collision codegen behavior is unaffected except where it was already
  diverging from x86.
- x86 codegen untouched; `.autoport/gold` pristine; no goal_src edit.

## Regression check (recent collision fixes kept)
The three recent per-site fixes live in libgk/mips2c + CMakeLists and are UNTOUCHED
by this goalc-codegen change; verified still in effect:
- Gcollision-arm `-ffp-contract=off` on the 5 collide TUs — intact.
- Gcollision-wallslide collide_cache m9/m10 bare-low32 #f-guard — intact.
- Gledge-glitch mips2c vftoi0 cvttss2si emulation — intact (the goalc fix now
  applies the SAME conversion semantics in the GOAL layer; consistent, not
  over-broad).
The AFTER in-game run exercised all of them together (ground collision, wall stop,
ledge fall, stand-up) crash-free → no regression.

## Temporary instrumentation — REMOVED
All temporary diagnostics were **removed/deleted** before the final build — there
are **no leftover** debug hooks:
- The gated per-logic-tick `colldump_tick()` state-dump hook in
  `game/kernel/jak1/kmachine.cpp` + its declaration in `kboot.h` + the call site in
  `kboot.cpp` were reverted to pristine HEAD (`git checkout`); `grep COLLDUMP`
  over `game/` and `android/` returns nothing, and the final shipped
  `libgk.so` contains **0** `COLLDUMP` strings (deploy_verify confirmed the clean
  libgk is on the device).
- The standalone sweep/validation sources (`conv_sweep.cpp`, `seq_validate.cpp`)
  under `.autoport/reports/Gcollision-systemic/` are investigation evidence, not
  shipped code.
- The ONLY shipped code change is the arm64 codegen fix in
  `goalc/emitter/IGenARM64.cpp`/`.h` and `goalc/compiler/IR.cpp`.
- `git status --porcelain goal_src/` is empty (goal_src 1-to-1); `.autoport/gold`
  is pristine.

## Final gates
- x86 desktop reaches `link finish: logo`.
- `deploy_verify.sh eae4df44`: PASS (clean fresh-HEAD libgk; build==APK==device).
- Owner eye is the final judge: trivially reproducible (warp + drive into the
  Geyser-step walls / off the blue-eco ledge); the device now behaves like x86.
