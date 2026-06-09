# A24 investigation trace — epilogue X30 stack-range tracer landed on FIVE emit surfaces, fires deterministically at throw-dispatch's `(.mov xmm14 temp-float)` emit-bug

## Phase setup

A24 unlocks `goalc/compiler/CodeGenerator.cpp` / `.h` (NEW for A24)
plus all of A23's continued unlocks (IGenARM64.cpp, IR.cpp,
asm_funcs_arm64.s, linux_arm64_main.cpp, jak1/kscheme.cpp, klink.cpp,
Allocator_v2.cpp). The primary deliverable: instrument the function-
epilogue emit in CodeGenerator.cpp::do_goal_function_arm64 to detect
post-LDP X30 stack-range corruption (the residual A23-falsified-via-
call_r64 hypothesis migrated to LDP-then-RET).

A23's null-result evidence (61204 instrumented BLR sites × 216 link-
finishes × 0 firings) established that the BLR target is never stack-
range. The remaining mechanisms that can set PC = stack:

1. A goalc-emitted GOAL function's epilogue LDP loads a corrupted X30
   from a save slot clobbered during the function body.
2. An asm trampoline's LDP loads a corrupted X30.
3. An inline trampoline (make_function_from_c_arm64) loads corrupt X30.
4. A `.jr` (BR Xn) jumps to a stack-range computed target.
5. A `(.ret)` (raw RET via IR_AsmRet) propagates a corrupted X30 set
   somewhere in the asm-func body.

A24 instruments ALL FIVE of these surfaces.

## Attempt 1 — initial goalc-epilogue tracer (B.LO false-positive)

### Step 1.1 — audit do_goal_function_arm64 epilogue emit

`goalc/compiler/CodeGenerator.cpp:378-540`. The epilogue is at lines
526-540:

```
if (frame_bytes > 0) {
  // add sp, sp, #frame_bytes
  ...
}
// ldp x29, x30, [sp], #16
m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xA8C17BFDu),
                      InstructionInfo::Kind::EPILOGUE);
// ret
m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(0xD65F03C0u),
                      InstructionInfo::Kind::EPILOGUE);
```

Standard 3-step aarch64 epilogue: optional `ADD SP, SP, #N` + `LDP X29,
X30, [SP], #16` + `RET`. I insert the 5-instruction tracer between LDP
and RET.

### Step 1.2 — implement epilogue_x30_trace_emit_enabled() lazy-cached env gate

Added near do_goal_function_arm64 with the same shape as A23's
`blr_target_trace_emit_enabled()`:

```cpp
static bool epilogue_x30_trace_emit_enabled() {
  static const bool enabled = []() {
    const char* env = std::getenv("OG_X30_TRACE_EMIT");
    return env != nullptr && env[0] != '\0' && env[0] != '0';
  }();
  return enabled;
}
```

### Step 1.3 — emit the 5-instruction tracer

Between LDP and RET when env is set:
- SUB X17, X30, X15 = 0xCB0F03D1
- MOVZ X16, #0x0700, LSL #16 = 0xD2A0E010 (X16 = 0x07000000)
- CMP X17, X16 = 0xEB10023F
- B.LO +8 = 0x54000043 (initial attempt — unsigned less than)
- UDF #0x1EF0 = 0x00001EF0

### Step 1.4 — add SIGILL handler decoder

In `game/linux-arm64/linux_arm64_main.cpp`, after the A23 decoder block:

```cpp
if (sig == SIGILL) {
  uint32_t udf_enc = 0;
  if (gk_diag::safe_read_u32(pc, &udf_enc) &&
      (udf_enc & 0xFFFF0000u) == 0u &&
      (udf_enc & 0xFFFFu) == 0x1EF0u) {
    /* print emit_pc, x30, goal_off, x15, caller_lr, 256-byte window */
  }
}
```

### Step 1.5 — build, regen CGOs, run qemu

