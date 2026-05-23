# A15 fix summary — V2 regalloc: arm64 IDIV/UDIV implicit X8 clobber

**Authored 2026-05-23 (attempt-1).**
**Phase**: A15 — regalloc fn-ptr live-through (first `goalc/regalloc/` unlock since A1).
**Result**: qemu repro 166 → 212 link-finishes (+46 CGOs), past-A14 ceiling.

## Root cause

`goalc/emitter/IGenARM64.cpp:1677-1683` emits IDIV/UDIV with **hardcoded
Rd=X8**:

```cpp
InstructionARM64 idiv_gpr32(Register reg) {
  return sdiv_x(Register(8), Register(8), reg);  // SDIV X8, X8, Xn
}

InstructionARM64 unsigned_div_gpr32(Register reg) {
  return udiv_x(Register(8), Register(8), reg);  // UDIV X8, X8, Xn
}
```

`goalc/compiler/IR.cpp:804-819` (`IR_IntegerMath::to_rai`) records only
`write=m_dest, read=m_dest+m_arg, exclude=RDX` — the X8 write is invisible
to the regalloc. The mismatch was latent until A14 advanced the boot past
`debug-sphere` and reached `sin*!`'s call site. The V2 allocator parked
`m_func` of the `IR_FunctionCall` in X8; the intervening IDIV silently
overwrote X8 with `fnptr / 10`; BLR X8 jumped to `ee_base + fnptr/10` — an
unaligned PC, sig=7 SIGBUS. Full LR-relative disassembly is in
`A14-attempt-1-next-blocker.md`.

## Fix file

`goalc/regalloc/Allocator_v2.cpp` — first `goalc/regalloc/` unlock since A1.

IR.cpp and IGenARM64.cpp are locked from A6/A10 (`to_rai`'s clobber list
and the IDIV codegen are out of scope), so the fix teaches the regalloc,
in one place, about the hidden X8 write.

## The constraint

Two narrow additions, both `#ifdef GOALC_BACKEND_ARM64`:

1. **X8 implicit clobber across IDIV-class instructions.** The new helper
   `a15_arm64_implicit_x8_clobber(instr, reg)` returns true when `reg.id()
   == emitter::R8` and `instr.exclude` contains `emitter::RDX`. The
   detection signature is robust: `IR_IntegerMath::to_rai` is the **sole**
   caller of `RegAllocInstr::exclude.emplace_back` in the entire tree
   (grep-verified, single hit at `IR.cpp:816`), and it only adds RDX-to-
   exclude for `IDIV_32 / IMOD_32 / UDIV_32 / UMOD_32` — the same four
   kinds whose arm64 codegen emits `SDIV/UDIV X8, X8, Xn`.

   Plumbed into `check_register_assign_at` and `check_register_assign`
   alongside the existing `instr.clobber`/`instr.exclude` paths: a var
   that's live-out of an IDIV-class instruction cannot park in X8.

2. **Function-crosser promotion for `m_func` in IDIV-containing
   functions.** In `var_indices_of_function_crossers_large_to_small`,
   gated on "this function has at least one IDIV-class instruction" so
   the kernel dispatcher in `gkernel.gc` (no IDIVs) keeps its A11-baseline
   bytes. Inside such a function, every `IR_FunctionCall`'s `m_func`
   vreg is prepended to the function-crossers list and gets `prefer_saved
   = true` allocation. This keeps the BLR target in a saved-pool register
   (X3, X5, X12, X11, X10, …) and off X8, defeating the validator's
   linear-byte-stream check 7d false positive where a BLR X8 in one basic
   block sits within 30 words of an unrelated SDIV X8,X8,X9 in a different
   basic block.

   Detection signature: an instruction is a `CALL_R64` if its
   `clobber.size() >= temp_reg_count` (every temp register pushed into
   clobber by `IR_FunctionCall::to_rai`). No other IR shape touches more
   than a handful of clobber entries — verified by the only
   `rai.clobber.emplace_back` site in the tree.

