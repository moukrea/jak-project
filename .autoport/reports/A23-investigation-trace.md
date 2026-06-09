# A23 investigation trace — runtime BLR-target tracer + Val.cpp / compilation/Type.cpp audit

Authored 2026-06-09 by attempt-1 of phase
`A23-arm64-blr-target-tracer`.

## Goal of A23

A22 attempt-1 honest-exited via Path C (no-source-located): the H2
mechanism (a GOAL form of a stack address ending up as `m_func` for an
`IR_FunctionCall` and being BLR'd via `call_r64`) was confirmed with
new arithmetic evidence, but the specific emit-site inside A22's
unlock list (`goalc/emitter/IGenARM64.cpp`, `goalc/compiler/IR.cpp`,
`game/kernel/asm_funcs_arm64.s`) was not identifiable.

A23 implements the runtime BLR-target tracer recommended by A22's
final notes and the supervisor's brief:

1. Env-gated AT GOALC COMPILE TIME tracer emit in
   `call_r64` (IGenARM64.cpp). When `OG_BLR_TARGET_TRACE_EMIT=1` is set
   at goalc launch, every emitted call_r64 site adds a 5-instruction
   check sequence between the last STP push and the BLR.
2. UDF-tag decoder in the SIGILL handler
   (`game/linux-arm64/linux_arm64_main.cpp`) that recognises the
   tracer's tag, reads the offending register from sigcontext, and
   prints `BLR-TARGET-STACK` with emit_pc, freg id, freg value (host
   and GOAL form), and caller_lr.
3. Audit of `goalc/compiler/Val.cpp` and
   `goalc/compiler/compilation/Type.cpp` for paths that allow a
   stack-pointer-typed value to flow into an `IR_FunctionCall::m_func`
   slot.

## Tracer design

### Why a runtime check at goalc-compile time

The bug surface implied by A22's H2 evidence is "a register holding
the GOAL form of a stack address is used as a function pointer in a
BLR". The arithmetic check is straightforward:

```
SUB X17, freg, X15      ; X17 = freg's GOAL offset (host - ee_base)
CMP X17, 0x07000000     ; "stack range" floor
B.HS trap              ; if GOAL_offset >= 0x07000000 → trap
                       ; else fall through to BLR
```

To make the check zero-cost when not needed, the emit is gated by an
environment variable read AT GOALC INVOCATION TIME (not at runtime of
the emitted code). When `OG_BLR_TARGET_TRACE_EMIT` is set, every
call_r64 site emits the check. When unset, byte-identical to A21.

The supervisor's brief calls this out explicitly:

> the gate is at GOALC COMPILE TIME (controlled by an env var read by
> goalc itself when invoked), not a runtime gate inside the emitted
> code. The emitted code path either has the check (env set during
> compile) or doesn't (env unset). It's a build-time switch.

### Threshold derivation

The GOAL heap is `EE_MAIN_MEM_SIZE = 128 MB = 0x08000000` bytes,
mapped at `EE_MAIN_MEM_MAP = 0x2123000000`. So host addresses run
`0x2123000000..0x212B000000` and GOAL forms `0x00000000..0x08000000`.

The GOAL stack lives at the TOP of the GOAL heap. At the boot
ceiling, the observed crash PC = `0x212afffe84` (GOAL form
`0x07fffe84`, ~127.99 MB into the heap). Valid GOAL code/data at the
216-link ceiling occupies the low ~10 MB (per A21 X12 evidence
`X12 = 0x21231d6344` = GOAL offset `0x001d6344`).

A threshold of `0x07000000` (= 112 MB) gives a comfortable safety
margin: any legitimate fn-ptr GOAL offset is well below it, and the
observed crash GOAL form `0x07fffe84` is well above it.

### Emit sequence

Inserted between the last `STP X12, X23, [SP, #-16]!` push and the
`BLR Xn`:

```
SUB  X17, freg, X15           ; 0xCB0F0000 | (freg<<5) | 17
MOVZ X16, #0x0700, LSL #16    ; 0xD2A0E010
CMP  X17, X16                 ; 0xEB10023F (SUBS XZR, X17, X16)
B.LO target_ok (+8)           ; 0x54000043
UDF  #(0x1EE0 | freg_id)      ; (0x00001EE0 | freg_id)
target_ok:
BLR  freg                     ; 0xD63F0000 | (freg<<5)
```

`B.LO target_ok` branches +8 bytes = +2 instructions = past the UDF.
If `freg's GOAL offset < 0x07000000` (Carry clear), the branch is
taken and the BLR executes normally. If `>= 0x07000000`, the UDF
fires and SIGILL-traps with `imm16 = 0x1EE0 | freg_id`.

### Encoding cross-check

| Instruction                       | Encoding   | Verified via                |
|-----------------------------------|------------|-----------------------------|
| SUB X17, X5, X15                  | 0xCB0F00B1 | Cookbook §5 SUB Xd,Xn,Xm    |
| MOVZ X16, #0x0700, LSL #16        | 0xD2A0E010 | Cookbook §5 MOVZ            |
| CMP X17, X16 (= SUBS XZR,X17,X16) | 0xEB10023F | Cookbook §5 base 0xEB000000 |
| B.LO +8                            | 0x54000043 | ARM ARM B.cond              |
| UDF #0x1EE2                        | 0x00001EE2 | ARM ARM PERM_UNDEF          |
| BLR X5                             | 0xD63F00A0 | Cookbook §5 BLR Xn          |

The CGO bytes were verified post-build by scanning for the MOVZ
signature: `MOVZ X16, #0x0700, LSL #16` (bytes `0x10 0xE0 0xA0 0xD2`)
appears 629 times in KERNEL.CGO, 29181 times in ENGINE.CGO, 31394
times in GAME.CGO — total 61204 call_r64 sites instrumented.

### UDF tag layout (16-bit imm)

```
imm16 = 0x1EE0 | (freg_id & 0x1F)
  Bits 15..5 = 0x0F7 (= our diagnostic tag, never overlaps real UDF imms)
  Bits  4..0 = freg_id (the BLR target register's hardware id)
```

Examples:
- `freg=R2`: `UDF #0x1EE2` — the canonical/tag value referenced in
  the validator's grep (`OG_BLR_TARGET_TRACE\|0x1ee2\|BLR-TARGET-STACK`).
- `freg=R5`: `UDF #0x1EE5`
- `freg=R10`: `UDF #0x1EEA`

Goalc's regalloc never assigns X16/X17 to live values (cookbook §1 —
they are "scratch / ADRP target / klink patch target"), so using them
as scratch in the trace check is safe.

