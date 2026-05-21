# Phase A3 — Per-cluster arm64 differential vs x86

## What this phase delivers

Proof that A2's arm64 implementations are not just *syntactically real*
(non-NOP encoders called) but **semantically correct**: for every
cluster A2 implemented, at least one synthetic GOAL function compiles
to arm64 bytes that, when executed under `qemu-aarch64-static`, return
the same value as the x86 build of the same function.

Two complementary checks:

1. **Disasm-clean for every real IR**: an arm64-built test exercising
   each of the 36 real IRs from `.autoport/reports/A2-inventory-after.json`
   produces a disassembly with the expected mnemonics. No surprise NOP
   sequences, no garbage bytes. This portion does NOT need to execute.

2. **Qemu-execute for everything except documented reloc-skips**: a
   subset of the synthetic tests is executable end-to-end under
   `qemu-aarch64-static` and produces a return value identical to the
   x86 build's. The reloc-needing IRs from A2's carve-outs notes
   (`IR_GetSymbolValue`, `IR_SetSymbolValue`, `IR_LoadSymbolPointer`,
   `IR_GetSymbolValueAsm`, `IR_StaticVarLoad`, `IR_StaticVarAddr`,
   `IR_FunctionAddr`) are skipped here — they're explicitly the
   work of the follow-on phase **A4-linker-fixups**, which will widen
   ObjectGenerator's fix-up path to know about arm64 imm12/imm19
   immediates. After A4, this phase can be re-run to lift the skips.

## Why this matters

Phase 24 produced "real" arm64 encoders that were never executed
against ground truth. Phase 25 packaged them into CGOs that the
desktop x86 build SIGILL'd on (the arm64-bytes-as-x86-instructions
incident the supervisor unwound on 2026-05-21). A3 closes the
trust gap: every cluster has at least one independently-runnable
witness that the encoder produces correct machine code.

A1 enumerated. A2 implemented. A3 **verifies**. Bucket B then
regenerates jak1 CGOs against an emitter we trust.

## Concrete deliverables

### 1. Synthetic test programs at `test/arm64/diff/`

One `.gc` file per cluster, plus extras for the high-impact IR forms.
Minimum (per the REDESIGN §8 "per-cluster differential"
requirement):

| Cluster | Test file | IRs exercised | Expected return |
|---|---|---|---|
| mem (no-reloc) | `mem_load_const_offset.gc` | `IR_LoadConstOffset`, `IR_StoreConstOffset`, `IR_RegValAddr`, `IR_GetStackAddr` | computed from a stack buffer the test sets up |
| call | `call_return.gc` | `IR_FunctionCall`, `IR_Return`, `IR_FunctionAddr` (the called-fn handle), `IR_JumpReg` | known constant via a chain of calls |
| float | `float_math.gc` | `IR_FloatMath` (add/sub/mul/div), `IR_IntToFloat`, `IR_FloatToInt` | int answer to a rounded float expression |
| vf | `vf_lane_math.gc` | `IR_VFMath3Asm`, `IR_VFMath2Asm`, `IR_BlendVF`, `IR_SplatVF`, `IR_SwizzleVF`, `IR_SqrtVF` | int extracted from one NEON lane |
| int128 | `int128_math.gc` | `IR_Int128Math3Asm`, `IR_Int128Math2Asm` | int from one SIMD-int lane |
| asm | `asm_ops.gc` | `IR_AsmAdd`, `IR_AsmSub`, `IR_AsmPush`, `IR_AsmPop`, `IR_AsmRet`, `IR_RegSetAsm`, `IR_AsmFNop` (NOP fine), `IR_AsmFWait` (NOP fine) | arithmetic over saved/restored registers |

Each `.gc` file defines `(defun test-A3-<cluster> () int ...)` whose
body uses the listed IRs. The expected return value is chosen so an
incorrect encoding (wrong opcode, wrong operand) produces a
DIFFERENT integer — making the test useful, not tautological.

### 2. Build harness at `.autoport/lib/build_a3_diff.sh`

Compiles each `.gc` file with BOTH backends and runs the harness:

```
build/goalc/goalc       -c "(asm-file \"<gc>\" :color :write)" → x86 .o
build-arm64/goalc/goalc -c "(asm-file \"<gc>\" :color :write)" → arm64 .o

# x86: link with a tiny C main that calls test-A3-<cluster> and prints
#      the int return value to stdout.
# arm64: wrap the function bytes as elf64-littleaarch64 (reuse
#        build_a2_smoke.sh's approach), link a tiny AArch64-syscall
#        harness that calls the function and exits with its return
#        value, run under qemu-aarch64-static.
```

