# Phase A2 — Implement real arm64 codegen for every jak1 blocker

## What this phase delivers

Real arm64 codegen for **every IR form on the A1 blocker list** in
`.autoport/reports/A1-ir-inventory.json` (`summary.jak1_blockers`),
modulo the "no-op-by-design" carve-outs below. After this phase,
when the supervisor re-runs `.autoport/lib/classify_ir_arm64.py`
followed by `.autoport/lib/build_a1_inventory.py`, the inventory's
`arm64_stub` count must drop from 35 to **≤ the carve-out
allowance**.

Inputs you get for free:
- `.autoport/reports/A1-ir-inventory.json` — work list + per-form
  emit counts (priority order).
- `.autoport/reports/A1-ir-inventory.md` — readable summary of the
  same.
- `goalc/compiler/IR.cpp` — every `do_codegen_arm64::` body that
  you'll either rewrite or extend.
- `goalc/emitter/IGenARM64.h` + `goalc/emitter/IGenARM64.cpp` — the
  arm64 instruction-encoding API. Phase 24 implemented MOV/MOVZ/
  MOVK/ADD/SUB/CMP/B/B.cond. Everything else needs new encoders.
- The desktop oracle at `.autoport/oracle/jak1-desktop-trace.txt` —
  ground truth for what a working x86 build looks like.

Outputs the phase produces:
- New `do_codegen_arm64` bodies on every blocker IR in `IR.cpp`.
- New encoder functions in `IGenARM64.cpp` for the arm64 instructions
  those bodies need (LDR / STR / BL / RET / ADRP+ADD / FADD / etc.).
- New tests at `test/arm64/emitter_smoke_A2.gc` exercising each new
  codegen path (the phase 24 file has 4 functions; this phase should
  have one per cluster, ~6 total).
- Regenerated CGOs in `out/jak1/iso/` from a fresh `(mi)` run using
  the rebuilt goalc (x86 backend, so the desktop oracle still works).

## Why this matters

A1 confirmed it numerically: 35 of the 41 IR forms jak1 uses have
NO real arm64 codegen. Without this phase, every arm64-compiled
jak1 CGO is mostly zero-emit garbage — exactly the situation phase
25 left us in, packaged into the Android APK.

A2 is the largest single chunk of remaining work in the whole port.
Plan it deliberately. Implement clusters in priority order. Commit
after each cluster so a mid-phase failure doesn't lose work.

## The carve-outs (what does NOT need to become "real")

A few IR forms emit zero-or-one trivial instructions on x86 by
design. The A1 classifier marks them as `stub` because its threshold
is "≥1 non-NOP arm64 instruction." For these forms, the arm64
implementation should **mirror x86**:

