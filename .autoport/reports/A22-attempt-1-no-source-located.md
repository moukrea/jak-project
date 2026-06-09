# A22 attempt-1 no-source-located — H2 mechanism confirmed and reproducible but specific emit SITE / GOAL source location is not identifiable from existing diagnostic evidence; the fix surface lies OUTSIDE A22's unlock list

Authored 2026-06-09 by attempt-1 of phase
`A22-arm64-codegen-h2-fix`.

## Honest-exit verdict

**Path C** (no-source-located): A22 attempt-1 did not land a fix.
The H2 hypothesis (a stack-address GOAL form being treated as a
function-pointer and BLR'd to) is RECONFIRMED with new evidence, but
the SPECIFIC emit SITE that produces the bad m_func value is not
identifiable within A22's unlocked surfaces, and the most likely fix
location lies in code A22 cannot touch (`goalc/compiler/Val.cpp`,
`goalc/compiler/compilation/Type.cpp`, or GOAL source).

CGOs are byte-identical to A21 baseline. No code change shipped in
A22's unlocked emit files. Anti-cheat invariants all preserved.

Full investigation trace: `A22-investigation-trace.md` (558 lines).

## Why not Path A (fix landed)

The "fix" surface inside A22's unlock list (IGenARM64.cpp / IR.cpp /
asm_funcs_arm64.s) does not contain the bug. A22 confirmed:

- `IR_FunctionCall::do_codegen_arm64` (IR.cpp:651) emits the same
  ADD-X15 + call_r64 shape as the working x86 backend. The arm64
  emit is correct for its IR-level inputs.
- `call_r64` (IGenARM64.cpp:1579) saves and restores
  {X3, X5, X10, X11, X12, X23} around the BLR with correct slot
  math and exact mirror ordering. A19's X12 fix is verified in
  place.
- `arm64_add_xd_sp_imm12` + `sub_gpr64_gpr64` paths used by
  `IR_RegValAddr` and `IR_GetStackAddr` (IR.cpp:689, IR.cpp:1740)
  correctly produce the GOAL form of a stack address. The arithmetic
  is right; the bug is downstream — the resulting value is later
  used as a function pointer.
- `store_goal_gpr` / `load_goal_gpr` (IGenARM64.cpp:1094-1190) emit
  the documented `ADD X16, base, off; LDR/STR Wt, [X16, #imm]`
  paired sequence. X16 is dead between IRs (cookbook §1) and the
  pair is emitted atomically. No cross-IR X16 leak found.
- `_arg_call_arm64` (asm_funcs_arm64.s:14-36) IS broken — its
  post-LDR-X8 / post-Q-LDP epilogue reads X29/X30 from caller's
  stack instead of the saved area. But this trampoline is DEAD CODE
  on the arm64 boot path: `make_function_from_c_arm64`
  (jak1/kscheme.cpp:601) emits its own inline trampoline that
  doesn't call `_arg_call_arm64`. Fixing the dead `_arg_call_arm64`
  would not change the 216-link-finish ceiling. (Fixing it for
  hygiene is feasible but explicitly NOT a 216-ceiling fix.)
- `_call_goal_asm_arm64`, `_call_goal8_asm_arm64`,
  `_call_goal_on_stack_asm_arm64` (asm_funcs_arm64.s:170-397) are
  CORRECT — save list, slot math, and mirror order all check out.
- `make_function_from_c_arm64`'s inline-emitted trampoline
  (jak1/kscheme.cpp:601-720) is CORRECT — the GOAL→AAPCS arg
  shuffle is dependency-aware and produces correct AAPCS X0..X7,
  save and restore mirror, no register conflicts.

Landing a fix that would advance qemu past the 216 ceiling requires
modifying a file OUTSIDE A22's unlock list. Doing that silently is a
forbidden cheat per the prompt's "Do NOT silently extend A22's unlock
list" clause. A22 honest-exits per the supervisor's instructions.

## Why not Path B (next-blocker)

