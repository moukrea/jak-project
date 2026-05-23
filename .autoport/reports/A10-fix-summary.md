# A10 — IR.cpp stack-var address fix summary

Authored 2026-05-23. Closes the X4-vs-SP encoding gap left by A9 by
emitting `ADD Xd, SP, #imm12` (Rn = 31) directly inside IR.cpp for
`IR_GetStackAddr` and `IR_RegValAddr`, and removes the A9 X4=SP
pre-load workaround from `CodeGenerator.cpp::do_goal_function_arm64`.

## The bug A10 fixes

`goalc/emitter/IGenARM64.cpp::arm64_reg5(Register r)` returns
`r.id() & 0x1f`. The shared `Register` enum gives `RSP = 4`, so
`arm64_reg5(RSP) = 4` — the encoder writes the AArch64 X4 register
encoding instead of the SP encoding (which is Rn = 31). Every IR
that routed through `IGen::ARM64::mov_gpr64_gpr64(dst, RSP)` or
`IGen::ARM64::lea_reg_plus_off(dst, RSP, off)` emitted
`MOV/ADD dst, X4, …` instead of `MOV/ADD dst, SP, …`. X4 is whatever
the previous arg-shuffle left in it (kernel trampoline `st`, or
the most recent GOAL→C call's `mov x4, x8`), so stack-var addresses
resolved to garbage. Subsequent writes through that garbage pointer
stepped on the caller's `call_r64` X3/X5/X10/X11/X23 preserved-area
slots, producing the X3-clobber-after-BLR symptom captured in
`.autoport/reports/A9-attempt-1-next-blocker.md`.

A9 worked around this in `CodeGenerator.cpp`'s main IR loop by
emitting `ADD X4, SP, #0` (`0x910003E4`) immediately before each
`IR_GetStackAddr` / `IR_RegValAddr`, syncing X4 to the live SP value
so the broken IGen helpers' `mov/add dst, X4, …` evaluated to the
intended `mov/add dst, SP, …`. The workaround unblocked 19+ extra
CGOs (post-A9 reached `link finish: texture`, 64 link finishes; pre-A9
crashed at display.gc, ~45 link finishes). It came at the cost of one
extra 4-byte instruction per stack-var IR (~1.7 KB ENGINE, ~1.8 KB
GAME, 0 KB KERNEL — the kernel has no stack-var ops).

## What A10 does

`goalc/compiler/IR.cpp` now emits the correct encoding directly:

```c++
// A10 helper (anonymous namespace, near get_stack_offset).
static InstructionARM64 arm64_add_xd_sp_imm12(Register dst, uint32_t imm12) {
  ASSERT(imm12 <= 0xfff);
  uint32_t rd = static_cast<uint32_t>(dst.id()) & 0x1fu;
  uint32_t enc = 0x91000000u | ((imm12 & 0xfffu) << 10) | (31u << 5) | rd;
  return InstructionARM64(enc);
}
```

Encoding (ADD immediate, 64-bit, sf=1, op=add, S=0, sh=0):

```
  bits 31..22  1001 0001 00     (= 0x91 0..)
  bits 21..10  imm12
  bits 9..5    Rn = 31           (SP)
  bits 4..0    Rd
```

So `arm64_add_xd_sp_imm12(dst, 0)` returns `0x910003E0 | (dst.id() & 0x1f)`
which is the canonical encoding of `MOV Xd, SP` (an alias for
`ADD Xd, SP, #0`). When `imm12 != 0` we get `ADD Xd, SP, #imm12`.

### Call sites

`IR_RegValAddr::do_codegen_arm64` (was line 616 in IR.cpp):

```c++
void IR_RegValAddr::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                     const AllocationResult& allocs,
                                     emitter::IR_Record irec) {
  int stack_offset = get_stack_offset(m_src, allocs);
  auto dst = get_reg(m_dest, allocs, irec);
  ASSERT(stack_offset >= 0);
  gen->add_instr(arm64_add_xd_sp_imm12(dst, static_cast<uint32_t>(stack_offset)), irec);
  gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dst, emitter::gRegInfo.get_offset_reg()),
                 irec);
}
```

`IR_GetStackAddr::do_codegen_arm64` (was line 1581 in IR.cpp):

```c++
void IR_GetStackAddr::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto dest_reg = get_reg(m_dest, allocs, irec);
  int offset = GPR_SIZE * allocs.get_slot_for_var(m_slot);
  ASSERT(offset >= 0);
  gen->add_instr(arm64_add_xd_sp_imm12(dest_reg, static_cast<uint32_t>(offset)), irec);
  gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dest_reg, gRegInfo.get_offset_reg()),
                 irec);
}
```

The `offset == 0` branch is gone — `ADD Xd, SP, #0` is the canonical
`MOV Xd, SP` encoding, so one path covers both. All other IR_*
arm64 emits in IR.cpp are byte-identical.

### CodeGenerator.cpp follow-up

`do_goal_function_arm64`'s X4-pre-load workaround (the
`emitter::InstructionARM64(0x910003E4u)` emitted before each
`IR_GetStackAddr` / `IR_RegValAddr`) is removed; the comment block is
collapsed to a short pointer to this A10 doc. The rest of
`do_goal_function_arm64` (prologue/epilogue + spill load/store ops) is
byte-identical to A9.

