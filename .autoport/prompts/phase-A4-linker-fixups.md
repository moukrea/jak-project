# Phase A4 — Arm64 link-time fix-up support

## What this phase delivers

Widens `ObjectGenerator` to know about **arm64 instruction-immediate**
fix-up kinds, so the 7 IR bodies A2 wrote that emit placeholder
symbol/static/function references actually get patched at link time.
After A4: the 7 forms A3 reloc-skipped can qemu-execute and match
x86, and bucket B (jak1 CGO regen) produces arm64 binaries that the
runtime can actually load.

The 7 IRs (per A2's `linker_followup` note):
- `IR_GetSymbolValue`, `IR_SetSymbolValue` — LDR / STR via the
  symbol-table base register, offset = symbol's slot in the table
- `IR_LoadSymbolPointer` — ADRP + ADD-imm12 page-relative address
  computation for an arbitrary symbol
- `IR_GetSymbolValueAsm` — same load as IR_GetSymbolValue, asm form
- `IR_StaticVarLoad`, `IR_StaticVarAddr` — same patterns for
  static-segment references
- `IR_FunctionAddr` — ADRP+ADD or MOV-via-MOVZ/MOVK chain for a
  function pointer (the BL imm26 for IR_FunctionCall is intra-segment
  and was handled by phase 24's jump-link extension)

The corresponding arm64 instruction encodings and patchable bits:

| Fix-up kind | Instruction | Bit field | Scale | Signed? |
|---|---|---|---|---|
| `LDR_IMM12_UNSIGNED` | LDR (immediate, unsigned offset) | bits 21:10 | × size (1/2/4/8) | unsigned |
| `STR_IMM12_UNSIGNED` | STR (immediate, unsigned offset) | bits 21:10 | × size | unsigned |
| `ADD_IMM12` | ADD (immediate) | bits 21:10 + shift bit 22 | none / × 4096 | unsigned |
| `BL_IMM26` | B / BL | bits 25:0 | × 4 | signed (PC-relative) |
| `B_COND_IMM19` | B.cond | bits 23:5 | × 4 | signed (PC-relative) — phase 24 already does this for jump-link |
| `ADRP_IMM21` | ADRP | immhi[18:0] (bits 23:5) + immlo[1:0] (bits 30:29) | × 4096 | signed (page-relative) |

(BL_IMM26 and B_COND_IMM19 are already handled by phase 24's
`handle_temp_jump_links` extension — A4 doesn't need to redo them.
The new kinds are LDR_IMM12, STR_IMM12, ADD_IMM12, ADRP_IMM21.)

## Why this matters

Without A4, jak1's regenerated arm64 CGOs are unloadable at runtime —
the symbol-table lookups, static-data accesses, and cross-function
references would all dereference zero. Bucket B's "regen jak1 CGOs
with the now-complete emitter" goal is gated on this phase.

A3 proved A2's encoders produce the right *instruction shapes*. A4
makes those shapes link-complete.

## Concrete deliverables

### 1. ObjectGenerator widening

Edit `goalc/emitter/ObjectGenerator.h` and `.cpp` to:

- Add a new enum or set of fix-up kinds for arm64 immediates (the
  6 listed above; 4 are new, 2 were done in phase 24). Whatever
  shape fits best with the existing x86 fix-up enum.
- Extend `handle_temp_instr_sym_links()` so the
  `ASSERT(instruction.get_disp_size() == 4)` becomes a switch over
  fix-up kinds: x86 sym-links stay 4-byte; arm64 LDR_IMM12 / ADD_IMM12
  patches into bits 21:10; ADRP_IMM21 splits the immediate across
  the two non-contiguous immhi/immlo fields.
- The patching code computes the actual immediate value (e.g., symbol's
  offset in the table, or page-difference for ADRP), masks it to the
  field width, validates range, and writes it into the instruction
  word using bit-level operations. For ADRP specifically: the value
  is `(target_page - current_page)` where `page = addr >> 12`; the
  result is signed 21-bit.

### 2. IR-side re-wiring

Edit `goalc/compiler/IR.cpp` so the 7 IR bodies — currently emitting
`ARM64::*_placeholder()` or `ARM64::*_plus_s32(..., LINK_SYM_NO_OFFSET_FLAG)`
— call the appropriate `link_instruction_*()` methods after the
encoder, registering the fix-up kind. The pattern should mirror what
the x86 path already does for these same IRs (look at the
do_codegen_x86 bodies as templates for the registration structure;
just substitute the arm64 fix-up enum for the x86 one).

**Do NOT change** the existing x86 do_codegen_x86 bodies. A4 touches
only do_codegen_arm64 bodies + ObjectGenerator's switch logic.

### 3. Encoder helpers (if needed)

If `IGen::ARM64::lea_reg_plus_off32`, `adrp_placeholder`, or others
return instruction-words with hard-coded 0 immediates, that's fine —
the linker fix-up overwrites them. If the encoder is missing the
bit-width metadata the patcher needs, add a small accessor (e.g.,
`Instruction::arm64_fixup_kind()`) on `emitter::Instruction` so the
patcher can switch on it without parsing opcode bytes.

### 4. Re-run A3 harness with empty skip list

Either:

- (preferred) extend `.autoport/lib/build_a3_diff.sh` with an
  `--include-reloc-skipped` mode that doesn't filter the 7 IRs, or
- write a sibling script `.autoport/lib/build_a4_diff.sh` that
  invokes the same logic with the bigger test set.

Then produce `.autoport/reports/A4-coverage.json` with the same
schema as A3's coverage report but with `reloc_skipped = []` and
all 36 real IRs in the `qemu_executed=true, matches_x86=true` set.

### 5. (mi) regen — arm64 CGOs must load + run a smoke probe

After A4's linker work lands, regenerate jak1's arm64 CGOs and run
the simplest possible probe under `qemu-aarch64-static`: load
`KERNEL.CGO`, follow the symbol-table to find a single named symbol
(e.g., the `'#f` false symbol's slot), and exit-with-its-offset.
If the symbol-table walk produces zero or garbage, the relocation
patching has a bug. If it produces a stable nonzero value, A4
worked.

A scaffold for the smoke probe can borrow from the qemu_harness in
A3. The probe doesn't need a working dispatcher — just the CGO
loader stub + a symbol-lookup.

The probe lives at `test/arm64/a4_kernel_probe.S` (or .c) and its
output is captured into `.autoport/reports/A4-kernel-probe.txt`.

## Anti-cheat constraints

1. **Do not edit `do_codegen_x86` bodies.** A4's validator diffs
   `goalc/compiler/IR.cpp` against the A3 landing commit and fails
   if any x86 codegen lines moved.
2. **Do not edit the classifier**
   (`.autoport/lib/classify_ir_arm64.py`). It's still locked since
   A1. The 36-real / 5-stub / 1-missing count from A2 stays.
3. **Do not weaken A3's harness** (`build_a3_diff.sh`). If you
   extend it, the extension must be opt-in (a flag/env var) so
   running the original harness with the original args still
   produces A3's exact coverage JSON. The validator re-runs both.
4. **Do not pad the coverage with hand-crafted JSON entries.** The
   A4-coverage.json must be produced by actually running the
   harness with the now-empty reloc-skip list. The validator
   re-runs the harness and diffs key fields.
5. **The kernel-symbol probe (deliverable #5) must produce a
   non-zero, deterministic result.** "Zero / random" would mean the
   ADRP/ADD pair pointed at unmapped memory; "different each run"
   would mean the patcher writes to a non-stable location. Both
   are real bugs to find, not tolerances to widen.

## Files you will create / modify

| Path | Purpose |
|---|---|
| `goalc/emitter/ObjectGenerator.{h,cpp}` | arm64 fix-up kinds + extended `handle_temp_instr_sym_links` |
| `goalc/emitter/IGenARM64.{h,cpp}` | maybe small accessors (instruction-kind metadata) |
| `goalc/emitter/Instruction.h` (or sibling) | possibly extend with arm64 fix-up tag |
| `goalc/compiler/IR.cpp` | the 7 arm64 IR bodies now call `link_instruction_*()` |
| `.autoport/lib/build_a3_diff.sh` (extend) or new `build_a4_diff.sh` | runs the harness with reloc-skip lifted |
| `test/arm64/a4_kernel_probe.S` or .c | tiny qemu probe for the kernel symbol table |
| `.autoport/reports/A4-coverage.json` | A3-shape coverage with empty reloc-skip |
| `.autoport/reports/A4-coverage.md` | human summary |
| `.autoport/reports/A4-kernel-probe.txt` | probe stdout (the offset value) |

## Pitfalls

- **ADRP's split immediate** is the trickiest fix-up: 21 bits across
  immhi[18:0] (bits 23:5) and immlo[1:0] (bits 30:29). Get the
  shifting wrong and the target address is off by a page. Use a unit
  test on the patcher itself — feed in a known page-delta, verify
  the encoded bits.

- **LDR's scaled offset** is sized by the access size. LDR Xt
  scales by 8; LDR Wt scales by 4; LDR Ht by 2; LDR Bt by 1. The
  fix-up kind for LDR needs to know the access size to compute the
  patched value correctly. Either encode size in the fix-up kind
  enum or add an accompanying field.

- **The 7 IR bodies' arm64 encoder calls today** use
  `LINK_SYM_NO_OFFSET_FLAG` as a sentinel s32. Decide whether the
  fix-up registration should:
   (a) read the placeholder byte pattern back and overwrite it, OR
   (b) zero out the immediate field before patching, OR
   (c) write the actual offset directly during patching, ignoring
       whatever the encoder put there.
  (c) is simplest. Match what phase 24 did for B/B.cond.

- **Symbol-table layout is identical to x86** in the GOAL runtime —
  the symbol-table base register (`gRegInfo.get_st_reg()`) holds the
  same address in both backends, and each symbol's slot offset is
  the same byte offset. So the value the linker writes for an
  IR_GetSymbolValue fix-up is the same on both backends. Don't
  recompute it.

- **The link-time pass is per-segment** (see
  `ObjectGenerator::generate_data_v3()` calling `handle_temp_*` per
  segment in a loop). All fix-up writes happen at link time, after
  every function in the segment has been emitted, with the segment
  layout fixed. PC-relative computations use that final layout.

## Reading list

- `.autoport/SUPERVISOR_JOURNAL.md` — A2 entry + A3 entry + A4 plan
- `.autoport/reports/A2-carve-outs.json.notes.linker_followup`
- `.autoport/reports/A3-coverage.json` — the 7 IRs marked
  `skipped_reason="reloc-needed; deferred to A4-linker-fixups"`
- `goalc/emitter/ObjectGenerator.{h,cpp}` — particularly
  `handle_temp_instr_sym_links()` lines 444-500 (the assertion site)
  and `handle_temp_jump_links()` (phase 24's pattern to extend)
- `goalc/emitter/IGenARM64.cpp` — the 7 encoders the IR bodies call
  (`load32s_gpr64_gpr64_plus_gpr64_plus_s32`, `adrp_placeholder`,
  `lea_reg_plus_off`, etc.)
- `goalc/compiler/IR.cpp` — the 7 IR bodies' do_codegen_arm64;
  also their do_codegen_x86 siblings for the link-registration
  pattern to mirror
- ARM ARM C6.2.93 (LDR imm12), C6.2.181 (STR imm12), C6.2.4 (ADD
  imm), C6.2.10 (ADRP)
- Phase 24 commit `c6572b9c6` (the jump-link extension is the
  template)

## Done definition

`.autoport/validators/phase-A4-linker-fixups.sh` exits 0. That
script verifies:

- `A4-coverage.json` exists, parses, and has the A3 schema.
- `A4-coverage.json.summary.reloc_skipped` is **empty**.
- `A4-coverage.json.summary.other_skipped` is **empty**.
- Every "real" IR from `A2-inventory-after.json` is in
  `A4-coverage.json.by_ir` with `qemu_executed=true` and
  `matches_x86=true`.
- The 7 previously-skipped IR bodies in `IR.cpp` now contain text
  matching `link_instruction_` calls (grep — bodies extracted via
  the same awk pattern the supervisor used in the recon step).
- `ObjectGenerator.cpp` diff vs A3's landing shows arm64-specific
  fix-up handling added (new enum values, new switch cases, new
  bit-manipulation code).
- `goalc/compiler/IR.cpp`'s do_codegen_x86 bodies are unchanged
  (validator uses the same hunk-walker A2 introduced).
- Classifier byte-identical to A1's landing.
- A4-kernel-probe.txt exists, contains a non-zero stable integer
  (validator re-runs the probe and compares).
- Desktop gk smoke test reaches `link finish: logo` (no x86
  regression).
- (mi) succeeds.

## Note on follow-on

After A4 passes, bucket B is unblocked. B1 (regen jak1 CGOs with
the now-complete emitter) can produce arm64 CGOs that the runtime
can actually load. Bucket C (Linux-arm64 to title) then becomes
the next major milestone.
