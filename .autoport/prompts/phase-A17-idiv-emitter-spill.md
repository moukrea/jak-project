# Phase A17 — emitter-side IDIV spill: localize X8 clobber to the IDIV emit

## First step — read the cookbook

Read `.autoport/CODEGEN_COOKBOOK.md`. §11 "What NOT to do" — pay
particular attention to the A15 qemu-vs-device divergence lesson.

## Status

**Authored 2026-05-24 by the supervisor** after A16's diagnostic
captured the device crash signature (`A16-DIAG adrp-pair` walk +
`preserved` entries) and REFUTED A15's x16-clobber hypothesis. The
actual device crash at 166 link-finishes is **the same SDIV-clobbers-
X8 bug as the original A14 next-blocker** — both qemu and device hit
it at the `sin` call site (qemu: `sin*!` hash=0xff8c9691; device:
`sin` hash=0xff8c9691).

Two prior regalloc-layer fix attempts (A15-1 and A15-2) both passed
qemu but regressed real-device boot, with the regression caused by
the regalloc constraint graph changes themselves introducing
allocation ripples in unrelated functions.

A17 is the **emitter-side fix** (claude's "A16-b" recommendation in
both `A15-attempt-2-next-blocker.md` and `A16-fix-summary.md`):
preserve X8 across the IDIV inside the emit itself, so the regalloc
never sees X8 as clobbered and its allocations elsewhere stay
byte-identical to the A14 baseline.

## Bucket

A — codegen (emitter).

## Motivation

Per `goalc/emitter/IGenARM64.cpp` (lines ~1677-1690), the current
arm64 IDIV/UDIV emit is one instruction with hardcoded Rd=X8:

```cpp
InstructionARM64 idiv_gpr32(Register reg) {
  return sdiv_x(Register(8), Register(8), reg);  // SDIV X8, X8, Xn
}

InstructionARM64 unsigned_div_gpr32(Register reg) {
  return udiv_x(Register(8), Register(8), reg);  // UDIV X8, X8, Xn
}
```

The IR-level `IR_IntegerMath::to_rai` records `read/write m_dest,
exclude RDX` — but the X8 write is invisible to the regalloc, which
can park `m_func` of a subsequent `IR_FunctionCall` in X8 across the
IDIV. The SDIV clobbers X8 with `m_dest / 10`. The BLR jumps to
`ee_base + m_dest/10`. SIGBUS (unaligned PC) or SIGILL (UDF #0 if
target aligns to a 0-word).

## Goal (concrete, narrow)

Rewrite `idiv_gpr32` / `unsigned_div_gpr32` to emit a 6-instruction
sequence that preserves X8 across the SDIV. **The function must
return ONE InstructionARM64 — so the sequence either needs a new
emit signature that returns multiple instructions, OR the existing
IR.cpp call site needs to be updated to emit the sequence inline.**

