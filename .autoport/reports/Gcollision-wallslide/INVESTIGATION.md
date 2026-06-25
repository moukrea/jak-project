# Gcollision-wallslide — investigation log (WIP, NOT a pass)

Owner defect (2026-06-25): hitting a ledge too high right of the Geyser steps →
Jak slow-slides down the wall and **ends CROUCHED, never standing back up on his
own even with no input**, differs from x86. Residual after the Gcollision-arm
FMA fix.

## Method
x86-first, deterministic state/value diffs. Device (arm64, eae4df44) has NO goalc
listener → all device state read via gated C++ byte-offset hooks in libgk; x86
read via the goalc REPL. Fixes must be translation-layer (mips2c / android /
goalc-arm64), goal_src byte-identical 1-to-1.

## What is PROVEN (high confidence)
1. **The collision PROBE math is bit-identical x86↔arm64.** At one wedge spot
   both produce dmr (dist²−radius²) = −195382.5 exactly; predecessor's
   `-ffp-contract=off` made the 5 collide TUs bit-identical; objdump shows zero
   fmadd in the arm64 collide objects.
2. **At the stuck walls the can-exit-duck? head-probe (method 9 collide-puss-
   work) is CLEAR on the device** — per-triangle dump: 26000+ frames, ALL hit=0;
   `(method 10 collide-puss-work)` is NEVER called (cache holds only mesh prims).
   x86 at the same world coords (spots tx=-5342971/ty=23828 and tx=-5237659/
   ty=9111): `fill-and-probe-using-spheres` returns **blocked=#f (can stand)**.
3. **No NaN/Inf** anywhere in the captured collision state (`nf=0` across all
   captures) — this is NOT a float-corruption / NaN-compare bug.
4. **The duck-stance:trans stand-up gate (EXIT-1) is what fails to fire.** With
   no input, `fall-test`/`slide-down-test` can't fire (status has `onsurf`), so
   the only self-exit is `(if (and (or (not cpad-hold-l1r1) prevent-duck)
   (and (not roll) (can-exit-duck?))) (go target-stance))`. The device shows
   `hold=0` (no L1/R1 latched), the session has ZERO roll states, and the probe
   is clear. Jak exits only when GIVEN input (move-legs→duck-walk, jump).
5. Two stuck spots (tx=-5330629 and -5278032) were verified divergent: x86
   `fill-and-probe` clear (would self-exit), device stuck. Some other stuck spots
   (S1 tx=-5289353, S4) are genuine overhangs where x86 ALSO blocks (normal).

## Root-cause lead (the [[arm64-mips2c-fnull-guard]] class)
- GOALC arm64 materialises `#f` as the symbol-table register `st_reg` — a HOST
  pointer `g_ee_main_mem + offset` (IR.cpp IR_LoadSymbolPointer::do_codegen_arm64,
  `#f → get_st_reg()`).
- The mips2c VM stores symbols as BARE 32-bit offsets (mips2c_private.h:311,
  `addr - g_ee_main_mem`).
- A C++ diagnostic (`PUSS9-RET-ODD`) confirmed method 9's symbol return is
  sometimes host-tagged (0x7f0014fd24) and sometimes a bare offset (upper-32=0),
  depending on caller register state → wall-specific.
- Hypothesis: GOALC's `(when v1-12 (return #t))` in `probe-using-spheres` does a
  64-bit compare of the mips2c return against host-pointer `#f`; a bare-offset
  `#f` reads as "not false" → fill-and-probe wrongly reports a block →
  `can-exit-duck?`=#f → permanent crouch. x86 (single 32-bit pointer model) is
  unaffected. Same documented class as the per-site `gpr_addr` COMPARE fixes
  already in collide_cache.cpp (those fix the compare side; this is the return).

## Fixes ATTEMPTED
- **Attempt 1** (caller-s7 canonical return): re-emit method 9/10 #t/#f using the
  s7 representation the caller passed at entry. FAILED on device (still stuck).
- **Attempt 2 — KEPT in tree** (host-pointer return, `gpuss_canonical_symbol_
  return` in collide_cache.cpp): re-tag method 9/10 #t/#f as the host pointer
  `g_ee_main_mem + (u32)ret` that GOALC compares against (arm64-only). This is a
  REAL, correct fix for the confirmed bare-vs-host return divergence (verified to
  boot + play crash-free), BUT it did NOT resolve the stuck-crouch on device.

## Why the fixes did not fix the symptom
Both attempts addressed the method-9/10 RETURN. Their failure means either (a) the
duck-probe's method-9 return was already host-tagged for that call path (so the
fix is a no-op for it and the bare-return mismatch is a different query), or (b)
`can-exit-duck?` is actually #t on the device and EXIT-1 fails for a reason in the
GOALC-compiled duck-stance:trans / probe-using-spheres codegen itself (the
`(when v1-12)` GOALC compare, or the inline-VU0 bbox loop), which is NOT fixable
in libgk and needs a goalc-arm64 codegen change + a full consistent CGO rebuild.

## Could NOT measure
`can-exit-duck?` called directly from the kernel loop via `_call_goal8_asm_systemv`
**crashes** (alloc_from_heap→memset SIGSEGV) — its `(new 'stack-no-clear ...)`
needs the target-process stack/pp context. So whether the device's
`can-exit-duck?` is #t or #f at the stuck spot is UNMEASURED (the decisive
unknown). A safe measurement needs an in-target-context call (a one-shot probe
spawned on *target*'s stack), or a non-allocating C++ replica of the probe.

## Recommended next steps
1. Build a non-allocating C++ replica of the can-exit-duck? probe (2 head spheres
   at *target* trans, call fill-and-probe via call_method_of_type on the target's
   own stack) to read its ACTUAL #t/#f on device — the decisive unmeasured value.
2. If can-exit-duck? is #f despite method-9 clear → the bug is GOALC
   probe-using-spheres codegen (the `(when v1-12)` 64-bit symbol compare or the
   `.ftoi.vf` bbox); fix in goalc arm64 (make symbol/#f conditional branches
   compare low-32) — needs a full consistent CGO rebuild. The kept host-tag
   return fix complements that.
3. If can-exit-duck? is #t → the bug is the EXIT-1 surrounding predicate
   (cpad-hold? pointer-array access, or the `(and/or)` branch) — re-verify the
   cpad-info offset (the device cpad read returned cpadn=-1; offset 668 for
   unknown-cpad-info00 may be wrong) and the ja-group animation pointer.
4. Confirm x86 ACTUALLY self-exits at the exact divergent spots (drive/teleport
   x86 into a duck against the wall and observe), to rule out "stuck-crouch is
   normal on both" before committing a goalc/CGO fix.

## Key artifacts (this dir)
- x86 oracle: x86_4spots.txt (S2/S3 blocked=#f), x86_puss*.txt (per-triangle).
- device: device_gwall_steps.txt, device_m10_stuck.txt (method-9 all hit=0,
  method-10 0 calls), device_puss_multi.txt, device_cpad.txt (ced call crash),
  device_fix2_verify.txt (host-tag fix FAILED, 5 walls all stuck).
- harness: gwall_x86_*.sh (REPL probes), the C++ hooks were reverted.
