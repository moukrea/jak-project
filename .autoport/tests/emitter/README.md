# Emitter unit-test harness (phase A7)

Fast, deterministic tests for `goalc/emitter/IGenARM64.cpp`. Runs in under
30 seconds end-to-end, catches the cascade of bugs that A5/A6 surfaced one
3-minute device cycle at a time:

- LDR/STR W-form imm12 overflow → silent NOP (A5)
- `(void)off;` helpers dropping the EE-base register (A6)
- `make_function_from_c` emitting x86 opcodes (A6)
- FFI trampoline forgetting AAPCS slot shuffle (A6)
- klink sym-PTR ADRP+ADD vs MOVZ+MOVK rewrite (A6)
- `call_r64` caller-side callee-saved register clobber (A6)

## Layout

```
encoding/                Level 0 — pure encoding asserts (C++ static link
                         against the real goalc/emitter/IGenARM64.cpp,
                         compiled into a one-shot test binary)
exec/                    Level 1 — handwritten arm64 asm exercised end-to-end
                         under qemu-aarch64-static
run.sh                   Entrypoint — builds + runs both levels in sequence
```

## Running

```
bash .autoport/tests/emitter/run.sh
```

Exit 0 iff every encoding assertion and every qemu exec test passes.

## Adding a new emit_ helper

1. Add the helper to `goalc/emitter/IGenARM64.{h,cpp}`.
2. Append its name to `encoding/test_coverage_manifest.cpp` (the
   `kAllIGenArm64Helpers` array) and bump the size assertion.
3. Write at least one encoding test for the helper in the appropriate
   `encoding/test_*.cpp` (arithmetic / loads / stores / branches /
   far_relocs / far_reloc_ptr), or add a new test_*.cpp + entry in
   `encoding/CMakeLists.txt`.
4. If the helper emits a multi-instruction sequence with semantic
   invariants beyond byte-equality (preserves a register across a call,
   reconstructs a 64-bit constant, etc.), add a matching `exec/test_*.s`
   handwritten reference.

## Anti-cheat

The harness compiles the REAL `goalc/emitter/IGenARM64.cpp` — never a forked
copy. The A7 validator greps `encoding/CMakeLists.txt` for the path to
enforce that. No assertion stubs: every `EXPECT_ENC` must match a bit-exact
encoding derived independently from the ARM ARMv8-A ISA reference.

Codegen-locked since A6-close: A7 is tooling-only. No file under
`goalc/compiler/`, `goalc/emitter/IGen*`, or `goalc/emitter/ObjectGenerator*`
is modified by this phase.