| IR form | x86 behavior | arm64 expected |
|---|---|---|
| `IR_Null` | emits nothing | emit nothing |
| `IR_ValueReset` | emits nothing | emit nothing |
| `IR_Nop` | one `nop` | one `nop` (still "stub" by the classifier, that's fine) |

The A2 validator allows these three to stay classified as `stub`.
**Every other blocker must become `real`.** Padding NOPs around a
real instruction doesn't satisfy the validator — see the anti-cheat
section.

## Clustering (recommended work order)

Implement in this order. After each cluster: rebuild goalc, run
`(mi)`, run gk smoke, run the classifier, commit. That way a
partial pass still ships value.

### Cluster A2-mem (load/store, 9 forms, ~432K jak1 emits)
- `IR_LoadConstOffset` (135K)
- `IR_GetSymbolValue` (90K)
- `IR_LoadSymbolPointer` (83K)
- `IR_StoreConstOffset` (60K)
- `IR_StaticVarLoad` (29K)
- `IR_StaticVarAddr` (23K)
- `IR_SetSymbolValue` (6K)
- `IR_GetStackAddr` (3K)
- `IR_RegValAddr` (85)

These need new arm64 encoders: `LDR (immediate, GPR64/GPR32)`,
`STR (immediate)`, `ADRP+ADD` for symbol addressing, and the
GOAL-runtime symbol-table base register convention (x86 uses r15;
arm64 should pick a callee-saved GPR — see `EmitterTypeFlags::r15`
in the existing x86 path).

### Cluster A2-call (function call + control, 5 forms, ~70K)
- `IR_FunctionCall` (59K)
- `IR_FunctionAddr` (9K)
- `IR_JumpReg` (4)
- (IR_Null, IR_ValueReset already carved out)

`IR_FunctionCall` is the big one. Implement the GOAL calling
convention: arguments in x0-x7, return in x0, link in x30, frame
on sp. Match what `do_goal_function_arm64`'s prologue/epilogue
(phase 24, in CodeGenerator.cpp) expects. Use `BL` for direct
calls, `BLR` for indirect.

### Cluster A2-float (3 forms, ~22K)
- `IR_FloatMath` (16K) — FADD/FSUB/FMUL/FDIV in SP single-precision
- `IR_IntToFloat` (4K) — SCVTF
- `IR_FloatToInt` (1.8K) — FCVTZS

Use `s0-s31` (NEON single regs). Match the x86 SSE convention for
register allocation if `EmitterRegisterClass::FloatReg` already maps
those to fixed indices.

### Cluster A2-vf (vector float, 6 forms, ~6.6K)
- `IR_VFMath3Asm` (3K)
- `IR_BlendVF` (1.9K)
- `IR_SplatVF` (1.1K)
- `IR_SwizzleVF` (188)
- `IR_VFMath2Asm` (130)
- `IR_SqrtVF` (20)

GOAL's VF is a 4-wide float vector — maps to arm64 NEON v0-v31
(treated as `q` regs / `4s` lanes). VFMath3Asm and VFMath2Asm
carry an explicit mnemonic from the GOAL `(.vfadd …)` macro — you
need a translation table from VU/SSE mnemonics to NEON
`(fadd|fsub|fmul|fdiv).4s` etc. The mnemonic mapping is the work;
the NEON encoding itself is straightforward.

### Cluster A2-int128 (SIMD integer, 2 forms, ~1.2K)
- `IR_Int128Math3Asm` (996)
- `IR_Int128Math2Asm` (240)

These cover SIMD integer ops the original PS2 VU emitted (PADDB,
PADDW, etc.). Map to NEON `add.16b`, `add.8h`, etc. via another
mnemonic table.

### Cluster A2-asm (inline-asm IRs, 9 forms, ~650)
- `IR_RegSetAsm` (482)
- `IR_AsmFNop` (48)
- `IR_AsmFWait` (34)
- `IR_AsmAdd` (23)
- `IR_AsmPop` (21)
- `IR_AsmPush` (21)
- `IR_AsmRet` (8)
- `IR_AsmSub` (6)
- `IR_GetSymbolValueAsm` (3)

These are GOAL `(.asm ...)` inline-asm escapes. Some are
straightforward (AsmRet → `ret`, AsmAdd → `add`). AsmPush/AsmPop
need the AArch64 stack convention (`stp x?, x?, [sp, #-16]!` /
`ldp ...`). AsmFNop and AsmFWait map to `nop` (these were x86 FPU
synchronisation primitives that have no arm64 equivalent — emit
`nop` and document why; the classifier won't see this as `real`
either, so document the exception in the inventory).

## Anti-cheat constraints (CRITICAL)

The previous orchestrator's phase 24 wrote 41 functions whose
bodies were "NOP-fallback" — they emitted a NOP and returned, so
the symbol existed but no work happened. Phase 25 then changed
those to zero-emit so the validator's "ret density" metric was
satisfied. This pattern is the cheat lineage to avoid.

**Forbidden patterns**:

1. A body that emits only `nop` instructions and returns — except
   for the three carve-outs above. The classifier will flag this
   as `stub`; the validator will fail.

2. Editing `.autoport/lib/classify_ir_arm64.py` to call NOPs
   "real". The classifier is **input** to the validator; the
   validator runs it twice for sha256 reproducibility and fails if
   the script changes mid-phase. If you have a legitimate
   classifier bug (e.g., the carve-outs above need handling),
   document it in the supervisor journal before editing — and even
   then prefer fixing the inventory schema over relaxing the
   classifier.

3. Editing **any** `do_codegen_x86` body in `IR.cpp`. The desktop
   oracle is x86-only; if you change x86 codegen you'll break the
   oracle's reproducibility check and the supervisor will halt
   you. Touch only `do_codegen_arm64` bodies + add new encoders in
   `IGenARM64.{h,cpp}` + (carefully) extend `CodeGenerator.cpp`'s
   dispatch wiring.

4. Adding a `do_codegen_arm64` body that emits *only* an existing
   arm64 instruction stream copied from `do_codegen_x86`. The x86
   stream is x86 bytes — copying them into the arm64 path
   propagates the phase 25 cheat at a smaller scale. Every arm64
   body must call arm64 encoders, never the x86 ones.

5. Calling `goalc --backend arm64` to "regenerate CGOs" without
   first verifying that the x86 backend still produces *exactly
   the same* CGO bytes as before. If your changes accidentally
   touch shared code (Val.cpp, ObjectGenerator.cpp), the x86
   output drifts and the desktop oracle breaks. Diff
   `out/jak1/iso/KERNEL.CGO` against the supervisor's working
   pre-edit version (committed in commit `9ee66e113`'s tree)
   before declaring done. ANY non-trivial byte-level diff in the
   x86 CGO is a regression.

## Done definition

The validator at `.autoport/validators/phase-A2-emitter-implement.sh`
exits 0. That script verifies:

- A1's inventory artifacts still exist (sanity).
- Re-running the classifier produces an updated count: every entry
  in A1's `jak1_blockers` is now classified `real` **OR** is one
  of the three carve-outs (`IR_Null`, `IR_ValueReset`, `IR_Nop`)
  plus the two documented exceptions (`IR_AsmFNop`, `IR_AsmFWait`,
  if you mark those as exceptions in `.autoport/reports/A2-carve-outs.json`).
- `git diff HEAD~ -- goalc/compiler/IR.cpp` shows no changes to any
  `do_codegen_x86::` body (only `do_codegen_arm64` and new helper
  fns).
- `cmake --build build --target goalc -j8` succeeds (x86 goalc still
  compiles).
- `cmake --build build-arm64 --target goalc -j8` succeeds OR you
  document why build-arm64 isn't being used yet (the build dir was
  set up by phase 24 — restore it if needed; see `goalc/CMakeLists.txt`
  and the GOALC_BACKEND_ARM64 flag).
- A fresh x86 `(mi)` run produces CGOs identical to the
  supervisor's pre-A2 working set (`out/jak1/iso/KERNEL.CGO` hash
  matches what `git ls-tree 9ee66e113 -- out/jak1/iso/KERNEL.CGO`
  would show — except that file is gitignored, so cache the
  reference hash in `.autoport/reports/A2-baseline-x86-cgo-hashes.txt`
  at the start of your work and compare at the end).
