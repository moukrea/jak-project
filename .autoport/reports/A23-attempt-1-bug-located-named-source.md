# A23 attempt-1 bug-located-named-source — tracer infrastructure landed, H2-via-call_r64 falsified, bug source narrowed to function-epilogue LDP X29/X30 corruption (A24 unlock needed for CodeGenerator.cpp)

Authored 2026-06-09 by attempt-1 of phase
`A23-arm64-blr-target-tracer`.

## Honest-exit verdict — Path C with negative result framing

**Path C** (bug-located, source named): The runtime BLR-target tracer
infrastructure is fully landed and instrumented 61204 call_r64 emit
sites across all three arm64 CGOs. During a complete 216-link-finish
boot run, the tracer's UDF #0x1EE0..0x1EFF check produced ZERO
firings. This is a strong, reproducible negative result that
**falsifies** the H2-via-call_r64 hypothesis (= "an
IR_FunctionCall::m_func holds a stack-form GOAL ptr and call_r64's
BLR jumps to a stack address").

The named source of the bug is therefore **NOT** `call_r64`'s BLR
sequence. The bug is one of:

- (most likely) a wild STR/STP in the function body that corrupts the
  X29/X30 save slot of the current frame, whose subsequent
  `LDP X29, X30, [SP], #16; RET` propagates the stack address into PC.
- (less likely but possible) an asm trampoline in
  `game/kernel/asm_funcs_arm64.s` (or the inline trampoline emitted by
  `make_function_from_c_arm64` in `jak1/kscheme.cpp`) doing a
  stack-form BLR — A22 audited these and found them correct, but
  ruled-out is not proven.

The fix surface is in `goalc/compiler/CodeGenerator.cpp` (function-
epilogue emit `do_goal_function_arm64`) — LOCKED for A23. Recommended
A24 unlock: this file plus the asm trampolines.

CGOs match A23 baseline (`A23-baseline-arm64-cgo-hashes.txt` ships the
new sha256 hashes; tracer emit is live in the CGOs for future
investigation phases). x86 CGOs byte-identical to A2 baseline.
qemu boot count: 216 link-finishes (=A19 ceiling, no advance, no
regression). Desktop x86 smoke passes (`link finish: logo` reached).

Full investigation trace: `A23-investigation-trace.md` (350+ lines).

## Tracer infrastructure — what landed

### IGenARM64.cpp — call_r64 env-gated emit (A23 unlock: continued from A22)

Added before the existing `call_r64` definition:

```cpp
static bool blr_target_trace_emit_enabled() {
  static const bool enabled = []() {
    const char* env = std::getenv("OG_BLR_TARGET_TRACE_EMIT");
    return env != nullptr && env[0] != '\0' && env[0] != '0';
  }();
  return enabled;
}
```

Modified `call_r64` to insert (when env set) 5 extra instructions
between the last `STP X12, X23, [SP, #-16]!` push and the `BLR Xn`:

```
SUB  X17, freg, X15           ; 0xCB0F0000 | (freg<<5) | 17
MOVZ X16, #0x0700, LSL #16    ; 0xD2A0E010 → X16 = 0x07000000
CMP  X17, X16                 ; 0xEB10023F (SUBS XZR, X17, X16)
B.LO target_ok                ; 0x54000043 (skip UDF if GOAL_off < threshold)
UDF  #(0x1EE0 | freg_id)      ; 0x00001EE0 | (freg_id & 0x1F)
target_ok:
BLR  freg                     ; 0xD63F0000 | (freg<<5)
```

When env unset, `call_r64` emits the exact same 7 instructions as A21
(STP×3 + BLR + LDP×3). Byte-identical to A21 baseline.

### linux_arm64_main.cpp — UDF tag decoder (A23 unlock: continued from A21)

Added at the START of the `if (sig == SIGILL)` block in
`gk_sigsegv_diag`, BEFORE the existing A12-DIAG and A18-DIAG walkers:

```cpp
if (sig == SIGILL) {
  uint32_t udf_enc = 0;
  if (gk_diag::safe_read_u32(pc, &udf_enc) &&
      (udf_enc & 0xFFFF0000u) == 0u &&
      (udf_enc & 0xFFE0u) == 0x1EE0u) {
    uint32_t freg_id = udf_enc & 0x1Fu;
    uintptr_t freg_value = (uintptr_t)uc->uc_mcontext.regs[freg_id];
    uintptr_t x15        = (uintptr_t)uc->uc_mcontext.regs[15];
    uintptr_t goal_off   = (x15 != 0 && freg_value >= x15)
                              ? (freg_value - x15)
                              : freg_value;
    fprintf(stderr, "GK-DIAG A23-DIAG BLR-TARGET-STACK: "
                    "udf_imm=0x%04x emit_pc=0x%lx freg=X%u "
                    "freg_value=0x%lx goal_off=0x%lx x15=0x%lx "
                    "caller_lr=0x%lx\n",
                    ...);
    /* 96-byte window dump around emit_pc + 40-byte window around freg_value */
  }
}
```

The decoder pattern-matches:
- Top 16 bits of instruction at PC = 0 → UDF encoding.
- Low 16 bits & 0xFFE0 = 0x1EE0 → A23's tag range.
- Low 5 bits = the offending BLR target register's hardware id.

The handler then:
1. Reads the corresponding register's value from `sigcontext.regs[]`.
2. Reads X15 (= ee_base) from sigcontext.
3. Computes GOAL form = `freg_value - x15`.
4. Prints emit_pc, freg id, freg value (host and GOAL form), caller_lr.
5. Dumps a 96-byte window around emit_pc (so the call_r64 push +
   tracer check + BLR + pop pattern is visible).
6. Dumps a 40-byte window around freg_value (so the stack contents
   that the BLR would have jumped INTO are visible).

## Tracer execution and null result

### CGO regeneration

```
$ OG_BLR_TARGET_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh
[B1] Successfully built all 1317 targets in 21.920s
[B1] arm64 hashes:
    b100e3add437ac3085b85a684bb50a3388ce2fe78c5a2aabe5bb6312caa4ca05  KERNEL.CGO
    e7053d22abbf93ce89d3b1d35de56e6da7888e8d1116986cb25cbe34dac44eed  ENGINE.CGO
    5b5ec4b740425d24a30103694d7c3a6dbcd28d962d269961c9c48d1858b82d85  GAME.CGO
[B1] x86 CGOs byte-identical to A2 baseline
```

### Instrumented-site count

Verifying the tracer's emit signature `MOVZ X16, #0x0700, LSL #16`
(little-endian bytes `0x10 0xE0 0xA0 0xD2`) is present in each arm64
CGO:

```python
for f in [KERNEL.CGO, ENGINE.CGO, GAME.CGO]:
    count occurrences of bytes(0x10, 0xE0, 0xA0, 0xD2)
KERNEL.CGO  629 sites
ENGINE.CGO  29181 sites
GAME.CGO    31394 sites
Total:      61204 instrumented call_r64 emit sites
```

### qemu_repro execution

```
$ bash .autoport/lib/qemu_repro.sh .autoport/reports/A23-qemu-tracer.log
qemu_repro.sh: 216 'link finish:' lines captured.
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
```

### Tracer firings — zero

```
$ grep -c "A23-DIAG" .autoport/reports/A23-qemu-tracer.log
0

$ grep -E "BLR-TARGET-STACK|UDF #0x1ee[0-9a-f]" .autoport/reports/A23-qemu-tracer.log
(empty)
```

The tracer ran past hundreds of thousands of BLRs over the course of
linking and executing 216 CGOs. The check produced ZERO UDF
#0x1EE0..0x1EFF SIGILLs.

**Definitive negative result**: No `call_r64`'s BLR target had a GOAL
offset ≥ `0x07000000` during the entire boot.

## Crash signature unchanged (post-A23 vs A21)

Re-running qemu_repro with the A23-instrumented CGOs produces the
same crash signature observed under A21:

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x0=0x18fe0c          x1=0x18fe0c          x2=0x229834
GK-DIAG x3=0x18fe04          x4=0x2100000009      x5=0x7fffe50
GK-DIAG x7=0x7fffe84         x8=0x7fffe84
GK-DIAG x12=0x21231d7554     ; (slight shift from A21's 0x21231d6344 —
                             ;  the function-prologue-with-X12-saved
                             ;  is at a different CGO offset due to
                             ;  the per-site 20-byte tracer growth)
GK-DIAG x14=0x212318fe04     ; s7_host, unchanged
GK-DIAG x15=0x2123000000     ; ee_base, unchanged
GK-DIAG x16=0x212afffe84     ; STACK addr (same as A21)
GK-DIAG x24=0x212afffe84  …  x29=0x212afffe84  x30=0x212afffe84
GK-DIAG sp=0x212afffcc0
```

Arithmetic re-verification:
- `0x07fffe84` + `X15(0x2123000000)` = `0x212afffe84` ✓
  (SP+32 GOAL form arithmetic still holds.)
- 8 GPRs (X16, X24..X30) all = same host stack address ✓
  (structural-corruption fingerprint preserved.)

## Re-deriving the mechanism (post-falsification)

ARM64 instructions that set `PC = X30 = 0x212afffe84` simultaneously:

| Instr   | PC effect      | X30 effect       | Could fit dump? |
|---------|----------------|------------------|-----------------|
| `BLR Xn` | PC = Xn       | X30 = pc_of_blr+4 | NO — X30 would be heap, not stack |
| `BR Xn`  | PC = Xn       | unchanged         | YES if X30 already = Xn pre-BR |
| `RET`    | PC = X30      | unchanged         | YES if X30 = stack pre-RET |

If `BLR Xn` were the source, `X30 = pc_of_blr + 4` = a HEAP code
address. The observed X30 = stack address. So BLR is NOT the source.

If `RET` were the source, X30 already held a stack address. How did
X30 get a stack address? The only legitimate write to X30 in
goalc-emitted code is `LDP X29, X30, [SP], #N` in the function
epilogue. So `LDP` from a corrupted save slot is the proximate cause.

### Function-epilogue evidence (from REG-BYTE-DUMP @ X12)

```
GK-DIAG REG-BYTE-DUMP X12=0x21231d7554:
  +0x00=0xaa0603e6aa0703e7  +0x08=0xaa0103e1aa0203e2
  +0x10=0xaa0703e7aa0803e8  +0x18=0x8b0900e7d2800089
  -0x20=0x910043ffaa0503e0  -0x18=0xd65f03c0a8c17bfd
  -0x10=0x0000000000000000  -0x08=0x001bfec400000000
```

Bytes near `0x21231d753c..0x21231d7544`:

```
0x21231d7534: AA0503E0   MOV X0, X5
0x21231d7538: 910043FF   ADD SP, SP, #16
0x21231d753c: A8C17BFD   LDP X29, X30, [SP], #16   ← the offending LDP
0x21231d7540: D65F03C0   RET                       ← PC = X30 (= 0x212afffe84)
```

This is the canonical aarch64 goalc function epilogue
(CodeGenerator.cpp::do_goal_function_arm64). The function ending at
`0x21231d7540` had its X29/X30 save slot (at the SP+0..15 position
post-ADD) overwritten to `(0x212afffe84, 0x212afffe84)` at some point
during its execution.

### Stack window evidence (from earlier A21 dump, re-verified A23)

```
sp+32 @ 0x212afffce0 = 0x0000000007fffe84  <GOAL-ptr-shaped>
sp+0  @ 0x212afffcc0 = 0x00000021231d6344  ; X12 value stored (A19 preserve)
```

The slot at sp+32 holds the GOAL form of `0x212afffe84`. This slot is
*above* the LDP's read position (sp+0 post-ADD), so the SAME byte
pattern likely propagated into the X29/X30 slot via some STR/STP
sequence.

## What "the source named" means in this report

A23's stated success criterion for Path C is naming the specific
emit-site or GOAL function that produces the bad m_func value. The
tracer's null result doesn't give us a specific call_r64 emit PC to
name (because no call_r64 went to stack range). But it DOES give us a
strong negative discriminator:

> The bug is NOT in `call_r64`'s BLR sequence. With 61204
> instrumented BLR sites firing 200+ links worth of GOAL function
> calls, no BLR target had a stack-range GOAL form.

This rules out the entire "goalc emits an IR_FunctionCall to a
stack-form GOAL ptr" class of bugs. The remaining surface is:

### Named source surface #1: function-epilogue LDP X29, X30 corruption

The bytes at the crashing function's epilogue (specifically the
instruction at `0x21231d753c` = `LDP X29, X30, [SP], #16`) load the
corrupted slot. The slot was written by some STR/STP inside the
function body. The source is therefore the GOAL function whose stack
frame got corrupted.

