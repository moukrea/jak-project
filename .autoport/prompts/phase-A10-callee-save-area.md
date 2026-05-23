# Phase A10 — caller's save-area preservation across GOAL→GOAL BLR

## Status

**Authored 2026-05-23 by the supervisor** after A9's spill ops landed
and unblocked 16 additional CGOs (45→61 link finishes). The remaining
boot crash is in a deeper layer: a GOAL→GOAL callee corrupts the
caller's preserved-register save area on the stack.

## Bucket

A — codegen (IR-level emit).

## Motivation

Per `.autoport/reports/A9-attempt-1-next-blocker.md`, post-A9 boot
crashes with:

```
GK-DIAG sig=11 fault=0x3 pc=0x21244fdf88
GK-DIAG x3=0xffffffdedd000003   ← garbage; was 0 pre-call
```

The disassembly (from the next-blocker report) shows the caller
pushes X3=0 with `stp x3, x5, [sp, #-16]!` before a `blr x9`, and
pops it back with `ldp x3, x5, [sp], #16` after. X3 should be 0
after the pop but holds `0xffffffdedd000003`. The callee corrupted
the caller's save area.

Three candidates per claude's analysis:
1. **Vector/128-bit store with miscomputed slot index** in a callee
   (most likely) — STR Qt that reaches above the callee's own frame
   into the caller's preserved area.
2. **Multi-slot var offset computation** doesn't account for A9's
   new `frame_bytes` SP movement.
3. **`set_var_to_stack_pointer` ireg** returns pre-prologue SP
   instead of post-prologue SP, so callees write into caller's frame.

The callee at `X9 = 0x21231c3944` is in engine.cgo space.

## Goal (concrete)

Identify which IR_* op in the callee produces an OUT-OF-BOUNDS store
that reaches above the callee's own frame, then fix the emit to
correctly account for `frame_bytes`. The fix likely needs to update
one of:

- `IR_StackVar::do_codegen_arm64` — offset computation relative to
  post-prologue SP
- `IR_GetStackAddr::do_codegen_arm64` — same shape
- `IR_StoreConstOffset::do_codegen_arm64` for vector-size stores
- `IR_SetVarToStackPointer::do_codegen_arm64` (if it exists) — must
  return post-prologue SP

After the fix, qemu_repro.sh must show boot progressing PAST the
current `knuth-rand` ceiling — ideally reaching `link finish: logo`
or `engine: state=`. D4 device-validator must pass end-to-end.

## Scope (locks)

**UNLOCKED for A10 only:**

- `goalc/compiler/IR.cpp` — narrow to the specific IR_* op found
  via diagnostics. Other IR_* op emits remain byte-identical.
- `goalc/compiler/CodeGenerator.cpp` — narrow extension: ONLY if a
  per-function-frame-size argument needs threading through to the
  IR codegen path.

**STILL LOCKED:**

- `goalc/emitter/IGenARM64.{cpp,h}`
- `goalc/emitter/ObjectGenerator.{cpp,h}`
- `goalc/compiler/CodeGenerator.h`
- `goalc/compiler/IR.h`
- `.autoport/lib/classify_ir_arm64.py`

## Anti-cheat invariants

Same as A6/A7/A8/A9:

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` in
  `.cpp` / `.h` / `.s`.
- D4 validator's hardened check #10 must pass (≥3/5 SDL/GL
  real-init markers, no synthesised renderer-entered dodge).
- 0 NOPs in arm64 patcher report (A5 invariant).
- x86 CGOs byte-identical to A2 baseline (the change must be
  arm64-only via `#ifdef GOALC_BACKEND_ARM64` or a clean arm64
  function-split).
- Desktop x86 `gk` smoke still reaches `link finish: logo`.

## Required deliverables

1. The IR.cpp emit fix that closes the caller's-save-area corruption.
2. arm64 CGOs regenerated; new `.autoport/reports/A10-baseline-arm64-cgo-hashes.txt`.
3. CGO sync into APK assets:
   `cp out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO android/app/src/jak1/assets/iso_data/jak1/`
4. `bash .autoport/lib/qemu_repro.sh` — must show boot progressing past
   `link finish: knuth-rand` to a later milestone (`link finish: logo`
   or `engine: state=` ideally).
5. `bash .autoport/validators/phase-D4-android-apk-title.sh` exits 0
   end-to-end (hardened SDL/GL marker check passes).
6. `.autoport/reports/A10-fix-summary.md` — names the failing IR op
   + the emit-sequence change + a disassembly snippet showing the
   correction.

## Honest exit condition

If diagnostic logging identifies the offending IR but the fix needs
IR.h structural changes or another lock unlock, commit the diagnostic
+ next-blocker report. The supervisor will read it and decide on A11.

## Cost expectation

Narrow, diagnosis-roadmap exists. ~1-2 hours / $30-50.

## Rate-budget caution

Weekly rate is at 72% when this phase starts. Each cascade phase
adds ~5-15% to weekly. If A10 takes more than 2 attempts, weekly
could hit 85%+ which approaches the natural halt zone. Bias toward
the honest-exit-with-diagnosis route if a quick fix isn't apparent —
better to commit progress + handoff than to spin retries against
weekly cap.
