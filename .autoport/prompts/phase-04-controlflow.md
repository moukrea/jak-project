# Phase 04 — Branches, labels, comparisons

## Goal

Implement branch instructions and comparison-producing operations. Validator: `control-flow` tests pass on both backends; no regression in earlier tags.

## Scope

- `cmp`, `cmn` (compare, compare negative) — these set NZCV flags
- `tst` (test bits, sets flags)
- Conditional branches: `b.eq`, `b.ne`, `b.lt`, `b.le`, `b.gt`, `b.ge`, `b.lo`, `b.ls`, `b.hi`, `b.hs`
- Unconditional branch: `b` (PC-relative, ±128 MB)
- `bl` (branch with link — for function calls, but we'll only handle the encoding here; full call convention is phase 05)
- `cbz` / `cbnz` (compare-and-branch on zero/nonzero — useful peephole)
- Label resolution: forward references, patching at finalize time

## Key differences from x86

- x86 has flag-setting on arithmetic results "for free" (most ops set EFLAGS). AArch64 has a separate `s` suffix (`adds`, `subs`) for flag-setting variants. Decide which path the existing goalc IR expects and match it.
- AArch64 has no equivalent of x86 `jmp [reg]` indirect branch with the same encoding — use `br Xn` (branch register) or `blr Xn`.
- Branch ranges are smaller than x86's near jumps in some cases. For long-distance branches, materialize the target in a register and use `br`.

## Diff-tests

- if/else with both arms taken
- Loops (use a recursive function — simpler than a labeled loop)
- Switch-like dispatch
- Backward branches (typical of loops)
- Forward branches that get patched

## Success

```bash
ctest -L control-flow --output-on-failure
ctest -L "int-arith|mem-ops" --output-on-failure  # no regression
```
