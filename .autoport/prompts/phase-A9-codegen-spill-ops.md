# Phase A9 — implement arm64 spill load/store + frame setup in CodeGenerator

## Status

**Authored 2026-05-23 by the supervisor** after A8 delivered the
qemu repro infrastructure + full root-cause analysis. A8 honestly
exited because the fix requires unlocking `goalc/compiler/CodeGenerator.cpp`
which A8 didn't have. A9 is the narrow unlock for the specific
function `CodeGenerator::do_goal_function_arm64` to implement real
spill ops where it currently emits NOPs.

## Bucket

A — emitter / linker (codegen layer).

## Motivation

Per `.autoport/reports/A8-displaygc-root-cause.md` +
`.autoport/reports/A6-attempt-5-blocker.md`:

The display.gc top-level NULL-fn-ptr BLR is rooted in 4 lines of
`goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64` (around
line 425-440) that emit NOPs (`0xd503201fu`) as placeholders for the
register allocator's spill load/store ops. When the V2 allocator
needs to spill a function-pointer ireg (font-context's method 0)
across a method-call arg-shuffle, the spill silently no-ops and the
reload returns whatever the arg-2 register was overwritten with —
typically 0 for the failing case.

The comment in that function explicitly admits the gap:

> "We deliberately do not implement saved-reg backup / spill restore...
>  If a function ever needs spills the regalloc will assert and we'll
>  know to expand this."

display.gc reaches a function that DOES need spills. A8's
Allocator_v2 mitigation (promote feeder vars to function-crossers)
helps but doesn't cover all GOAL programs. The right fix is to
implement real spill emit.

## Goal (concrete, narrow)

In `goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64`,
replace:

- Prologue NOP placeholder (line ~412-421) with real
  `SUB SP, SP, #frame_bytes` (16-byte-aligned frame size based on
  `allocs.stack_slots_for_spills` + `allocs.stack_slots_for_vars`).
- Spill load NOP (line ~430) with real
  `LDR Xt, [SP, #spill_off]` from the slot indicated by `op.slot`,
  into register `op.reg`.
- Spill store NOP (line ~437) with real
  `STR Xt, [SP, #spill_off]`.
- Epilogue NOP (line ~442-449) with real
  `ADD SP, SP, #frame_bytes`.

For imm12 < 4096 use the direct SP-relative encoding. For larger
frames (rare; would require complex GOAL functions), emit a
`MOV X16, #frame_bytes; SUB SP, SP, X16` (and matching ADD)
sequence — but the A8 analysis indicates display.gc's failing case
needs only a single 8-byte slot, so a single-slot path suffices for
this phase.

## Scope (locks)

**UNLOCKED for A9 only:**

- `goalc/compiler/CodeGenerator.cpp` — narrow: ONLY the
  `do_goal_function_arm64` function. Other functions in this file
  remain byte-identical.

**STILL LOCKED:**

- `goalc/compiler/IR.cpp`
- `goalc/compiler/CodeGenerator.h`
- `goalc/emitter/IGenARM64.{cpp,h}`
- `goalc/emitter/ObjectGenerator.{cpp,h}`
- `.autoport/lib/classify_ir_arm64.py`

## Anti-cheat invariants

Same as A6/A7/A8:

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` in
  `.cpp` / `.h` / `.s`.
- D4 validator's hardened check #10 must pass: ≥3/5 SDL/GL real-init
  markers, no synthesised renderer-entered marker dodge.
- 0 NOPs in arm64 patcher report (A5 invariant).
- x86 CGOs byte-identical to A2 baseline (the change is arm64-only
  inside `do_goal_function_arm64` — must conditional-compile or be
  in an arm64-specific function).
- Desktop x86 `gk` smoke still reaches `link finish: logo`.

## Required deliverables

1. `goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64` — real
   spill prologue/epilogue + LDR/STR.
2. arm64 CGOs regenerated. New `.autoport/reports/A9-baseline-arm64-cgo-hashes.txt`.
3. `bash .autoport/lib/qemu_repro.sh` (from A8) — must show the
   display.gc top-level executing past the previous NULL-fn-ptr BLR.
   Add a "FIRST POST-FIX CGO LINKED" line at the end of qemu_repro
   that names the first CGO whose link finish was previously
   unreached.
4. `bash .autoport/validators/phase-A6-emitter-off-register.sh`
   exits 0 (the device validator).
5. `.autoport/reports/A9-fix-summary.md` — short summary of the
   exact emit sequence used, frame-size calculation, and a
   disassembly snippet showing the LDR/STR replacing the NOPs.

## Honest exit condition

If the fix lands but ANOTHER bug surfaces downstream (likely —
once spills work properly, more of the runtime executes and may hit
new emitter cases), commit the spill fix and write
`.autoport/reports/A9-attempt-N-next-blocker.md` describing the
next layer. Don't try to fix multiple bug classes in one phase.

## Cost expectation

Narrow, diagnosis-already-done. Probably 1-2 hours / $30-50.
A8's root-cause report already has the exact emit-sequence
pseudocode. A9 is mostly mechanical translation of that pseudocode.
