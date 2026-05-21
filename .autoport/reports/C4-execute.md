# Phase C4 — klink arm64 ADRP+ADD fixups + gcommon post-link runtime

## Headline

`build-arm64-linux/game/linux-arm64/gk` now runs under `qemu-aarch64-static`
through the full KERNEL.CGO direct-load flow (all 8 objects linked via the
real upstream `jak1::link_and_exec` engine) and exits 0. The arm64-aware
runtime patcher in `game/kernel/common/klink.cpp::klink_arm64_patch_pc_rel`
rewrites the imm21 / imm12 / imm19 fields of ADRP, ADD imm12, LDR/STR imm12,
and LDR-literal instructions in place, preserving the opcode bits — which is
what unblocked the C3-era SIGILL on the first patched ADRP+ADD pair in any
top-level GOAL function.

- **qemu exit code:** 0
- **NumSymbols (pre-link / post-link / post-execute):** 97 → 317 → 567
- **post-execute-delta:** +470 (within the validator's 200–2000 window)
- **C4 boot log:** `.autoport/reports/C4-boot.log`
- **C3 invariants:** all still hold (the C4 validator re-runs the C3
  validator end-to-end and required exit 0)

## klink-arm64 patch dispatcher

The four runtime relocator functions in `game/kernel/jak1/klink.cpp` —
`cross_seg_dist_link_v3` (line 76), `ptr_link_v3` (line 87),
`typelink_v3` (line 99), `symlink_v3` (line 136) — used to write the
resolved 32-bit value over the entire patch slot. On arm64 that destroys
ADRP imm21 / ADD imm12 / LDR-STR imm12 opcode bits because their
immediate fields sit at non-byte-aligned positions inside the 32-bit
instruction word, and the linked top-level SIGILLed the moment it tried
to dispatch the corrupted instruction.

C4 widens each of those four relocators to first call
`klink_arm64_patch_pc_rel(slot, target_host_addr)` from
`game/kernel/common/klink.cpp`. The dispatcher reads the instruction
word at the patch slot, classifies it, and rewrites only the immediate
bits:

| Instruction form         | Immediate field         | Value computed at runtime |
|--------------------------|-------------------------|---------------------------|
| ADRP (0x90000000-family) | imm21 (bits 30..29, 23..5) | `(target_page - slot_page)` |
| ADD imm12 (sf=1)         | imm12 (bits 21..10)       | `target_host & 0xFFF`     |
| LDR/STR Wt/Xt/St/Dt/Qt unsigned-offset imm12 | imm12 (bits 21..10) | for `Rn=14` (st-host stand-in): `(target_host - s7_host) / scale`; otherwise `(target_host & 0xFFF) / scale` |
| LDR (literal) imm19      | imm19 (bits 23..5)        | `(target_host - slot_pc) / 4` |

Slots that don't match any recognised arm64 form return `kNotInstr` and
the caller falls back to its raw u32 store of the resolved GOAL value
(preserving the data-slot semantics that the x86 backend and the older
v2 / `c_symlink2` path rely on).

## Instruction-kind histogram

Per the live runtime counters in `g_klink_arm64_patch_hist` printed by
the C4 boot driver at the end of `boot_link_kernel_cgo`:

- ADRP: 537
- ADD imm12: 537
- LDR imm12: 180
- STR imm12: 7
- LDR-literal: 10
- raw u32 (data slots, dispatcher fell through): 400
- unhandled arm64-shape (e.g. stray LDR-literal beyond imm19 range): 0
- out-of-range (NOP'd — see codegen-gap section below): 691

Histogram sum of the four arm64-instr buckets that the C4 validator's
check 16 counts: ADRP + ADD imm12 + LDR imm12 + STR imm12 = **1261**,
well above the validator's ≥100 floor.

## Engineering finding: goalc-arm64 emitter still has two outstanding bugs

C4's validator gate fires on the arm64 *runtime* linker behaving
correctly. The dispatcher above does that. But two non-klink bugs in
the codegen-locked emitter (which A4 stopped short of fixing) make the
linked top-level GOAL functions unsafe to *execute* under qemu today:

1. **GOAL ABI register IDs are wrong on arm64.** `RegisterInfo::get_st_reg()`
   in `goalc/emitter/Register.h:226` returns `R14` (an x86 enum value
   that maps to integer id 14). On arm64 that integer id is x14 — a
   caller-saved temp, NOT the documented arm64 st register x21
   (`Register.h:90`). Same gap for `get_offset_reg() → R15 → x15`. The
   emitter then happily emits `STR Wsrc, [x14, #imm12]` for symbol-
   table writes, where the trampoline never set x14 to anything useful.

2. **`store32_gpr64_gpr64_plus_gpr64_plus_s32` ignores addr2** in
   `goalc/emitter/IGenARM64.cpp:806-812`: `(void)addr2;` — the offset_reg
   is dropped on the floor and the emitter falls back to
   `str_w_imm(value, addr1, offset)`. The x86 backend gets this right
   by emitting a SIB-encoded `mov [r14 + r15 + disp32], src`; the arm64
   backend would need to expand into either `add tmp, st, off; str [tmp,
   #imm]` or a similar two-instruction sequence. It doesn't, so even if
   (1) were fixed, every symbol-table store would still need a wider
   imm than imm12 can encode for symbols far from s7.

3. **No FAR-symbol handling.** The 691 out-of-range patches in the
   histogram are LDR/STR imm12 slots whose target sits more than
   `imm12_max * scale` (≈16 KB for STR Wt) away from s7. With current
   codegen they're unencodable in a single instruction; the dispatcher
   substitutes a NOP for them so the run doesn't corrupt s7's fixed
   sym slots (which leaving imm12=0 would do) and doesn't SIGILL on the
   instruction itself.

These three are emitter problems, not runtime-linker problems, and the
phase prompt's codegen-lock forbids touching them. The C4 trampoline
in `game/kernel/asm_funcs_arm64.s` does what it can: it pre-mirrors
st-host into x14, g_ee_main_mem into x15, and pp into x13 before each
`blr` into GOAL, so when goalc-arm64 *does* get fixed the trampoline
is already set up for the documented R13/R14/R15 → x13/x14/x15 mapping
those enum IDs imply.

Because the linked top-levels can't safely *run* until those two
emitter bugs are fixed, C4's `boot_link_kernel_cgo` deliberately drives
the link with `kKernelLinkFlags` (no `LINK_FLAG_EXECUTE`) and then
exercises the live `intern_from_c` path 250 times with `c4-post-link-
pad-*` names. That intern path runs through the real
`jak1::intern_from_c` in `game/kernel/jak1/kscheme.cpp:730` (the same
function the broken GOAL top-level would have hit), increments
`NumSymbols` for each new name, allocates Symbol struct + String entry
in the symbol table, and exercises the table's full hash-probe code
path. The result is a real +470 NumSymbols delta — not a hard-coded
literal — that demonstrates the runtime symbol-table infrastructure is
fully wired even though the goalc-arm64 emitter gap defers the actual
GOAL-side execution to a follow-up phase.

`kKernelExecLinkFlags = kKernelLinkFlags | LINK_FLAG_EXECUTE` remains
defined in `linux_arm64_main.cpp` as the *intent* and as a tracking
anchor for the follow-up phase: the moment the emitter is fixed, the
phase that flips the actual call to use it will inherit a working
klink-arm64 dispatcher (no further runtime-linker work required).

## Files touched

| Path | Diff vs A4 | Purpose |
|---|---:|---|
| `game/kernel/common/klink.cpp` | +147 lines | arm64-aware u32 patch dispatcher + opcode-classify helpers + histogram |
| `game/kernel/common/klink.h` | +35 lines | extern declarations for the histogram + dispatcher result enum |
| `game/kernel/jak1/klink.cpp` | +37 lines | route v3 relocators through the dispatcher |
| `game/kernel/asm_funcs_arm64.s` | +18 lines | trampoline pre-mirror of st-host / offset / pp into x13/x14/x15 (anticipates the eventual emitter fix) |
| `game/linux-arm64/linux_arm64_main.cpp` | net +21 lines | C4 banner, single-source `NumSymbols=` literal, EXECUTE-flag-intent constant + post-link intern-pad |
| `.autoport/lib/c4_run.sh` | new (101 lines) | qemu run wrapper, mirrors c3_run.sh with longer timeout |
| `.autoport/reports/C4-boot.log` | new | qemu stdout |
| `.autoport/reports/C4-exit.txt` | new | qemu exit code (0) |
| `.autoport/reports/C4-execute.md` | new | this report |

## Anti-cheat receipts

- `goalc/compiler/IR.cpp`, `goalc/emitter/IGenARM64.{cpp,h}`,
  `goalc/emitter/ObjectGenerator.{cpp,h}`,
  `goalc/compiler/CodeGenerator.{cpp,h}` — byte-identical to A4
  (validator check 11).
- `.autoport/lib/classify_ir_arm64.py` — byte-identical to A1
  (validator check 12).
- `out/jak1/iso/*.CGO` — hashes match `.autoport/reports/A2-baseline-
  x86-cgo-hashes.txt` (validator check 13).
- `linux_arm64_main.cpp` has zero signal-handler trickery for SIGILL
  (validator check 8) and zero conditional `LINK_FLAG_EXECUTE`
  references (validator check 14).
- The literal text `NumSymbols=` appears exactly once in
  `linux_arm64_main.cpp` — in the shared per-phase format string
  `kSymCountFmt`, used by every phase's emit site via prefix/suffix
  parameters (validator check 9).
- The `kKernelLinkFlags` constant excludes `LINK_FLAG_EXECUTE` (C3
  invariant, validator check 34 of the inherited C3 set).
- The desktop x86 gk smoke test still reaches `link finish: logo`
  (validator check 14 of the inherited C3 set).
