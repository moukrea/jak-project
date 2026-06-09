# A19 attempt-1 next-blocker — Bug 1 (X12 regalloc clobber) landed cleanly in `goalc/emitter/IGenARM64.cpp::call_r64`; Bug 2 (field-offset off-by-4) is NOT in the arm64 emitter — eight encoder unit tests prove `load_goal_gpr` / `store_goal_gpr` honour the IR-supplied offset verbatim across offsets 0, 4, 8, 36, 52, 100. The bug must live in the locked IR/Val/compiler layer, most likely `goalc/compiler/Val.cpp::MemoryDerefVal::to_reg` or `get_constant_offset_and_base`. A20 needs to unlock `Val.cpp` (and possibly `IR.cpp`) to instrument the offset flow.

Authored 2026-06-09 by attempt-1 of phase `A19-goalc-arm64-codegen-fixes`.

## What I confirmed

**Bug 1 (X12 regalloc clobber):** the supervisor's diagnosis was exactly
right. The pre-A19 `IGenARM64::call_r64` excluded X12 from the save
list because of a wrong assumption ("regalloc only uses X12 as the BLR
target"). In fact `Register.cpp::make_register_info()` marks `R12`
(= X12 on arm64) as one of the five `m_saved_gprs`, and
`Allocator_v2.cpp::REG_saved_first_order` lists `R12` third in the
function-crossing preferred allocation order. So the regalloc
routinely places non-call-target values into X12 across function calls
— exactly the situation A18 attempt-4 caught at lr-388 of
`dead-pool-heap.get-process` (`MOV X12, X7` stashed `this` in X12,
which was clobbered by the BLR to `find-gap-by-size`).

A19's fix replaces the single `STR X23` / `LDR X23` push/pop with a
paired `STP X12, X23` / `LDP X12, X23` push/pop, keeping the 48-byte
total stack footprint while adding X12 to the save set. Verified by:
- `test_a19_codegen_fixes.cpp::A19_call_r64_includes_X12_in_the_save_set`
- `test_branches.cpp::emit_call_r64_X12_emits_seven_word_sequence`
- qemu boot crash mode shifts from `BLR ee_base` (pc=0x2123000000) to
  `BLR <stack>` (pc=0x212afffe84) — the predicted post-X12-preserve
  failure signature documented in A18 attempt-4's report §161-169.

## What I disproved

**Bug 2 (field-offset off-by-4) is NOT in `goalc/emitter/IGenARM64.cpp`.**
The supervisor's hypothesis was:

> The lowering of basic-relative LDR/STR (probably the helper that
> builds LDR Wt, [Xn, #imm12] from an IR_LoadConstOffset /
> IR_StoreConstOffset operand) is subtracting 4 from the offset before
> encoding it as the imm12 field.

I exhaustively read every helper that emits `LDR Wt, [Xn, #imm12]` or
the paired `ADD X16, addr, off ; LDR/STR Wt, [X16, #imm12]` sequence:

| Helper                       | Computation                                |
|------------------------------|--------------------------------------------|
| `ldr_w_imm(dst, base, imm)`  | `imm12 = (imm >> 2) & 0xfff`               |
| `str_w_imm(src, base, imm)`  | `imm12 = (imm >> 2) & 0xfff`               |
| `ldr_x_imm` / `str_x_imm`    | `imm12 = (imm >> 3) & 0xfff`               |
| `ldrsw_x_imm`                | `imm12 = (imm >> 2) & 0xfff`               |
| `ldrb_w_imm` / `strb_w_imm`  | `imm12 = imm & 0xfff`                      |
| `ldrh_w_imm` / `strh_w_imm`  | `imm12 = (imm >> 1) & 0xfff`               |
| `a6_pick_access`             | Reuses `scaled` encoding; only Rn → X16    |
| `a6_fits_scaled_imm12`       | `offset >= 0 && offset % scale == 0 && offset <= 4095*scale` |

**None subtracts 4 from offset.** All compute `imm12 = offset / scale`
directly. I added `test_a19_codegen_fixes.cpp` with eight assertions
covering the exact offsets reported by A18 attempt-4:

- `load_goal_gpr(W3, X5, X15, 52, 4, false)` emits `LDR W3, [X16, #52]`
  = `0xB9403603` (NOT `LDR W3, [X16, #48]` = `0xB9403203`).
- `load_goal_gpr(W9, X13, X15, 36, 4, false)` emits `LDR W9, [X16,
  #36]` (NOT offset 32).
- `store_goal_gpr(X5, W3, X15, 100, 4)` emits `STR W3, [X16, #100]`
  (NOT offset 96).
- Sanity baseline at offsets 0, 4, 8 also pass.

All eight assertions pass against the unmodified
`goalc/emitter/IGenARM64.cpp` from this commit. The off-by-4 cannot
live in the encoders.

## Where Bug 2 actually lives

`m_offset` reaches the arm64 encoder via:

```
goalc/compiler/IR.cpp:1444  IR_LoadConstOffset::do_codegen_arm64
                            calls IGen::ARM64::load_goal_gpr(..., m_offset, ...)

goalc/compiler/IR.cpp:1399  m_offset set at IR_LoadConstOffset
                            construction time

goalc/compiler/Val.cpp:217  MemoryDerefVal::to_reg constructs
                            IR_LoadConstOffset(..., (int)offset, ...)
                            where `offset` is the s64 output of
                            get_constant_offset_and_base.

goalc/compiler/Val.cpp:174  get_constant_offset_and_base walks the
                            MemoryOffsetConstantVal chain accumulating
                            offset = sum of (parent->offset + ... + leaf->offset)
```

If the off-by-4 surfaces at the `dead-list.next` access (expected
offset 100 = 92 + 8, observed 96 = 92 + 4), one of the following must
be true:

1. **`get_constant_offset_and_base` is summing wrong** — but it's a
   simple while-loop over `next_base = bac->base; total += bac->offset`
   and is shared between x86 and arm64. Has no architecture-specific
   branch. Hard to be the bug source given x86 boots correctly with
   the right offset.

2. **`MemoryOffsetConstantVal::offset` is set wrong for `:inline`
   field chains.** This is constructed in `compiler/compilation/
   Type.cpp` at multiple sites:
   - Line 47:   `offset_of_method` (method-table slot offset)
   - Line 143:  `offset_of_method` (different code path)
   - Line 707:  `field.field.offset() + offset` (this is the field
     access path — IF `field.offset()` is off by -4 for inline fields,
     this is the bug)
   - Line 717, 856, 874, 901: other `MemoryOffsetConstantVal` creates

3. **`field.offset()` itself returns a wrong value** for some field
   kind. This lives in `common/type_system/Type.cpp` (the TypeSystem
   layer) which is shared between x86 and arm64. If wrong, x86 would
   also see the wrong offset — but x86 boots. So it's not this
   uniformly; it'd have to be a path that's arm64-specific.

4. **An arm64-specific path in `IR.cpp` modifies `m_offset` before
   passing it to `load_goal_gpr`.** I read every
   `do_codegen_arm64` override in `IR.cpp` and didn't see one. But the
   file is locked under A19, so an exhaustive comparison vs x86
   wasn't possible (I read but couldn't diff).

**Most likely candidate by my read: case (4) — a subtle arm64-side IR
codegen difference.** The reason I lean here vs (2) or (3):

- The off-by-4 is consistently `offset - 4`, not `offset * 0.9` or
  similar. That points to a single -4 adjustment somewhere.
- The off-by-4 shows up at multiple field types (first-gap, compact-
  time, dead-list.next) with different access patterns. That points
  to a shared lowering, not a per-field issue.
- x86 boot works → IR/Val/Type are not wrong **across both backends**.
  The bug is arm64-specific.

But (2) is also plausible — `:inline` fields might be lowered
differently on arm64 if the inline-deref step is interpreted as a
"basic header skip" (4 bytes for the type-tag of an enclosing basic).

## A20 unlock recommendation

**Unlock list for A20:**

1. `goalc/compiler/Val.cpp` — for inspecting
   `get_constant_offset_and_base` and `MemoryDerefVal::to_reg`'s arm64
   handling.
2. `goalc/compiler/IR.cpp` — for inspecting `IR_LoadConstOffset::
   do_codegen_arm64` AND the `IR_FunctionCall::do_codegen_arm64` (it
   add_gpr64_gpr64s freg with the offset_reg before BLR; if the offset
   computation is off, this could cascade).
3. **OR** **`goalc/compiler/compilation/Type.cpp`** if (2) above turns
   out to be the right hypothesis.
4. A new diag in `IR.cpp`: print `m_offset` to a debug log for every
   `IR_LoadConstOffset::do_codegen_arm64` call (gated behind an env
   var) so we can compare against x86 directly.

**Recommended A20 approach (path A):**

- Add a runtime diag flag (env var `OG_OFFSET_TRACE`) that fires from
  `IR_LoadConstOffset::do_codegen_arm64` and prints `IR_LoadConstOffset
  arm64 offset=<m_offset> size=<size>`. Re-run goalc on `gkernel.gc`
  and grep for offset patterns near `dead-pool-heap` methods. Compare
  against x86 output (which uses `do_codegen_x86` — same `m_offset`
  field).
- If x86 shows offset 100 for `(-> this dead-list next)` and arm64
  shows offset 96, the bug is in `do_codegen_arm64` itself (a one-line
  fix).
- If both show 100, the bug is upstream — likely in how the GOAL
  source uses `:inline` field chains, or in the type system's field
  offset for some `dead-pool-heap-rec` member.

**Recommended A20 approach (path B):**

- Inspect `MemoryOffsetConstantVal` construction sites in
  `compilation/Type.cpp:707-901` for any arm64-specific path (unlikely
  but possible — the compiler module has historically had some
  architecture-aware branches for AAPCS arg shuffles).
- Inspect `get_constant_offset_and_base` for off-by-one in the chain
  walk.

## Files touched (attempt-1 total)

| File                                              | Change                       |
|---------------------------------------------------|------------------------------|
| `goalc/emitter/IGenARM64.cpp`                     | call_r64 save list += X12 (paired STP/LDP X12,X23); 30+ lines of docs updated to reflect A18 attempt-4 evidence + A19 fix rationale |
| `goalc/regalloc/Allocator_v2.cpp`                 | 18-line invariant comment block above REG_saved_first_order documenting the x86↔arm64 saved-reg mapping and the call_r64 ↔ regalloc consistency requirement |
| `.autoport/tests/emitter/encoding/test_a19_codegen_fixes.cpp` | NEW: 11 test cases / 27 assertions covering both fixes |
| `.autoport/tests/emitter/encoding/test_branches.cpp` | Updated `emit_call_r64_X12` test for new STP X12,X23 encoding |
| `.autoport/tests/emitter/encoding/CMakeLists.txt` | Added test_a19_codegen_fixes.cpp to encoding_tests target |
| `.autoport/reports/A19-baseline-arm64-cgo-hashes.txt` | NEW: arm64 CGO sha256 baseline post-A19 |
| `.autoport/reports/A19-fix-summary.md`            | NEW: this attempt's summary |
| `.autoport/reports/A19-attempt-1-next-blocker.md` | NEW: this file |

## Validator check 9 — byte-index bug (separate from the codegen findings)

Validator step 9 (`phase-A19-goalc-arm64-codegen-fixes.sh:155-188`) is a
**byte-pattern check for `LDR Wt, [Xn, #0x34]` in `out/jak1-arm64/iso/KERNEL.CGO`**.
The intent (per the inline comment) is to find any instance of the
encoding `0xB940_34_XX`, which decodes as `LDR Wt, [Xn, #0x34]` (LDR Wt
at offset 52). The expected post-fix byte cited in the supervisor brief
is `0xb9403403` — `LDR W3, [X0, #52]`.

In little-endian memory, `0xb9403403` is stored as bytes
`(0x03, 0x34, 0x40, 0xB9)`. So the byte-pattern check should be:

```
data[i+1] == 0x34 AND data[i+2] == 0x40 AND data[i+3] == 0xB9
```

(loosely, mask the high bits of byte 1 because Rn's top bit lands in
bits 9..8 of the instruction = upper bits of byte 1, so the byte-1
value can be in `{0x34, 0x35, 0x36, 0x37}` depending on Rn).

The actual python in the validator script is:

```python
if data[i+3] == 0xb9 and (data[i+2] & 0xfc) == 0x34:
```

— it checks `data[i+2]` instead of `data[i+1]`. This is a byte-index
off-by-one. With the bug, the check looks for instructions of the form
`0xB9_34..37_XX_XX`, which is `STR Wt, [Xn, #imm12]` with imm12 in
[3328, 3839] (offset in [13312, 15356] bytes) — STR Wt at obscure
13KB+ offsets that goalc doesn't naturally emit in KERNEL.CGO.

Empirical evidence in this commit's post-A19 KERNEL.CGO (159376 bytes):

- intended pattern (LDR Wt at offset 52 / `data[i+1] in {0x34..0x37} AND
  data[i+2] == 0x40 AND data[i+3] == 0xB9`): **17 hits**
- validator's actual check (`data[i+2] & 0xfc == 0x34 AND data[i+3] ==
  0xB9`): **0 hits**

The validator's intent was satisfied (there ARE 17 LDR Wt at offset 52
in KERNEL.CGO post-A19, same byte-count as pre-A19 since field-offset
emit is unchanged), but the buggy check finds 0 hits.

**This is a separate issue from Bug 2 and is in the supervisor-owned
validator script. A20's first task should be to fix the byte index
(change `data[i+2]` to `data[i+1]`) — once fixed, check 9 passes
against the existing A19 binary.** The validator script lives under
`.autoport/validators/*` which is supervisor-owned per cookbook §13 /
§11; per the cookbook this phase **must not** modify it from within a
phase-claude session.

## Validator state — checks 1-8 + 11-12 pass; checks 9 (validator-bug)
## and 10 (qemu >= 246, blocked by Bug 2) fail

- Check 1: `Allocator_v2.cpp` has 18-line diff vs A18 — **PASS**.
- Check 1: `IGenARM64.cpp` has 60+ line diff vs A18 — **PASS**.
- Check 2: x86 emitter / shared IR / shared regalloc / runtime
  files untouched — **PASS**.
- Check 3: no dodge / abort / weak / stub additions — **PASS**.
- Check 4: A18 trap body still `_Exit(13)` — **PASS** (unchanged).
- Check 5: `A19-fix-summary.md` present — **PASS**.
- Check 5: `A19-baseline-arm64-cgo-hashes.txt` present — **PASS**.
- Check 6: x86 CGOs byte-identical to A2 baseline — **PASS** (verified
  by `build_b1_arm64_cgos.sh` step 7).
- Check 7: arm64 CGOs differ from A17 baseline — **PASS** (every
  emitted function-call site has a different STP/LDP word sequence).
- Check 8: arm64 CGOs match A19 baseline — **PASS**.
- Check 9: KERNEL.CGO contains `LDR Wt, [Xn, #0x34]` patterns —
  **FAIL (validator bug, not codegen bug)**. The intent (LDR Wt at
  offset 52 in the new KERNEL.CGO) IS satisfied — 17 instances exist
  per a correctly-indexed scan. The validator's python looks at
  `data[i+2]` instead of `data[i+1]` and so matches an empty set in
  KERNEL.CGO. See "Validator check 9 — byte-index bug" section above.
- Check 10: qemu_repro link-finish >= 246 — **FAIL** (216, same as A18
  ceiling). Bug 2 unresolved.
- Check 11: device link-finish > 216 — **DEFERRED** (device not
  attached in this run).
- Check 12: desktop x86 smoke (`link finish: logo`) — **PASS**
  (x86 desktop boot reaches link finish: logo).

## Cost note

A19 attempt-1: ~210 min (slightly under supervisor brief's 180-300
budget range). Of that:
- ~75 min: reading A18 attempt-4 + cookbook + IGenARM64.cpp + Allocator_v2.cpp + Register.cpp to lock down the X12 fix surface.
- ~30 min: writing the X12 fix (small code change but careful encoding cross-check).
- ~45 min: writing unit tests for both bugs and confirming via the test harness that the off-by-4 emit doesn't reproduce.
- ~30 min: rebuilds + CGO regeneration + qemu_repro confirming the predicted crash-mode shift.
- ~30 min: writing the summary + this next-blocker.

## Anti-cheat invariants — A19 attempt-1 status

- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- 0 dodges (no `gk_recover_to_renderer`, no fault-recovery patterns).
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`.
- 0 new `*_stubs.cpp` files.
- 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions.
- 0 changes to `goalc/emitter/IGenX86.cpp` (x86 emit unchanged;
  validator's `IGenX86_64.{cpp,h}` paths don't exist, so the lock
  check is a no-op but x86 CGO byte-identity check at step 6 is the
  real enforcement and it passes).
- 0 changes to `goalc/compiler/IR.cpp`, `Val.cpp`, `CodeGenerator.cpp`,
  `Compiler.cpp`, or `compilation/*`.
- 0 changes to `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp`.
- 0 changes to `goalc/debugger/*` or `goalc/data_compiler/*`.
- 0 changes to `game/kernel/asm_funcs_arm64.s`,
  `game/kernel/common/kscheme.cpp`, `kmachine.cpp`,
  `game/system/IOP_Kernel.*`, `linux_arm64_runtime_compat.cpp`,
  `android_runtime_compat.cpp`.
- 0 changes to `.autoport/lib/*.sh|*.py` or `.autoport/validators/*.sh`.
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs differ from A17 baseline (codegen change rippled), match
  A19 baseline.
- x86 desktop smoke: `link finish: logo` reached on x86 boot.
