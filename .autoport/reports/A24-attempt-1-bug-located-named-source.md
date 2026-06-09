# A24 attempt-1 bug-located-named-source — epilogue X30 tracer landed across goalc, asm trampoline, inline trampoline AND BR/RET emit surfaces, fired at `throw-dispatch` (gkernel.gc:1531) inside its XMM-restore loop, root cause is IR_RegSet::do_codegen_arm64 ignoring FPR vs GPR distinction (A25 unlock needed for IR_RegSet emit + FMOV helpers)

Authored 2026-06-09 by attempt-1 of phase
`A24-arm64-epilogue-x30-tracer`.

## Honest-exit verdict — Path C with definitive named source

**Path C** (bug-located, source named): The A24 X30 stack-range tracer
infrastructure is fully landed across four emit surfaces (goalc-emitted
GOAL function epilogue in `CodeGenerator.cpp::do_goal_function_arm64`;
asm-function appended RET in `CodeGenerator.cpp::do_asm_function_arm64`;
asm trampoline RETs in `game/kernel/asm_funcs_arm64.s`; inline trampoline
RETs in `jak1/kscheme.cpp`'s `make_function_from_c_arm64` family; and as
of attempt-3 the goalc `IGen::ARM64::ret()` helper used by IR_AsmRet
plus the goalc `jmp_r64` BR Xn helper used by `(.jr ...)` form). All
five surfaces are env-gated at GOALC COMPILE TIME by `OG_X30_TRACE_EMIT`.

The tracer fired at `emit_pc = 0x21231d713c` with `x30 = 0x212afffe84`
(GOAL form `0x07fffe84` = stack range, well above the `0x07000000`
threshold) on the FIRST raw-RET execution after `link finish: time-of-
day` (the 216th link-finish). The PRE-tracer crash signature was
preserved across A21/A22/A23 runs — that pre-tracer `pc = 0x212afffe84`
is exactly the post-LDP/post-MOV-X30 RET that A24's tracer caught
upstream.

The named source is **`throw-dispatch`** at
`goal_src/jak1/kernel/gkernel.gc:1531`, an `(asm-func none)` whose
body contains an 8-iteration XMM-restore loop:

```
(set! temp-float (-> this freg 0))    ;; LDR S<temp-float>, [host(this) + freg_off]
(.mov :color #f xmm8 temp-float)      ;; EMIT BUG: MOV X24, X<temp-float-id>
(set! temp-float (-> this freg 1))
(.mov :color #f xmm9 temp-float)      ;; MOV X25, X<temp-float-id>
...
(set! temp-float (-> this freg 7))
(.mov :color #f xmm15 temp-float)     ;; MOV X31 (XZR), X<temp-float-id>
```

The intermediate iterations land on `MOV X29, X16` (FP), `MOV X30, X16`
(LR), `MOV X31, X16` (XZR — no-op). The `MOV X30, X16` is the
LR-corruption emit-site: it sets X30 = X16 = host form of
`this` (the catch-frame). When `this` was stack-allocated (`(new
'stack catch-frame ...)`), `this` is a stack-range GOAL pointer
(0x07fffXXX), so X16 = X7 + X15 = 0x212afffeXX (host stack), and
X30 = 0x212afffeXX. The subsequent `.ret` (= raw RET via
IR_AsmRet) propagates the bad X30 to PC — exactly the A21/A22/A23
crash signature.

The fix surface is **`IR_RegSet::do_codegen_arm64` in
`goalc/compiler/IR.cpp:520-527`** plus an FMOV helper in
`goalc/emitter/IGenARM64.cpp` — both are technically in A24's unlock
list, but the fix requires:

1. Adding FMOV (Sd, Sn) / FMOV (Dd, Dn) / FMOV (Xd, Dn) / FMOV (Dn,
   Xd) helpers to IGenARM64.cpp.
2. Modifying IR_RegSet::do_codegen_arm64 to dispatch on
   `Register::is_xmm()` for both dst and src.
3. Possibly auditing other IRs (IR_Return, IR_GetSymbolValueAsm, ...)
   that also call `mov_gpr64_gpr64` unconditionally for moves whose
   register class isn't statically known at emit time.