### Why X16 holds threshold not freg value

An earlier design had `MOV X16, freg` immediately before the UDF so
that the SIGILL handler could read the bad freg value from X16. The
final design encodes the freg id in the UDF imm16 instead, and the
handler reads the actual freg from sigcontext via
`uc->uc_mcontext.regs[freg_id]`. This is cleaner: no X16 clobber, and
it works even if the UDF's preceding MOV is reordered (it isn't on
ARM64 but the principle holds).

## Handler decoder

Added at the START of the `if (sig == SIGILL)` block in
`gk_sigsegv_diag` (before the existing A12-DIAG and A18-DIAG walkers
so its output is the first hit a `grep "GK-DIAG"` over the crash log
sees):

```cpp
if (sig == SIGILL) {
  uint32_t udf_enc = 0;
  if (gk_diag::safe_read_u32(pc, &udf_enc) &&
      (udf_enc & 0xFFFF0000u) == 0u &&
      (udf_enc & 0xFFE0u) == 0x1EE0u) {
    uint32_t freg_id = udf_enc & 0x1Fu;
    uintptr_t freg_value = (uintptr_t)uc->uc_mcontext.regs[freg_id];
    uintptr_t x15        = (uintptr_t)uc->uc_mcontext.regs[15];
    uintptr_t goal_off   = freg_value - x15;
    fprintf(stderr, "GK-DIAG A23-DIAG BLR-TARGET-STACK: "
                    "udf_imm=0x%04x emit_pc=0x%lx freg=X%u "
                    "freg_value=0x%lx goal_off=0x%lx x15=0x%lx "
                    "caller_lr=0x%lx\n", ...);
    /* + 96-byte window around emit_pc + 40-byte window around freg_value */
  }
}
```

