# Phase A15 — regalloc fix: function-pointer source must live through intervening defs before BLR

## First step — read the cookbook

Read `.autoport/CODEGEN_COOKBOOK.md` first. ~30 seconds vs 5–15
minutes of rediscovery.

## Status

**Authored 2026-05-23 by the supervisor** after A14 closed
`__mem-move` (commit da0fbacc4) and the boot ceiling advanced from
158 → 166 link-finishes (+8 CGOs including `dma-buffer`, `dma-bucket`,
`pc-cheats`, `pckernel-h/impl`, ..., `debug-sphere`). The post-A14
crash is a different bug class from A11/A12/A14's unbound-sym
cascade: a sig=7 SIGBUS via BLR-to-unaligned-PC where the BLR's
target register was clobbered by an SDIV.

**The cascade has changed shape.** This is the first codegen-side
bug in the cascade since A10. A15 unlocks `goalc/regalloc/` for the
first time since A1.

## Bucket

A — codegen (register allocator).

## Motivation

Per `.autoport/reports/A14-attempt-1-next-blocker.md`'s
disassembly:

```
lr- 96  b9400208  ldr   w8,  [x16]              ; w8 = sin*! sym value = 0x52d0b4
lr- 92  d2801680  mov   x0,  #0xb4              ; arg 0
lr- 80  9ac90d08  sdiv  x8,  x8,  x9            ; x8 = 0x52d0b4 / 10 = 0x84812  ← CLOBBER
lr-…    (float arith, FDIV / FMUL / SCVTF, x8 unread)
lr- 28  aa0803e8  mov   x8,  x8                 ; "preserve" the WRONG value
lr- 20  8b0f0108  add   x8,  x8,  x15           ; X8 = ee_base + 0x84812 (junk)
lr-  4  d63f0100  blr   x8                       ← SIGBUS (unaligned PC)
```

The V2 register allocator assigned the function-pointer source
(load at `lr-96`) AND the SDIV destination (the `/10` for degree-to-
radian scaling) to the same physical register X8. There's no
intervening reload of the fn-ptr; the regalloc thought the SDIV
was safe because X8 wasn't read between `lr-92` and `lr-28` — but
it's read by the BLR at `lr-4` via the no-op `mov x8, x8` chain.

Diagnosis: the live-range computation does not mark a CALL_R64's
target register as live-through any IR op whose destination is the
same vreg. The fix is to add that constraint.

## Goal (concrete, narrow)

In `goalc/regalloc/Allocator_v2.cpp`, add ONLY the X8 implicit-clobber
awareness for IDIV-class instructions:

> Detect IDIV/UDIV-class IR instructions (via their unique
> `exclude={RDX}` signature — IR.cpp:816 is the SOLE caller of
> `RegAllocInstr::exclude.emplace_back` in the tree) and treat X8 as
> implicitly clobbered across them inside
> `check_register_assign_at` and `check_register_assign`. A vreg
> live-out of an IDIV-class instruction cannot park in X8 on arm64.

This is the surgical fix for the sin*! sig=7 SIGBUS bug.

## ⚠️ Lessons from attempt-1 (reverted at 316b31d0c + cfb2a3c55)

The first attempt also added a "function-crossers promotion" that
forced every `IR_FunctionCall::m_func` vreg into saved-first allocation
inside any function containing an IDIV. **DO NOT DO THIS.** It was
added to satisfy attempt-1's overly-aggressive validator check 7d
(now relaxed), not because the underlying bug required it.

The function-crossers promotion changes register usage broadly across
the function, and on the real Redmi Note 9 Pro device caused the boot
to crash with sig=4 SIGILL at PC=0x72072df604 (in math-camera-h's
top-level — 113 link-finishes WORSE than A14). qemu-aarch64-static
ran the same instruction sequence cleanly; only real hardware
refused it. **Device is the ground truth.**

ONLY do the X8 implicit-clobber awareness. Don't touch the
function-crossers allocation path, don't pin m_func to saved-first,
don't add any "broader" regalloc constraints to satisfy validator
checks. The validator's check 7d has been relaxed precisely so that
the surgical fix can land without provoking the broader change.

## ⚠️ Device-first verification

qemu_repro is a proxy, not the goal. After your fix:

1. Verify qemu_repro advances past 166 (good signal but not sufficient).
2. Verify D4 device validator on the Redmi Note 9 Pro (eae4df44) ALSO
   advances past 166. If qemu advances but device REGRESSES (the
   attempt-1 failure mode: +46 qemu, -113 device), the fix is broken
   — revert it and write an honest-exit next-blocker explaining what
   the device CPU refused.

## Scope (locks)

**UNLOCKED for A15 only:**