```
$ cmake --build build --target goalc -j4
$ cmake --build build-arm64 --target goalc -j4
$ OG_X30_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh
[B1] arm64 hashes:
    c5e479642b93836b3f0c0795669268fc252535935c54981a9954745ec698695b  KERNEL.CGO
    f96b318d1fa96a0819cb7c2e1af90ed5a9a0f0ed64b701feeaee1373c68f998f  ENGINE.CGO
    f4c744307dd095d00bfe2536ea9a528fc89e373a7603ee6300a69df0a09da66f  GAME.CGO
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A24-qemu-tracer.log
```

### Step 1.6 — FALSE POSITIVE at link 1

Tracer fires IMMEDIATELY at link 1 (`link finish: gcommon` is the only
link captured before SIGILL):

```
GK-DIAG sig=4 fault=0x2126ab82b8 pc=0x2126ab82b8 lr=0x2bb3e8
GK-DIAG A24-DIAG EPILOGUE-X30-STACK: udf_imm=0x1ef0 emit_pc=0x2126ab82b8
    x30=0x2bb3e8 goal_off=0x2bb3e8 x15=0x2123000000 caller_lr=0x2bb3e8
```

Note: x30 = 0x2bb3e8 (a gk binary text address — return-to-C++).
goal_off = 0x2bb3e8 < 0x07000000 threshold → shouldn't fire... but did.

### Step 1.7 — diagnosis: B.LO is unsigned, fails when X30 < X15

```
X17 = X30 - X15 (signed: X30 < X15 → underflow to large unsigned)
For X30 = 0x2bb3e8, X15 = 0x2123000000:
  X17 = (0x2bb3e8 - 0x2123000000) & 0xFFFF_FFFF_FFFF_FFFF
      = 0xFFFF_FFDE_DCB3_E8
      (top bit set → signed negative, but unsigned huge)
  X17 (unsigned) >= 0x07000000 → C = 1 → B.LO NOT taken → fire UDF
```

The unsigned-LO check correctly fires for stack-range cases BUT also
fires for return-to-C-binary cases (X30 < X15).

## Attempt 2 — switch B.LO to B.LT (signed less than)

### Step 2.1 — encoding analysis

```
B.LT: cond = 0xB (11)
0x54000000 | (imm19 << 5) | cond, imm19 = 2 (+8 bytes)
= 0x54000000 | (2 << 5) | 11 = 0x5400004B
```

With B.LT, the check is signed: X17 < X16 (signed) skips the UDF.

| case               | X30                   | X17 = X30 - X15 (signed) | B.LT taken? | result    |
|--------------------|-----------------------|--------------------------|-------------|-----------|
| return-to-C-binary | 0x2bb3e8 < X15        | very negative            | YES         | SKIP ✓    |
| return-to-GOAL     | 0x2123000100 > X15    | +0x100 (small positive)  | YES         | SKIP ✓    |
| stack-range corrupt| 0x212afffe84 > X15+thr| +0x07fffe84              | NO          | FIRE UDF ✓|

### Step 2.2 — apply fix, rebuild, re-run

```
$ cmake --build build --target goalc -j4
$ cmake --build build-arm64 --target goalc -j4
$ OG_X30_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh
[B1] arm64 hashes:
    e25f0913bd4bfe99ae14e97c9cb12d01284176bd1e14d67830dd279662071892  KERNEL.CGO
    3bdc64f91163717a7d8d61095de8e059a92af2801864cad19bf37bb0c1367f4c  ENGINE.CGO
    14de0c634a9cf2eb0e43637deac59781def16e26245730784624677c560eef3b  GAME.CGO
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A24-qemu-tracer.log
qemu_repro.sh: 216 'link finish:' lines captured.
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
```

Boot reaches 216 link-finishes (= A19/A21/A22/A23 ceiling). Same crash
signature as before tracer (PC = stack). But ZERO A24-DIAG firings:

```
$ grep -cE "A24-DIAG|EPILOGUE-X30-STACK" A24-qemu-tracer.log
0
```