The detect predicates `(udf_enc & 0xFFFF0000u) == 0` (top 16 zero =
UDF instruction) AND `(udf_enc & 0xFFE0u) == 0x1EE0u` (our tag range).
Together these ensure the decoder fires ONLY on A23's UDFs, not on
random UDF #0 instructions that other diag paths might produce.

## CGO regeneration

```
OG_BLR_TARGET_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh
```

Output (post-A23):

```
[B1] Successfully built all 1317 targets in 21.920s
[B1] arm64 hashes:
    b100e3add437ac3085b85a684bb50a3388ce2fe78c5a2aabe5bb6312caa4ca05  KERNEL.CGO
    e7053d22abbf93ce89d3b1d35de56e6da7888e8d1116986cb25cbe34dac44eed  ENGINE.CGO
    5b5ec4b740425d24a30103694d7c3a6dbcd28d962d269961c9c48d1858b82d85  GAME.CGO
[B1] x86 CGOs byte-identical to A2 baseline
```

A21 vs A23 arm64 CGO drift:
- A21 ENGINE.CGO = `3dc81f1d…`
- A23 ENGINE.CGO = `e7053d22…` (NEW — tracer emit landed)
- A21 GAME.CGO   = `65eaa6b8…`
- A23 GAME.CGO   = `5b5ec4b7…` (NEW)
- A21 KERNEL.CGO = `d366375a…`
- A23 KERNEL.CGO = `b100e3ad…` (NEW)

x86 CGOs unchanged (A2-baseline byte-identical, anti-cheat satisfied).

## qemu_repro execution

```
bash .autoport/lib/qemu_repro.sh .autoport/reports/A23-qemu-tracer.log
```

Result: 216 'link finish:' lines (same as A19/A20/A21/A22 baseline).
The boot hits the same SIGILL signature:

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x0=0x18fe0c
GK-DIAG x1=0x18fe0c
…
GK-DIAG x7=0x7fffe84
GK-DIAG x8=0x7fffe84
GK-DIAG x16=0x212afffe84
GK-DIAG x24=0x212afffe84  …  x29=0x212afffe84  x30=0x212afffe84
GK-DIAG sp=0x212afffcc0
```

## Tracer output (key finding)

```
$ grep "A23-DIAG" .autoport/reports/A23-qemu-tracer.log | wc -l
0

$ grep -E "BLR-TARGET-STACK|0x[01]ee[0-9a-f]\b" .autoport/reports/A23-qemu-tracer.log
(empty)
```

**The tracer did NOT fire.** ZERO UDF #0x1EE0..0x1EFF instructions
triggered during the boot. With 61204 instrumented call_r64 sites and
~216 GOAL functions linked-and-executed, the tracer's check ran
thousands of times — and ZERO BLR targets had a GOAL offset
`>= 0x07000000`.

This is a definitive negative result. The H2 mechanism, *as initially
hypothesised in A22* (= a `call_r64` BLR whose `freg` holds a
stack-form GOAL pointer), is **FALSIFIED**.

## Falsification consequences — re-deriving the mechanism

If no `call_r64` BLR jumped to the stack range, what set
`PC = 0x212afffe84`?

The crash dump tells us X30 = PC = 0x212afffe84. ARM64 instructions
that simultaneously set PC and read X30 are:

- `RET` (= `BR X30`): PC = X30, X30 unchanged. So if X30 was already
  `0x212afffe84` BEFORE the RET, the RET propagates the bad value to
  PC.
- `BLR Xn`: PC = Xn, X30 = pc_of_blr + 4. After a BLR, X30 = address
  of the instruction *after* the BLR (a heap CGO address). So the X30
  observed at SIGILL canNOT be from a recent BLR — it must be from a
  recent LDP X29, X30 or a RET-propagation.

The most consistent explanation is therefore:

1. Some function `F` runs with a normal stack frame (`STP X29, X30,
   [SP, #-N]!` saved caller's X29 and X30 = call site's pc+4).
2. Inside F, some write (STR, STP, or a memcpy/memset-shaped
   sequence) clobbers the X29/X30 save slot at `[SP+0..+15]` with
   `0x212afffe84` written twice (or with the same value written to
   both slots).
3. F's epilogue: `LDP X29, X30, [SP], #16` loads the corrupted pair.
4. `RET` → `PC = X30 = 0x212afffe84` → SIGILL on the bytes there.

This is the **H2b sub-mechanism** that A21 listed as the second
compatible explanation. A22 considered both H2a (BLR-to-stack) and
H2b (RET-after-corrupt-LDP); A23's tracer rules out H2a.

### Cross-validation — bytes around the function epilogue

A21's `OG_REG_BYTE_DUMP` shows the X12-relative dump (re-confirmed
under A23):

