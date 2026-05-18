# Phase 03 — Memory load/store codegen for AArch64

## Goal

Implement memory load/store instructions in IGen_arm64.cpp. Validator: diff-tests tagged `mem-ops` pass on both backends; no regression in `int-arith`.

## Scope

- `ldr` / `str` (32-bit and 64-bit, with all addressing modes goalc uses)
- `ldrb` / `strb` (byte)
- `ldrh` / `strh` (half)
- `ldrsb` / `ldrsh` / `ldrsw` (signed loads)
- Pre/post-indexed forms where the x86 emitter uses base+offset patterns
- `ldp` / `stp` (load/store pair) — used for stack frame setup, important for phase 05

## Approach

1. Read goalc/emitter/IGen.cpp for every load/store function. Mirror each.
2. AArch64 addressing modes:
   - `[Xn]` — base only
   - `[Xn, #imm]` — base + immediate offset (range depends on instruction)
   - `[Xn, Xm]` / `[Xn, Xm, LSL #s]` — base + scaled register
   - `[Xn, #imm]!` — pre-indexed (writeback)
   - `[Xn], #imm` — post-indexed
3. Immediate offset ranges differ by instruction size. For unaligned offsets or out-of-range immediates, x86 emits a single op; on arm64 you may need to materialize the offset in a temp register first. Document this in code comments.
4. Endianness: AArch64 is little-endian by default (matches x86). No swap needed for normal loads.

## New diff-tests under `test/diff/inputs/` tagged `mem-ops`:

- Read/write `int8/int16/int32/int64` to a stack slot
- Read/write through a base+offset pointer
- Signed vs unsigned byte/half loads (sign extension correctness)
- Pair load/store for register save/restore

## Success criteria

```bash
ctest -L mem-ops --output-on-failure   # all PASS both backends
ctest -L int-arith --output-on-failure # no regression
```