Pseudo-target sequence (per claude's A16-b recommendation):

```
sub  sp, sp, #16             ; carve scratch slot
str  x8, [sp]                ; preserve caller's X8 (top of stack)
sdiv x8, x8, xN              ; existing SDIV
mov  Xdst, x8                ; copy result to allocated dest (if Xdst != X8)
ldr  x8, [sp]                ; restore caller's X8
add  sp, sp, #16             ; restore SP
```

If `m_dest` is allocated to X8 itself (the existing case), the
`mov Xdst, x8` after the SDIV becomes a no-op `mov x8, x8` AND the
subsequent `ldr x8, [sp]` would overwrite the result. So we need to
handle the X8-dest case specially:

```
; If m_dest == X8:
sdiv x8, x8, xN              ; just SDIV; no preserve needed (caller had no X8
                             ; value if it allocated X8 to m_dest)
; If m_dest != X8:
sub  sp, sp, #16
str  x8, [sp]
sdiv x8, x8, xN
mov  Xdst, x8
ldr  x8, [sp]
add  sp, sp, #16
```

This makes the SDIV use of X8 **invisible to the regalloc** for the
m_dest != X8 case (the regalloc only sees `m_dest read+write`, no
X8 involvement), and the m_dest == X8 case is the regalloc's
existing model (allocator already knows it's writing X8 via m_dest).

## Scope (locks)

**UNLOCKED for A17 only:**

- `goalc/emitter/IGenARM64.cpp` — rewrite `idiv_gpr32` /
  `unsigned_div_gpr32` and any related helper that emits the
  hardcoded-X8 SDIV/UDIV.
- `goalc/compiler/IR.cpp` — IF the rewrite needs IR-level changes
  to emit the 6-instruction sequence (e.g., a new `IR_IntegerMath`
  emit path that calls into the multi-instr sequence). The IR-level
  signalling should stay minimal — ideally the emitter produces the
  full 6-instr sequence on its own.

**STILL LOCKED** (carried forward from A6–A16):

- `goalc/emitter/IGenARM64.h` — only the .cpp is unlocked.
- `goalc/emitter/ObjectGenerator.{cpp,h}`.
- `goalc/compiler/CodeGenerator.{cpp,h}`.
- `goalc/compiler/IR.h`.
- `goalc/regalloc/*` — **DO NOT TOUCH**. The whole point of A17 is
  to keep the regalloc at the A14 baseline. Changes to regalloc
  would re-introduce the A15-shape divergence.
- `.autoport/lib/classify_ir_arm64.py`.
- `game/kernel/asm_funcs_arm64.s`.
- `game/kernel/common/kscheme.cpp`.
- `game/kernel/common/kmachine.cpp`.
- `game/system/IOP_Kernel.{cpp,h}`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/android_runtime_compat.cpp`.
- `game/kernel/common/klink.{cpp,h}`.
- `.autoport/lib/*.sh`, `.autoport/lib/*.py`,
  `.autoport/validators/*.sh` (supervisor-owned).

## Anti-cheat invariants

Inherited from A6–A16. **Key reminders**:

- arm64 CGOs WILL byte-change vs A14 baseline (the IDIV emit produces
  different bytes — that's the point). A17 must regenerate the
  baseline file.
- The byte change must be CONFINED to IDIV/UDIV sites (verify by
  computing byte-diff distribution — should cluster around IDIV
  callers, not be evenly distributed across the file).
- x86 CGOs MUST stay byte-identical to A2 baseline (the change must
  be inside `#ifdef GOALC_BACKEND_ARM64` or in an arm64-only emit
  function that x86 doesn't call).
- The fix must be a real instruction sequence, NOT:
  - A stub that returns 0.
  - A CBZ-around-call dodge.
  - A renamed _impl helper with `return 0;`.
- The validator's CBZ-around-BLR fingerprint scan still applies.
- The rename-evasion detector still applies.

## Device-first verification

**This is the critical constraint** (the lesson from A15):

After your fix:

1. Verify qemu_repro advances past 166 link-finishes.
2. Verify the D4 device validator on the Redmi Note 9 Pro
   (eae4df44) ALSO advances past 166. If qemu advances but device
   REGRESSES (like A15-1 -113 and A15-2 -101), the fix is broken —
   **revert immediately** and write an honest-exit next-blocker.

The byte-change-confined-to-IDIV-sites check should help confirm
that no allocation ripples occurred. If the byte-diff is evenly
distributed across the function (not clustered at IDIV sites),
something else changed and the fix is suspect.

## Required deliverables

1. `goalc/emitter/IGenARM64.cpp` rewrite of `idiv_gpr32` /
   `unsigned_div_gpr32` to emit the 6-instr preserve-restore
   sequence (or 1-instr if m_dest == X8).
2. arm64 CGOs regenerated; new
   `.autoport/reports/A17-baseline-arm64-cgo-hashes.txt`.
3. CGO sync into APK assets.
4. `bash .autoport/lib/qemu_repro.sh` — must reach > 166 link-finishes.
5. **`bash .autoport/validators/phase-D4-android-apk-title.sh`** —
   device must also reach > 166 link-finishes (no regression).
6. `bash .autoport/validators/phase-A17-idiv-emitter-spill.sh` exits 0.
7. `.autoport/reports/A17-fix-summary.md` — names the exact emit
   change, a disassembly snippet at the previously-failing sin call
   site, and the byte-diff distribution evidence (sites where bytes
   changed vs A14 baseline).

## Honest exit condition

If A17 lands but device regresses (any qemu-vs-device divergence
≥ 20 link-finishes), revert the commit and write A17-attempt-N-
next-blocker.md. The supervisor will pivot strategy.

## Cost expectation

~90-120 min. The emit rewrite is ~30 LoC plus the multi-instruction
emit signature (potentially new helper in IGenARM64.cpp). Then a
full arm64 rebuild + CGO regen + qemu + device validation cycle.

## Rate-budget caution

Weekly rate at 88% — well past the natural halt threshold. User
has explicitly granted autonomy. If A17 doesn't pass cleanly on
attempt 1, honest-exit fast.