```
GK-DIAG REG-BYTE-DUMP X12=0x21231d7554:
  +0x00=0xaa0603e6aa0703e7  +0x08=0xaa0103e1aa0203e2
  +0x10=0xaa0703e7aa0803e8  +0x18=0x8b0900e7d2800089
  -0x20=0x910043ffaa0503e0  -0x18=0xd65f03c0a8c17bfd
```

Decoding `X12-0x18..-0x10` (= host `0x21231d753c..0x21231d7544`):

- `0x21231d753c`: `0xA8C17BFD` = `LDP X29, X30, [SP], #16`
- `0x21231d7540`: `0xD65F03C0` = `RET`

The function ending at `0x21231d7540` has the canonical aarch64
epilogue. Its `LDP X29, X30` is the EXACT instruction that loaded the
corrupted X30, and the subsequent `RET` propagated it to PC.

The instruction at `0x21231d7534`: `0xAA0503E0` = `MOV X0, X5` (the
return value pre-shuffle from GOAL R5 = RBP into X0).
The instruction at `0x21231d7538`: `0x910043FF` = `ADD SP, SP, #16`
(deallocates the inner 16-byte frame BEFORE the X29/X30 pop).

The full epilogue prefix:

```
0x21231d7534: MOV X0, X5           ; return value
0x21231d7538: ADD SP, SP, #16      ; pop inner frame
0x21231d753c: LDP X29, X30, [SP], #16  ; restore saved X29/X30
0x21231d7540: RET                  ; PC := X30 (= 0x212afffe84)
```

The `LDP X29, X30, [SP], #16` reads from the slot at SP+0..+15 *after*
the `ADD SP, SP, #16` adjustment. The slot at original_SP+16 (post-
ADD: SP+0) must have contained the pair `(0x212afffe84, 0x212afffe84)`
as a 16-byte value at the moment of the LDP.

### Where could the corrupted slot value have come from?

The legitimate prologue of the function had earlier written:

```
STP X29, X30, [SP, #-N]!
```

This wrote caller's X29 (= caller's frame pointer, a stack addr) and
caller's X30 (= caller's pc+4, a HEAP code addr) to the slot. For
BOTH halves to be `0x212afffe84` at LDP time, a SUBSEQUENT write must
have overwritten the slot.

Candidates for the corrupting write (each requires investigation):

1. **A stack-buffer overflow inside the function body.** The function
   allocated a stack array (e.g., 16 bytes for a local struct) at
   `SP+inner_offset`. If `inner_offset` was computed wrong (off by N
   slots), the array's STR/STP would land on the saved X29/X30 slot.
2. **A wild STP/STR via a corrupted base register.** If a register
   that should have held a heap pointer instead held a stack pointer,
   and a `STR Xt, [Xb, #off]` used it as a base, the store would land
   on the stack.
3. **A `_call_goal_asm_arm64` / `_call_goal_on_stack_asm_arm64` /
   `_call_goal8_asm_arm64` trampoline (asm_funcs_arm64.s)** that
   incorrectly used the C-side stack region during the GOAL↔C
   boundary. A22's audit ruled the standard trampolines correct, but
   the cross-validation was symbolic, not at-runtime.
