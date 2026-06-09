# A28 — arm64 codegen fix sprint: PATH A (boot advances)

## Result

**qemu link-finish count: 462** (baseline: 216 — advance of **+246**, more than
2.1×). x86 desktop boot still reaches `link finish: logo`. x86 CGOs
byte-identical to A2 baseline (unchanged by the arm64-only emit changes).

The 216 ceiling that A20–A27 spent eight phases diagnosing was broken by two
correlated fixes in the arm64 emitter, both targeting the same class of bug:
the arm64 backend mis-emulating x86-shaped GOAL asm-func semantics.

## What was broken (the two bugs)

### Bug 1 — `:reg rsp` → X4 instead of SP

The GOAL kernel's catch-frame ctor (`gkernel.gc:1483`) and throw-dispatch
(`gkernel.gc:1583`) declare a stack-pointer alias via `(rlet ((sp :reg rsp …)))`
and use it to capture / restore the host stack pointer:

```
;; catch-frame ctor — capture host SP into the frame
(set! temp sp)
(.sub temp off)
(set! (-> this sp) (the int temp))

;; throw-dispatch — restore it on unwind
(set! sp (the uint (-> this sp)))
(.add sp off)
```

The x86 register id for RSP is **4**. The arm64 backend's `arm64_reg5()` masks
the id to 5 bits and historically treated id 4 as **X4** — a normal GPR —
because the regalloc never assigns id 4 and the existing convention at
`IGenARM64.cpp:32-34` claimed "we always emit literal SP=31 below when we
mean the stack pointer". That contract only held for explicit `.push`/`.pop`
emits which hard-code SP=31. User-level `(set! sp value)` and `(set! reg sp)`
went through `mov_gpr64_gpr64(dst, src)` (ORR alias) which dutifully encoded
id 4 as X4.