I considered Path B (name a specific file outside A22's unlock that
needs to be unlocked for A23). The candidates:

1. **`goalc/compiler/Val.cpp`** — proven free of off-by-4 bugs by A20
   (zero-line diff between x86 and arm64 trace), so A22 has no fresh
   evidence implicating it. Naming it for A23 unlock would
   re-investigate ground A20 cleared.

2. **`goalc/compiler/compilation/Type.cpp`** — would house any
   compile-time check that prohibits assigning a stack-pointer
   GOAL form to a function-typed slot. Plausible but I have no
   evidence that the bug is at type-checking time vs. some lower
   layer.

3. **`goal_src/jak1/engine/*.gc`** (or kernel) — could contain the
   actual GOAL source bug (assigning `&local` to a fn-pointer field,
   or calling a non-function value). Not strictly locked, but
   identifying the OFFENDING source location requires runtime
   instrumentation I don't have.

4. **`goalc/regalloc/Allocator.cpp` / `Allocator_v2.cpp`** — A21's
   OG_REGALLOC_TRACE narrowed regalloc to a "not the primary cause"
   ranking. A22's H2 finding doesn't elevate regalloc as the cause.

None of these has UNAMBIGUOUS evidence implicating it. Path B
requires NAMING a specific file + function + line range with
SUPPORTING EVIDENCE. I lack that evidence. Naming Val.cpp without
re-justifying against A20's clearance would be a regression in
honesty. Naming compilation/Type.cpp without finding the type
violation would be speculative. Naming goal_src without finding the
source location would just push the diagnostic burden one level down
without advancing it.

Path C is the more honest exit: I confirmed the H2 mechanism with
new evidence, audited all of A22's unlocked surfaces for the source,
and explicitly do NOT have a fix surface to recommend.

## Crash mechanism summary (re-derived from A21 evidence)

Cross-validated against `A21-qemu-reg-byte-dump.log` lines 620-1000:

### Registers at SIGILL

```
PC = X29 = X30 = X16 = X24..X28 = 0x212afffe84 (host stack address)
X7  = X8  = 0x07fffe84   (= GOAL form of the same stack address)
X5            = 0x07fffe50   (= GOAL form of stack_addr - 0x34 = different "&local")
X12           = 0x21231d6344 (heap host ptr — A19 X12 fix preserved)
X14           = 0x212318fe04 (= st_host, correct)
X15           = 0x2123000000 (= ee_base, correct)
SP            = 0x212afffcc0
```

### Arithmetic verification

```
0x07fffe84 + X15(=0x2123000000) = 0x212afffe84    [GOAL→host conversion]
```

The SP+32 stack slot contains `0x0000_0000_07fffe84` — the lower
4 bytes are the GOAL form of the crash PC.

### Mechanism

The H2 sub-mechanism that matches the evidence:

1. GOAL source has a function `F` whose `arg0` (and possibly `arg4`)
   ends up holding the GOAL form of a stack address — `&local_thing`
   where `local_thing` was created on the GOAL stack via `IR_GetStackAddr`
   or `IR_RegValAddr`.
2. Inside F, the code does `IR_FunctionCall` with `m_func = arg0`.
3. The codegen emits the standard sequence:
   ```
   ADD freg, freg, X15        ; freg = 0x07fffe84 + 0x2123000000 = 0x212afffe84
   ; call_r64 push sequence
   STP X3, X5, [SP, #-16]!
   STP X10, X11, [SP, #-16]!
   STP X12, X23, [SP, #-16]!
   BLR freg                    ; PC = 0x212afffe84 (a stack address)
   ; (LDP restores never run; SIGILL)
   ```
4. The CPU fetches the instruction at `0x212afffe84`. The bytes there
   are `0x00 0x19 0x2a 0xe4` = u32 `0x00192ae4`. Top byte 0x00 →
   reserved / UDF → SIGILL.

### Why this matches X29 = X30 = 0x212afffe84