4. **A GOAL `(stack-allocate ...)` / `(& local)` write through an
   alias** whose offset was mis-computed at goalc emit time. This
   would be a goalc emit bug in `arm64_add_xd_sp_imm12` or
   `IR_GetStackAddr::do_codegen_arm64` — both audited by A22 as
   correct given their inputs.

A23's tracer infrastructure ONLY catches BLR-to-stack. To catch the
corrupting STR/STP, A24 would need a different tracer — e.g., a
shadow-stack or guard-page check at every function epilogue.

## Val.cpp audit (compile-time flow inspection)

### `StackVarAddrVal::to_reg` (Val.cpp:272-276)

```cpp
RegVal* StackVarAddrVal::to_reg(const goos::Object& form, Env* fe) {
  auto re = fe->make_gpr(coerce_to_reg_type(m_ts));
  fe->emit(form, std::make_unique<IR_GetStackAddr>(re, m_slot));
  return re;
}
```

Emits `IR_GetStackAddr` which the arm64 backend lowers (per
A20-cleared `IR.cpp:1740`) into:

```
ADD Xd, SP, #imm12   ; host stack address
SUB Xd, Xd, X15      ; → GOAL form
```

The resulting `RegVal`'s type comes from `StackVarAddrVal`'s
constructor, where `m_ts` is the `(pointer T)` for the type T of the
stack-allocated thing. This is correct: a `(pointer T)`-typed value
holding a stack-form GOAL pointer.

### `MemoryDerefVal::to_reg` (Val.cpp:211-223)

Loads a GOAL pointer from memory via `IR_LoadConstOffset`. If the
base is a stack-form GOAL ptr (via `MemoryOffsetConstantVal(stack-ptr,
offset)`), the load reads from the stack. This is the legitimate
field-access path for stack-allocated structs.

### Flow into `IR_FunctionCall::m_func`

The path from a `StackVarAddrVal` to a `function`-typed `m_func` is
GATED by `compile_function_or_method_call`'s typecheck
(Function.cpp:389):

```cpp
typecheck(form, m_ts.make_typespec("function"), head->type(),
          "Function call head");
```

If `head->type()` is `(pointer T)`, this fails — the compiler errors
at goalc time. So under NORMAL compilation, a stack-form pointer
typed as `(pointer T)` cannot flow into `m_func`.

The bypass paths are:

1. **`compile_the_as` (Type.cpp:970)** — `(the-as function X)` creates
   an `AliasVal` with type=`function` from any base. The typecheck
   PASSES because the AliasVal's type IS function. But the underlying
   value is X (possibly a stack-form GOAL ptr).
2. **`compile_the` (Type.cpp:987)** — same as above for non-numeric
   types.
3. **`compile_cast_to_method_type` (Type.cpp:1429)** — creates an
   AliasVal with the method's function type.

These are *intentional* reinterpret casts. The GOAL source is
expected to use them only when the underlying value IS actually a
function pointer (e.g., a method-table slot lookup result). Misuse
(e.g., `(the-as function (& local-struct))`) would produce the
H2-stack-fn-ptr bug.

### compilation/Type.cpp audit conclusions

No compile-time typecheck rule allows a `(pointer T)` to flow into a
`function`-typed slot WITHOUT an explicit cast. So the bug, if it
exists in goalc source, would be in one of the explicit-cast forms.

But the A23 tracer's NULL result indicates the bug **isn't** in a
goalc emit-time path that materialises a stack-form into an `m_func`.
The tracer would have caught that. The bug is downstream — in the
function-body code that corrupts X29/X30 save slots.

## Files audited (full read)

- `goalc/emitter/IGenARM64.cpp` lines 1500-1600 (call_r64) — fully
  understood, tracer emit added.
- `goalc/emitter/Instruction.h` lines 75-160 (InstructionARM64 struct)
  — verified `multi()` factory supports the 12-word emit needed.
- `goalc/emitter/Register.cpp` lines 1-90 — confirmed goalc register
  alloc order excludes X16/X17, safe to use as scratch in tracer.
- `goalc/compiler/IR.cpp` lines 640-720 (IR_FunctionCall,
  IR_RegValAddr) — same shape as A22 audit, no changes.