## Byte-level verification

Pattern counts in the new `out/jak1-arm64/iso/ENGINE.CGO`:

| Pattern (LE bytes / hex)      | Decoded                | A9 count | A10 count |
|-------------------------------|------------------------|---------:|----------:|
| `e3 03 04 aa` / `0xAA0403E3` | `MOV X3, X4`           | 295      | **0**     |
| `e3 03 00 91` / `0x910003E3` | `ADD X3, SP, #0`       | 0        | **299**   |
| `0x910003E4`                  | `ADD X4, SP, #0` (workaround) | hundreds | **0**     |
| `0x910003E0..3FF` (any imm12, Rn=31, Rd∈0..15) | `ADD Xd, SP, #imm12` | small    | **3573**  |

Every `MOV X3, X4` instance produced by the A9-era stack-var emit is
gone and replaced by `ADD X3, SP, #0` (Rn=31 — correct SP read). The
~4 instances of `ADD Xd, SP, #imm12` per stack-var IR are also gone
from CodeGenerator.cpp's workaround (no more `0x910003E4` words).

## Boot progression (qemu_repro)

`bash .autoport/lib/qemu_repro.sh` extended boot:

| Phase                      | `link finish:` count | Last reached      | Crash site                          |
|----------------------------|---------------------:|-------------------|-------------------------------------|
| pre-A9                     | ~45                  | font-h            | display.gc NULL fn-ptr BLR          |
| post-A9 (spill + X4 workaround) | 64              | texture           | sig=4 SIGILL at ee_base (W9=0 sym-MEM) |
| **post-A10**               | **64**               | **texture**       | **same sig=4 SIGILL at ee_base**    |

A10 reaches the **same** boot ceiling as A9 attempt-2. That is the
expected outcome: A10 is a clean refactor — it replaces A9's
`mov X3, X4 ; pre-load X4=SP ; …` two-instruction sequence with a
single `add X3, SP, #imm12` semantically equivalent op. The boot
progression doesn't change because the next-layer bug (texture sym-MEM
= 0) is a different class outside A10's narrow IR.cpp unlock. See the
next-blocker section below for a follow-up phase.

`out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO` regenerated with the
patched compiler. New baseline saved to
`.autoport/reports/A10-baseline-arm64-cgo-hashes.txt`:

```
f4107e2bff1d627b8d6e7b1cceb921eb66a3201ffe54c6b753e8b7eb68d8a8f3  KERNEL.CGO
81b410874f6c6f7d5660c7f399051f01decc8feba69719e9ec1799a58a50566c  ENGINE.CGO
ddc16e88e016a1d81f29ff4bf4f1f0ca62a781e610aaf2a3651e5e795a326f89  GAME.CGO
```

The three x86 CGOs are byte-identical to the A2 baseline (verified by
`build_b1_arm64_cgos.sh` step 5 — A2 hashes in
`.autoport/reports/A2-baseline-x86-cgo-hashes.txt` matched). The desktop
`gk` reaches `link finish: logo` cleanly (validator check 9 / desktop
smoke).