- `goalc/regalloc/` — narrow: the live-range / liveness-propagation
  path that handles CALL_R64 target-reg lifetimes. Other regalloc
  invariants (spill ops, AAPCS arg shuffles) unchanged.

**STILL LOCKED** (carried forward from A6–A14):

- `goalc/emitter/IGenARM64.{cpp,h}` (A6/A8 unlocks closed).
- `goalc/emitter/ObjectGenerator.{cpp,h}` (A5/A8 closed).
- `goalc/compiler/CodeGenerator.{cpp,h}` (A9 closed; A10 cleaned
  up A9's workaround).
- `goalc/compiler/IR.{cpp,h}` (A10 closed).
- `.autoport/lib/classify_ir_arm64.py`.
- `game/kernel/asm_funcs_arm64.s`.
- `game/kernel/common/kscheme.cpp`.
- `game/kernel/common/kmachine.cpp`.
- `game/system/IOP_Kernel.{cpp,h}`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp` (A13's IOP
  init stands).
- `android/android_runtime_compat.cpp`.
- `game/kernel/common/klink.{cpp,h}` (A11/A12/A14 bindings stand).
- `.autoport/lib/*.sh`, `.autoport/lib/*.py`,
  `.autoport/validators/*.sh` (supervisor-owned).

## Anti-cheat invariants

Inherited from A6–A14 (see cookbook §6 + §11). **Key change**:

- arm64 CGOs WILL byte-change vs A11 baseline (the regalloc fix
  produces different bytes — that's the point). A15 must regenerate
  the baseline file and the validator's check 7b uses the NEW A15
  baseline going forward.
- x86 CGOs MUST stay byte-identical to A2 baseline (the regalloc
  change must be conditional on the arm64 backend).
- The fix must be a REAL regalloc constraint, not:
  - A stub function returning the fn-ptr (rename-evasion bait).
  - A binary patch that injects `MOV X8, [saved]` after the SDIV
    (that's the CBZ-cheat shape).
  - A C++ workaround that runtime-reloads the sym before every BLR
    (that's a structural cheat — the bug is the allocator's, not
    the runtime's).
- Inline-stub + rename-evasion detectors still fire.
- D4 hardened SDL/GL check (≥3/5 markers, no dodge).
- Desktop x86 `gk` smoke still reaches `link finish: logo`.
- Link-finish count regression check: ≥ 166 (A14 ceiling).
- Strict advance check: > 166.

## Binary-level verification

Post-fix, the disassembly of the failing call site MUST show one
of these patterns (verified by `aarch64-linux-gnu-objdump -d` on
`out/jak1-arm64/iso/ENGINE.CGO` near `sin*!`'s callers):

(a) **Different physical reg**: the SDIV destination is now Xn
    (n != 8), the BLR target stays X8.
(b) **Reload of fn-ptr**: the BLR site re-loads the fn-ptr from
    its sym slot just before the BLR (extra LDR W8, [X16] right
    after the SDIV).
(c) **Spill+reload**: the fn-ptr is spilled to stack before the
    SDIV and reloaded into the BLR target reg before the call.

If the disassembly shows the same `SDIV X8, X8, ... ; ... ; BLR X8`
pattern, the fix didn't actually constrain the allocator — that's
a no-op cheat and fails.

## Required deliverables

1. The regalloc constraint change in `goalc/regalloc/`.
2. arm64 CGOs regenerated; new
   `.autoport/reports/A15-baseline-arm64-cgo-hashes.txt`.
3. CGO sync into APK assets:
   `cp out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO \
    android/app/src/jak1/assets/iso_data/jak1/`
4. `bash .autoport/lib/qemu_repro.sh` — must reach > 166 link-finishes.
5. `bash .autoport/validators/phase-A15-regalloc-fnptr-livethrough.sh`
   exits 0.
6. `.autoport/reports/A15-fix-summary.md` — names the regalloc file
   + the live-range constraint added + a disassembly snippet showing
   the new pattern at the previously-failing call site.

## Honest exit condition

If the regalloc fix lands but another bug surfaces (likely — the
boot will go deeper), commit the fix + new baseline + write
`A15-attempt-N-next-blocker.md`. The supervisor will read it and
author A16.

## Cost expectation

~90-120 min. The fix is small (likely <30 LoC) but requires:
- Reading the V2 allocator to find the live-range computation.
- A full arm64 rebuild + CGO regen + baseline update.
- Verifying the bug pattern is gone at the byte level.

## Rate-budget caution

Weekly rate at 85% — **PAST the natural halt threshold**. The user
has explicitly overridden halt to continue. If A15 doesn't pass on
attempt 1, honest-exit IMMEDIATELY with a next-blocker — no spin
retries.