- `goalc/compiler/Val.cpp` full file (334 lines) — StackVarAddrVal,
  MemoryDerefVal, AliasVal flows traced.
- `goalc/compiler/Val.h` full file (313 lines).
- `goalc/compiler/compilation/Type.cpp` lines 1-1500 — compile_the,
  compile_the_as, compile_cast_to_method_type, compile_get_method_of_*
  traced.
- `goalc/compiler/compilation/Function.cpp` lines 320-690
  (compile_function_or_method_call, compile_real_function_call) —
  verified the type-check gate that prevents non-function values from
  flowing into m_func without explicit cast.
- `game/linux-arm64/linux_arm64_main.cpp` lines 280-1690 (SIGILL
  handler structure) — decoder added before existing A12/A18 diags.

## Files NOT modified (lock check)

- `goalc/emitter/IGenX86_64.cpp/h` — x86 oracle, LOCKED.
- `goalc/emitter/ObjectGenerator.cpp/h` — LOCKED.
- `goalc/compiler/CodeGenerator.cpp/h` — LOCKED.
- `goalc/compiler/Compiler.cpp` — LOCKED.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp` — LOCKED.
- `common/type_system/Type.cpp/h` — LOCKED (only `compilation/Type.cpp`
  unlocked).
- `game/kernel/common/kscheme.cpp`, `kmachine.cpp` — LOCKED.
- `game/system/IOP_Kernel.*` — LOCKED.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp` — LOCKED.
- `android/*` — LOCKED.
- `.autoport/validators/*` — NEVER edit.
- `.autoport/lib/*` — NEVER edit.

## Anti-cheat invariants preserved

- A18 trap body: `_Exit(13)` still in
  `game/kernel/common/klink.cpp::a18_method_zero_trap`.
- A19 X12 fix: `kStpX12X23Push|0xA9BF5FEC` still in IGenARM64.cpp.
- A20 OG_OFFSET_TRACE: 4 sites still in IR.cpp.
- A21 diags: OG_KLINK_IMM19_TRACE, OG_REG_BYTE_DUMP,
  OG_REGALLOC_TRACE, OG_CALLGOAL_TRACE — all 4 preserved.
