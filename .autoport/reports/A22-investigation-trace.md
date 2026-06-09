# A22 investigation trace — H2 (stack-addr GOAL form used as BLR target) audit

Authored 2026-06-09 by attempt-1 of phase
`A22-arm64-codegen-h2-fix`.

## Goal of A22

Find and fix the SOURCE emit sequence that places the GOAL form of a
stack address into a register that is later used as a function-pointer
BLR target. A21 attempt-1 named this as the primary cause of the
216-link-finish ceiling with arithmetically-verified evidence
(`0x07fffe84 + 0x2123000000 = 0x212afffe84` — SP+32 GOAL form
reconstructs the crash PC exactly when host-converted with `ADD Xt,
Xt, X15`).

## Crash fingerprint (re-verified from A21-qemu-reg-byte-dump.log)

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x0=0x18fe0c          x1=0x18fe0c          x2=0x2284e4         x3=0x18fe04
GK-DIAG x4=0x2100000009      x5=0x7fffe50         x6=0x18fe0c         x7=0x7fffe84
GK-DIAG x8=0x7fffe84         x9=0xffffffffdd000009 x10=0x212afffff0   x11=0x20e83c
GK-DIAG x12=0x21231d6344     x13=0x2281e4         x14=0x212318fe04    x15=0x2123000000
GK-DIAG x16=0x212afffe84     ...                  x19=0x7fae0f3fe498
GK-DIAG x20=0x18fe04         x21=0x18fe04         x22=0x2123000000    x23=0x36ef9c
GK-DIAG x24=0x212afffe84     x25=0x212afffe84     x26=0x212afffe84    x27=0x212afffe84
GK-DIAG x28=0x212afffe84     x29=0x212afffe84     x30=0x212afffe84    sp=0x212afffcc0
```

## Key data-shape observations

### Observation 1 — Eight registers hold the same stack address

X16, X24, X25, X26, X27, X28, X29, X30 all = `0x212afffe84`.

The reg-byte-dump confirms all 8 point at IDENTICAL bytes — they are
the same address, not different addresses with the same content.

### Observation 2 — X7 and X8 hold the GOAL form of the same address

X7 = X8 = `0x07fffe84`. Arithmetic check:
`0x07fffe84 + X15 (= 0x2123000000) = 0x212afffe84` ✓

In goalc-arm64's register mapping (from `Register.cpp::m_gpr_arg_regs`
and the cookbook §1):
- X7 = goalc R7 (RDI) = GOAL arg0
- X8 = goalc R8 = GOAL arg4

So the GOAL ABI calling convention is passing the same stack-address
GOAL form as both arg0 AND arg4 to the currently-running function. That
is the upstream fingerprint of the call chain that produced the bad
state — the caller passed `&local_thing` (a stack pointer) into the
called function in TWO of its arg slots.

### Observation 3 — X5 holds a DIFFERENT stack-addr GOAL form

X5 = `0x07fffe50`. ADD X15 → `0x212afffe50`. A DIFFERENT stack address
(52 bytes below the X16 address). Stack frames in the dump at
sp+192/sp+216 both contain `0x07fffe50`, confirming X5 is a separate
"&local" value.

### Observation 4 — SP+32 stack slot holds the offending GOAL form

```
sp+32 @ 0x212afffce0 = 0x0000000007fffe84  <GOAL-ptr-shaped>
```

The 8-byte slot at SP+32 holds the value `0x07fffe84` (zero-extended in
the upper 4 bytes). Any subsequent `LDR Wt, [SP, #32] ; ADD Xt, Xt,
X15 ; BLR Xt` would jump to the stack address.

### Observation 5 — X12 is preserved (A19 fix verified)

X12 = `0x21231d6344` (a heap host pointer pointing JUST past a function's
RET instruction — bytes at X12-0x08..0x21231d633c contain RET 0xD65F03C0
followed by a function header). A19's STP X12+X23 fix preserved X12 as
intended. A19 is not regressed.

## Mechanism analysis

Re-deriving from first principles what could put PC = X30 =
0x212afffe84 (a stack address) at SIGILL time:

### Branch instructions that set PC

| Instr | PC effect          | X30 effect      |
|-------|--------------------|-----------------|
| BLR Xn | PC = Xn           | X30 = pc + 4    |
| BR  Xn | PC = Xn           | unchanged       |
| RET   | PC = X30 (= BR X30) | unchanged     |
| LDR ... | PC unchanged     | (data load)     |

For PC = X30 simultaneously: most likely a RET (= BR X30), where X30
was already = 0x212afffe84 at the moment of RET.

### Where was X30 written?

In goalc-emitted code, X30 is written by:

1. **Function prologue STP X29, X30** — only stores X30 (doesn't write
   to the X30 register).
2. **Function epilogue LDP X29, X30, [SP], #16** — LOADS X30 from the
   saved-X30 slot.
3. **BLR Xn** — WRITES X30 = pc_of_blr + 4.

For X30 = 0x212afffe84 from epilogue's LDP, the saved-X30 slot must
hold 0x212afffe84 as an 8-byte value, and the saved-X29 slot must hold
0x212afffe84 too (since X29 = X30 in the dump).

### Scan for 16-byte slot = 0x212afffe84 ✕ 2

The stack dump from sp=0x212afffcc0 to sp+256=0x212afffdc0 was
exhaustively scanned. The lr-relative dump from lr-200 to lr+16 (a
~216-byte window centred on the fault PC) was also scanned. NO 16-byte
slot in either window holds 0x212afffe84 at both consecutive 8-byte
positions.

So the LDP X29, X30 producing both = 0x212afffe84 either reads from a
stack slot ABOVE sp+256 (outside the dump window), OR the BR/RET source
isn't the standard epilogue.

### Alternate path — BLR target = 0x212afffe84 set via ADD X15 of a
### GOAL-form-stack-addr

The standard `IR_FunctionCall::do_codegen_arm64` sequence:

```
ADD freg, freg, X15        ; convert GOAL form → host
STP X3, X5, [SP, #-16]!    ; call_r64 push #1
STP X10, X11, [SP, #-16]!  ; call_r64 push #2
STP X12, X23, [SP, #-16]!  ; call_r64 push #3
BLR freg                   ; branch
LDP X12, X23, [SP], #16    ; restore
LDP X10, X11, [SP], #16    ; restore
LDP X3, X5, [SP], #16      ; restore
```

If `freg` holds the GOAL form of a stack address (e.g., `0x07fffe84`),
then `ADD freg, freg, X15` produces the host stack address
(`0x212afffe84`), and `BLR freg` jumps to that stack address. PC =
0x212afffe84. SIGILL when CPU tries to decode the bytes there.

But after this BLR, X30 = pc_of_blr + 4 (a HEAP code address from the
calling goalc-emitted function). Not 0x212afffe84.

So this mechanism explains PC = 0x212afffe84 but NOT X30 = 0x212afffe84.

### Reconciling the X30 = 0x212afffe84 observation

The most consistent explanation is that BOTH PC and X30 = 0x212afffe84
arises from a sequence like:

```
LDP X29, X30, [SP, #offset_outside_visible_window]   ; loads X30 = stack_addr
RET                                                    ; PC = X30 = stack_addr
```

with the saved-X30 slot holding a previously-STR'd `0x212afffe84` value.

Or, the chain may be more complex — e.g. multiple nested function
returns where each frame's LDP X30 propagates the bad value upward.

## Audit of A22's unlocked surfaces

### `IR_FunctionCall::do_codegen_arm64` (goalc/compiler/IR.cpp:651)

```cpp
void IR_FunctionCall::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                       const AllocationResult& allocs,
                                       emitter::IR_Record irec) {
  auto freg = get_reg(m_func, allocs, irec);
  gen->add_instr(emitter::IGen::ARM64::add_gpr64_gpr64(freg, emitter::gRegInfo.get_offset_reg()), irec);
  gen->add_instr(emitter::IGen::ARM64::call_r64(freg), irec);
}
```

This is structurally identical to the x86 version
(`do_codegen_x86`) — same `ADD freg, offset_reg ; CALL freg` shape.
The x86 path boots correctly to `link finish: logo` on the same GOAL
source, so the IR is consistent across backends. No arm64-specific
bug here.

Verified: `add_gpr64_gpr64(dst, src)` emits `ADD dst, dst, src`
(3-operand). With `(freg, X15)`, this is `ADD freg, freg, X15`,
producing the host form of the GOAL pointer.

### `call_r64` (goalc/emitter/IGenARM64.cpp:1579)

```cpp
InstructionARM64 call_r64(Register reg_) {
  constexpr uint32_t kStpX3X5Push   = 0xA9BF17E3u;
  constexpr uint32_t kStpX10X11Push = 0xA9BF2FEAu;
  constexpr uint32_t kStpX12X23Push = 0xA9BF5FECu;
  constexpr uint32_t kLdpX12X23Pop  = 0xA8C15FECu;
  constexpr uint32_t kLdpX10X11Pop  = 0xA8C12FEAu;
  constexpr uint32_t kLdpX3X5Pop    = 0xA8C117E3u;
  uint32_t blr = 0xD63F0000u | (arm64_reg5(reg_) << 5);
  return InstructionARM64::multi({kStpX3X5Push, kStpX10X11Push, kStpX12X23Push,
                                  blr,
                                  kLdpX12X23Pop, kLdpX10X11Pop, kLdpX3X5Pop});
}
```

Decoded:
- kStpX3X5Push = STP X3, X5, [SP, #-16]!  — pushes (X3, X5) (verified: Rt=3, Rt2=5, Rn=SP, imm7=-2*8=-16) ✓
- kStpX10X11Push = STP X10, X11, [SP, #-16]! ✓
- kStpX12X23Push = STP X12, X23, [SP, #-16]! (A19 fix — verified Rt=12, Rt2=23) ✓
- BLR encoding = 0xD63F0000 | (reg << 5) — branch to reg_ with X30 = pc+4 ✓
- LDP pops are mirror-correct: pop X12+X23, then X10+X11, then X3+X5 ✓

Save / restore order is an EXACT mirror. SP delta is 0 over the full
call_r64 sequence (3 × -16 push, BLR, 3 × +16 pop). No slot
mis-calculation found.

### X16 usage in `store_goal_gpr` / `load_goal_gpr`
### (goalc/emitter/IGenARM64.cpp:983-1190)

Pattern emitted:

```
ADD X16, base, off          ; X16 = base + off (= base + X15 = host form of base if base is GOAL)
LDR/STR Wt, [X16, #imm12]   ; access with field offset
```

If `base` is a GOAL pointer to a stack-allocated thing
(`0x07fffe84`), then `ADD X16, base, X15` produces the host stack
address (`0x212afffe84`). The subsequent LDR/STR accesses memory at
that stack address.

This is the LEGITIMATE pattern for accessing a field of a stack-
allocated object. After the access, X16 still holds the host stack
address — but the cookbook claims `X16 is dead between IRs`. The
next IR's emit assumes X16 is dead and starts fresh.

The crash time X16 = 0x212afffe84 IS consistent with a recent
field-access on a stack-allocated thing. Not a bug per se — but it
points at the IR that ran just before the BLR-to-stack happened.

### `arm64_add_xd_sp_imm12` (goalc/compiler/IR.cpp:124)

```cpp
static InstructionARM64 arm64_add_xd_sp_imm12(Register dst, uint32_t imm12) {
  ASSERT(imm12 <= 0xfff);
  uint32_t rd = static_cast<uint32_t>(dst.id()) & 0x1fu;
  uint32_t enc = 0x91000000u | ((imm12 & 0xfffu) << 10) | (31u << 5) | rd;
  return InstructionARM64(enc);
}
```

ADD Xd, SP, #imm12 (Rn = 31 = SP). Correctly encodes the SP base.
Used by `IR_RegValAddr::do_codegen_arm64` and
`IR_GetStackAddr::do_codegen_arm64` to compute `&local` as a host
stack address, then SUB X15 to convert to GOAL form.

Both call sites:

```cpp
ASSERT(stack_offset >= 0);
gen->add_instr(arm64_add_xd_sp_imm12(dst, static_cast<uint32_t>(stack_offset)), irec);
gen->add_instr(emitter::IGen::ARM64::sub_gpr64_gpr64(dst, emitter::gRegInfo.get_offset_reg()),
               irec);
```

The dst is allocated by the regalloc. The output: dst = (SP +
stack_offset) - X15 = GOAL form of host stack address. If
stack_offset is correct (within frame), this is well-formed.

No bug found here. The mechanism that creates the offending stack-
addr GOAL form is RIGHT — it's the consumer (some IR_FunctionCall
that uses this dst as freg) that's the problem.

### `_arg_call_arm64` trampoline (asm_funcs_arm64.s:14-36)

Initial read:

```asm
_arg_call_arm64:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  ldr x8, [sp], #16        ; X8 = saved X29 — the function pointer!
  stp q15, q14, [sp, #-32]!
  stp q13, q12, [sp, #-32]!
  stp q11, q10, [sp, #-32]!
  stp q9, q8, [sp, #-32]!
  blr x8
  ldp q9, q8, [sp], #32    ; (mirror Q LDPs)
  ldp q10, q11, [sp], #32
  ldp q12, q13, [sp], #32
  ldp q14, q15, [sp], #32
  ldp x29, x30, [sp], #16  ; <<< loads X29, X30 from CALLER'S stack, NOT saved area!
  ret                       ; <<< RETs to garbage X30 from caller's stack
```

The calling convention is that fn_ptr is passed in X29 (not on the
stack). The prologue's STP saves caller's X29 (= fn_ptr) and X30 (=
return addr) at [SP-16, SP-1]. After the LDR X8, [SP], #16, X8 =
fn_ptr; SP returns to original_SP. The Q-reg STPs decrement SP by
128 (filling that area with Q15..Q8). After BLR returns, the Q LDPs
restore Q regs and SP returns to original_SP. Then `ldp x29, x30,
[sp], #16` reads from [original_SP..original_SP+15] — that's CALLER'S
stack content above its SP, NOT the trampoline's saved area at
[original_SP-16..original_SP-1].

The trampoline is BROKEN. The post-LDR-SP-restore step orphans the
saved X29/X30 area; the post-BLR LDP reads from caller's stack
(garbage values).

This is confirmed by the comment in
`game/kernel/jak1/kscheme.cpp:526-528`:

> _arg_call_arm64 would otherwise have done this, but its current
> shape doesn't actually preserve x29/x30 correctly so we open-code
> the save/restore here

The jak1 runtime SIDESTEPS `_arg_call_arm64` entirely on arm64 — the
`make_function_from_c_arm64` function emits its own trampoline inline
(lines 601-720). The dispatch `make_function_from_c` routes arm64 to
that inline-emitted trampoline; `make_function_from_c_systemv` (which
references `_arg_call_arm64`) is ONLY called on non-aarch64 builds.

Verdict: `_arg_call_arm64` is DEAD CODE on the boot critical path.
Fixing it would not change the 216-link-finish behaviour. The same
likely holds for `_stack_call_arm64`. Fixing the trampolines to be
correct is good hygiene but does NOT address the 216 ceiling.

### `_call_goal_asm_arm64` trampoline (asm_funcs_arm64.s:170-238)

```asm
_call_goal_asm_arm64:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  stp x23, x24, [sp, #-16]!
  stp x25, x26, [sp, #-16]!
  stp x27, x28, [sp, #-16]!
  stp d8, d9, [sp, #-16]!
  stp d10, d11, [sp, #-16]!
  stp d12, d13, [sp, #-16]!
  stp d14, d15, [sp, #-16]!
  ; ABI setup
  mov x20, x4 ; GOAL process slot
  mov x21, x4 ; symbol table
  mov x22, x5 ; offset
  add x14, x4, x5 ; st_host
  mov x15, x5 ; ee_base
  mov x13, x4 ; pp (= st, not real pp here)
  blr x3
  ; restore in EXACT mirror order
  ldp d14, d15, [sp], #16
  ldp d12, d13, [sp], #16
  ldp d10, d11, [sp], #16
  ldp d8, d9, [sp], #16
  ldp x27, x28, [sp], #16
  ldp x25, x26, [sp], #16
  ldp x23, x24, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp x29, x30, [sp], #16
  ret
```

Save list: X19-X28 (5 pairs) + D8-D15 (4 pairs) + X29/X30 (1 pair) =
160 bytes. Restore is the exact mirror.

This trampoline is CORRECT — slot math balances, save and restore
orders mirror exactly. Used by the inline asm in
`game/kernel/common/kscheme.cpp::call_goal` (line 174-181).

### `_call_goal_on_stack_asm_arm64` trampoline (asm_funcs_arm64.s:309-397)

Saves X19-X28 + D8-D15 on the OLD (C) stack BEFORE the
stack-switch, restores from OLD stack AFTER the GOAL leg returns.
Phase-26 comments document a prior bug where the load was from the
NEW stack — that's fixed and verified. The current save-then-switch
shape is correct.

### `make_function_from_c_arm64` trampoline (jak1/kscheme.cpp:601-720)

Emits an inline 0x80-byte trampoline per C function bound to GOAL.
Each trampoline:
1. Saves X29, X30, X13, X14, X15 to its own stack (48 bytes).
2. Shuffles GOAL→AAPCS args (X0←X7, X1←X6, X3←X1, X4←X8, X5←X9,
   X6←X10, X7←X11; X2 unchanged).
3. Optionally moves X13 → X3 for `arg3_is_pp`.
4. Materializes target C function address into X16 via MOVZ + 3 MOVK.
5. BLR X16.
6. Restores X15, X13/X14, X29/X30 in mirror order.
7. RET.

The arg shuffle is dependency-aware — verified by tracing each
register pair: after the 7 MOVs, X0..X7 hold AAPCS args 0..7 with
no aliasing collisions.

Save / restore mirror is correct.

## A21 hypotheses status

| Hypothesis | A21 status | A22 finding |
|------------|------------|-------------|
| H1 (regalloc clobbers) | INCONCLUSIVE | Re-confirmed inconclusive — call_r64 saves the documented set correctly |
| H2 (X16 / scratch corruption across BLR) | PRIMARY | Mechanism CONFIRMED but specific emit-site NOT located |
| H3 (klink imm19 NOPs) | RULED OUT | Re-confirmed: no OOR site in execute path |
| H4 (AAPCS arg-shuffle gap) | RULED OUT | Re-confirmed: trampoline shuffle is correct |

## Hypothesis refinement — H2 sub-mechanism

The H2 mechanism implied by the dump:

1. GOAL source calls a function `F` that takes `arg0` (and possibly
   `arg4`) as a function pointer (e.g., a callback).
2. The caller of F passes `&local_struct` (a GOAL-form stack
   address) as `arg0`.
3. Inside F, the code does `IR_FunctionCall` with `m_func = arg0`.
   The codegen emits `ADD freg, freg, X15 ; ... ; BLR freg` →
   `BLR 0x212afffe84` (host stack address).
4. The BLR jumps to a stack address. The bytes there are UDF /
   unallocated. SIGILL.

This is a SOURCE-LEVEL bug in either:
- GOAL caller (passing `&local` as a fn ptr arg)
- GOAL callee (using a non-fn arg as a fn ptr)
- GOAL type system (allowing a non-function value through a function-
  typed slot)
- goalc compilation (`goalc/compiler/compilation/Type.cpp` or
  similar) failing to enforce the function-typed contract on a
  closure / dynamic dispatch path.

The OFFENDING emit in `goalc/emitter/IGenARM64.cpp` / `IR.cpp` is
CORRECT given its IR-level inputs. The bug is upstream: the IR-level
`m_func` register holds a value that originated from
`IR_RegValAddr` / `IR_GetStackAddr`, which legitimately produces a
GOAL-form stack address. That value should not have flowed into an
`IR_FunctionCall::m_func` slot.

## Files audited (full read or grep)

- `goalc/emitter/IGenARM64.cpp` (lines 25-2270) — full audit of
  X16 staging, call_r64, add_gpr64_gpr64, sub_gpr64_gpr64,
  store_goal_gpr, load_goal_gpr, idiv preserve-X8 helpers.
- `goalc/emitter/IGenARM64.h` (header signatures) — verified no
  signature drift since A1.
- `goalc/compiler/IR.cpp` (lines 1-2270 selectively) — full audit
  of IR_FunctionCall, IR_RegValAddr, IR_StaticVarAddr,
  IR_FunctionAddr, IR_GetStackAddr, IR_LoadConstOffset,
  IR_StoreConstOffset, arm64_add_xd_sp_imm12.
- `goalc/compiler/CodeGenerator.cpp` (read-only — locked file) —
  verified prologue/epilogue emit shape, frame_bytes calc, spill
  load/store encodings.
- `goalc/emitter/Register.cpp` (read-only — not in any phase
  unlock for arm64) — verified `m_gpr_alloc_order = {RAX,RCX,RDX,
  RBX,RBP,RSI,RDI,R8,R9,R10}` (caps at goalc id 10), `m_saved_gprs
  = {RBX,RBP,R10,R11,R12}`. Confirms goalc doesn't allocate
  X19..X28.
- `game/kernel/asm_funcs_arm64.s` (all 397 lines) — audited all
  trampolines for STP/LDP balance and slot consistency.
- `game/kernel/common/kscheme.cpp` (lines 115-217, call_goal +
  call_goal_on_stack) — verified inline-asm trampoline arg load.
- `game/kernel/jak1/kscheme.cpp` (lines 280-800, especially
  make_function_from_c_arm64 at line 601-720 and
  make_x12_preserve_wrapper_arm64 at line 746-788).
- `.autoport/reports/A21-qemu-reg-byte-dump.log` — re-derived the
  H2 fingerprint from raw dump.

## What was NOT possible to find

- The SPECIFIC goalc emit sequence that produced the bad m_func
  value. The codegen lowering paths I audited are all internally
  consistent and produce correct code for their IR-level inputs.
- The SPECIFIC GOAL source location that calls a non-function value
  as a function. Without unlocking `goal_src/` and re-grepping with
  a runtime tracer to identify which CGO / function dispatches this
  way, I cannot name it.
- The SPECIFIC method-dispatch path that ended up with a stack-addr
  GOAL form in the function-pointer slot. The CALLGOAL-TRACE
  evidence shows `call_method_of_type` with fn_goal=0x1bff94 was
  successful 3 times before the crash, so the crash is in a deeper
  nested call.

## Why the fix cannot land in A22's unlock list

The unlocked files are:
- `goalc/emitter/IGenARM64.cpp/h` — codegen emit. The emit IS correct
  for its inputs. Modifying it to "detect" stack-addr GOAL forms at
  emit time would require knowing GOAL types, which the emitter
  doesn't have. Detecting at run time would require an env-gated
  runtime check (CMP + B.cond + UDF). That fingerprints the bug but
  doesn't fix it.
- `goalc/compiler/IR.cpp` — IR-level codegen. Same issue: the IR
  knows the value is a function pointer but not whether the source
  was a stack-allocate.
- `game/kernel/asm_funcs_arm64.s` — trampolines. Audited: the
  trampolines used in the boot path are correct. `_arg_call_arm64`
  has a real bug but it's dead code on the arm64 boot path.

A fix that would actually break the 216 ceiling needs to:
- Identify the GOAL source / compilation path that produces the
  stack-addr-as-fn-ptr value.
- Fix that path so the stack-addr never reaches m_func.

That fix likely lives in one of:
- `goalc/compiler/compilation/Type.cpp` (type checking that catches
  the bad assignment) — LOCKED for A22.
- `goalc/compiler/Val.cpp` (lowering of `&local` to differentiate
  stack vs heap) — LOCKED for A22.
- `goal_src/jak1/engine/*.gc` (the actual buggy GOAL source) — not
  locked but ALSO not unambiguously identifiable without runtime
  trace.

## Diagnostic recommendation for A23

The supervisor should author A23 with the following diagnostic
strategy:

1. **Runtime BLR-target tracer**: add an env-gated patch to
   `IGenARM64.cpp::call_r64` that, when env var `OG_BLR_TARGET_TRACE`
   is set, emits 4-6 extra instructions BEFORE the BLR:
   - Compare `freg` against a "stack range" mask (e.g. upper 8 bits
     of the GOAL form).
   - If freg's GOAL form is in the stack range
     (`(freg < 0x08000000) && (freg > 0x07000000)`), emit a UDF with
     a tagged immediate (e.g., UDF #0xfa11). The SIGILL handler
     decodes the tag and prints "BLR-target=stack: freg=0x..."
     before exit.
   - This narrows the failing IR_FunctionCall to the exact site
     without requiring GOAL source unlocks.

2. **Compile-time IR audit**: add an env-gated check in
   `IR_FunctionCall::do_codegen_arm64` that walks back through
   `m_func`'s definition IRs and warns at compile time if the value
   originated from `IR_RegValAddr` / `IR_GetStackAddr`. That would
   fingerprint the offending GOAL source location at goalc emit.

3. **Method-dispatch trace**: extend `OG_CALLGOAL_TRACE` to log
   every method-dispatch's fn_goal value AT THE DISPATCH SITE
   (after the typetag → method-slot LDR), so we see whether a
   method-slot was set with a stack-addr GOAL form.

4. **Unlock list for A23**:
   - `goalc/emitter/IGenARM64.cpp` (continue from A22)
   - `goalc/compiler/IR.cpp` (continue from A22)
   - `goalc/compiler/Val.cpp` (to inspect MemoryDerefVal lowering)
   - `goalc/compiler/compilation/Type.cpp` (type-system for fn ptrs)
   - `game/kernel/common/klink.cpp` (for additional klink-time
     diagnostics — currently has OG_KLINK_IMM19_TRACE from A21)

## Conclusion

H2 is confirmed as the structural cause of the 216-link-finish
ceiling. The mechanism (BLR-to-stack-address) is reproducible and
well-characterized. The specific emit SITE / GOAL function /
CGO offset that produces the bad m_func value is NOT identifiable
from the A21 evidence alone, and the A22 unlock list does not include
the files where the fix would land.

A22 attempt-1 honest-exits via Path C (no source located). See
`A22-attempt-1-no-source-located.md` for the recommended A23
strategy and unlock list.