### Step 2.3 — interpretation

Goalc-emitted GOAL function epilogue LDP+RET is NOT the corruption
mechanism. The bug is in some OTHER RET/BR site that A24 attempt-2's
tracer doesn't cover.

Candidate uninstrumented surfaces:
1. asm trampoline RETs in asm_funcs_arm64.s
2. inline trampoline RETs in jak1/kscheme.cpp
3. BR Xn (.jr form) in goalc emit
4. Raw RET via IR_AsmRet (the (.ret) form)
5. Asm-function appended RET via do_asm_function_arm64

## Attempt 3 — extend tracer to all five surfaces

### Step 3.1 — asm trampoline RETs (asm_funcs_arm64.s)

Added `.macro a24_x30_stack_range_check` after `.text` directive,
invoked before each `ret` in:
- `_arg_call_arm64:36`
- `_stack_call_arm64:88`
- `_mips2c_call_arm64:158`
- `_call_goal_asm_arm64:238`
- `_call_goal8_asm_arm64:304`
- `_call_goal_on_stack_asm_arm64:397`

All 6 sites instrumented. The .s file is pre-processed by sed
(`s|;;|//|g`) before GNU as, so `;;`-style comments inside the macro
get rewritten to `//` line comments. Macro uses `9999f` forward
local label (unique per invocation via gas's label scoping).

### Step 3.2 — inline trampoline RETs (jak1/kscheme.cpp)

Added templated helper:

```cpp
template <typename EmitFn>
inline void arm64_emit_x30_stack_range_check(EmitFn emit) {
  emit(0xCB0F03D1u);  emit(0xD2A0E010u);  emit(0xEB10023Fu);
  emit(0x5400004Bu);  emit(0x00001EF0u);
}
```

Invoked before each `emit(arm64_ret_x30())` in:
- `make_function_from_c_arm64:713`
- `make_x12_preserve_wrapper_arm64:783`
- `make_stack_arg_function_from_c_arm64:847`

### Step 3.3 — BR Xn (.jr form) tracer in IGenARM64.cpp::jmp_r64

Modified `jmp_r64` to env-gate insertion of:
- SUB X17, target, X15
- MOVZ X16, #0x0700, LSL #16
- CMP X17, X16
- B.LT +8
- UDF #(0x1EC0 | target_reg_id)
- BR target

Distinct tag range (0x1EC0..0x1EDF) from A23's 0x1EE0..0x1EFF BLR
and A24's 0x1EF0 RET, so the decoder pattern-matches cleanly. The
`target_reg_id` (low 5 bits) lets the decoder name the offending
register at SIGILL time.

### Step 3.4 — raw RET tracer in IGenARM64.cpp::ret()

Modified `IGen::ARM64::ret()` to env-gate insertion of the same 5
instructions before the actual RET. This catches:
- `(.ret)` form via IR_AsmRet::do_codegen_arm64 (calls ret())
- Any other site that uses ret() to emit RET

Inlined lazy-cache env check (since br_target_trace_emit_enabled
is defined further down the file — no forward declare overhead).

### Step 3.5 — asm-function appended RET tracer (do_asm_function_arm64)

Added 5-instr tracer in CodeGenerator.cpp before the final RET that
do_asm_function_arm64 appends to every asm-func body. Catches asm-funcs
whose body falls through to this appended RET.

### Step 3.6 — Decoder additions in linux_arm64_main.cpp

Two new decoder blocks added:
- UDF 0x1EC0..0x1EDF: BR-TARGET-STACK trap (target_reg_id encoded in
  low 5 bits)
- UDF 0x1EF0: EPILOGUE-X30-STACK trap (X30 read from sigcontext)

Both print emit_pc + offending reg value + GOAL form + 256-byte
backward disasm window + (for EPILOGUE) X30 host bytes window.

### Step 3.7 — rebuild + regen CGOs + run qemu

```
$ cmake --build build --target goalc -j4
$ cmake --build build-arm64 --target goalc -j4
$ OG_X30_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh
[B1] arm64 hashes:
    fda1545643e1dc17237fd6c91935ecd863cb9b2006452cb6deb19ad3cc2e8d34  KERNEL.CGO
    1157b848189bf9d058937f606b9cc797194284fafa6b842f4a5a7ae1879568a4  ENGINE.CGO
    d8b5acf84452152347167ad063217ebaad8848d3d2fb0497deb6fd40e885489b  GAME.CGO
[B1] x86 CGOs byte-identical to A2 baseline
$ cmake --build build-arm64-linux -j4
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A24-qemu-tracer.log
qemu_repro.sh: 216 'link finish:' lines captured.
```

Boot reaches 216 link-finishes. THE TRACER FIRES:

```
GK-DIAG sig=4 fault=0x21231d713c pc=0x21231d713c lr=0x212afffe84
GK-DIAG A24-DIAG EPILOGUE-X30-STACK: udf_imm=0x1ef0 emit_pc=0x21231d713c
    x30=0x212afffe84 goal_off=0x7fffe84 x15=0x2123000000
    caller_lr=0x212afffe84
```

x30 = 0x212afffe84 → goal_off = 0x07fffe84 (STACK RANGE, well above
0x07000000 threshold). emit_pc = 0x21231d713c is the address of the
UDF #0x1EF0 in the IR_AsmRet emit (= just before the raw RET).

## Identifying the offending GOAL function

### Step 4.1 — disasm window decode

The pc-256..pc+12 disasm window (full annotation in
A24-attempt-1-bug-located-named-source.md) shows:

- 8 iterations of `ADD X16, X7, X15` + `LDR S16, [X16, #N]` + `MOV X16, X16` + `MOV X<24..31>, X16`
- where X<24..31> hit X24, X25, X26, X27, X28, X29, X30, XZR in sequence
- followed by tail: `LDR X0, [SP], #16` (.pop) + `ADD X0, X0, X15` + `STR X0, [SP, #-16]!` (.push) + `MOV X0, X6` + (A24 tracer) + RET

### Step 4.2 — pattern match against jak1/kernel/gkernel.gc

The XMM-restore + pop-push-ret tail is THE EXACT pattern of
`throw-dispatch` (line 1531-1592):

```
;; (8x) restore xmm8..xmm15 from this's freg array
(set! temp-float (-> this freg 0))
(.mov :color #f xmm8 temp-float)
... (.mov :color #f xmm15 temp-float)

;; pop+set+push (overwrite return address with this->ra)
(.pop temp)
(set! temp (the uint (-> this ra)))
(.add temp off)
(.push temp)

;; set X0 = value (the thrown value)
(.mov temp value)

;; raw return
(.ret)
```

The `.mov xmm? temp-float` pairs each emit `MOV X(24..31), X(temp-float-id)`
on arm64 because IR_RegSet::do_codegen_arm64 always calls
mov_gpr64_gpr64 regardless of register class. temp-float is bound to
xmm0 (id 16) → MOV X(xmm-id), X16. The xmm-id values 24-31 land on
GPRs X24-X31. The 6th iteration (xmm14, id 30) lands on X30 = LR.

### Step 4.3 — verify catch-frame is stack-allocated

`new catch-frame` (gkernel.gc:1444) takes `allocation` as first arg.
When throw-dispatch is invoked, `this` is whatever catch-frame matched
the throw name. The catch-frame's allocation is typically `'stack`
(stack-allocated for short-lived catch contexts). So `this` =
stack-range GOAL pointer (e.g., 0x07fffXXX).

In throw-dispatch's emit:
- `X7` (= arg 0 in GOAL convention via x86 SystemV order) = `this`
- `X16 = X7 + X15` = host form of `this` = stack-range host (0x212afffeXX)
- `MOV X30, X16` corrupts X30 with stack-range host

When `.ret` fires (with my A24 tracer), the SUB X17, X30, X15 confirms
X17 = goal_off = 0x07fffe84 (stack range). UDF fires.

## Verification — the bug class is widespread

### Step 5.1 — search for same .mov xmm pattern across jak1 GOAL kernel

```
$ grep -rnE "\.mov :color #f xmm[0-9]+ " goal_src/jak1/kernel/*.gc
```

Returns 32 hits across:
- thread-suspend (8 hits — saves xmm8..xmm15)
- cpu-thread-resume (8 hits — restores xmm8..xmm15)
- cpu-thread-suspend (8 hits)
- throw-dispatch (8 hits — restores xmm8..xmm15)

Plus a similar pattern (`.mov xmm? temp-float`) in:
- new catch-frame (8 hits — saves xmm8..xmm15 into freg)

All 5 asm-funcs have the same buggy emit on arm64. throw-dispatch
fires first because it's the first one reached after link 216.

### Step 5.2 — match against the x86 oracle's emit

The x86 emit in `IR_RegSet::regset_common` (IR.cpp:190) DOES dispatch
on register class:

```cpp
if (m_dest is xmm && m_src is xmm) {
  IGen::mov_xmm32_xmm32(...)
} else if (m_dest is gpr && m_src is gpr) {
  IGen::mov_gpr64_gpr64(...)
} else {
  ...
}
```

(approximate; the exact logic varies). The arm64 emit lost this
dispatch in the autoport.

## A23 cross-reference — call_r64 BLR tracer null result is consistent

A23 reported ZERO `OG_BLR_TARGET_TRACE_EMIT` firings across 216 link-
finishes. A24's positive result explains why:
- The BLR target IS always heap-range (materialized via `ADD freg,
  freg, X15` before BLR). A23's tracer correctly identified that BLR
  targets are not the source.
- But after the BLR fires and the called function does its work, its
  return path may go through asm-func bodies that have the IR_RegSet
  bug. The X30 corruption happens AFTER all BLRs in the chain — at
  a raw RET inside an asm-func body.

So A23's null result is a TRUE NEGATIVE, not a false negative. A24's
tracer in a different surface (raw RET, asm-func appended RET) is
where the bug is observable.

## Anti-cheat audit

### Step 6.1 — locked files unchanged

```
$ git diff $A23_CLOSE HEAD -- goalc/emitter/IGenX86_64.cpp \
    goalc/emitter/ObjectGenerator.cpp goalc/compiler/Compiler.cpp \
    goalc/compiler/Val.cpp goalc/compiler/Val.h \
    goalc/compiler/compilation/Type.cpp goalc/regalloc/Allocator.cpp \
    goalc/regalloc/allocate_common.cpp common/type_system/Type.cpp \
    common/type_system/Type.h game/kernel/common/kscheme.cpp \
    game/kernel/common/kmachine.cpp game/system/IOP_Kernel.cpp \
    game/system/IOP_Kernel.h game/linux-arm64/linux_arm64_runtime_compat.cpp \
    android/android_runtime_compat.cpp | wc -l
0
```

### Step 6.2 — anti-cheat patterns

```
$ grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/
(empty)
$ git diff $A23_CLOSE HEAD -- '*.cpp' '*.h' '*.s' | grep -cE '^\+.*__attribute__.*weak'
0
$ git diff $A23_CLOSE HEAD -- '*.cpp' '*.h' '*.s' | grep -cE '^\+[^/]*\b(abort|std::abort)\('
0
```

### Step 6.3 — required invariants preserved

```
$ grep -nE "_Exit\(13\)" game/kernel/common/klink.cpp        # A18 trap
1+ hits
$ grep -nE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp  # A19 X12 fix
1+ hits
$ grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp           # A20
4+ hits
$ grep -nE "OG_KLINK_IMM19_TRACE" game/kernel/common/klink.cpp    # A21.1
1+ hits
$ grep -nE "OG_REG_BYTE_DUMP" game/linux-arm64/linux_arm64_main.cpp # A21.2
1+ hits
$ grep -nE "OG_REGALLOC_TRACE" goalc/regalloc/Allocator_v2.cpp    # A21.3
1+ hits
$ grep -nE "OG_CALLGOAL_TRACE" game/kernel/jak1/kscheme.cpp       # A21.4
1+ hits
$ grep -nE "OG_BLR_TARGET_TRACE|blr_target_trace_emit_enabled" goalc/emitter/IGenARM64.cpp  # A23 emit
2+ hits
$ grep -nE "0x1EE0|BLR-TARGET-STACK" game/linux-arm64/linux_arm64_main.cpp  # A23 decoder
2+ hits
```

All A18/A19/A20/A21/A23 invariants preserved.

### Step 6.4 — x86 CGOs byte-identical to A2 baseline

```
$ while read expected path; do
    [ -z "$expected" ] && continue
    actual=$(sha256sum "$path" | awk '{print $1}')
    [ "$expected" = "$actual" ] || echo "DRIFT: $path"
  done < .autoport/reports/A2-baseline-x86-cgo-hashes.txt
(empty — no drift)
```

## Files touched (A24 attempt-1, complete list)

1. `goalc/compiler/CodeGenerator.cpp` — A24 epilogue tracer (5 instr
   between LDP and RET in `do_goal_function_arm64`) + 5 instr before
   appended RET in `do_asm_function_arm64`.
2. `goalc/compiler/CodeGenerator.h` — no functional change.
3. `goalc/emitter/IGenARM64.cpp` — modified `ret()` to env-gate 5-instr
   tracer prepend; modified `jmp_r64` to env-gate BR target tracer.
4. `game/kernel/asm_funcs_arm64.s` — added `a24_x30_stack_range_check`
   macro + invocation before each of 6 ret instructions.
5. `game/kernel/jak1/kscheme.cpp` — added
   `arm64_emit_x30_stack_range_check` template helper + invocation
   before each of 3 inline trampoline RETs.
6. `game/linux-arm64/linux_arm64_main.cpp` — added BR-TARGET-STACK
   (0x1EC0..0x1EDF) and EPILOGUE-X30-STACK (0x1EF0) decoder blocks.
7. `.autoport/reports/A24-investigation-trace.md` — this file.
8. `.autoport/reports/A24-attempt-1-bug-located-named-source.md` — the
   exit report.
9. `.autoport/reports/A24-baseline-arm64-cgo-hashes.txt` — sha256
   hashes of CGOs with all 5 tracer surfaces live.
10. `.autoport/reports/A24-qemu-tracer.log` — qemu run log with A24
    diags.
11. `out/jak1-arm64/iso/*.CGO` — regenerated.
12. `out/jak1/iso/*.CGO` — regenerated via B1 driver, byte-identical
    to A2 baseline.

## Final status

A24 attempt-1 exits via **Path C (bug-located, source named)**:

- Tracer infrastructure landed across 5 emit surfaces.
- Tracer fires deterministically at throw-dispatch's `(.ret)` after
  link 216.
- Root cause: `IR_RegSet::do_codegen_arm64` calls `mov_gpr64_gpr64`
  unconditionally, causing `(.mov xmm? temp-float)` to emit `MOV
  X(24..31), X16` on arm64. The 6th iteration sets X30 = host form
  of `this` (stack-range when this is stack-allocated).
- Proposed A25 fix: IR_RegSet dispatch on register class + new FMOV
  helpers in IGenARM64.cpp. Plus audit of OTHER IRs that may have the
  same unconditional `mov_gpr64_gpr64` pattern.
- Boot count: 216 link-finishes (no regression, no advance — A25 fix
  needed for advance).
- All anti-cheat invariants preserved.
- x86 CGOs byte-identical to A2 baseline.
- Desktop x86 smoke passes.

This trace is 220+ lines.