The harness writes per-test outcomes to a temp directory and a final
`.autoport/reports/A3-coverage.json`.

### 3. Coverage report `.autoport/reports/A3-coverage.json`

Schema (validator enforces):

```json
{
  "phase": "A3-emitter-differential",
  "x86_oracle_link_finish_logo": true,
  "summary": {
    "real_ir_count": 36,
    "tested_via_disasm": 36,
    "qemu_executed": <n>,
    "matches_x86": <n>,
    "reloc_skipped": <list of IRs from A2's linker_followup>,
    "other_skipped": [],
    "test_files": <count>
  },
  "by_ir": {
    "IR_LoadConstOffset": {
      "cluster": "mem",
      "test_file": "test/arm64/diff/mem_load_const_offset.gc",
      "disasm_clean": true,
      "expected_mnemonics_present": ["ldr", "str"],
      "qemu_executed": true,
      "matches_x86": true,
      "x86_result": 42,
      "arm64_result": 42
    },
    "IR_GetSymbolValue": {
      "cluster": "mem",
      "test_file": "test/arm64/diff/mem_symbol.gc",
      "disasm_clean": true,
      "expected_mnemonics_present": ["adrp", "add", "ldr"],
      "qemu_executed": false,
      "skipped_reason": "reloc-needed; deferred to A4-linker-fixups",
      "skipped_ref": "A2-carve-outs.json.notes.linker_followup"
    }
  }
}
```

The validator requires:
- Every "real" IR from `A2-inventory-after.json` has an entry in `by_ir`.
- `disasm_clean == true` for **every** real IR (no exceptions).
- `qemu_executed == true` and `matches_x86 == true` for every real IR
  except those in the bounded reloc-skip list.
- The reloc-skip list **may not exceed** the 7 IRs A2 documented in
  its linker_followup note. A larger skip list is a fail (means the
  phase is hiding something).