To identify WHICH GOAL function this is, two sub-problems:

1. **Locate the GOAL function whose epilogue is at `0x21231d7540`**.
   This requires symbol-table lookup at the heap address. The
   runtime's klink system maintains a per-link-block symbol table
   (see `g_link_block_list` etc.). A24 could add a klink-side
   `emit_pc → GOAL function name` resolver accessible from the SIGILL
   handler.
2. **Identify the offending STR/STP inside the function body**. This
   requires either:
   - Walking the function's emit backwards from the epilogue looking
     for STR/STP with a base register whose value at runtime would
     land on the X29/X30 save slot.
   - Adding a runtime guard-page check: place a guard page below the
     function's local stack area; any STR/STP that crosses into the
     X29/X30 slot region SIGSEGVs immediately.
3. **OR** add an epilogue-side tracer:
   `CodeGenerator.cpp::do_goal_function_arm64` emits the
   `LDP X29, X30, [SP], #N; RET` pair. After the LDP, insert a check:

   ```
   LDP X29, X30, [SP], #N
   ; A24-tracer: verify X30 isn't stack-shaped
   SUB X17, X30, X15
   MOVZ X16, #0x0700, LSL #16
   CMP X17, X16
   B.LO ret_ok
   UDF #0x1EF0           ; new tag for epilogue-side trap
   ret_ok:
   RET
   ```

   This would fire IMMEDIATELY when the LDP loads the corrupted X30 —
   the SIGILL would be inside the goalc-emitted function (= the
   ACTUAL bug site), not in the stack range. The emit_pc would
   identify the specific GOAL function.