- Desktop gk still reaches `link finish: logo` within 60s under
  the working invocation `gk --game jak1 --portable -fakeiso
  --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem`.
- For every new "real" arm64 body, `aarch64-linux-gnu-objdump -d`
  on a compiled smoke test shows the expected instruction
  mnemonics (LDR for IR_LoadConstOffset, BL for IR_FunctionCall,
  FADD for IR_FloatMath, etc.). The validator runs objdump on
  `test/arm64/emitter_smoke_A2.gc` output and grep-confirms each
  expected mnemonic.

## Files you will create / modify

| Path | Purpose |
|---|---|
| `goalc/compiler/IR.cpp` | New/expanded `do_codegen_arm64` bodies for each blocker |
| `goalc/emitter/IGenARM64.h` + `.cpp` | New arm64 encoders (LDR/STR/BL/BLR/FADD/...) |
| `goalc/emitter/Register.h`? | Possibly add NEON register class wiring |
| `test/arm64/emitter_smoke_A2.gc` | Per-cluster smoke functions |
| `test/arm64/CMakeLists.txt` | Wire the new smoke file into the ctest target |
| `.autoport/reports/A2-baseline-x86-cgo-hashes.txt` | sha256 of pre-edit CGOs, captured at phase start |
| `.autoport/reports/A2-carve-outs.json` | Documented exceptions list (IR_Null, IR_ValueReset, IR_Nop, IR_AsmFNop, IR_AsmFWait) |
| `.autoport/reports/A2-inventory-after.json` | Re-run classifier output after A2's work |

