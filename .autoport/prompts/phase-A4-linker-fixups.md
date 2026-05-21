# Phase A4 — Arm64 link-time fix-up support

## Status

**Placeholder.** Will be authored by the supervisor after A3 passes.

The work required is well-defined by A2's
`.autoport/reports/A2-carve-outs.json.notes.linker_followup`:

> ObjectGenerator::handle_temp_instr_sym_links() asserts that the
> patched instruction has get_disp_size() == 4, which is true on x86
> (32-bit displacement field) but not on arm64 (immediate fields are
> imm12/imm19, not at byte-aligned positions). The real arm64
> encoder calls still emit the right instruction shape; only the
> runtime relocation is unhooked.

A4's deliverable: widen `ObjectGenerator` to know about arm64
fix-up kinds (LDR imm12 unsigned offset, B/BL imm26 PC-relative,
B.cond imm19 PC-relative, ADRP imm21 page-relative), and wire the
seven IR bodies A3 reloc-skipped to actually call
`link_instruction_*()` again.

After A4: re-run A3 with the now-empty reloc-skip list to prove
every real IR qemu-executes correctly. Then bucket B is unblocked.

## Bucket

A — AArch64 emitter completion (REDESIGN.md §8). A4 is the
linker-side counterpart to A2's encoder-side work.

## Reading list (when the supervisor authors this)

- `.autoport/reports/A2-carve-outs.json.notes.linker_followup`
- `goalc/emitter/ObjectGenerator.{h,cpp}` — particularly
  `handle_temp_instr_sym_links()` and `handle_temp_jump_links()`
  (the latter was already extended in phase 24 for arm64 B/B.cond
  but only for label-jumps inside the same function, not for
  cross-symbol references).
- Phase 24 commit `c6572b9c6` ObjectGenerator.cpp diff — for the
  word-displaced 26-bit/19-bit patcher pattern A4 generalizes.
- `goalc/compiler/IR.cpp` — the 7 IR bodies whose
  `link_instruction_*()` calls are currently skipped.
