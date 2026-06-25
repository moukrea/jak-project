# Gcollision-wallslide — DIAGNOSIS (preserved 2026-06-25, before reordering Ginput-replay ahead)

## Status
**Root cause FOUND + candidate fix written. The struggle was VERIFICATION** (reliably reproducing the
stuck-crouch on-device to confirm the fix) — exactly what the owner flagged ("il galère à reproduire")
and what the `Ginput-replay` macro is built to solve. Diagnosis + fix preserved here so the next
attempt resumes from VERIFICATION, not from scratch.

## Root cause (arm64-vs-x86 divergence, translation layer — NOT goal_src)
`can-exit-duck?` effectively returns `#f` on arm64 at certain Geyser-Rock walls → Jak ends **permanently
crouched** even with no input (owner defect). x86 is unaffected.

The mechanism is the **[[arm64-mips2c-fnull-guard]]** class, on the symbol-**RETURN** side:
- `collide-puss-work` (mips2c leaves, method 9/10) returns the GOAL symbol `#t`/`#f` to the GOALC caller
  `probe-using-spheres`, tested with `(when v1-12 (return #t))`.
- mips2c stores/returns symbols as **bare 32-bit offsets** (`addr - g_ee_main_mem`, mips2c_private.h:311).
- GOALC arm64 materialises the `#f` it compares against as the **symbol-table register = a HOST pointer**
  `g_ee_main_mem + offset` (IR.cpp `IR_LoadSymbolPointer` do_codegen_arm64 → `get_st_reg()`).
- So the 64-bit `(when v1-12)` compares **bare-offset `#f` ≠ host-pointer `#f`** → reads "not false" →
  `fill-and-probe-using-spheres` wrongly reports a blocking head sphere → `can-exit-duck?` = `#f` → stuck
  crouched. The per-triangle hit/miss math is itself bit-identical to x86; only the boolean **return
  pointer representation** diverges. (Other sites in this file fix the COMPARE side via per-site
  gpr_addr; this is the RETURN side.)

## Candidate fix (saved as patches in this dir)
- `collide_cache-fix.patch` (55 lines): adds `gpuss_canonical_symbol_return()` re-tagging the `#t`/`#f`
  offset as the host pointer GOALC expects, **arm64-only** (`#if defined(__aarch64__)`); x86 return left
  untouched. goal_src 1-to-1.
- `candidate-fix.patch` (223 lines): the above PLUS the kernel-side GWALL instrumentation
  (kboot.cpp/.h, kmachine.cpp) used to trace the stuck-crouch — **instrumentation, must be removed before
  any PASS**.

## How to resume (next attempt, AFTER Ginput-replay lands)
1. Re-apply `collide_cache-fix.patch` (the fix only; leave the kernel instrumentation OUT, or add it
   temporarily and remove before PASS).
2. Use the **Ginput-replay macro** to VERIFY: owner records ONE demo that drives Jak to the wall and
   produces the stuck-crouch; replay it deterministically — BEFORE the fix it reproduces stuck-crouch,
   AFTER the fix Jak self-exits the duck. Compare arm64 vs x86 state-anchored (`can-exit-duck?` /
   probe-return value at the matching control state must become identical).
3. Validate per `phase-Gcollision-wallslide.sh` (x86-first, goal_src 1-to-1, instrumentation removed).

## Caveat
The fix is plausible and well-reasoned but was **NOT yet confirmed on-device** (verification kept failing
to reproduce reliably). Do NOT mark wall-slide PASS on this diagnosis alone — confirm via the macro.