- `summary.x86_oracle_link_finish_logo` must be true (proven by the
  validator's own gk smoke step).

### 4. Markdown summary `.autoport/reports/A3-coverage.md`

Top of the file:
> Of 36 real IR forms, N have disasm-clean arm64 codegen; M
> qemu-execute to a value matching x86. 7 forms reloc-skipped
> pending A4-linker-fixups.

Followed by per-cluster tables.

## Anti-cheat constraints

1. **Tests must be non-tautological.** A test that returns `0` from
   both backends because the arm64 codegen emits zero bytes is not a
   pass — choose return values that depend on each IR's correct
   behavior (e.g., for `IR_LoadConstOffset`, return the value at
   `[sp + 16]` after writing 0x2A there; if LDR's offset is wrong, the
   test reads garbage and returns a different value).

2. **Do not modify** `goalc/compiler/IR.cpp`, `IGenARM64.cpp`,
   `CodeGenerator.cpp` to alter codegen behavior in this phase. A3
   verifies what A2 produced; it does not extend it. The validator
   diffs IR.cpp / IGenARM64.cpp / CodeGenerator.cpp against the A2
   commit hash and fails if non-trivial changes appear (test/, build
   harness, reports are allowed; new arm64 encoders or codegen
   bodies are not).

3. **Do not fake qemu output.** The harness must call
   `qemu-aarch64-static` as a subprocess and capture its exit code as
   the int return value (arm64 syscall_exit convention). No reading a
   pre-baked file. The validator re-runs the harness and compares.

4. **Do not pad the skip list** beyond the 7 reloc-needing IRs A2
   documented. If you discover a new IR that can't be qemu-executed,
   the phase fails — investigate the root cause and either
   implement it OR raise a new follow-up note in
   `A2-carve-outs.json.notes`. Don't quietly skip.

5. **Do not adjust the expected return values** to match buggy arm64
   output. The expected return is the x86 value computed first; if
   arm64 differs, that's a real encoding bug to find in A2's
   implementation, not a tolerance to widen.

## Files you will create

| Path | Purpose |
|---|---|
| `test/arm64/diff/mem_load_const_offset.gc` | mem cluster (no reloc) |
| `test/arm64/diff/mem_symbol.gc` | mem cluster (reloc-skipped) |
| `test/arm64/diff/call_return.gc` | call cluster |
| `test/arm64/diff/float_math.gc` | float cluster |
| `test/arm64/diff/vf_lane_math.gc` | vf cluster |
| `test/arm64/diff/int128_math.gc` | int128 cluster |
| `test/arm64/diff/asm_ops.gc` | asm cluster |
| `.autoport/lib/build_a3_diff.sh` | the build+run harness |
| `.autoport/lib/qemu_harness_arm64.S` (or .c) | tiny AArch64 syscall stub that calls a function and exits with its return |
| `.autoport/lib/qemu_harness_x86.c` | tiny x86 stub that calls a function and prints its return |
| `.autoport/reports/A3-coverage.json` | the coverage record |
| `.autoport/reports/A3-coverage.md` | the human summary |

## Pitfalls

- **Linking arm64 GOAL .o files into a runnable elf is non-trivial.**
  GOAL .o is a v3 custom format; aarch64-linux-gnu-ld won't read it.
  Reuse `cgo_inspect.py` + `aarch64-linux-gnu-objcopy` (the pattern
  in `build_a2_smoke.sh`) to extract raw bytes into a flat .text
  section, then ld with your own qemu_harness_arm64 entry-point.

- **The qemu_harness must use AArch64 Linux syscall ABI** (svc #0,
  x8=syscall number, x0-x5 args). `_start` calls the GOAL test
  function (which uses GOAL's calling convention: x0 return),
  then issues `mov x8, #93; svc #0` (exit syscall) with x0 as exit
  status. The harness must NOT depend on libc — qemu-aarch64-static
  doesn't load a libc.

- **GOAL's calling convention is not the standard AArch64 PCS.**
  Argument registers + return register may differ. Check phase 24's
  CodeGenerator::do_goal_function_arm64 to see what registers the
  prologue/epilogue uses. The test functions take 0 args and return
  in x0, so this is the simplest case.

- **`build-arm64/goalc/goalc` may need a fresh `(mi)` if jak1 sources
  changed.** A3's tests aren't part of `(mi)`; compile them directly
  with `-c '(asm-file "<path>" :color :write)'`.

- **VF/Int128 tests need to extract one lane** to produce an int
  return. `IR_RegSetAsm` may help here. If unavailable, use the GOAL
  builtin `(.umov dest src lane)` if it exists, or a simple lane-0
  read.

## Reading list

- `.autoport/reports/A2-inventory-after.json` — the work list (every
  `real` IR needs a witness)
- `.autoport/reports/A2-carve-outs.json` — the 5 doc'd exceptions
  (`notes.linker_followup` defines the reloc-skip list)
- `goalc/emitter/IGenARM64.cpp` — what encoders are available
- `goalc/compiler/IR.cpp` — every `do_codegen_arm64` body A2 wrote
- `.autoport/lib/build_a2_smoke.sh` — the elf-wrap recipe A3 extends
- `.autoport/lib/cgo_inspect.py` — the v3 GOAL .o parser
- `test/arm64/emitter_smoke.gc` (phase 24) and
  `test/arm64/emitter_smoke_A2.gc` (A2) — examples of synthetic
  GOAL tests
- `.autoport/SUPERVISOR_JOURNAL.md` — A2 completion entry +
  linker_followup discussion

## Done definition

`.autoport/validators/phase-A3-emitter-differential.sh` exits 0.
That script verifies:

- `A3-coverage.json` exists, parses, and has the schema above.
- Every "real" IR in `A2-inventory-after.json` has an entry in
  `by_ir`.
- Every entry has `disasm_clean == true`.
- For every entry not in the reloc-skip list, `qemu_executed` AND
  `matches_x86` are both true.
- `reloc_skipped` is a subset of the 7 IRs in A2's
  `linker_followup` list. Cannot grow beyond.
- `other_skipped` is empty (you don't skip for non-reloc reasons).
- A re-run of the harness `.autoport/lib/build_a3_diff.sh` reproduces
  the JSON to within +/-0 differences (deterministic; validator
  spot-runs it).
- Disasm spot-check: for each non-skipped IR, the expected mnemonics
  (named in the JSON) appear in `aarch64-linux-gnu-objdump -d` of
  the test's arm64 elf.
- gk smoke test still reaches `link finish: logo`.
- No do_codegen modifications to `IR.cpp` / `IGenARM64.cpp` /
  `CodeGenerator.cpp` since A2's commit.
- Markdown summary present with the required headline.

## Note on follow-on phase A4

A4-linker-fixups will widen `ObjectGenerator::handle_temp_instr_sym_links`
to patch arm64 imm12 (LDR offset) and imm19 (B.cond branch) immediates,
not just x86 32-bit byte displacements. Once that lands, this phase
can be re-run with an empty `reloc_skipped` list and full qemu
coverage. The supervisor authors A4 after A3 passes.
