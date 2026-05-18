# Phase 06 — Scalar floating-point codegen

## Goal

Implement scalar single/double-precision float ops. Validator: `float` tests pass; no regression.

## Scope

- Move between integer and float regs: `fmov` w↔s, x↔d, immediate forms
- Arithmetic: `fadd`, `fsub`, `fmul`, `fdiv`, `fneg`, `fabs`, `fsqrt`
- Compare: `fcmp` (sets flags, then conditional branches as in phase 04)
- Conversion: `fcvtzs` (float → int with truncation), `scvtf` (int → float), `fcvt` (single↔double)
- Loads/stores: `ldr s/d`, `str s/d` (extends phase 03)

## Caveats

- NaN handling: x86 and ARM have slightly different default NaN propagation. Match what goalc/the game expects (likely IEEE754 default).
- Denormals: ARM has FZ (flush-to-zero) bit in FPCR. The default on Linux is *not* FZ. Verify the game's float behavior doesn't depend on FZ on x86.
- Rounding modes: leave as default (round-to-nearest-even).

## Success

```bash
ctest -L float --output-on-failure
ctest -L "int-arith|mem-ops|control-flow|abi" --output-on-failure  # no regression
```
