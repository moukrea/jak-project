# Phase A20 — goalc arm64 field-offset bug (off-by-4 in the compiler layer)

## First step — read these

1. `.autoport/CODEGEN_COOKBOOK.md`.
2. `.autoport/reports/A19-attempt-1-next-blocker.md` — disproves
   off-by-4 in IGenARM64.cpp encoders, narrows candidates to
   `goalc/compiler/{Val.cpp, IR.cpp, compilation/Type.cpp}`.
3. `.autoport/reports/A19-fix-summary.md` — what A19 shipped (X12
   regalloc fix; the Bug 1 deliverable that stays in HEAD).
4. `.autoport/reports/A18-attempt-4-next-blocker.md` — the original
   disasm-level evidence for off-by-4 (LDR W3,[X16,#0x30] = 48 where
   we expected #0x34 = 52 for first-gap).

## Status

**Authored 2026-06-09 by the supervisor** after A19 attempt-1
honest-exited. A19 shipped the X12 regalloc fix solidly (qemu crash
mode shifted from BLR-ee_base to BLR-stack-address — exactly the
A18 attempt-4 prediction), but proved with 8 encoder unit tests that
the field-offset off-by-4 is NOT in IGenARM64.cpp's imm12-encoding
helpers. The bug must live upstream in the locked compiler layer.

A20 widens the unlock to inspect and fix the compiler-side offset
flow.

## The off-by-4 evidence (restated for A20)

From A18 attempt-4 disasm of `dead-pool-heap.find-gap-by-size`
compiled body (entry at GOAL 0x21231d34e4):

```
0x21231d34f0  0x8b0f00b0  ADD X16, X5, X15      ; X16 = host(this)
0x21231d34f4  0xb9403203  LDR W3, [X16, #0x30]  ; W3 = [host(this) + 48]
```

The source line is `(let ((rec (-> this first-gap))) ...)` — the
first body statement of find-gap-by-size. The expected offset for
`first-gap` is **52** per `gkernel-h.gc:298` and the type-chain
walk (basic +4 + process-tree fields[31] + dead-pool +0 +
dead-pool-heap[allocated-length, compact-time, compact-count-targ,
compact-count, fill-percent] = 32+5×4 = 52). x86 boots and reaches
the title screen, which means x86 emits offset 52 for the same
expression.

Cross-confirmed by the other A18-attempt-4 finds:
- `compact-time` read site: 32 instead of 36 (off by -4).
- `dead-list.next` write site: 0x60 (96) instead of 0x64 (100, =
  dead-list@92 + next@8 — a nested `:inline` access).

## A19's narrowing — what's been ruled out

A19's `test_a19_codegen_fixes.cpp` (`load_goal_gpr` / `store_goal_gpr`
at offsets 0, 4, 8, 36, 52, 100) proves:

- `IGenARM64::ldr_w_imm`, `str_w_imm` compute `imm12 = offset / 4`
  with NO -4 adjustment.
- `IGenARM64::a6_pick_access` reuses the same encoders.
- `IGenARM64::call_r64` (post-A19) doesn't touch field-load
  offsets at all.

So the off-by-4 cannot live in `goalc/emitter/IGenARM64.cpp`.

## A19's candidate list (per next-blocker §136-176)

1. `goalc/compiler/IR.cpp::IR_LoadConstOffset::do_codegen_arm64`
   — most likely site for an arm64-specific -4 adjustment.
2. `goalc/compiler/Val.cpp::MemoryDerefVal::to_reg` — constructs
   `IR_LoadConstOffset(..., (int)offset, ...)` from
   `get_constant_offset_and_base`'s s64 output.
3. `goalc/compiler/Val.cpp::get_constant_offset_and_base` — walks
   the `MemoryOffsetConstantVal` chain, accumulates offsets.
4. `goalc/compiler/compilation/Type.cpp` — sets up
   `MemoryOffsetConstantVal` for field accesses; multiple
   construction sites (lines 47, 143, 707, 717, 856, 874, 901 per
   the next-blocker).
5. `common/type_system/Type.cpp::field.offset()` — but this is shared
   and would break x86, so unlikely.

The next-blocker's preferred attack path:

- Add `OG_OFFSET_TRACE` env-gated diag in
  `IR_LoadConstOffset::do_codegen_arm64` that prints `m_offset` +
  size + call site.
- Add the same diag in `IR_LoadConstOffset::do_codegen_x86` for
  reference.
- Re-run goalc on `gkernel.gc` with the diag enabled; diff x86 vs
  arm64 outputs for the failing expressions
  (`dead-pool-heap.find-gap-by-size`, `compact-time`, etc.).
- If x86 emits m_offset=52 and arm64 emits m_offset=48 for the same
  expression, the bug is in the IR-construction-time arm64-specific
  path (or in a post-construction adjustment). One-line fix.
- If both emit m_offset=52 but the IR_LoadConstOffset::do_codegen_arm64
  body adjusts before passing to load_goal_gpr, that's where the bug
  is.
- If both emit m_offset=48, the bug is even further upstream (Type.cpp
  layout or :inline path).

## Bucket

A — emitter / compiler.

## Goal

Land the off-by-4 fix in the smallest possible diff. After A20, qemu
boot must reach **at least 246 link-finishes** (216 + 30) — the same
threshold A19 couldn't clear because Bug 2 was unresolved.

## Scope (locks)

**UNLOCKED for A20:**

- `goalc/compiler/Val.cpp` — for inspecting + fixing
  `get_constant_offset_and_base` and `MemoryDerefVal::to_reg`.
- `goalc/compiler/Val.h` — if header changes are needed.
- `goalc/compiler/IR.cpp` — for inspecting + fixing
  `IR_LoadConstOffset::do_codegen_arm64` /
  `IR_StoreConstOffset::do_codegen_arm64` /
  `IR_FunctionCall::do_codegen_arm64`. The x86 `do_codegen_x86`
  bodies are the reference oracle; do NOT modify those.
- `goalc/compiler/IR.h` — if header changes are needed.
- `goalc/compiler/compilation/Type.cpp` — if the off-by-4 surfaces
  in `MemoryOffsetConstantVal` construction sites.
- `.autoport/tests/emitter/` — add unit tests for the fix.
- `.autoport/reports/A20-*.md` + `A20-baseline-arm64-cgo-hashes.txt`.

**STILL LOCKED:**

- `goalc/emitter/IGenARM64.{cpp,h}` — A19's X12 fix stays in HEAD;
  no further emitter changes. The encoder unit tests A19 added are
  the regression guard.
- `goalc/emitter/IGenX86_64.{cpp,h}` — x86 emit MUST not change.
- `goalc/compiler/Compiler.cpp` — the compiler driver stays locked.
- `goalc/compiler/CodeGenerator.cpp` — the locked architecture
  driver. (Note: A8/A9 originally proposed unlocks here but they
  were resolved at lower layers; A20 should be the same.)
- `goalc/regalloc/Allocator_v2.cpp` — only documentation comment.
  A19's invariant block stays; no further changes.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp` — shared.
- `common/type_system/Type.cpp` — shared with x86. If you think the
  fix needs to be here, ESCALATE in next-blocker; don't edit without
  supervisor unlock.
- All of `game/kernel/*` (no runtime changes).
- `game/kernel/asm_funcs_arm64.s`.
- `android/*` and `game/linux-arm64/*`.
- `.autoport/validators/*` (NEVER edit validator scripts).
- `.autoport/lib/*` (NEVER edit supervisor lib).

## Anti-cheat invariants

- **x86 CGOs MUST be byte-identical to A2 baseline.** Hardest
  regression check. If your fix breaks x86, you edited a shared path
  instead of the arm64 one. Revert and look harder.
- **arm64 CGOs MUST differ from A19 baseline.** Fixing the off-by-4
  changes every basic-relative field offset emit on arm64, so every
  CGO will have different bytes. New baseline
  `A20-baseline-arm64-cgo-hashes.txt` is required.
- 0 changes to `IGenARM64.cpp` (A19's X12 fix stays untouched).
- 0 changes to `IGenX86_64.cpp` (x86 oracle).
- 0 dodges, no `__attribute__((weak))`, no MAP_FIXED, no synthesised
  types, no fake printfs.
- 0 changes to anti-cheat surfaces (a18_method_zero_trap stays
  `_Exit(13)`, no lib/validator edits).

## Forbidden cheat patterns

These will get the attempt reverted and fingerprinted:

- Editing `do_codegen_x86` to make x86 also emit offset 48 (matching
  x86 to a broken arm64 is the wrong direction; x86 is the oracle).
- Adding a runtime "arm64 offset adjustment table" in `game/kernel/`
  that rewrites the emitted LDR/STR offsets post-load (same shape as
  the kStateSeq cheat).
- Adding an arm64-specific branch in `common/type_system/Type.cpp`
  to compute different field offsets (the type system MUST be
  architecture-agnostic).
- "Fixing" by removing/no-oping the offending field accesses in GOAL
  source (`goal_src/*.gc` is locked).
- Inflating CGO hash diversity by touching unrelated files to make
  check 7 pass.

## Required deliverables

1. **The off-by-4 fix** — single commit in `goalc/compiler/Val.cpp`,
   `goalc/compiler/IR.cpp`, or both. Commit message must name the
   exact function + the disasm before/after byte (e.g.
   `0xb9403203` → `0xb9403603`).
2. **Unit tests** in `.autoport/tests/emitter/` (or `goalc/test/`):
   - Compile a fixture with `(deftype foo (basic) ((a int32) (b int32)
     (c int32)))`, call `(-> obj c)`, assert the arm64-emitted byte
     encodes imm12=offset 8 (not offset 4).
   - A negative test: ensure x86 emit for the same expression matches
     the pre-fix x86 baseline (proves x86 wasn't touched).
3. **`A20-fix-summary.md`**: what changed, before/after disasm of
   `find-gap-by-size` first LDR (should show
   `0xb9403203 → 0xb9403603`).
4. **`A20-baseline-arm64-cgo-hashes.txt`**: fresh sha256 of every
   `out/jak1-arm64/iso/*.CGO`.
5. **qemu boot advance**: `bash .autoport/lib/qemu_repro.sh` must
   reach **at least 246 link-finishes**. (Equivalent of the strict
   advance that A19 couldn't clear.)
6. **`A20-attempt-N-next-blocker.md`** if you can't reach > 216 link
   finishes after the fix — honest-exit naming the new failure mode.

## Honest exit conditions

- Diagnostic shows x86 and arm64 BOTH emit `m_offset=48` for
  find-gap-by-size's first LDR — the bug is shared (further upstream
  than the locked surface). Honest-exit; A21 needs `common/type_system/Type.cpp`
  unlock.
- Fix lands but qemu boot still dies at 216 (off-by-4 wasn't the only
  issue) — fix is a real deliverable but the supervisor needs to author
  A21 for the next layer.
- Fix lands and qemu advances but a new SIGILL surfaces — that's the
  next bug class. Document in next-blocker; supervisor authors A21.

## Cost expectation

120-240 min for the diag + fix + tests + baseline regen.

- 30-60 min: build the diag patch (OG_OFFSET_TRACE in IR.cpp), rebuild
  goalc, dump x86 vs arm64 traces, identify the diverging site.
- 30-60 min: write the fix. One-line change likely.
- 30-60 min: write unit tests, regenerate baseline.
- 30 min: rebuild + qemu_repro + write summary.

Cost-of-attempt cap: ~$50. Honest-exit before $100 if no progress.