Effect: catch-frame.sp captured X4's caller-leftover garbage instead of the
real SP, and throw-dispatch's `(set! sp (-> this sp)); (.add sp off)` wrote
to X4 instead of moving the real stack pointer. The throw-dispatch `.pop;
.push; .ret` epilogue then operated on the still-original (throw function's)
SP, so the supposed "restore catch-frame stack, jump to protectee" became
"corrupt throw's own stack, return into throw".

### Bug 2 — `.ret` on arm64 uses LR instead of popping the stack

GOAL asm-funcs (catch-frame ctor, throw-dispatch, reset-and-call,
return-from-thread, thread-suspend/resume, deactivate's RA overwrite,
enter-state) are x86-shaped:

- the caller's `call` is assumed to have pushed the return address on the stack
- the body uses `(.pop temp)` to read it (or `(.push temp)` to install a custom RA)
- `(.ret)` is assumed to pop the top-of-stack and jump

arm64 violates the first and third assumptions: BL/BLR write LR (X30)
rather than pushing, and RET reads X30 instead of popping. Without
compensation: `(.pop temp)` at the head of an asm-func reads stack garbage
(thread-suspend wrote that garbage to `this.pc` → subsequent
thread-resume jumped to it), and throw-dispatch's `(.push temp); (.ret)`
ignored the catch-frame's RA pushed onto the stack and RETurned to whatever
X30 still held (the throw function's call site), so the throw never unwound
to the protectee and the kernel busy-looped or fell into the
"throw could not find tag" trap.

This bug was masked by Bug 1 in the original failure: throw-dispatch
couldn't restore SP, so the corrupted-stack RET often segfaulted before the
.ret-vs-LR distinction could fire. After A28 fix-1 lands, the throw cleanly
reaches the `(.ret)` and the LR misuse becomes the next blocker — hence
A28 needed both fixes to land together.

## The fix

### Fix 1: `IGenARM64.cpp` — translate id 4 → SP in mov/add/sub

```cpp
// mov_gpr64_gpr64 (line 619+):
if (dst5 == 4u || src5 == 4u) {
  const uint32_t real_dst = (dst5 == 4u) ? 31u : dst5;
  const uint32_t real_src = (src5 == 4u) ? 31u : src5;
  uint32_t add_imm0 = 0x91000000u | (real_src << 5) | real_dst;
  return InstructionARM64(add_imm0);   // ADD Xd|SP, Xn|SP, #0  (MOV alias)
}
```

ARM64's MOV-via-ORR alias rejects SP as either operand (ORR encodes Rn=31 as
XZR, not SP). The canonical SP-aware MOV is `ADD Xd|SP, Xn|SP, #0` — the
immediate-add form treats Rn=31 / Rd=31 as SP. Same idea for `add_gpr64_gpr64`
and `sub_gpr64_gpr64`: the shifted-register encoding (0x8B000000 / 0xCB000000)
treats Rn=31 / Rd=31 as XZR, so we switch to the extended-register form
(0x8B206000 / 0xCB206000 with option=011=UXTX, imm3=0) which honours SP for
Rn/Rd. Rm=31 in extended-form is still XZR; the kernel's `(.add sp off)` /
`(.sub sp off)` patterns always have Rm = offset_reg (id 15), never id 4.

### Fix 2: asm-func prologue + IR_AsmRet epilogue

`CodeGenerator.cpp::do_asm_function_arm64`:

```cpp
// Prepend STR X30, [SP, #-16]! to save the caller's RA — making arm64
// asm-funcs look as if x86 `call` had pushed it.
constexpr uint32_t kStrX30PrependSP = 0xF81F0FFEu;
m_gen.add_instr_no_ir(f_rec, emitter::InstructionARM64(kStrX30PrependSP),
                      InstructionInfo::Kind::PROLOGUE);
```

`IR.cpp::IR_AsmRet::do_codegen_arm64`:

```cpp
// LDR X30, [SP], #16 ; RET — pop top-of-stack into X30, then RET.
// Reproduces x86 `ret` on arm64.
constexpr uint32_t kLdrX30PopSP = 0xF84107FEu;
gen->add_instr(emitter::InstructionARM64(kLdrX30PopSP), irec);
gen->add_instr(emitter::IGen::ARM64::ret(), irec);
```

Together the two changes re-establish the x86 contract for the entire family
of asm-func patterns: catch-frame's `.pop temp; .push temp` round-trip at
lines 1475-1480 (read + put back), thread-suspend's bare `.pop temp` to
capture the call's RA, throw-dispatch / reset-and-call / deactivate's
`.push X; .ret` to jump to a custom address. The leak when an asm-func ends
in `.jr` (no .ret) is 16 bytes of stack — harmless for the one-shot kernel
trampolines.

## Disasm before/after

**throw-dispatch SP restore (`gkernel.gc:1583-1584`)**

Before (X4 garbage):
```
697c: ldrsw x9, [x16, #8]    ; load this.sp
6984: mov x4, x9              ; X4 := SP — WRONG, touches a normal reg
6988: add x4, x4, x15         ; X4 += offset_reg — still WRONG
698c: ldr x0, [sp], #16       ; .pop using the OLD, unchanged SP
```

After (real SP):
```
697c: ldrsw x9, [x16, #8]
6984: mov sp, x9              ; 0x9100013F = ADD SP, X9, #0 — real SP
6988: add sp, sp, x15         ; 0x8B2F63FF = ADD SP, SP, X15 (UXTX)
698c: ldr x0, [sp], #16       ; .pop on the restored SP
```

**catch-frame SP capture (`gkernel.gc:1483-1485`)**

Before: `aa0403e0 mov x0, x4` (reads X4's garbage)
After:  `910003e0 mov x0, sp` (= ADD X0, SP, #0) — captures real SP

## Validator evidence

- qemu link-finish count: **462** (was 216). Last 10: pc-anim-util,
  autosplit-h, …, gsound. Goes well past the old throw-not-found trap
  into the gsound RPC subsystem.
- qemu exit: SIGABRT at gsound's `Assertion failed: 'rec->cmd.finished &&
  rec->cmd.started'` — a runtime RPC/Overlord layer assertion, NOT an
  arm64 codegen crash. This is a downstream blocker unmasked by the A28
  advance; out of scope for this phase.
- x86 desktop boot: reaches `link finish: logo` cleanly. x86 CGOs
  byte-identical to A2 baseline (the IGenARM64 + arm64-only CodeGenerator
  branch don't touch the x86 path; build_b1_arm64_cgos.sh verifies).
- No new weak/abort/dodge/stubs/fake-link printf. No edits to IGenX86,
  goal_src, or .autoport infra.

## Next blocker (unblocked surface, not A28 scope)

The gsound RPC assertion is in `game/overlord` or `game/sce` — a runtime
layer, not codegen. The `rec->cmd.finished && rec->cmd.started` invariant
is the OVERLORD RPC's "command pair must be matched". The arm64 build's
RPC stub or LoadDGOTest wrapper is likely not maintaining the started/
finished flags through the new code paths reached past link-finish 216.
A29 candidate: audit the linux-arm64 overlord stub set.

## Files changed

- `goalc/emitter/IGenARM64.cpp` — `mov/add/sub_gpr64_gpr64` get id-4→SP
  translation paths (~60 lines added).
- `goalc/compiler/CodeGenerator.cpp` — `do_asm_function_arm64` prepends
  `STR X30, [SP, #-16]!` (~50 lines added with rationale comment).
- `goalc/compiler/IR.cpp` — `IR_AsmRet::do_codegen_arm64` emits
  `LDR X30, [SP], #16; RET` instead of bare RET (~15 lines).