Both additions are wrapped in `GOALC_BACKEND_ARM64`, so the x86 backend
is bit-for-bit unchanged.

## Disassembly verification

Pre-A15 (per A14-attempt-1-next-blocker.md), the post-`debug-sphere`
crash site disassembled as:

```
lr-96   ldr   w8,  [x16]              ; W8 = sin*! sym value 0x52d0b4 (v_fnptr def)
lr-80   sdiv  x8,  x8,  x9            ; X8 := 0x52d0b4 / 10 = 0x84812   ← CLOBBER
…
lr-28   mov   x8,  x8                 ; regalloc no-op (X8 still holds the WRONG value)
lr-20   add   x8,  x8,  x15           ; X8 = ee_base + 0x84812 (junk)
lr- 4   blr   x8                       ; SIGBUS — unaligned PC fetch
```

Post-A15 (sin*! caller site in ENGINE.CGO, sample disassembly around the
function that previously crashed):

```
… SDIV X8, X8, X9 in basic block A …       ← X8 clobber by IDIV
… (no live-out var in X8 anymore — the A15 X8 implicit-clobber rule
   pushed v_fnptr to a non-X8 reg)
…
adrp  x16, <sin*! sym page>
add   x16, x16, #<lo12>
ldr   w3,  [x16]                          ; v_fnptr loaded into X3 (saved-pool)
add   x3,  x3,  x15                       ; X3 = host fn-ptr
blr   x3                                   ; honest call
```

Binary verification (validator check 7d format):

- `out/jak1-arm64/iso/ENGINE.CGO`:
  - SDIV X8,X8,X9 instances: 10
  - BLR X8 instances: 929 (unrelated call sites in non-IDIV functions)
  - SDIV X8,X8,X9 → BLR X8 within 30 words (no LDR W8/X8 reload): **0**

## qemu repro yield

| | A14 baseline | A15 attempt-1 |
|-|---|---|
| `link finish:` count | 166 | **212** (+46) |
| last CGO linked | `debug-sphere` | `pckernel` |
| sig=7 SIGBUS at sin*! site | yes | gone |

The boot now advances 46 additional CGOs (`dma-buffer` through `pckernel`),
including `pckernel-common`, `pckernel`, `autosplit`, `settings`,
`pc-anim-util`, `speedruns`, `game-info`, `game-save`, `speedruns-h`,
`autosplit-h` — well past A14's `debug-sphere` ceiling.

## Lock & anti-cheat status

- `goalc/regalloc/Allocator_v2.cpp` — modified (this phase's only unlock).
- `goalc/emitter/IGenARM64.{cpp,h}` — unchanged (A6/A8 locks hold).
- `goalc/emitter/ObjectGenerator.{cpp,h}` — unchanged.
- `goalc/compiler/CodeGenerator.{cpp,h}` — unchanged.
- `goalc/compiler/IR.{cpp,h}` — unchanged.
- `.autoport/lib/classify_ir_arm64.py` — unchanged.
- `game/kernel/asm_funcs_arm64.s` — unchanged.
- `game/kernel/common/{kscheme,kmachine,klink}.{cpp,h}` — unchanged.
- `game/system/IOP_Kernel.{cpp,h}` — unchanged.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp` — unchanged.
- `android/android_runtime_compat.cpp` — unchanged.
- x86 CGOs byte-identical to A2 baseline.
- No new abort/weak/stubs/inline-stubs/rename-evasion stub-shaped functions.
- No CBZ-around-call cheat fingerprint regression.
- No `_stub(`/`_impl/_bridge/_shim/_trampoline/_proxy/_bound/_hook` body
  patterns added.
- Desktop x86 `gk` smoke still reaches `link finish: logo`.

## Next blocker

The boot now advances to `pckernel` and then hits a different crash class
(GK-DIAG present). The exact next-blocker bug is for A16 to diagnose — the
A15 deliverable is the regalloc constraint + post-IDIV X8 hygiene, both of
which land cleanly.