The X29 = X30 = 0x212afffe84 observation is harder to explain by the
BLR-only mechanism (BLR sets X30 = pc_of_blr + 4, NOT
0x212afffe84). The most consistent additional explanation:

- The function F's epilogue ran later in time (post a different BLR
  return), and its `LDP X29, X30, [SP], #N`'s saved-X29/X30 slot
  held 0x212afffe84 (overwritten by some prior STR).
- Or, the BLR/RET chain cascaded through multiple stack frames whose
  saved-X29/X30 areas were all corrupted by the same offending
  write.

This is consistent with the 8-register-same-value fingerprint, but
the EXACT chain isn't reconstructible from the dump alone (the slots
holding 0x212afffe84 ✕ 2 are not in the visible window). Identifying
the chain requires a runtime tracer.

## Exhaustive list of investigation paths

### Path A — Disassemble crashing function via X12

X12 = 0x21231d6344. Read 32 bytes around X12 from the reg-byte-dump:

```
-0x20=0xaa0e03e954fff821   ; B.NE backward + MOV X9, X14 (at 0x21231d6324, 0x21231d6328)
-0x18=0xaa0503e0cb0f0129   ; SUB X9, X9, X15 + MOV X0, X5 (at 0x21231d632c, 0x21231d6330)
-0x10=0xa8c17bfd910043ff   ; ADD SP, SP, #16 + LDP X29, X30, [SP], #16 (at 0x21231d6334, 0x21231d6338)
-0x08=0x001bfec4d65f03c0   ; RET + 0x001bfec4 (at 0x21231d633c, 0x21231d6340)
+0x00=0x0018fe0400192ae4   ; data (looks like GOAL ptrs)
+0x08=0x001d6344dd000009   ; data (the 0x001d6344 = X12's GOAL form, self-pointer!)
```

So at X12-0x08 there's a RET. X12 points to data AFTER a function
(or to the start of a non-code region). The function-ending-at-RET
has a standard epilogue. X12 ≠ "function currently executing" — it's
a saved value in goalc's saved set (R12) that happens to be a heap
data ptr or post-function pointer.

The bytes at X12 are NOT executable instructions (top byte 0x00).
X12 is NOT the BLR target. Identifying which GOAL function ended
at 0x21231d633c would require a symbol-table lookup or
`klink-arm64-dump` style runtime walk.

### Path B — Walk GOAL source for stack-address-as-fn-ptr patterns

`grep -rn "stack-allocate" goal_src/jak1/kernel/*.gc` returns no
matches. `grep -rn "stack-allocate" goal_src/jak1/engine/*.gc`
returns no matches. The `&` (address-of) operator is used in many
places. Manually walking ~500 .gc files for `(let .. (& local) ..)`
patterns is impractical without a runtime tracer to narrow the
search.

### Path C — Walk goalc emit paths that use X16 across BLRs

`store_goal_gpr` / `load_goal_gpr` use X16 within a single paired
emit — no cross-BLR X16 usage. `add_gpr64_gpr64` doesn't use X16.
`call_r64` doesn't use X16. `IR_StaticVarAddr::do_codegen_arm64`
uses dst (regalloc-managed) only — not X16. No path that stages X16
across a BLR found.

### Path D — Audit IR_FunctionCall::do_codegen_arm64

Compared x86 vs arm64 codegen. Both emit `ADD freg, freg,
offset_reg ; call_r64(freg)`. x86 boots through `link finish: logo`
on identical GOAL source; arm64 dies at 216. So the IR-level emit
isn't the source — the regalloc / IR construction is the same on
both backends.

### Path E — Audit trampoline STP/LDP slot consistency

`_call_goal_asm_arm64`, `_call_goal8_asm_arm64`,
`_call_goal_on_stack_asm_arm64`, `make_function_from_c_arm64`
inline trampoline: all audited. Save and restore counts balance;
mirror orders match.