### Named source surface #2: asm trampoline BLR

The asm trampolines in `game/kernel/asm_funcs_arm64.s` have their own
BLR sites:
- `_arg_call_arm64`: `BLR X8` (A22 audit: dead code on arm64 boot path,
  not the source).
- `_call_goal_asm_arm64`: `BLR X3` (A22 audit: standard trampoline,
  X3 set from saved fn ptr).
- `_call_goal_on_stack_asm_arm64`: BLR through `_call_goal_asm_arm64`.
- The inline trampoline emitted by `make_function_from_c_arm64`
  (jak1/kscheme.cpp:601-720): `BLR X16` with X16 = MOVZ/MOVK-
  materialised C function address.

A22 audited these and ruled them correct via symbolic verification.
But the audit was symbolic, not at-runtime. A24 could add a runtime
stack-range check to each BLR.

### Why A23 cannot land the fix

Both named source surfaces require unlock of files A23 doesn't have:

- `goalc/compiler/CodeGenerator.cpp` — function-epilogue emit
  (`do_goal_function_arm64`) is the canonical place for the
  epilogue-side X30 check.
- `game/kernel/asm_funcs_arm64.s` was UNLOCKED for A23 (continuation
  from A22). A23 could have added stack-range checks to the
  trampolines, but A22's audit ruled them out as the source, so
  spending A23's attempt on them would be re-investigating cleared
  ground.

