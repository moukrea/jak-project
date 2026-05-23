# A6 attempt 5 — final blocker (CodeGenerator.cpp spill-NOP bug)

Authored 2026-05-23 by attempt-5 worker. This builds on attempt-4's
report, narrows the root cause to a single line in
`goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64`, and
demonstrates that the bug cannot be fixed within A6's lock anchors.

## TL;DR

The display.gc top-level NULL-fn-ptr BLR is rooted in a 4-line block
in `goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64` that
emits NOPs as placeholders for the regalloc's spill load/store ops:

```cpp
for (const auto& op : bonus.ops) {
    if (op.load) {
        m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);
        // ^^ NOP placeholder. SHOULD be `STR Xt, [SP, #imm]` (store)
        //    or `LDR Xt, [SP, #imm]` (load).
    }
}
ir->do_codegen_arm64(&m_gen, allocs, i_rec);
for (const auto& op : bonus.ops) {
    if (op.store) {
        m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);
        // ^^ same.
    }
}
```

The comment in that function explicitly admits the gap:

```cpp
// We deliberately do not implement saved-reg backup / spill restore: the
// GOAL register allocator is x86-shaped and the synthetic phase-24 smoke
// file's four functions are tiny enough that all values stay live in
// caller-saved registers. [...] If a function ever needs spills the
// regalloc will assert and we'll know to expand this.
```

…but the regalloc never asserts. When display.gc's top-level (a big
function with many live values) compiles, the V2 regalloc spills 1-N
vars to stack. Each spill load/store becomes a NOP. The spilled
value is silently lost; the consumer reads stale register state.

For the specific BLR-target case: the regalloc spills the
function-pointer ireg, the arg-shuffle writes another value into the
chosen register, the NOP reload doesn't restore the function pointer,
and `BLR X3` fires with whatever stale value is in X3 (in our
captures: either `0` from a literal-0 IR_LoadConstant64, or `0x18`
from a literal-24 IR_LoadConstant64 — depending on which ireg
"won" X3 in the contention).

## What this attempt added

Two arm64-only fixes already committed at `01fbfc703`:

1. **`goalc/compiler/compilation/Function.cpp`** —
   `compile_real_function_call` now emits `IR_RegSet(temp_function,
   function)` BEFORE the arg `IR_RegSet`s on arm64. This shortens the
   `function` ireg's live range (def→IR_RegSet) so it doesn't span
   the arg shuffle, and makes `temp_function` the long-lived
   function-pointer holder that crosses the call boundary.

2. **`goalc/regalloc/Allocator_v2.cpp`** —
   `var_indices_of_function_crossers_large_to_small` (arm64-only)
   also includes vars whose last use is a move that feeds an existing
   function crosser. Prepended (not appended) so feeders win
   first-dibs on saved regs before bigger crossers claim them all.

Combined effect: the function-pointer ireg is no longer the var that
contends with arg-shuffle for X2. Different vars now contend, with
different specific values surviving in X3 at BLR time:

| Attempt           | BLR target X3 value          | Source                       |
|-------------------|------------------------------|------------------------------|
| attempt-4 (pre)   | `X15 + 0` (NULL fn-ptr)      | literal-0 of `(... 0 ...)`   |
| attempt-5 (post)  | `X15 + 0x18` (host of GOAL 24)| literal-24 of `(... 24 ...)` |

In both cases the underlying mechanism is identical: a var with a
literal small-int value gets allocated to X3 (RBX, a saved reg),
survives the arg shuffle (because saved regs aren't clobbered by
the AAPCS-style arg-position writes), and the NOP spill-reload
doesn't overwrite X3 with the actual function pointer. The
function pointer is "in the regalloc's intent" placed in X3, but
the load that should have realised that intent is a NOP. So X3
holds whatever the EARLIER MOVZ left there.

Decoded LR-byte sequence (attempt 5, iter 12 on device):

```
lr-100:  d2800303    movz x3, #0x18              ; X3 = 24 (literal arg y)
...
lr-44:   aa0303e8    mov  x8, x3                 ; X8 = 24 (arg-4 position)
lr-28:   aa0c03eb    mov  x11, x12               ; arg-7 setup
lr-24:   d503201f    nop                         ; *** SPILL LOAD PLACEHOLDER
                                                   ; should be: ldr x3, [sp, #spill_slot]
lr-20:   8b0f0063    add  x3, x3, x15            ; X3 = host of GOAL ptr 24
lr-16:   a9bf17e3    stp  x3, x5, [sp, #-16]!    ; call_r64 save
lr-12:   a9bf2fea    stp  x10, x11, [sp, #-16]!
lr-8:    f81f0ff7    str  x23, [sp, #-16]!
lr-4:    d63f0060    blr  x3                     ; *** CRASH: jumps to host of GOAL 24
```

The `nop` at `lr-24` is the smoking gun. With a real `LDR X3, [SP, #N]`
there, X3 would be filled with the spilled function pointer; the
subsequent `ADD X3, X3, X15; BLR X3` would dispatch correctly.

## Why we can't fix this in A6's locked scope

The fix is mechanical — replace the two `NOP placeholder` lines in
`do_goal_function_arm64` with calls that emit `STR Xt, [SP, #imm]`
and `LDR Xt, [SP, #imm]` from `op.reg` and `op.slot`. Both bits of
information are already in the `StackOp::Op` struct. The new
prologue would also need to subtract enough stack space for the
spill slots (currently `stack_usage = 16` is hardcoded).

But `goalc/compiler/CodeGenerator.cpp` is in A6's hard-locked file
list:

```bash
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    [ "$(git diff "$A4" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] || fail
done
```

Any byte-level diff against the A4 anchor fails the validator. The
4-line NOP-placeholder block has been there since A4 and is the
direct cause of the bug.

Workarounds attempted within the lock anchor:

- **Expanding `m_gpr_alloc_order`** to include more saved regs:
  unchanged CGO output (the V2 allocator uses its own internal
  `REG_saved_first_order` from `Allocator_v2.cpp`, not Register.cpp's
  field).

- **`REG_saved_first_order` reorder** (Allocator_v2.cpp, arm64-only):
  doesn't help — the crossers competing for saved regs are already
  many; the regalloc still spills SOME var, which still emits a NOP.

- **Treating function-feeder vars as crossers**
  (Allocator_v2.cpp's `var_indices_of_function_crossers_large_to_small`,
  arm64-only): changed which var is spilled, but didn't eliminate the
  spill. New var that's now in X3 (literal 24) → same crash shape.

- **`compile_real_function_call` IR reorder** (Function.cpp,
  arm64-only): changed the live-range topology so `function` ireg is
  short. `temp_function` ireg becomes the crosser. But the regalloc
  still finds OTHER vars to spill (the literal args, which
  outnumber the saved regs). Same crash shape with a different
  value in X3.

The common thread: **as long as the regalloc spills ANY var on the
arm64 path, the NOP-placeholder emit silently loses it.** Eliminating
all spills in a function as big as display.gc's top-level requires
either (a) substantially expanding the saved-reg pool (which means
adding registers to the goalc Register enum — locked via
`goalc/emitter/IGenARM64.h`), (b) running the regalloc in a
spills-impossible mode (which means it fails compilation for any
function with high reg pressure, breaking dozens of unrelated
CGOs), or (c) emitting real spill instructions in
`CodeGenerator.cpp::do_goal_function_arm64`.

(c) is the obvious and correct fix. It requires unlocking
`CodeGenerator.cpp`.

## Recommendation to the supervisor

Insert **A8.1 (or extend A8's unlock)** to include
`goalc/compiler/CodeGenerator.cpp` with the narrow scope:
*emit real spill load/store instructions in
`do_goal_function_arm64` instead of NOP placeholders, and bump the
prologue stack reservation to cover `allocs.stack_slots_for_spills`
8-byte slots.*

The change is small:

```cpp
// Prologue: reserve stack for spills + the saved FP/LR pair.
int spill_bytes = allocs.stack_slots_for_spills * 8;
int stack_reserve = (spill_bytes + 15) & ~15;  // 16-byte align
m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xA9BF7BFDu),
                      InstructionInfo::Kind::PROLOGUE);  // stp x29,x30,[sp,#-16]!
m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0x910003FDu),
                      InstructionInfo::Kind::PROLOGUE);  // mov x29, sp
if (stack_reserve > 0) {
    // sub sp, sp, #stack_reserve
    uint32_t enc = 0xD10003FFu | ((stack_reserve & 0xfff) << 10);
    m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(enc),
                          InstructionInfo::Kind::PROLOGUE);
}
debug->stack_usage = 16 + stack_reserve;

// Per-IR spill load/store: emit real STR/LDR.
for (const auto& op : bonus.ops) {
    if (op.load) {
        // LDR Xt, [SP, #slot*8]
        uint32_t imm12 = (op.slot * 8) >> 3;  // scaled by 8 for 64-bit LDR
        uint32_t enc = 0xF9400000u | ((imm12 & 0xfff) << 10) | (31 << 5)
                       | (arm64_reg5(op.reg));
        m_gen.add_instr(emitter::InstructionARM64(enc), i_rec);
    }
}
// (similar for op.store with STR base 0xF9000000)
```

Total diff: maybe 20 lines. Once that lands, both my arm64 fixes from
`01fbfc703` continue to work (they reduce register pressure, which
reduces the spill count — both still improve allocation quality, but
the bug no longer requires zero spills to avoid).

A6 attempt 5 commits stay in place: they're independently correct
arm64-only allocator improvements that survive past the
CodeGenerator.cpp fix.

## What this attempt commits

- Diag handler enhancement (`android/gk_android_main.cpp`) — already
  in via `d8240257f` from A7's tooling, but the LR-byte dump it
  produces is what enabled this attempt's root-cause identification.
- `goalc/compiler/compilation/Function.cpp` — IR reorder
  (`01fbfc703`).
- `goalc/regalloc/Allocator_v2.cpp` — function-feeder heuristic
  (`01fbfc703`).
- `.autoport/reports/A6-baseline-arm64-cgo-hashes.txt` — regenerated
  with the above fixes (`e496ef9` and `01fbfc703`).
- This blocker analysis (`A6-attempt-5-blocker.md`).

The A6 validator still fails on the D4 re-pass for the reasons
above. F1 / E1-E3 will also fail until the spill-NOP bug is fixed
in `CodeGenerator.cpp`.