## Pitfalls

- The `IGenARM64.{h,cpp}` API is incomplete. Phase 24 hand-encoded
  MOV/ADD/SUB/CMP/B/B.cond directly. For LDR/STR with immediate
  offset you'll need a new encoder taking (rd, rn, imm) and producing
  the 32-bit instruction word per ARM ARM C6.2.93. Don't reuse
  hand-encoded `InstructionARM64(0x…)` literals — the validator
  rejects bodies that only emit pre-baked words because that's how
  phase 24's stubs evaded detection.

- `IR_FunctionCall` must respect the desktop x86 calling convention
  too — argument passing on x86 uses GOAL's `function-arg-regs`
  list (which is set in `goalc/compiler/Compiler.cpp`). The arm64
  variant must map the same logical-argument-index sequence onto
  x0-x7. Don't reorder; that breaks intra-CGO compatibility.

- VF and Int128 mnemonic translation tables (cluster A2-vf,
  A2-int128) are the hardest piece of A2. Allocate budget. If you
  can't finish them in one attempt, commit what you have and let
  the orchestrator retry — but only after the carve-outs JSON
  records exactly which VF mnemonics remain unmapped so the next
  attempt picks up cleanly.

- The `--ir-emit-stats` flag from phase A1 still works — use it
  liberally to verify your changes don't shift x86 emit counts
  (which would mean you accidentally edited a shared path).

## Reading list (open these before you start)

- `.autoport/reports/A1-ir-inventory.json` and
  `.autoport/reports/A1-ir-inventory.md` — your work list
- `goalc/compiler/IR.cpp` — particularly the 6 already-`real`
  `do_codegen_arm64` bodies (`IR_Return`, `IR_LoadConstant64`,
  `IR_RegSet`, `IR_IntegerMath`, `IR_GotoLabel`,
  `IR_ConditionalBranch`) — these are the template
- `goalc/emitter/IGenARM64.h` and `.cpp` — the encoder API; you'll
  extend it heavily
- The ARM Architecture Reference Manual (online), sections on:
  - C6.2.93 (LDR immediate)
  - C6.2.181 (STR immediate)
  - C6.2.34 (BL)
  - C6.2.36 (BLR)
  - C7.2.36 (FADD)
  - C7.2.81 (FMOV / SCVTF / FCVTZS conversions)
  - C7.2.226 (NEON ADD/SUB/MUL by-vector)
- `.autoport/SUPERVISOR_JOURNAL.md` — context on what was rolled
  back and why
- The phase 24 commit `c6572b9c6` — for the encoder pattern that
  worked (MOV/ADD/CMP/branch families)
- `.autoport/oracle/jak1-desktop-trace.txt` — the desktop trace
  your changes must NOT break

## A note on size

This phase is intentionally large. The orchestrator budget is
1200 turns × 30 retries because A2 is genuinely the
multi-week chunk of work REDESIGN.md §11 warned about. If you
finish all clusters in one attempt — fantastic. If not, commit
progress per cluster and let stuck-detection fire when truly stuck
(at which point the supervisor will split A2 into sub-phases). Do
NOT artificially pad commits to make progress look bigger than it
is; the supervisor reads the diffs.