## Honest scope of the A10 fix

A10's narrow IR.cpp unlock corrects every site where the
`arm64_reg5(RSP) → X4` collision corrupted stack-var arithmetic. The
boot reaches the same point as A9's workaround did; A10's bytes are
strictly cleaner (no X4 indirection, one instruction per stack-var IR
instead of two).

The remaining blocker — the **texture sym-MEM = 0 BLR-to-ee_base
SIGILL** — is a different bug class:

```
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x2126ab8058
GK-DIAG x9=0x2123000000   ; BLR target = ee_base (= GOAL ptr 0)
GK-DIAG x16=0x2123196b9c  ; sym-MEM addr (GOAL ptr 0x196b9c)
GK-DIAG x15=0x2123000000  ; ee_base — confirms x16 decoded correctly
```

The disassembly slice around `lr` (matches A9 attempt 2's report
byte-for-byte):

```
lr-52  ADRP X16, page          ; A5 sym-MEM ADRP
lr-48  ADD  X16, X16, #0xb9c   ; sym address materialised
lr-44  LDR  W9, [X16, #0]      ; W9 = sym value (= 0 — sym slot never bound)
lr-40  ADRP X8, page           ; arg0 address calc
…
lr-16  STP  X3, X5, [SP,#-16]! ; call_r64 push
lr-4   BLR  X9                  ; SIGILL: X9 = ee_base, *(u32*)ee_base = 0 = UDF #0
```

The sym slot at GOAL ptr 0x196b9c holds 0. The ADRP+ADD compute the
correct sym address (the A5 far-reloc encoding is correct — X16 in
the dump matches the expected slot). The slot just contains 0, which
means whatever symbol it backs has never been bound by any earlier
top-level execution.

This is **not** a stack-var or save-area corruption — it's either a
symbol-binding ordering bug (a `(define …)` in a later CGO's top-level
that an earlier CGO's top-level already referenced) or a deeper klink
fix-up issue (the LDR-literal patcher described in
`A8-displaygc-root-cause.md` could plant 0 in a slot if the literal
pool sits > 1 MB from the function). Neither root cause is reachable
from the narrow `IR.cpp` unlock A10 holds.

## Recommendation to the supervisor

Open **A11** (or B-class) with one of the following unlocks:

1. `game/kernel/jak1/klink.cpp` — instrument `klink_arm64_patch_pc_rel`
   to print every LDR-literal patch site whose imm19 == 0 (silent
   substitution). If the texture top-level execution hits one of those,
   that's the root cause.
2. `game/kernel/common/symbol.cpp` (and friends) — add a sym-MEM hash
   instrumentation so we can dump which symbols are bound at the point
   texture.gc's top-level starts executing. Identify the offending
   symbol; trace which CGO's top-level should have bound it; check link
   order.
3. `goalc/data_compiler/dir_tpages.cpp` / `link_data.cpp` — review CGO
   link order vs runtime initialisation dependencies. The
   `(define <sym>)` events live in each CGO's top-level; if the
   reference site's top-level runs first, the sym is still 0.

A10's IR.cpp fix stands across any subsequent unlocks — it is a strict
improvement (one cleaner instruction per stack-var IR, no X4
indirection). The D4 device validator should re-run against the A10
CGOs once the texture sym=0 root cause is closed.

## D4 device validator status

`bash .autoport/validators/phase-D4-android-apk-title.sh` cannot pass
end-to-end on this fix because the renderer never starts — the
texture sym=0 SIGILL kills the boot at `link finish: texture`,
before `android_renderer_run: entered` would fire and before any
SDL/GL initialisation. This mirrors A9-attempt-2's outcome on the
same physical Redmi Note 9 Pro device.

`.autoport/reports/A10-fix-summary.md` (this file) and
`.autoport/reports/A10-baseline-arm64-cgo-hashes.txt` document the
A10 deliverables for the supervisor's review. Per A10's "Honest exit
condition" the IR.cpp diagnostic + this next-blocker write-up are
committed even though the validator's check 7/8 cannot clear on this
phase's narrow unlock.