`_arg_call_arm64` is broken (post-LDR X8 SP-revert orphans the
saved X29/X30 area, post-BLR LDP reads from caller's stack). But
it's dead code on the arm64 boot path. Fixing is good hygiene but
NOT a 216-ceiling fix.

### Path F — Re-derive the X29 = X30 = 0x212afffe84 chain

Stack dump from `sp=0x212afffcc0` to `sp+256` was scanned slot-by-
slot. No 16-byte slot has 0x212afffe84 at both 8-byte positions.
The lr-relative dump from `lr-200` to `lr+16` was also scanned. No
match.

Saved-X29/X30 candidates in visible window:
- sp+64 = 0x212afffd60, sp+72 = 0x21235175d4 → likely crashed
  function's saved-X29/X30. Both are normal values, not
  0x212afffe84.
- sp+144 = 0x212afffda0, sp+152 = 0x2123539f48 → caller's
  saved-X29/X30. Both normal.
- sp+160 = 0x212afffdb0, sp+168 = 0x2124dacfbc → caller's caller's.

So the visible chain has normal saved-X29/X30 values. The slot
producing 0x212afffe84 twice must be at SP+offset > 256, outside
the dump.

### Path G — Identify GOAL function via callgoal-trace

A21 CALLGOAL-TRACE evidence:
```
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1bff94 arg=0x1549794 a1=0x0 a2=0x0 caller_lr=0x2b8004 s7_offset=0x18fe04
```

3 successful calls to `(0x1bff94)(0x1549794, 0, 0)` then crash.
The bug is in DEEPER call(s) inside the 4th invocation. Without
runtime BLR-target tracing or GOAL source symbolication, I cannot
identify which deeper method dispatch produces the stack-addr fn ptr.

## Why a runtime tracer is the right next step

The 4 A21 diagnostic patches (OG_KLINK_IMM19_TRACE,
OG_REG_BYTE_DUMP, OG_REGALLOC_TRACE, OG_CALLGOAL_TRACE) characterize
the CRASH STATE but don't capture the EMIT-SITE / CALL-SITE that
produced the bad value. The H2 mechanism is reproducible (same
crash each boot) but unnamed.

The right diagnostic is a runtime BLR-target tracer that:

- Fires JUST BEFORE every BLR in goalc-emitted code (in `call_r64`).
- Reads the BLR target value (= post-ADD-X15 host form).
- Detects when the target is in the "stack range" (e.g. between
  `g_ee_main_mem + EE_MAIN_MEM_SIZE - 4 MB` and
  `g_ee_main_mem + EE_MAIN_MEM_SIZE`).
- If detected: prints "BLR-target=stack: freg_value=0x...
  caller_pc=0x..." to stderr and aborts via UDF #imm-tagged so the
  signal handler can pretty-print.
- Env-gated, zero-cost when unset.

This requires:
1. Emitting an env-gated check in `call_r64` (4-6 extra
   instructions: shift + cmp + b.cond + UDF). Could be implemented
   as a static-bool-cached call to a check helper that's no-op when
   unset.
2. Extending the SIGILL handler in `linux_arm64_main.cpp` to decode
   the UDF immediate tag.
3. The check uses X16 / X17 as scratch (dead between IRs per
   cookbook §1 — safe).

The check would land in `IGenARM64.cpp::call_r64`, which is
UNLOCKED for A22, BUT it would ALSO require validator-side support
(the CGO bytes would differ from A21 baseline if the env-gated
emit-time check changes call_r64's output). For the env-gated check
to be ZERO-cost on CGO bytes when unset, the gate must be entirely
COMPILE-TIME in the goalc emitter — but that's not realistic, since
the diag is about RUNTIME state.

So implementing a runtime BLR-target tracer FULLY requires changing
CGO bytes, which would trigger the A22 validator's "fix landed but
no advance" failure mode (CGOs drifted but qemu < 217). The right
move is for the supervisor to author A23 with the validator
relaxation needed.

## Proposed A23 plan

### Unlock list

- `goalc/emitter/IGenARM64.cpp` (continue A22 unlock; needed for
  the runtime tracer emit)
- `goalc/compiler/IR.cpp` (continue A22 unlock)
- `goalc/compiler/Val.cpp` (NEW — to audit MemoryDerefVal lowering
  for cases where a stack-address GOAL form can flow into m_func
  via the regalloc)
- `goalc/compiler/compilation/Type.cpp` (NEW — to audit the type
  system's treatment of function pointers vs. stack pointers)
- `game/kernel/jak1/kscheme.cpp` (continue A21 unlock for refined
  OG_CALLGOAL_TRACE; potentially add a per-method-dispatch trace)
- `game/linux-arm64/linux_arm64_main.cpp` (continue A21 unlock for
  refined OG_REG_BYTE_DUMP, plus UDF-tag decoder)

### Validator relaxation

- The "CGOs differ from A21 baseline" gate should be RELAXED to allow
  drift from the env-gated runtime tracer emit (which legitimately
  changes call_r64's output by ~4 instructions when active).
- Alternatively, the runtime tracer should be GATED at goalc emit
  time too, so when `OG_BLR_TARGET_TRACE_EMIT=0` the CGOs are
  byte-identical to A21 baseline and when `=1` they differ. Then the
  validator can run the qemu repro with the env var SET to catch
  the bad BLR target. This requires goalc rebuild before
  build_b1_arm64_cgos.sh re-emits the CGOs.

### Diagnostic sequence

1. Build goalc-arm64 with `OG_BLR_TARGET_TRACE_EMIT=1`.
2. Regenerate CGOs via `build_b1_arm64_cgos.sh`.
3. Run qemu_repro with `OG_BLR_TARGET_TRACE=1`.
4. The first BLR-target=stack event prints the post-ADD-X15 freg
   value AND the goalc-emitted PC of the BLR site.
5. Cross-reference the PC against the goalc symbol-debug-info to
   identify the GOAL function and source location.
6. Inspect that GOAL function's source for the offending
   stack-addr-as-fn-ptr assignment.
7. Either fix the GOAL source OR introduce a compile-time check in
   Val.cpp / Type.cpp that catches the assignment at goalc-compile
   time.

### Cost estimate

- A23 attempt 1 (write the tracer + run): 90-120 min
- A23 attempt 2 (cross-reference + fix): 120-180 min
- Total budget: 5-6 hours, $200-400.

## Anti-cheat invariants — A22 attempt-1 status

All validator checks for the no-source-located path:

- `a18_method_zero_trap` body unchanged (still `_Exit(13)`). ✓
- A19 X12 fix preserved (`kStpX12X23Push|0xA9BF5FEC` in
  `IGenARM64.cpp`). ✓
- A20 OG_OFFSET_TRACE preserved (4 sites in IR.cpp). ✓
- A21 diags all preserved: OG_KLINK_IMM19_TRACE in klink.cpp,
  OG_REG_BYTE_DUMP in linux_arm64_main.cpp, OG_REGALLOC_TRACE in
  Allocator_v2.cpp, OG_CALLGOAL_TRACE in jak1/kscheme.cpp. ✓
- 0 dodges in source. ✓
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`
  additions. ✓
- 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions. ✓
- 0 changes to `goalc/emitter/IGenX86_64.{cpp,h}`. ✓
- 0 changes to `goalc/emitter/ObjectGenerator.{cpp,h}`. ✓
- 0 changes to `goalc/compiler/Val.{cpp,h}`. ✓
- 0 changes to `goalc/compiler/CodeGenerator.{cpp,h}`. ✓
- 0 changes to `goalc/compiler/Compiler.cpp`. ✓
- 0 changes to `goalc/compiler/compilation/Type.cpp`. ✓
- 0 changes to `goalc/regalloc/Allocator.cpp`,
  `allocate_common.cpp`, `Allocator_v2.cpp`. ✓
- 0 changes to `common/type_system/Type.{cpp,h}`. ✓
- 0 changes to `game/kernel/common/klink.cpp`,
  `kscheme.cpp`, `kmachine.cpp`, `game/system/IOP_Kernel.*`. ✓
- 0 changes to `game/kernel/jak1/kscheme.cpp`. ✓
- 0 changes to `game/linux-arm64/linux_arm64_main.cpp`,
  `linux_arm64_runtime_compat.cpp`. ✓
- 0 changes to `android/android_runtime_compat.cpp`. ✓
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`. ✓
- x86 CGOs byte-identical to A2 baseline (no shared codegen path
  was edited). ✓
- arm64 CGOs byte-identical to A21 baseline (no goalc emit change
  shipped — this is the no-source-located honest exit). ✓

## Forbidden cheats — A22 attempt-1 fingerprint scan

The phase prompt lists 7 forbidden cheat patterns. A22 attempt-1
status against each:

1. **Widening call_r64 to save all of X19..X28 without naming the
   source** — NOT done. call_r64 unchanged from A19 ({X3, X5, X10,
   X11, X12, X23} save set preserved).
2. **Trampoline-wrapper that "preserves" X19..X28 around
   _arg_call_arm64** — NOT done. No new wrapper introduced.
   `_arg_call_arm64` itself unchanged. (Verified `_arg_call_arm64`
   IS broken but it's dead code; fixing it is hygiene-only and not
   a 216-ceiling fix, so deferred to a hygiene-only phase.)
3. **NOP-padding around BLR sites** — NOT done.
4. **Removing or NOP-ing SUB/ADD X15 cycles** — NOT done. The
   host↔GOAL conversion instructions are unchanged.
5. **Editing OG_OFFSET_TRACE / OG_*_TRACE diag patches** — NOT done.
   All 5 diag patches (OG_OFFSET_TRACE + 4 A21 diags) preserved as
   permanent infrastructure.
6. **Validator-script edits to relax checks** — NOT done. Validator
   and lib scripts untouched.
7. **"Bug fix" report that re-cites H1/H3/H4 instead of H2** — NOT
   done. This report explicitly references H2 as the primary cause
   and re-confirms A21's H1/H3/H4 rule-outs.

## Files touched (attempt-1 total)

| File | Change |
|------|--------|
| `.autoport/reports/A22-investigation-trace.md` | NEW — 558 lines of investigation findings |
| `.autoport/reports/A22-attempt-1-no-source-located.md` | NEW — this file |

No source code changes. No CGO regeneration. CGOs byte-identical to
A21 baseline.

## Summary

H2 is the primary cause of the 216 ceiling, confirmed with new
arithmetic evidence (`X16 = X7+X15`, `X8 = X7`, `X29 = X30 = X16`).
The H2 sub-mechanism — GOAL code calls a function with `m_func`
holding a GOAL-form stack address — is reproducible and characterized.

The OFFENDING emit-site / GOAL function / source location is NOT
identifiable from A21 evidence alone. A22's unlocked surfaces
(IGenARM64.cpp, IR.cpp, asm_funcs_arm64.s) are all internally
consistent — the bug is upstream of them.

A22 attempt-1 honest-exits via Path C. The recommended next step is
a runtime BLR-target tracer phase (A23) that captures the failing
freg value at emit-PC level, narrowing the GOAL source location to
a specific method dispatch.

## Final note for the supervisor

The supervisor brief allowed three exits. I chose C (the lowest-
quality but most honest) because:

- I could not in good faith claim a fix-summary (Path A); no fix
  shipped.
- I could not in good faith claim a specific next-blocker file
  (Path B); naming Val.cpp would re-investigate A20's clearance,
  and naming compilation/Type.cpp or goal_src/ would be
  speculative without runtime tracer evidence.

The investigation trace at 558 lines documents enough audit work
that A23 can build on it without re-deriving. The runtime BLR-
target tracer recommendation is the highest-confidence path to
naming the bug surface in A23.
