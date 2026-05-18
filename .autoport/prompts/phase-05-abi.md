# Phase 05 — Function calls and AArch64 ABI

## Goal

Implement the calling convention plumbing so GOAL functions can call each other and call into C++ runtime. Validator: `abi` tests pass; full Jak 1 build cross-compiles cleanly (link only, no execution).

## Scope

- AAPCS64 calling convention:
  - x0..x7: integer/pointer argument registers
  - v0..v7: floating-point argument registers
  - x8: indirect result location
  - x18: platform register (reserved on Linux/Android)
  - x29: frame pointer
  - x30: link register (return address)
  - SP: stack pointer (must be 16-byte aligned at public function boundaries)
- Caller-saved vs callee-saved registers (x19..x28 callee-saved; x9..x15 caller-saved)
- Stack frame prologue/epilogue (stp x29, x30, [sp, #-16]! / ldp ... + ret)
- The GOAL↔C++ trampoline equivalent of `game/kernel/asm_funcs.asm` — create `game/kernel/asm_funcs_arm64.S` with the same set of entry points but in AArch64 assembly.
- Update CMakeLists to pick the right .asm/.S based on target architecture.
- Update the regalloc (`goalc/regalloc/`) to understand the AArch64 register file: 31 general-purpose x-registers (x0..x30) and 32 v-registers. Mark the right ones reserved (sp, fp, lr, x18, x16/x17 for trampolines).

## This is the hardest pre-Jak-boot phase

You are modifying the register allocator. This is where miscompiles love to hide. Be paranoid. Add lots of diff-tests:

- Many-argument calls (more than 8 args → spill to stack)
- Recursive calls
- Tail calls if goalc supports them
- Calls that cross GOAL↔C++ boundary in both directions
- Functions that use all 10 callee-saved registers
- Functions that return structs (uses x8)

## Constraints

- Do NOT modify any code under `goal_src/`. The GOAL kernel source is the same.
- Document every divergence from the x86 ABI in `goalc/emitter/IGen_arm64.cpp` with a comment.

## Success

```bash
ctest -L abi --output-on-failure
# Full cross-compile sanity:
cmake -B build-arm64 -G Ninja -DGOALC_BACKEND=arm64
cmake --build build-arm64
```
