# Phase A23 — arm64 runtime BLR-target tracer + Val.cpp / Type.cpp audit (locate the source emit-site of the stack-addr-as-fn-ptr value)

## First step — read these

1. `.autoport/CODEGEN_COOKBOOK.md`.
2. `.autoport/reports/A22-attempt-1-no-source-located.md` — A22's honest exit. **Specifically read §"Why a runtime tracer is the right next step" (lines 262-304) and §"Proposed A23 plan" (lines 306-354).** A23 is the supervisor's instantiation of that plan.
3. `.autoport/reports/A22-investigation-trace.md` — 558 lines of A22's audit. Key findings to NOT re-derive:
   - `IR_FunctionCall::do_codegen_arm64` (IR.cpp:651) emits same shape as x86 — correct at IR level.
   - `call_r64` (IGenARM64.cpp:1579) save/restore math correct, mirror order correct.
   - `arm64_add_xd_sp_imm12` + `sub_gpr64_gpr64` produce GOAL form of stack addr correctly (this is the source of the GOAL-form stack-addr values — but the *production* is correct; the *use* of them as fn-ptrs is the bug).
   - `store_goal_gpr` / `load_goal_gpr` X16 pair usage is atomic, no cross-IR leak.
   - `_arg_call_arm64` IS broken (its post-LDR-X8 epilogue reads X29/X30 from caller's stack), BUT it's DEAD CODE on the arm64 boot path (`make_function_from_c_arm64` jak1/kscheme.cpp:601 emits an inline trampoline that doesn't call `_arg_call_arm64`). **Fixing `_arg_call_arm64` would be hygiene-only and would NOT advance the 216 ceiling.** A23 may fix it as a side-effect but the validator does not credit it as the H2 fix.
   - `_call_goal_asm_arm64`, `_call_goal8_asm_arm64`, `_call_goal_on_stack_asm_arm64`, `make_function_from_c_arm64` inline trampoline: all correct.
   - X12 = 0x21231d6344 at SIGILL points to GOAL DATA, not to the executing function (X12-0x08 has RET `0xd65f03c0`). X12 is just a saved value in goalc's saved set, not the BLR target.
4. `.autoport/reports/A21-attempt-1-bug-class-identified.md` — A21's H2 verdict (with arithmetic verification).
5. `.autoport/reports/A21-qemu-reg-byte-dump.log` — raw qemu log with crash-time register state.
6. `.autoport/reports/A20-attempt-1-next-blocker.md` — A20's off-by-4 falsification.
7. `goalc/compiler/Val.cpp` — the type representation of values, including stack-pointer values (`StackVarAddrVal`, `MemoryDerefVal`, function-pointer-typed values). **Specifically audit how a value of type `stack-pointer-T` can flow into a slot typed as `(function ...)` or `pointer-to-function`.** A22 ruled this out for the off-by-4 hypothesis but did NOT audit for the fn-pointer-vs-stack-pointer flow specifically.
8. `goalc/compiler/compilation/Type.cpp` — the compile-time type-checking rules. **Specifically audit whether assigning a value of type `(pointer T)` (where T is heap-or-anything) to a slot of type `(function ARGS RET)` is checked or silently allowed.**

## Status

**Authored 2026-06-09 by the supervisor** after A22 attempt-1 honest-exited via Path C. A22 confirmed the H2 mechanism with new arithmetic evidence (X7=X8=0x07fffe84 = GOAL form of crash PC) but could not identify the specific emit-site / GOAL function within A22's unlock list.

Pre-A23 supervisor reality-checks:

- Independently verified A22's PASS: x86 CGOs match A2 baseline; arm64 CGOs match A21 baseline; qemu link-finish count = 216 (unchanged); A18+A19+A20+A21 invariants all preserved; 0 cheats.
- Independently re-ran qemu_repro.sh and confirmed crash signature matches A22's analysis.
- Read A22's investigation-trace.md in full; the audit is thorough and the Path C exit is the honest choice given the evidence.

## The bug (re-stated for A23)

`m_func` value passed to `IR_FunctionCall::do_codegen_arm64` is a GOAL form of a HOST STACK ADDRESS, not a heap-resident GOAL function pointer. The arm64 emit dutifully:

```
ADD freg, freg, X15         ; freg = stack_GOAL + ee_base = host stack addr
STP X3,X5, [SP,#-16]!        ; call_r64 prologue
STP X10,X11, [SP,#-16]!
STP X12,X23, [SP,#-16]!
BLR freg                     ; PC = host stack address → SIGILL
```

The "fix" is upstream of `do_codegen_arm64`: a Val that was produced by `IR_GetStackAddr` / `IR_RegValAddr` (correctly producing a GOAL-form stack addr) ends up as the `m_func` argument of `IR_FunctionCall`. The question is WHERE.

**A23's job is to (a) instrument the goalc-arm64 emit to detect stack-range BLR targets at runtime, then (b) cross-reference the detected emit-site against the GOAL function symbol table to NAME the specific GOAL source location, then optionally (c) fix the source flow if it's in Val.cpp / compilation/Type.cpp.**

## Investigation steps

### Step 1 — Implement `OG_BLR_TARGET_TRACE` in goalc emit

In `goalc/emitter/IGenARM64.cpp`, the `call_r64(reg)` helper at line 1579 emits the call-target BLR. Add an env-gated emit that, when the env var `OG_BLR_TARGET_TRACE_EMIT=1` is set during goalc compile, inserts a check sequence before the BLR:

```
; reg = X? — the BLR target (post-ADD-X15 host form)
; X16, X17 are dead-between-IRs scratch (per cookbook §1)
LDR  X17, ee_main_mem_top    ; top of EE main memory (= heap upper bound)
CMP  reg, X17
B.LO target_ok               ; if reg < top, normal path
; OUT OF HEAP RANGE — likely STACK or invalid
MOV  X16, #DEAD_CALL_TAG     ; e.g. 0xCAFEDEAD
UDF  #0x1ee2                 ; SIGILL with distinctive tag in the encoding
target_ok:
BLR  reg
```

The env-gate is at GOALC COMPILE TIME: when `OG_BLR_TARGET_TRACE_EMIT=1` is set during goalc compile, the extra ~6 instructions are emitted into every `call_r64` site. When unset (default), nothing changes; CGOs are byte-identical to A21 baseline.

After A23 emits the gated check, regenerating the arm64 CGOs with the env var set will produce a NEW baseline (A23-baseline-arm64-cgo-hashes.txt). The validator must accept that new baseline as the gold reference.

**Why this is honest, not a cheat**: the gate is at GOALC COMPILE TIME (controlled by an env var read by goalc itself when invoked), not a runtime gate inside the emitted code. The emitted code path either has the check (env set during compile) or doesn't (env unset). It's a build-time switch. This is the same pattern Linux kernel uses for CONFIG_KASAN-style debug builds.

### Step 2 — Decode the UDF tag in the SIGILL handler

In `game/linux-arm64/linux_arm64_main.cpp`, extend `gk_sigsegv_diag` (or whatever handles sig=4) to:

- Detect when the UDF instruction at PC has immediate `0x1ee2`.
- Read X16 to get the DEAD_CALL_TAG (= 0xCAFEDEAD).
- Read the BLR target reg (which is implicit in the UDF emit; you need to remember which reg held the bad value — easiest: include the reg encoding in the UDF immediate or stash it in another known location like the lower bits of X16).
- Print:
  ```
  GK-DIAG BLR-TARGET-STACK: udf_imm=0x1ee2 freg=X? freg_value=0x... emit_pc=0x... caller_lr=0x...
  ```
- The `emit_pc` is the PC of the UDF instruction (which is at the emit-site of the check, immediately before the BLR).
- Cross-reference `emit_pc` against the linked CGO symbol table (the runtime maintains this in `g_link_block_list` or similar).

### Step 3 — Cross-reference emit_pc to GOAL function

The goalc-emitted code has symbol-debug-info that maps emit-PC ranges to GOAL function names. The runtime's klink system maintains this mapping. From `emit_pc`, walk the active link blocks to find which GOAL function the PC is in. Print the function name in the GK-DIAG output.

If the symbol-debug-info isn't accessible from the SIGILL handler (low-level signal context), defer the lookup to a post-mortem step (e.g., dump emit_pc to a file, then run a separate decoder on the qemu-killed core).

### Step 4 — Run qemu, capture the BLR-TARGET-STACK event

```
OG_BLR_TARGET_TRACE=1 bash .autoport/lib/qemu_repro.sh /tmp/a23-tracer.log
```

The first UDF #0x1ee2 firing tells us the offending BLR site. The `emit_pc` + `caller_lr` + `freg_value` triple identifies the GOAL function and the specific call.

### Step 5 — Audit Val.cpp / compilation/Type.cpp for the flow

With the GOAL function name in hand, look at its `.gc` source. The function calls SOMETHING and the SOMETHING is a stack-pointer GOAL form. Where in Val.cpp / compilation/Type.cpp does the type system allow this?

Two failure modes to look for in Val.cpp:

- A `MemoryDerefVal` lowering that produces an integer-typed Val from a stack base (correct) but then an upstream codegen treats the result as a function-pointer (wrong upstream).
- A `StackVarAddrVal` (or `IR_GetStackAddr` IR) that's allowed to be used in an `IR_FunctionCall::m_func` slot without a type check.

In compilation/Type.cpp, look for:

- `typecheck` function that compares an actual type against an expected type. Is there a path where `(pointer ?)` is allowed where `(function ARGS RET)` is expected?
- `lookup_method` or `dispatch_method` that returns a method address from an object — does it correctly return a heap-resident method ptr, or can it return a stack-resident value if the object's type has a stack-allocated methods table?

### Step 6 — Fix or honest-exit

If the audit identifies a Val.cpp or Type.cpp bug, fix it. Re-run qemu without the tracer env var (so CGOs go back to "A21 + the gated runtime tracer"). Verify qemu boot count >= 217.

If the audit identifies a GOAL source bug (e.g., `(let ((f (& local-fn))) (call f))`), the fix is in GOAL source. Document the GOAL source location in `A23-bug-located-named-source.md` and recommend A24 to land the GOAL source fix.

If neither audit identifies a bug, honest-exit with the located emit-PC and a recommendation for A24.

## Scope (locks)

**UNLOCKED for A23:**

- `goalc/emitter/IGenARM64.cpp` / `.h` — continue A22 unlock; needed for the env-gated tracer emit in call_r64.
- `goalc/compiler/IR.cpp` — continue A22 unlock.
- `game/kernel/asm_funcs_arm64.s` — continue A22 unlock; **may** fix the broken `_arg_call_arm64` as hygiene (will not affect 216 ceiling but is cleanup).
- `build-arm64-android/asm_funcs_arm64_gnu.s` — generated mirror.
- **NEW:** `goalc/compiler/Val.cpp` / `.h` — for stack-form / fn-pointer flow audit + potential fix.
- **NEW:** `goalc/compiler/compilation/Type.cpp` — for fn-ptr-vs-stack-ptr type rule audit + potential fix.
- `game/linux-arm64/linux_arm64_main.cpp` — extend SIGILL handler to decode UDF tag (`OG_REG_BYTE_DUMP` env-gate must persist).
- `game/kernel/common/klink.cpp` — extend if needed to expose link-block symbol lookup (`OG_KLINK_IMM19_TRACE` env-gate must persist).
- `goalc/regalloc/Allocator_v2.cpp` — refined tracer if needed (`OG_REGALLOC_TRACE` env-gate must persist).
- `game/kernel/jak1/kscheme.cpp` — refined tracer if needed (`OG_CALLGOAL_TRACE` env-gate must persist).
- `.autoport/reports/A23-*`.
- `.autoport/tests/emitter/`.

**STILL LOCKED:**

- `goalc/emitter/IGenX86_64.cpp` / `.h` — x86 oracle, NEVER edit.
- `goalc/emitter/ObjectGenerator.cpp` / `.h`.
- `goalc/compiler/CodeGenerator.cpp` / `.h`.
- `goalc/compiler/Compiler.cpp`.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp` — shared regalloc, A22 cleared.
- `common/type_system/Type.cpp` / `.h` — LOWER-level type system; compilation/Type.cpp is the type-CHECKING layer; common/type_system/Type.cpp is the type-REPRESENTATION layer. Only the checking layer is unlocked.
- `game/kernel/common/kscheme.cpp` — shared (jak1/kscheme.cpp is unlocked).
- `game/kernel/common/kmachine.cpp`.
- `game/system/IOP_Kernel.cpp` / `.h`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/*`.
- `.autoport/validators/*` — NEVER edit.
- `.autoport/lib/*` — NEVER edit.
- `.autoport/prompts/phase-*-*.md` except `phase-A23-*`.
- `.autoport/supervisor.sh`, `.autoport/orchestrator.py`.

## Anti-cheat invariants

- **x86 CGOs MUST be byte-identical to A2 baseline.** Hard regression check. Val.cpp + compilation/Type.cpp are SHARED code paths — any edit must not change x86 output.
- **A18 trap body** `std::_Exit(13)` in klink.cpp.
- **A19 X12 fix** `kStpX12X23Push|0xA9BF5FEC` in IGenARM64.cpp.
- **A20 OG_OFFSET_TRACE** ≥4 sites in IR.cpp.
- **A21 4 diags** in their respective files.
- 0 `__attribute__((weak))` additions.
- 0 `abort()` / `std::abort()` additions.
- 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- 0 modifications to `.autoport/lib/*.sh|*.py` or `.autoport/validators/*.sh`.
- 0 `gk_recover_to_renderer` / `forced-recovery handoff` / `g_fault_recovery_armed`.

## Forbidden cheat patterns

### 1. Type.cpp typecheck relaxation

**Cheat fingerprint**: a Type.cpp edit that adds a special case allowing `(pointer T)` ↔ `(function ARGS RET)` casts silently.

**Why it's a cheat**: that would mask the H2 root cause. The bug is that a stack-pointer is FLOWING into a fn-ptr slot; the fix is either to stop the flow (Val.cpp lowering) or to catch the flow at type-check time and error out.

**Honest version**: add a typecheck that REJECTS the assignment, then re-run qemu. The arm64 build should fail at goalc-compile time with a clear error pointing at the GOAL source line. That tells us where the GOAL bug is. (Or, the same typecheck rejection would have rejected x86 too — but x86 boots — which means the flow doesn't happen on x86 OR x86 has a different lowering path. Either way, evidence advances.)

### 2. Val.cpp StackVarAddrVal disabling

**Cheat fingerprint**: a Val.cpp edit that prevents `StackVarAddrVal` from ever being created OR that converts every `StackVarAddrVal` to a no-op.

**Why it's a cheat**: stack-allocated values are a legitimate GOAL feature. Disabling them breaks every `(stack ...)` form in the code.

**Honest version**: only edit `StackVarAddrVal` to add a TYPE TAG that's checked at IR_FunctionCall::m_func reception. Or, ensure the regalloc cannot put a `StackVarAddrVal` result into a register flagged as "fn-pointer-candidate."

### 3. Wholesale call_r64 widening

**Cheat fingerprint** (carried forward from A22): widening call_r64 to save all X19..X28 without naming the source.

**Why it's a cheat**: discussed in A22's prompt; still applies in A23.

### 4. Removing OG_*_TRACE diag patches

**Cheat fingerprint**: removing OG_OFFSET_TRACE, OG_KLINK_IMM19_TRACE, OG_REG_BYTE_DUMP, OG_REGALLOC_TRACE, OG_CALLGOAL_TRACE.

**Why it's a cheat**: diag patches are the supervisor's regression check.

### 5. Validator script edits

**Cheat fingerprint**: any diff to `.autoport/validators/*.sh` or `.autoport/lib/*.sh|*.py`.

**Halt immediately**.

### 6. Tracer that doesn't actually detect stack-range

**Cheat fingerprint**: an `OG_BLR_TARGET_TRACE` emit that just prints every BLR target without filtering for stack-range, or that always returns "ok."

**Why it's a cheat**: the tracer must DETECT the specific bug condition. A no-op tracer that always passes is worthless.

**Honest version**: the tracer's CMP-against-heap-top must produce the UDF emit when the target is OUT of heap range. Verify by running qemu with the env var and confirming the UDF fires (vs. natural SIGILL).

### 7. Synthetic CGO baseline

**Cheat fingerprint**: writing an `A23-baseline-arm64-cgo-hashes.txt` that does NOT match the actual CGO file hashes.

**Why it's a cheat**: the baseline file is the supervisor's regression anchor for future phases. Faking it defeats the regression check.

**Honest version**: regenerate CGOs with the tracer-emit env var SET (`OG_BLR_TARGET_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh`), then `sha256sum out/jak1-arm64/iso/*.CGO > .autoport/reports/A23-baseline-arm64-cgo-hashes.txt`.

## Required deliverables

### Path A — Real fix landed

Qemu boot count ≥217 (real advance past A19 ceiling). Ship:

1. **A23-fix-summary.md** (≥250 lines): names the SPECIFIC Val.cpp / Type.cpp / GOAL source location of the bug, disasm before/after, qemu boot count advance, next CGO that's reached.
2. **A23-baseline-arm64-cgo-hashes.txt** — fresh sha256 of every `out/jak1-arm64/iso/*.CGO` (with OR without `OG_BLR_TARGET_TRACE_EMIT` — but pick ONE and document which).
3. Source-level fix in `goalc/compiler/Val.cpp` or `goalc/compiler/compilation/Type.cpp` (most likely) or `goalc/emitter/IGenARM64.cpp` / `IR.cpp` (less likely).
4. **A23-investigation-trace.md** (≥200 lines): the tracer emit + run + capture process; the symbol-table cross-reference; the audit walk.

### Path B — Honest next-blocker (fix surface outside A23 unlock)

If the audit identifies a file outside A23's unlock that needs editing, ship:

1. **A23-attempt-N-next-blocker.md** (≥250 lines): names the specific file + function + line range, the evidence, what A23 ruled out.
2. **A23-investigation-trace.md** (≥200 lines).
3. CGOs match A23 baseline OR A21 baseline (document which).

### Path C — Bug-located, source named (between B and C in quality)

If the runtime tracer fires and names the specific emit-PC + GOAL function but the fix isn't within A23's tooling reach:

1. **A23-bug-located-named-source.md** (≥250 lines): the specific emit-PC, the GOAL function name, the recommended fix (either GOAL source edit, or A24-unlock proposal).
2. **A23-investigation-trace.md** (≥200 lines).
3. Tracer emit landed (OG_BLR_TARGET_TRACE infrastructure in HEAD).
4. CGOs match A23 baseline (with tracer emit) or A21 baseline (without).
5. **This is the most likely successful exit if the tracer works.**

### Path D — No-source-located (lowest quality, like A22 Path C)

If even the tracer can't pinpoint the offending emit-site:

1. **A23-attempt-N-no-source-located.md** (≥250 lines): explain why the tracer failed (UDF didn't fire? Fired but emit_pc → symbol table lookup failed? Symbol table not maintained at that scope?).
2. **A23-investigation-trace.md** (≥200 lines).
3. Tracer emit landed (or proven to be incorrect — document either way).

## Validator gates (full enforcement in `phase-A23-arm64-blr-target-tracer.sh`)

1. Lock check vs A22 close anchor; DIFF=0 on locked files.
2. Anti-cheat: weak/abort/dodge/stubs/infra.
3. A18 trap `_Exit(13)`.
4. A19 X12 fix `kStpX12X23Push`.
5. A20 OG_OFFSET_TRACE ≥4 sites.
6. A21 4 diags present.
7. x86 CGOs byte-identical to A2 (HARD).
8. Required artifacts: ONE of {fix-summary, attempt-N-next-blocker, attempt-N-bug-located-named-source, attempt-N-no-source-located} + investigation-trace.md.
9. arm64 CGOs:
   - If fix-summary present: CGOs MUST differ from A21 baseline + A23-baseline file present + qemu boot ≥217.
   - If bug-located-named-source present: CGOs MAY match A21 baseline (no fix shipped) OR match A23-baseline (tracer emit landed); qemu boot ≥200.
   - Otherwise: CGOs MUST match A21 baseline + qemu boot ≥200.
10. Desktop x86 smoke reaches `link finish: logo`.
11. Path A/C: tracer infra grep — `OG_BLR_TARGET_TRACE` in IGenARM64.cpp AND in linux_arm64_main.cpp (UDF tag decoder).

## Max settings

- `max_turns: 1000` (A23 is more open-ended; investigation + emit + audit + decode all required).
- `max_retries: 5`.

## Cost expectation

- Tracer emit + run + decode + audit: $100-300 per attempt.
- 2-3 attempts typical: $200-700.
- Supervisor budget cap on this transition: $700.
