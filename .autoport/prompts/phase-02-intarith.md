# Phase 02 — Integer arithmetic codegen for AArch64

## Goal

Replace the `brk #0` stubs in `IGen_arm64.cpp` with real AArch64 encodings for integer arithmetic. Validator: all diff-tests tagged `int-arith` pass on BOTH backends, AND no other diff-test regresses.

## Scope (only these operations in this phase)

For both i32 (w-registers) and i64 (x-registers):
- `add`, `sub`
- `mul`, `udiv`, `sdiv`
- `and`, `orr`, `eor` (bitwise and / or / xor)
- `lsl`, `lsr`, `asr` (shift left, shift right unsigned, shift right signed)
- `neg`, `mvn` (negate, bitwise not)
- Immediate variants of add/sub/and/orr/eor where the x86 emitter supports them.

**Do NOT** in this phase: memory ops, control flow, function calls, floats, SIMD. Those are later phases.

## Approach

1. **Read the ARM Architecture Reference Manual** (ARMv8-A) — specifically section C3 (A64 instruction set, base integer). The exact instruction encodings are well-specified. Don't guess.

2. **Read the existing x86 IGen.cpp** for each of these ops to understand:
   - The function signature (what register/immediate types it takes)
   - What goalc IR-level invariants the result must satisfy
   - How the result is consumed downstream

3. **For each instruction, implement:**
   - The encoding function in IGen_arm64.cpp (returns the 4-byte instruction)
   - Hook it into the instruction stream the same way the x86 version does

4. **Extend the diff-test corpus**: add `.gc` test cases under `test/diff/inputs/` tagged `int-arith` covering:
   - Each op with various operand values (positive, negative, zero, edge values like INT_MIN)
   - Combinations: `(+ (* a b) (- c d))` etc.
   - Signed vs unsigned division correctness (this is a classic bug site)
   - Shift amounts at 0, 1, 31/63, and (UB) > bitwidth

5. **Update CodeTester_arm64** so it can actually execute the generated code under qemu-aarch64-static. Approach: write the instructions to a temp file, link with a minimal `_start` stub that calls the test entry point and returns its result as the exit code, run under qemu.

## Pitfalls to watch for

- AArch64 register names: `w0` is the 32-bit view of `x0`. Writes to a w-register zero the upper 32 bits of x. The x86 emitter doesn't have this implicit zeroing — make sure your codegen accounts for it.
- AArch64 division: `sdiv` and `udiv` do NOT trap on divide-by-zero (returns 0) and do NOT trap on INT_MIN/-1 (returns INT_MIN). x86 traps. The diff-test must either avoid these cases or assert matching behavior consistently.
- Immediate encodings on AArch64 are tricky: the "logical immediate" form for and/orr/eor has a specific bitmask format. Do NOT roll your own; use a reference implementation or the well-known lookup-table approach.

## Success criteria

```bash
cmake --build build-arm64 --target goalc-diff-runner
cd build-arm64
ctest -L int-arith --output-on-failure   # all PASS on both backends
ctest --output-on-failure                # no regressions in other labels
```

The validator additionally checks that the corpus actually has ≥ 12 int-arith tests (not just 3 trivial ones).