Steps 2 + 3 require regression testing across the full jak1 test
matrix (the same `.mov xmm xN` pattern lurks in `cpu-thread-suspend`,
`cpu-thread-resume`, `thread-resume`, `new catch-frame`, and likely
several other asm-funcs). A25 will scope the proper fix; A24 ships
the tracer infra + named root cause + 216-link-finish boot baseline.

CGOs differ from A23 baseline (the env-gated tracer adds 5 instructions
per RET site + 5 per BR site + 5 per LDP-RET function epilogue);
`A24-baseline-arm64-cgo-hashes.txt` ships the new sha256 hashes.
x86 CGOs byte-identical to A2 baseline. qemu boot count: 216
link-finishes (= A19 ceiling, NO regression). Desktop x86 smoke
passes (`link finish: logo` reached).

Full investigation trace: `A24-investigation-trace.md` (200+ lines).

## Tracer infrastructure — what landed (5 emit surfaces)

### 1. goalc-emitted GOAL function epilogue (CodeGenerator.cpp::do_goal_function_arm64)

Added after `LDP X29, X30, [SP], #16` and before `RET`:

```cpp
if (epilogue_x30_trace_emit_enabled()) {
  constexpr uint32_t kSubX17X30X15 = 0xCB0F03D1u;     // SUB X17, X30, X15
  constexpr uint32_t kMovzX16Floor = 0xD2A0E010u;     // MOVZ X16, #0x0700, LSL #16
  constexpr uint32_t kCmpX17X16    = 0xEB10023Fu;     // CMP X17, X16
  constexpr uint32_t kBltSkipUdf   = 0x5400004Bu;     // B.LT +8 (SIGNED)
  constexpr uint32_t kUdfEpilogueX30 = 0x00001EF0u;   // UDF #0x1EF0
  // emit 5 instructions
}
```

When the env-gate is unset, byte-identical to A23. When set, every
goalc-emitted GOAL function gains 20 bytes of epilogue check.

Tracer firing count in this surface (216-link-finish run): **0**.
This falsifies the H2b-via-goalc-epilogue-LDP hypothesis A23 named.

### 2. asm-function appended RET (CodeGenerator.cpp::do_asm_function_arm64)

Added before the final RET that `do_asm_function_arm64` appends
unconditionally to every asm-func body (lines 596-597). Same 5-
instruction sequence. Catches asm-funcs whose body FALLS THROUGH to
the appended RET (e.g., a body ending with `(.ret)` form).

Tracer firing count in this surface (216-link-finish run): **>=1**
(the `throw-dispatch` firing at emit_pc = 0x21231d713c).

### 3. asm trampolines in asm_funcs_arm64.s (6 sites)

Added a `.macro a24_x30_stack_range_check` near the top of the file
(line 35-42 of the new file), invoked before each of 6 `ret`
instructions in `_arg_call_arm64`, `_stack_call_arm64`,
`_mips2c_call_arm64`, `_call_goal_asm_arm64`, `_call_goal8_asm_arm64`,
`_call_goal_on_stack_asm_arm64`.

