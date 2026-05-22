# Phase A7 — emitter unit-test harness

## Status

**Authored 2026-05-23 by the supervisor** with user sign-off.
Tooling phase — no codegen changes. Builds a fast, deterministic
test harness so future emitter cascade bugs (A8+, F1's renderer
side, etc.) get caught in seconds instead of 3-minute device cycles.

## Bucket

A — emitter / linker (tooling layer).

## Motivation

A5+A6 cascaded through ~10 distinct arm64 emitter helper bugs over
~8 hours of wall time, each iteration costing ~3 min on device:

- LDR/STR W-form imm12 overflow (A5)
- 6 off-register `(void)off;` helpers (A6)
- `make_function_from_c` emitted x86 unconditionally (A6)
- FFI trampoline shuffle GOAL arg regs → AAPCS slots (A6)
- klink sym-PTR ADRP+ADD → MOVZ+MOVK rewrite (A6)
- Stack-arg trampoline shuffle (A6)
- `call_r64` caller-save register clobber (A6)

Every one of those was a 30-second unit test waiting to happen.
F1 (renderer port) will exercise XMM/vector emitter helpers that
the kernel-boot path barely touches — those will surface MORE
emitter bugs. A7 makes that next cascade fast.

## Goal (concrete)

A `.autoport/tests/emitter/run.sh` that:

- Builds + runs ALL emitter unit tests in **under 30 s total**
  on this host (cold start)
- Exits 0 iff every test passes
- Tests call the REAL `goalc/emitter/IGenARM64.cpp` and
  `goalc/emitter/ObjectGenerator.cpp` functions — never a forked
  copy
- Covers every emit_* / encode_* function used by GOAL bytecode
  generation, with at least one test per function

## Scope (two levels)

### Level 0 — encoding-only (C++ assert)

For each `emit_*` function in IGenARM64.cpp, write a unit test that
calls it with canonical inputs and asserts the produced 32-bit
instruction word matches the expected encoding.

Example shape:

```cpp
TEST_CASE("emit_add_w_register canonical encoding") {
    InstructionARM64 instr = emit_add_w(W0, W1, W2);
    ASSERT_EQ(instr.encoding, 0x0B020020u);  // ADD W0, W1, W2
}
```

Catches bugs like:
- `make_function_from_c` emitting x86 opcodes (the encoding would
  not match the expected arm64 pattern)
- `(void)off;` dropping an operand (the encoding would not include
  the off register)
- imm12 overflow producing a NOP (the encoding would be 0xD503201F
  instead of the LDR pattern)

Speed: < 1 ms per assertion. Hundreds run in < 1 s.

### Level 1 — execute under qemu-aarch64-static

For each emitter helper that produces multi-instruction sequences
(the trampolines, MOVZ+MOVK, register shuffles), build a small
arm64 ELF that exercises the sequence end-to-end and run it under
`qemu-aarch64-static`. Verify exit code / stdout matches the
expected output.

Example shape:

```bash
# test_ffi_aapcs_shuffle.s — assemble + run + check exit
$AARCH64_AS -o test.o test_ffi_aapcs_shuffle.s
$AARCH64_LD -static -o test test.o
ACT=$(qemu-aarch64-static ./test; echo $?)
[ "$ACT" = "42" ] || fail "expected 42, got $ACT"
```

Catches bugs like:
- FFI shuffle puts arg in wrong AAPCS slot
- BLR clobbers a caller-save GOAL needs preserved
- Stack-arg shuffle uses wrong stack offset
- klink sym-PTR resolution produces wrong absolute address

Speed: ~30 ms per test under qemu-user. Dozens run in < 5 s.

### Skipped — Level 2 (full goalc pipeline)

End-to-end "compile a GOAL function, execute, check output"
overlaps with d4_run.sh device cycle. Not worth duplicating.

## Required deliverables

```
.autoport/tests/emitter/
├── README.md                          # what each test verifies
├── run.sh                             # entrypoint: builds + runs all, exit 0 = green
├── encoding/                          # Level 0
│   ├── CMakeLists.txt                 # links against goalc/emitter/* objects
│   ├── test_helpers.h                 # assertion macros
│   ├── test_arithmetic.cpp            # add/sub/mul/div + W/X variants
│   ├── test_loads.cpp                 # load_goal_* + W/X/Q variants
│   ├── test_stores.cpp                # store_goal_* + W/X/Q variants
│   ├── test_branches.cpp              # b/bl/blr/bcond/cbz/cbnz
│   ├── test_far_relocs.cpp            # the A5-introduced MOVZ+MOVK ADRP+ADD class
│   └── test_far_reloc_ptr.cpp         # the A6 sym-PTR rewrite
└── exec/                              # Level 1
    ├── run_exec_tests.sh              # iterate exec/*.s under qemu
    ├── lib_common.s                   # shared prologue/epilogue
    ├── test_make_function_arm64.s     # confirm trampoline shape
    ├── test_ffi_aapcs_shuffle.s       # GOAL arg regs → AAPCS shuffle
    ├── test_call_r64_saves.s          # BLR caller-save restoration
    └── test_sym_ptr_movz.s            # MOVZ+MOVK GOAL offset resolution
```

## Cross-compile environment (host-specific)

This Fedora 43 host has:
- `aarch64-linux-gnu-gcc` / `aarch64-linux-gnu-as` / `aarch64-linux-gnu-ld`
- `qemu-aarch64-static` at `/usr/bin/qemu-aarch64-static`
- **`libstdc++` for aarch64 NOT installed** — Level 1 tests must
  be C or pure assembly, statically linked, no libstdc++

## Anti-cheat invariants

The phase MUST NOT modify any of these (verified by validator):

- `goalc/compiler/IR.cpp`, `goalc/emitter/IGenARM64.h`,
  `goalc/emitter/IGenARM64.cpp`, `goalc/emitter/ObjectGenerator.h`,
  `goalc/emitter/ObjectGenerator.cpp`,
  `goalc/compiler/CodeGenerator.{cpp,h}` — codegen lock from A6-close
- `.autoport/lib/classify_ir_arm64.py` — locked since A1
- The tests must `#include` the real headers and link against the
  real object files, NOT a forked subset

If a test FAILS on the current codegen, that means the emitter has
a bug — but the test must FAIL HONESTLY (assertion fires), not
silently pass by stubbing the emitter.

## What "PASS" means

- `.autoport/tests/emitter/run.sh` exits 0
- Total runtime < 30 s on this host
- Every `emit_*` function in IGenARM64.cpp has at least 1 test
- Validator's grep confirms tests link against real
  `goalc/emitter/` sources (not a forked test copy)
- Codegen + classifier lock files byte-identical to A6-close

## Cost estimate

2-4 hours / $30-60. Builds tooling that saves time on every future
codegen-touching phase. Net positive if F1 (renderer port) surfaces
any emitter bugs (highly likely).