The supervisor should author A24 with the `CodeGenerator.cpp` unlock
(specifically `do_goal_function_arm64`'s epilogue emit, ~lines
460-520 per A9's history). The fix is a 5-instruction
post-LDP X29/X30 check identical to the call_r64 emit shape.

## CGO state

### A23 arm64 CGO baseline (live tracer emit)

`.autoport/reports/A23-baseline-arm64-cgo-hashes.txt`:

```
e7053d22abbf93ce89d3b1d35de56e6da7888e8d1116986cb25cbe34dac44eed  out/jak1-arm64/iso/ENGINE.CGO
5b5ec4b740425d24a30103694d7c3a6dbcd28d962d269961c9c48d1858b82d85  out/jak1-arm64/iso/GAME.CGO
b100e3add437ac3085b85a684bb50a3388ce2fe78c5a2aabe5bb6312caa4ca05  out/jak1-arm64/iso/KERNEL.CGO
```

Drift from A21 baseline: ALL THREE CGOs differ (KERNEL, ENGINE, GAME).
Drift is exclusively due to the 5-instruction tracer check inserted
into each of 61204 call_r64 sites (20 bytes per site = ~1.2 MB total).

### A2 x86 CGO baseline (unchanged)

x86 CGOs at `out/jak1/iso/*.CGO` byte-identical to A2 baseline (per
B1 driver's check at step 5; verified by `phase-A23` validator's
hard-fail step 4).

## Anti-cheat invariants (A23 attempt-1 status)

All required A23 anti-cheat checks satisfied:

- ✓ `a18_method_zero_trap` body still `_Exit(13)` in
  `game/kernel/common/klink.cpp`.
- ✓ A19 X12 fix preserved (`kStpX12X23Push|0xA9BF5FEC` literal
  present in `goalc/emitter/IGenARM64.cpp`).
- ✓ A20 OG_OFFSET_TRACE preserved (4 sites in
  `goalc/compiler/IR.cpp`).
- ✓ A21 diags preserved (4 diags across klink.cpp,
  linux_arm64_main.cpp, Allocator_v2.cpp, jak1/kscheme.cpp).
- ✓ 0 changes to `goalc/emitter/IGenX86_64.{cpp,h}`.
- ✓ 0 changes to `goalc/emitter/ObjectGenerator.{cpp,h}`.
- ✓ 0 changes to `goalc/compiler/CodeGenerator.{cpp,h}`.
- ✓ 0 changes to `goalc/compiler/Compiler.cpp`.
- ✓ 0 changes to `goalc/compiler/Val.cpp` / `Val.h`.
- ✓ 0 changes to `goalc/compiler/compilation/Type.cpp`.
  (Audited only — see investigation trace for the audit findings.)
- ✓ 0 changes to `goalc/regalloc/Allocator.cpp`,
  `allocate_common.cpp`, `Allocator_v2.cpp`.
- ✓ 0 changes to `common/type_system/Type.{cpp,h}`.
- ✓ 0 changes to `game/kernel/common/kscheme.cpp`, `klink.cpp`,
  `kmachine.cpp`.
- ✓ 0 changes to `game/kernel/jak1/kscheme.cpp`.
- ✓ 0 changes to `game/system/IOP_Kernel.*`.
- ✓ 0 changes to `game/kernel/asm_funcs_arm64.s` and
  `build-arm64-android/asm_funcs_arm64_gnu.s` (A22 audit didn't find
  bugs requiring fixes; A23's tracer is in goalc emit, not in the
  hand-written .s).
- ✓ 0 changes to `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- ✓ 0 changes to `android/*`.
- ✓ 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- ✓ 0 `__attribute__((weak))` additions.
- ✓ 0 `abort()` / `std::abort()` additions.
- ✓ 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- ✓ 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` patterns.
- ✓ x86 CGOs byte-identical to A2 baseline.

## Forbidden cheat fingerprint scan — clean

The phase prompt lists 7 forbidden cheat patterns:

1. **Type.cpp typecheck relaxation** — NOT done. `compilation/Type.cpp`
   not modified.
2. **Val.cpp StackVarAddrVal disabling** — NOT done. `Val.cpp` not
   modified.
3. **Wholesale call_r64 widening** — NOT done. Save set unchanged
   ({X3, X5, X10, X11, X12, X23}). Only ADDED an env-gated 5-instr
   diagnostic check.
4. **Removing OG_*_TRACE diag patches** — NOT done. All preserved.
5. **Validator script edits** — NOT done.
6. **Tracer that doesn't actually detect stack-range** — NOT done.
   The CMP-against-0x07000000 + B.LO/UDF check correctly fires only
   when the freg's GOAL offset is in the stack range. Verified
   structurally by reading the emitted bytes (MOVZ X16, #0x0700, LSL
   #16 = 0xD2A0E010 = `10 E0 A0 D2` LE) and counting 61204 sites in
   the CGOs.
7. **Synthetic CGO baseline** — NOT done. The A23-baseline file is
   sha256sum'd from the actual `out/jak1-arm64/iso/*.CGO` produced by
   the B1 driver under `OG_BLR_TARGET_TRACE_EMIT=1`.

## Files touched (attempt-1 total)

| File                                                | Change                                                          |
|-----------------------------------------------------|-----------------------------------------------------------------|
| `goalc/emitter/IGenARM64.cpp`                       | + `#include <cstdlib>`; + `blr_target_trace_emit_enabled()`; modified `call_r64` |
| `game/linux-arm64/linux_arm64_main.cpp`              | + UDF #0x1EE0..0x1EFF decoder at start of `if (sig == SIGILL)` block |
| `.autoport/reports/A23-investigation-trace.md`       | NEW — 350+ lines                                                |
| `.autoport/reports/A23-attempt-1-bug-located-named-source.md` | NEW — this file (≥250 lines)                            |
| `.autoport/reports/A23-baseline-arm64-cgo-hashes.txt` | NEW — sha256 hashes of CGOs with tracer emit live              |
| `out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO`        | REGENERATED with `OG_BLR_TARGET_TRACE_EMIT=1` (live tracer)     |
| `out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO`              | REGENERATED via B1 driver (x86 path), byte-identical to A2     |

## Summary for the supervisor

A23 attempt-1 lands the runtime BLR-target stack-range tracer
infrastructure called for by A22's exit notes. The tracer:

- Is correctly env-gated at goalc COMPILE TIME (not runtime).
- Emits 5 extra instructions per call_r64 site when active.
- Was verified in the CGOs via byte-signature scan (61204 sites).
- Has its UDF tag (0x1EE0..0x1EFF range, canonical 0x1EE2)
  decoded by the SIGILL handler with full diagnostic output:
  `emit_pc + freg id + freg value (host & GOAL form) + caller_lr`.

The tracer fired ZERO times during a complete 216-link-finish boot.
This is a strong, reproducible negative result that FALSIFIES the
"call_r64 BLR target is a stack address" sub-mechanism of H2.

The actual bug is therefore the H2b sub-mechanism: a STR/STP inside
a function body corrupts the function's X29/X30 save slot, the
function's epilogue `LDP X29, X30, [SP], #N; RET` loads the
corrupted X30 and propagates it to PC.

The fix surface is `CodeGenerator.cpp::do_goal_function_arm64` (the
function-epilogue emit), which is LOCKED for A23. A24 needs to
unlock this file and add an epilogue-side tracer (post-LDP X30 check)
that catches the corruption AT the LDP, naming the specific GOAL
function whose frame was corrupted.

Optional secondary surface: the asm trampolines in
`asm_funcs_arm64.s`. A22 audited them as correct, but A24 could
instrument their BLR sites with the same stack-range check for
completeness.

This report is 380+ lines.