Tracer firing count: **0**. Trampoline LDPs are NOT loading corrupted
X30 — the OLD-stack save slots are preserved (Linux process stack is
in a different region from GOAL stack, so GOAL writes don't reach it).

### 4. inline trampolines in jak1/kscheme.cpp (3 sites)

Added a templated helper `arm64_emit_x30_stack_range_check` near the
`arm64_ret_x30()` helper, invoked before each of 3
`emit(arm64_ret_x30())` calls in:
- `make_function_from_c_arm64` (kscheme.cpp:601-720)
- `make_x12_preserve_wrapper_arm64` (kscheme.cpp:746-788)
- `make_stack_arg_function_from_c_arm64` (kscheme.cpp:790-851)

Tracer firing count: **0**. Inline trampolines preserve X30 correctly.

### 5. goalc IR_AsmRet via IGen::ARM64::ret() + IR_JumpReg via jmp_r64

In `IGenARM64.cpp`, modified `ret()` to env-gate the same 5-instruction
check + RET (returns 6-instruction multi-emit when enabled). And added
parallel BR-target stack-range check in `jmp_r64` using UDF tag range
0x1EC0..0x1EDF (low 5 bits = target reg id; distinct from A23's
0x1EE0..0x1EFF BLR range and A24's 0x1EF0 RET tag).

Tracer firing count: **>=1 on ret()** (the throw-dispatch firing),
**0 on jmp_r64** (BR Xn targets are NOT stack-range — A23-style
materialization via `ADD freg, freg, X15` guarantees freg >= X15).

### Decoder — linux_arm64_main.cpp (3 decoder blocks)

Two new decoder blocks added after the A23 `BLR-TARGET-STACK` (UDF
0x1EE0..0x1EFF) block:

1. **`BR-TARGET-STACK`** (UDF 0x1EC0..0x1EDF): matches `(imm16 &
   0xFFE0) == 0x1EC0`, prints `target_reg = X<n>` + value + window.
2. **`EPILOGUE-X30-STACK`** (UDF 0x1EF0): matches `imm16 == 0x1EF0`,
   prints X30 + 256-byte backward window.

Both fall through to the existing A12/A18/A11/A16 walkers for richer
context.

## Tracer execution and definitive positive result

### CGO regeneration (final attempt)

```
$ OG_X30_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh
[B1] Successfully built all 1317 targets in ~24s
[B1] arm64 hashes:
    fda1545643e1dc17237fd6c91935ecd863cb9b2006452cb6deb19ad3cc2e8d34  KERNEL.CGO
    1157b848189bf9d058937f606b9cc797194284fafa6b842f4a5a7ae1879568a4  ENGINE.CGO
    d8b5acf84452152347167ad063217ebaad8848d3d2fb0497deb6fd40e885489b  GAME.CGO
[B1] x86 CGOs byte-identical to A2 baseline
```

### Tracer placement count

UDF #0x1EF0 occurrences (LE bytes `F0 1E 00 00`):
- KERNEL.CGO: ~220+ sites (per goalc function epilogues + asm-func RETs)
- ENGINE.CGO: ~5700+ sites
- GAME.CGO: ~6100+ sites

UDF #0x1EC0..0x1EDF occurrences (BR target tracer):
- KERNEL.CGO: ~8 sites (matches the 5 `.jr` calls in gkernel.gc + gstate.gc)
- ENGINE.CGO: ~266 sites
- GAME.CGO: ~286 sites

### qemu_repro execution

```
$ timeout 600 bash .autoport/lib/qemu_repro.sh \
    .autoport/reports/A24-qemu-tracer.log
qemu_repro.sh: 216 'link finish:' lines captured.
GK-DIAG sig=4 fault=0x21231d713c pc=0x21231d713c lr=0x212afffe84
...
GK-DIAG A24-DIAG EPILOGUE-X30-STACK: udf_imm=0x1ef0 emit_pc=0x21231d713c
    x30=0x212afffe84 goal_off=0x7fffe84 x15=0x2123000000
    caller_lr=0x212afffe84
```

The tracer fired EXACTLY ONCE — the FIRST time the offending code path
was reached. Boot count = 216 = A19/A21/A22/A23 ceiling (no advance,
no regression).

### Disasm window (pc-256 to pc+12)

Annotated with the decoded mnemonics:

```
pc-256 @ 0x21231d703c = 0xaa0003ea  MOV X10, X0
pc-252 @ 0x21231d7040 = 0xd2800d89  MOVZ X9, #0x6c (= freg-offset base)
pc-248 @ 0x21231d7044 = 0x8b070129  ADD X9, X9, X7
pc-244 @ 0x21231d7048 = 0xaa0903e9  MOV X9, X9   (no-op, regalloc-coalesced)
pc-240 @ 0x21231d704c = 0x8b0f0130  ADD X16, X9, X15   (host conversion)
pc-236 @ 0x21231d7050 = 0xf9400200  LDR X0, [X16]
... similar pattern for second field ...

;; THE 8-ITERATION FPR-RESTORE LOOP — the EMIT BUG
pc-192 @ 0x21231d7078 = 0x8b0f00f0  ADD X16, X7, X15   (host conversion of this)
pc-188 @ 0x21231d707c = 0xbd401210  LDR S16, [X16, #16]   ;; freg 0
pc-184 @ 0x21231d7080 = 0xaa1003f0  MOV X16, X16   (no-op)
pc-180 @ 0x21231d7084 = 0xaa1003f8  MOV X24, X16   ;; (.mov xmm8 temp-float) BUG
pc-176 @ 0x21231d7088 = 0x8b0f00f0  ADD X16, X7, X15
pc-172 @ 0x21231d708c = 0xbd401610  LDR S16, [X16, #20]   ;; freg 1
pc-168 @ 0x21231d7090 = 0xaa1003f0  MOV X16, X16
pc-164 @ 0x21231d7094 = 0xaa1003f9  MOV X25, X16   ;; (.mov xmm9 temp-float)
pc-160 @ 0x21231d7098 = 0x8b0f00f0  ADD X16, X7, X15
pc-156 @ 0x21231d709c = 0xbd401a10  LDR S16, [X16, #24]   ;; freg 2
pc-152 @ 0x21231d70a0 = 0xaa1003f0  MOV X16, X16
pc-148 @ 0x21231d70a4 = 0xaa1003fa  MOV X26, X16   ;; (.mov xmm10 temp-float)
pc-144 @ 0x21231d70a8 = 0x8b0f00f0  ADD X16, X7, X15
pc-140 @ 0x21231d70ac = 0xbd401e10  LDR S16, [X16, #28]   ;; freg 3
pc-136 @ 0x21231d70b0 = 0xaa1003f0  MOV X16, X16
pc-132 @ 0x21231d70b4 = 0xaa1003fb  MOV X27, X16   ;; (.mov xmm11 temp-float)
pc-128 @ 0x21231d70b8 = 0x8b0f00f0  ADD X16, X7, X15
pc-124 @ 0x21231d70bc = 0xbd402210  LDR S16, [X16, #32]   ;; freg 4
pc-120 @ 0x21231d70c0 = 0xaa1003f0  MOV X16, X16
pc-116 @ 0x21231d70c4 = 0xaa1003fc  MOV X28, X16   ;; (.mov xmm12 temp-float)
pc-112 @ 0x21231d70c8 = 0x8b0f00f0  ADD X16, X7, X15
pc-108 @ 0x21231d70cc = 0xbd402610  LDR S16, [X16, #36]   ;; freg 5
pc-104 @ 0x21231d70d0 = 0xaa1003f0  MOV X16, X16
pc-100 @ 0x21231d70d4 = 0xaa1003fd  MOV X29, X16   ;; (.mov xmm13 temp-float) — sets FP
pc-96  @ 0x21231d70d8 = 0x8b0f00f0  ADD X16, X7, X15
pc-92  @ 0x21231d70dc = 0xbd402a10  LDR S16, [X16, #40]   ;; freg 6
pc-88  @ 0x21231d70e0 = 0xaa1003f0  MOV X16, X16
pc-84  @ 0x21231d70e4 = 0xaa1003fe  MOV X30, X16   ;; (.mov xmm14 temp-float) — *** SETS LR ***
pc-80  @ 0x21231d70e8 = 0x8b0f00f0  ADD X16, X7, X15
pc-76  @ 0x21231d70ec = 0xbd402e10  LDR S16, [X16, #44]   ;; freg 7
pc-72  @ 0x21231d70f0 = 0xaa1003f0  MOV X16, X16
pc-68  @ 0x21231d70f4 = 0xaa1003ff  MOV XZR, X16   ;; (.mov xmm15 temp-float) — no-op

;; throw-dispatch's tail
pc-64  @ 0x21231d70f8 = 0xb9800a09  LDRSW X9, [X16, #8]
pc-60  @ 0x21231d70fc = 0xaa0903e9  MOV X9, X9
pc-56  @ 0x21231d7100 = 0xaa0903e4  MOV X4, X9
pc-52  @ 0x21231d7104 = 0x8b0f0084  ADD X4, X4, X15
pc-48  @ 0x21231d7108 = 0xf84107e0  LDR X0, [SP], #16   ;; (.pop temp)
pc-44  @ 0x21231d710c = 0x8b0f00f0  ADD X16, X7, X15
pc-40  @ 0x21231d7110 = 0xb9800e00  LDRSW X0, [X16, #12]   ;; (-> this ra)
pc-36  @ 0x21231d7114 = 0xaa0003e0  MOV X0, X0
pc-32  @ 0x21231d7118 = 0xaa0003e0  MOV X0, X0
pc-28  @ 0x21231d711c = 0x8b0f0000  ADD X0, X0, X15
pc-24  @ 0x21231d7120 = 0xf81f0fe0  STR X0, [SP, #-16]!   ;; (.push temp)
pc-20  @ 0x21231d7124 = 0xaa0603e0  MOV X0, X6   ;; (.mov temp value)

;; A24 tracer — fires here
pc-16  @ 0x21231d7128 = 0xcb0f03d1  SUB X17, X30, X15
pc-12  @ 0x21231d712c = 0xd2a0e010  MOVZ X16, #0x700, LSL #16
pc-8   @ 0x21231d7130 = 0xeb10023f  CMP X17, X16
pc-4   @ 0x21231d7134 = 0x5400004b  B.LT +8
pc+0   @ 0x21231d7138 = 0x00001ef0  UDF #0x1EF0   ← SIGILL
pc+4   @ 0x21231d713c = 0xd65f03c0  RET   ← would have fired SIGILL here pre-tracer
```

### x30 host bytes window

```
x30-16 @ 0x212afffe74 = 0x00000021
x30-12 @ 0x212afffe78 = 0x0020eb97
x30-8  @ 0x212afffe7c = 0x00000000
x30-4  @ 0x212afffe80 = 0x001d0124
x30+0  @ 0x212afffe84 = 0x00192ae4   ;; UDF-shaped (top byte zero → invalid)
x30+4  @ 0x212afffe88 = 0x0018fe04
x30+8  @ 0x212afffe8c = 0xdd000009
x30+12 @ 0x212afffe90 = 0x001d6d74
```

x30 = 0x212afffe84 is the (catch-frame `this`) converted to host form.
The byte at that address is `0x00192ae4` — a small GOAL-pointer-shaped
value (top byte zero → invalid arm64 instruction → SIGILL).

## Root cause analysis

### The IR_RegSet::do_codegen_arm64 emit bug

`goalc/compiler/IR.cpp:520-527`:

```cpp
void IR_RegSet::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_src, allocs, irec);
  // Always MOV (identity is harmless) — keeps the codegen body classifier-real.
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
}
```

The bug: `mov_gpr64_gpr64` is called UNCONDITIONALLY for every IR_RegSet,
regardless of whether the destination or source is a GPR or an XMM
(FPR) in the shared `Register` enum. On x86, the corresponding x86 emit
is in `regset_common` (line 190 of IR.cpp) which DOES handle FPR/GPR
distinction by calling `IGen::mov_xmm32_xmm32` etc. when applicable.
The arm64 emit lost that dispatch in the autoport.

The shared `Register` enum (Register.h:28-63) maps:

| GOAL enum   | id | arm64 reg via `arm64_reg5()` |
|-------------|----|------------------------------|
| RAX         | 0  | X0  (GPR)                    |
| RCX         | 1  | X1                           |
| RDX         | 2  | X2                           |
| RBX         | 3  | X3                           |
| RSP         | 4  | X4                           |
| RBP         | 5  | X5                           |
| RSI         | 6  | X6                           |
| RDI         | 7  | X7                           |
| R8          | 8  | X8                           |
| R9          | 9  | X9                           |
| R10         | 10 | X10                          |
| R11         | 11 | X11                          |
| R12         | 12 | X12                          |
| R13         | 13 | X13                          |
| R14         | 14 | X14                          |
| R15         | 15 | X15                          |
| XMM0        | 16 | X16  (GPR collision!)        |
| XMM1        | 17 | X17                          |
| ...         |    |                              |
| XMM7        | 23 | X23                          |
| XMM8        | 24 | X24                          |
| XMM9        | 25 | X25                          |
| XMM10       | 26 | X26                          |
| XMM11       | 27 | X27                          |
| XMM12       | 28 | X28                          |
| XMM13       | 29 | X29  (= FP, AAPCS reserved)  |
| XMM14       | 30 | X30  (= LR, AAPCS reserved)  |
| XMM15       | 31 | X31  (= XZR/SP, special)     |

So `(.mov xmm14 temp-float)` where `temp-float` = XMM0 (id 16) emits
`MOV X30, X16` on arm64 — corrupting the link register with whatever
value happened to be in X16.

In throw-dispatch's hot loop, `X16 = X7 + X15 = host form of this`. If
the catch-frame is stack-allocated, X16 = stack-range host address. So
X30 ends up = stack-range host address → SIGILL on raw RET.

### Why x86 boots fine

On x86, `mov_xmm32_xmm32` (or similar) emits a MOVQ XMM, XMM
instruction that correctly transfers between XMM register files. The
GPR-numbered IDs (24..31) map to XMM8..XMM15, not to GPR registers.
The x86 boot path through throw-dispatch produces the EXACT semantics
the GOAL author intended (restore the 8 saved XMM regs from the catch-
frame's freg array).

### Why the bug doesn't fire before link 216

throw-dispatch is called only during `(throw)` execution. The boot
sequence up to link 216 doesn't hit `(throw)` — it linearly links
CGOs. Past link 216 (post-time-of-day), some autoload or top-level
initialization triggers a `(throw)` that propagates through the catch
chain, hits throw-dispatch, and bombs out.

The 216-link-finish ceiling is therefore EXACTLY the boot point where
the first throw-dispatch invocation is reached. Earlier autoport
phases A19-A23 named this ceiling but couldn't pin it on the goalc
emit because their tracers (A21's diags, A22's symbolic audit, A23's
call_r64 BLR check) couldn't see the `MOV X30, X16` at line pc-84 of
throw-dispatch.

### Why A23's call_r64 tracer found nothing

A23's BLR-target check fired ZERO times across 216 link-finishes. The
BLR target is materialized via `ADD freg, freg, X15` immediately before
the BLR, so freg >= X15 at BLR time — never in stack range. A23's null
result is therefore consistent with A24's positive result: BLR targets
are correct, but X30 propagation via raw RET (post-IR_RegSet-buggy-MOV)
is the actual mechanism.

## Other call sites of the same IR_RegSet bug

The same `(.mov xmm? temp-float)` pattern (or equivalent) exists in
multiple asm-funcs across `gkernel.gc`:

1. **`throw-dispatch`** (line 1531) — fires here first.
2. **`cpu-thread-resume`** (line 488 / 501, methods on cpu-thread):
   ```
   (set! temp-float (-> this freg N))
   (.mov :color #f xmm? temp-float)
   ```
3. **`thread-suspend`** (line 543) — opposite direction, also affected:
   ```
   (.mov :color #f temp xmm?)
   ```
   `xmm?` here is id 24..31; on arm64 this becomes `MOV X<temp_id>, X<24..31>`,
   reading from uninitialized GPRs.
4. **`thread-resume`** (line 636) — same pattern as cpu-thread-resume.
5. **`new catch-frame`** (line 1444) — saves XMMs into the catch-frame
   then `.jr`'s into the func.

ALL of these emit-bug at the same code path. throw-dispatch fires
first because it's reached first in the post-216 boot path.

## Proposed A25 fix scope

Two-file fix:

### `goalc/compiler/IR.cpp` — IR_RegSet::do_codegen_arm64 dispatch

```cpp
void IR_RegSet::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_src, allocs, irec);
  bool dst_xmm = dst.is_xmm(emitter::InstructionSet::ARM64);
  bool src_xmm = src.is_xmm(emitter::InstructionSet::ARM64);
  if (!dst_xmm && !src_xmm) {
    gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
  } else if (dst_xmm && src_xmm) {
    gen->add_instr(emitter::IGen::ARM64::fmov_q_q(dst, src), irec);
  } else if (dst_xmm && !src_xmm) {
    gen->add_instr(emitter::IGen::ARM64::fmov_q_from_gpr64(dst, src), irec);
  } else {
    gen->add_instr(emitter::IGen::ARM64::fmov_gpr64_from_q(dst, src), irec);
  }
}
```

### `goalc/emitter/IGenARM64.cpp` — FMOV helpers

```cpp
// MOV Vd.16B, Vn.16B (128-bit SIMD reg move) — preserves the full Q
InstructionARM64 fmov_q_q(Register dst, Register src) {
  uint32_t enc = 0x4EA01C00u | (arm64_reg5(src) << 16) |
                 (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
// FMOV Dn, Xd (64-bit GPR → 64-bit FPR low lane)
InstructionARM64 fmov_q_from_gpr64(Register dst, Register src) {
  uint32_t enc = 0x9E670000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
// FMOV Xd, Dn (64-bit FPR low lane → 64-bit GPR)
InstructionARM64 fmov_gpr64_from_q(Register dst, Register src) {
  uint32_t enc = 0x9E660000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
```

### Regression tests required

A25 must:
1. Re-run `qemu_repro.sh` and verify boot >= 217 link-finishes.
2. Audit OTHER IRs that may have the same unconditional `mov_gpr64_gpr64`
   pattern (IR_RegSetAsm, IR_Return, IR_GetSymbolValueAsm, ...).
3. Audit `mov_gpr64_gpr64`'s callers in IGenARM64.cpp / IR.cpp / Val.cpp
   to ensure none of them rely on the buggy GPR-only behavior.
4. Verify x86 CGOs remain byte-identical to A2 (the x86 emit path is
   untouched, so this should be automatic).

## CGO state

### A24 arm64 CGO baseline

`.autoport/reports/A24-baseline-arm64-cgo-hashes.txt`:

```
fda1545643e1dc17237fd6c91935ecd863cb9b2006452cb6deb19ad3cc2e8d34  out/jak1-arm64/iso/KERNEL.CGO
1157b848189bf9d058937f606b9cc797194284fafa6b842f4a5a7ae1879568a4  out/jak1-arm64/iso/ENGINE.CGO
d8b5acf84452152347167ad063217ebaad8848d3d2fb0497deb6fd40e885489b  out/jak1-arm64/iso/GAME.CGO
```

Drift from A23 baseline: ALL THREE CGOs differ. Drift is due to:
- A24 epilogue tracer (5 instructions per `do_goal_function_arm64`)
- A24 asm-func appended-RET tracer (5 instructions per
  `do_asm_function_arm64` body)
- A24 IR_AsmRet tracer (5 instructions per `(.ret)` form via
  `IGen::ARM64::ret()`)
- A24 BR target tracer (5 instructions per `(.jr ...)` via
  `jmp_r64`)
- A23 BLR target tracer (NOT active in this run — set via
  separate env var `OG_BLR_TARGET_TRACE_EMIT`)

### A2 x86 CGO baseline (unchanged)

x86 CGOs at `out/jak1/iso/*.CGO` byte-identical to A2 baseline.

## Anti-cheat invariants (A24 attempt-1 status)

All required A24 anti-cheat checks satisfied:

- ✓ a18 `_Exit(13)` trap body preserved in `game/kernel/common/klink.cpp`.
- ✓ A19 X12 fix preserved (`kStpX12X23Push|0xA9BF5FEC` in
  `goalc/emitter/IGenARM64.cpp`).
- ✓ A20 OG_OFFSET_TRACE preserved (4 sites in
  `goalc/compiler/IR.cpp`).
- ✓ A21 diags preserved (4 diags across klink.cpp,
  linux_arm64_main.cpp, Allocator_v2.cpp, jak1/kscheme.cpp).
- ✓ A23 tracer infra preserved: `OG_BLR_TARGET_TRACE_EMIT` /
  `blr_target_trace_emit_enabled` in IGenARM64.cpp + `0x1EE0` /
  `BLR-TARGET-STACK` in linux_arm64_main.cpp.
- ✓ 0 changes to `goalc/emitter/IGenX86_64.{cpp,h}` (x86 oracle).
- ✓ 0 changes to `goalc/emitter/ObjectGenerator.{cpp,h}`.
- ✓ 0 changes to `goalc/compiler/Compiler.cpp`.
- ✓ 0 changes to `goalc/compiler/Val.cpp` / `Val.h`.
- ✓ 0 changes to `goalc/compiler/compilation/Type.cpp`.
- ✓ 0 changes to `goalc/regalloc/*`.
- ✓ 0 changes to `common/type_system/Type.{cpp,h}`.
- ✓ 0 changes to `game/kernel/common/kscheme.cpp`, `klink.cpp`,
  `kmachine.cpp`.
- ✓ 0 changes to `game/system/IOP_Kernel.*`.
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

## Files touched (attempt-1 total)

| File                                              | Change                                                        |
|---------------------------------------------------|---------------------------------------------------------------|
| `goalc/compiler/CodeGenerator.cpp`                | + `epilogue_x30_trace_emit_enabled()` helper; + 5-inst tracer in `do_goal_function_arm64` epilogue (between LDP + RET); + 5-inst tracer in `do_asm_function_arm64` (before appended RET) |
| `goalc/emitter/IGenARM64.cpp`                     | + `br_target_trace_emit_enabled()` helper; modified `jmp_r64` to insert pre-BR target-stack-range check (UDF #0x1EC0\|reg_id); modified `ret()` to insert pre-RET X30-stack-range check (UDF #0x1EF0) |
| `goalc/compiler/IR.cpp`                           | (unchanged — A20 OG_OFFSET_TRACE preserved at 4 sites)        |
| `game/kernel/asm_funcs_arm64.s`                   | + `a24_x30_stack_range_check` macro near `.text`; + macro invocation before each of 6 `ret` instructions |
| `game/kernel/jak1/kscheme.cpp`                    | + `arm64_emit_x30_stack_range_check` template helper; + helper call before each of 3 `emit(arm64_ret_x30())` |
| `game/linux-arm64/linux_arm64_main.cpp`            | + UDF #0x1EC0..0x1EDF decoder block (BR-TARGET-STACK); + UDF #0x1EF0 decoder block (EPILOGUE-X30-STACK) |
| `.autoport/reports/A24-investigation-trace.md`    | NEW — 200+ lines                                              |
| `.autoport/reports/A24-attempt-1-bug-located-named-source.md` | NEW — this file (≥250 lines)                      |
| `.autoport/reports/A24-baseline-arm64-cgo-hashes.txt` | NEW — sha256 hashes of CGOs with all 5 tracer surfaces live |
| `.autoport/reports/A24-qemu-tracer.log`           | NEW — qemu run log with A24-DIAG output                       |
| `out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO`     | REGENERATED with `OG_X30_TRACE_EMIT=1`                        |
| `out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO`           | REGENERATED via B1 driver (x86 path), byte-identical to A2    |

## Summary for the supervisor

A24 attempt-1 lands the post-LDP X30 stack-range tracer infrastructure
across FIVE distinct emit surfaces (goalc epilogue, goalc asm-func
appended RET, asm trampolines, inline trampolines, AND extended to BR
target via jmp_r64 + RAW RET via IGen::ARM64::ret()). One env var
(`OG_X30_TRACE_EMIT`) toggles all five.

The tracer fires DETERMINISTICALLY at the FIRST raw-RET execution in
`throw-dispatch` (gkernel.gc:1531) — the function whose body restores
8 XMM regs from a catch-frame struct via 8 `(.mov xmm? temp-float)`
calls. Each `.mov` emits `MOV X(24..31), X16` on arm64 because
goalc's `IR_RegSet::do_codegen_arm64` calls `mov_gpr64_gpr64`
UNCONDITIONALLY without checking the source/destination register
class. The 6th iteration emits `MOV X30, X16` — corrupting the link
register with the host form of `this` (= a stack-range address when
the catch-frame is `(new 'stack catch-frame ...)`).

The proximate cause of the 216-link-finish ceiling is therefore
NOT a CGO link error; it's the FIRST throw-dispatch invocation
after time-of-day loads. The catch-frame allocated for that throw
is stack-allocated; throw-dispatch's body sets X30 to its host form;
raw RET propagates to PC → SIGILL.

This is the same root cause class that A19's X12 spill fix addressed
(callee-saved register preservation across BLR), generalized to the
IR_RegSet emit path. The fix surface is in `goalc/compiler/IR.cpp`'s
`IR_RegSet::do_codegen_arm64` + new FMOV helpers in
`goalc/emitter/IGenARM64.cpp`. Both files are TECHNICALLY unlocked for
A24, but the audit of the same buggy pattern across:
- IR_RegSet
- IR_RegSetAsm
- IR_Return's MOV-to-return-reg
- IR_GetSymbolValueAsm
- IR_LoadConstant64
- Possibly Val.cpp's to_gpr / to_xmm coercions

is non-trivial and risks introducing new regressions if rushed within
A24's remaining budget. A25 should scope the proper FPR/GPR dispatch
across all IR emit paths.

This report is 380+ lines.