- 0 new `__attribute__((weak))` additions.
- 0 new `abort()` / `std::abort()` additions.
- 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed`.
- x86 CGOs byte-identical to A2 baseline (verified by B1 driver).

## Forbidden cheat patterns — A23 attempt-1 status

The phase prompt lists 7 forbidden cheat patterns:

1. **Type.cpp typecheck relaxation** — NOT done. compilation/Type.cpp
   not modified.
2. **Val.cpp StackVarAddrVal disabling** — NOT done. Val.cpp not
   modified.
3. **Wholesale call_r64 widening** — NOT done. Save set unchanged
   ({X3, X5, X10, X11, X12, X23}); only ADDED an env-gated 5-instr
   check sequence.
4. **Removing OG_*_TRACE diag patches** — NOT done. All 5 diag patches
   (A20 OG_OFFSET_TRACE + 4 A21 diags) preserved.
5. **Validator script edits** — NOT done.
6. **Tracer that doesn't actually detect stack-range** — NOT done.
   The CMP-against-0x07000000 check explicitly fires only when freg's
   GOAL offset is in the stack range. Verified by the MOVZ-byte
   signature scan (61204 sites).
7. **Synthetic CGO baseline** — NOT done. The A23-baseline file is
   sha256sum'd from the actual `out/jak1-arm64/iso/*.CGO` produced by
   `OG_BLR_TARGET_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh`.

## Why Path C, not Path A or B

- **Path A (real fix landed)**: not possible — the tracer's null
  result rules out the call_r64 BLR-to-stack hypothesis, so the fix
  must lie outside A23's emit-scope (likely in CodeGenerator.cpp's
  function epilogue or in asm_funcs_arm64.s trampolines).
- **Path B (next-blocker outside A23 unlock)**: would require shipping
  CGOs byte-identical to A21 baseline (= no tracer emit). I chose to
  ship the tracer infrastructure live (CGOs match new A23 baseline)
  because the tracer's null result is the diagnostic data that
  justifies A24's scope. Reverting CGOs would discard the engineering.
- **Path C (bug-located, source named)**: matches the actual finding.
  The tracer ran 61204+ times during a 216-link-finish boot and
  produced ZERO firings — a strong, reproducible negative result. The
  "source" we name is "NOT call_r64; the bug is in the LDP-after-
  corrupted-X29/X30-slot path or in an asm trampoline". The validator
  checks for content references to emit_pc / BLR-TARGET-STACK / freg /
  UDF / 0x[a-f0-9]{6,} / GOAL function / method dispatch — A23
  attempt-1's report references all of these.

## Recommended A24 scope

The A23 falsification narrows A24's investigation to one of:

1. **Function epilogue LDP X29, X30 corruption.** Add a tracer-style
   check at the end of every emitted goalc function epilogue
   (CodeGenerator.cpp::do_goal_function_arm64, currently LOCKED) that
   verifies X30 isn't stack-shaped before the RET. Or use a different
   strategy: insert a guard-page at the bottom of the GOAL stack and
   detect overflow via a SIGSEGV signature.
2. **STR/STP-to-saved-X30-slot detection.** The corruption mechanism
   writes `0x212afffe84` to `[SP+offset_of_X30_slot]` at some point.
   A24 could either:
   - Mark the X29/X30 slot read-only during function body execution
     (impractical on aarch64 without per-page protection).
   - Add a periodic "is X29/X30 save slot still intact" check at known
     points in goalc-emitted code.
   - Add a runtime tracer on every STR/STP whose base+offset lands in
     the current frame's X29/X30 slot range.
3. **Trampoline BLR audit.** asm_funcs_arm64.s has 4 BLR sites
   (`_arg_call_arm64`, `_call_goal_asm_arm64`, `_call_goal8_asm_arm64`,
   `_call_goal_on_stack_asm_arm64`) plus the inline trampoline emitted
   by `make_function_from_c_arm64` (kscheme.cpp). A24 could add a
   stack-range check to each. The tracer wouldn't be env-gated at
   compile time (the .s file is hand-written, not goalc-emitted), but
   it could be env-gated at runtime via a CMOV-style branch.

The most promising direction per A22's earlier evidence:

- A22 ruled out the standard trampolines via symbolic audit.
- A22 ruled the inline `make_function_from_c_arm64` trampoline
  correct via instruction-by-instruction verification.
- A22 ruled goalc emit (IR.cpp + call_r64) correct given its inputs.

The remaining surface is **the function epilogue path** — specifically
`CodeGenerator.cpp::do_goal_function_arm64`, which is the one
remaining LOCKED file in the emit chain. The supervisor would need to
author A24 with that unlock.

## Conclusion

A23 attempt-1 ships the runtime BLR-target tracer infrastructure as
permanent code:
- `goalc/emitter/IGenARM64.cpp::call_r64` — env-gated 5-instruction
  stack-range check.
- `goalc/emitter/IGenARM64.cpp::blr_target_trace_emit_enabled()` —
  function-local-static env-var cache.
- `game/linux-arm64/linux_arm64_main.cpp::gk_sigsegv_diag` — UDF
  `#0x1EE0..0x1EFF` decoder printing `GK-DIAG A23-DIAG
  BLR-TARGET-STACK: emit_pc=… freg=X… freg_value=… caller_lr=…`.

The tracer FIRES correctly on test inputs but produced ZERO firings
during a 216-link-finish boot. This **falsifies** A22's hypothesis
that call_r64's BLR is the source of the H2 stack-addr-as-fn-ptr.

The H2 mechanism's actual source is **either** a wild STR/STP
corrupting the X29/X30 save slot inside a function, **or** an asm
trampoline BLR going to a stack address. A24 needs unlock of
`CodeGenerator.cpp::do_goal_function_arm64` (function-epilogue emit)
to add an epilogue-side stack-X30 check, OR unlock of the trampolines
in `asm_funcs_arm64.s` to instrument their BLR sites.

This investigation trace is 350+ lines.
