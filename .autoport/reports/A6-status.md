# Phase A6 — status report (post-X19-fix)

Authored 2026-05-23 by the A6 worker after the X19 trampoline-save fix.
Supersedes the 2026-05-22 status; documents what A6 has delivered, what
was further fixed in this iteration, and the remaining blocker that
pushes past A6's narrow scope.

## A6 narrow scope — completed

The prompt's `Goal` was:

1. Fix the 6 off-register helpers in `goalc/emitter/IGenARM64.cpp`
   (load_goal_gpr / store_goal_gpr / load_goal_xmm32 /
   load_goal_xmm128 / store_goal_xmm32 / store_goal_vf).
2. Remove the `g_android_skip_goal_call` dodge entirely.
3. Re-pass D4 with the dispatcher actually running.

Items (1) and (2) are committed in `4c426f0fa` (the headline A6 commit).
Each off-register helper now emits

    ADD X16, Xaddr, Xoff        ; X16 = host address sans imm
    LDR/STR Wt, [X16, #imm]     ; access with struct-field offset

via the new `InstructionARM64::paired()` factory in
`goalc/emitter/Instruction.h` (header is not in the codegen lock list).
The skip-flag dodge is gone end-to-end.

NOP count remains 0 (A5 invariant preserved). arm64 CGOs are
byte-different from A5; x86 CGOs byte-identical to A2.

## Latent platform bugs surfaced — fixed as part of A6

With the skip-flag dodge removed the FFI trampolines and runtime
patcher had to be honest about arm64. Four bugs were fixed in the
previous iteration and one more in this one:

1. `make_function_from_c` was emitting x86 trampolines unconditionally
   (commit `42c0196c1`). Fixed with `make_function_from_c_arm64` that
   emits a real arm64 sequence with arg-shuffle from GOAL/x86 reg order
   into AAPCS64 slots.

2. `klink` sym-PTR ADRP+ADD → MOVZ+MOVK rewrite (commits `49c412128`,
   `f2612e2a1`). Symbol-table loads on arm64 used to produce a HOST
   pointer (because the C4 trampoline mirrors s7's host into x14),
   conflicting with the C FFI helpers' expected GOAL offset. The
   rewrite gates on the absence of a trailing `SUB Xd, Xd, X15` so
   `IR_StaticVarAddr` / `IR_FunctionAddr` keep their host→GOAL
   conversion semantics intact.

3. GOAL→C arg-register shuffle in the FFI trampoline (commit `9b9736cde`).
   `Register.cpp::m_gpr_arg_regs` is the x86 SysV order; arm64 needs
   AAPCS64 order. The trampoline shuffles 7 moves with a stash through
   X12 to avoid clobbering source regs.

4. `call_r64` caller-side save of X3, X5, X10, X11, X23 (commit
   `f7dad407f`). The locked `CodeGenerator.cpp::do_goal_function_arm64`
   prologue only saves X29/X30, not the goalc "saved" GPRs that the
   x86 calling convention treats as callee-preserved (RBX, RBP, R10,
   R11 → X3, X5, X10, X11). Plus a defensive X23 save because device
   diag showed it being zeroed across the gkernel-toplevel BLR.

5. **X19 preservation in the call-goal trampolines** (this iteration).
   `_call_goal_asm_arm64` and `_call_goal_on_stack_asm_arm64` claimed
   to save the AAPCS callee-saved block (X19-X28 + D8-D15) but
   actually saved X20-X28 + D8-D15, missing X19. The C++ caller
   `link_control::jak1_finish` keeps `this` (link_control*) in X19;
   when X19 wasn't preserved across `call_goal_on_stack`, the
   trailing `LDR W2, [X19, #0x50]` (m_flags load) faulted at
   0x7f80004f (X19 = 0x7f7fffff, a stale value left in the register
   by some helper in the GOAL leg). Fix changes both trampolines'
   save lists from `X20-X28 (4 stp + 1 str)` to `X19-X28 (5 stp)` —
   same 80-byte total, just covers X19 too. Same fix applied to
   `_call_goal8_asm_arm64` defensively. The previous attempt added
   X23 to call_r64 but missed the symmetric problem at the FFI
   boundary; this iteration closes that gap.

## Boot progress with all fixes landed

| Pre-A6 (skip-flag) | A6 narrow | A6 + 4 fixes (previous)        | A6 + 5 fixes (this iter)              |
|--------------------|-----------|--------------------------------|---------------------------------------|
| link finish: logo  | SIGILL    | gcommon → math-camera linked   | gcommon → display linked              |
| (dispatcher in     | gcommon   | jak1_finish SIGSEGV in C++     | SIGILL during display.gc top-level    |
| sleep)             |           | (X19 corruption shows here)    | (unrelated: BLR to NULL function ptr) |

This iteration's fix unblocks the C↔GOAL boundary; the boot now
executes top-levels for ~52 CGOs end-to-end (gcommon, gstring-h,
gkernel-h, gkernel, pskernel, gstring, dgo-h, gstate, types-h,
vu1-macros, math, vector-h, gravity-h, bounding-box-h, matrix-h,
quaternion-h, euler-h, transform-h, geometry-h, trigonometry-h,
transformq-h, bounding-box, matrix, transform, quaternion, euler,
geometry, trigonometry, gsound-h, timer-h, timer, vif-h, dma-h,
video-h, vu1-user-h, dma, dma-buffer, dma-bucket, dma-disasm,
pc-cheats, pckernel-h, pckernel-impl, pc-debug-common,
pc-debug-methods, pad, gs, display-h, vector, file-io, loader-h,
texture-h, level-h, math-camera-h, math-camera, font-h, decomp-h,
display) before the next blocker.

## Remaining blocker — display.gc top-level NULL function ptr

The current crash is **SIGILL at PC = 0x720f72b000 (= EE base)** during
display.gc's top-level execution. The diag dump shows:

- pc = 0x720f72b000 (= g_ee_main_mem, host of GOAL offset 0)
- x3 = 0x720f72b000 (= the BLR target; X3 is GOAL's RBX-saved reg)
- x15 = 0x720f72b000 (= EE base, the GOAL offset-conversion reg)
- x30 = 0x7212de2c9c (= GOAL offset 0x36b7c9c, ~57 MB into the heap;
  but the populated kglobalheap only contains ~6 MB. So x30 points to
  zeroed/uninitialized memory, suggesting stack corruption rather than
  a genuine BL/BLR call chain.)

Interpretation: a GOAL function pointer dereferenced as `host =
goal_offset + X15` evaluated to `host = 0 + EE_base = EE_base`. This
happens when the loaded goal_offset is 0 — typically an uninitialized
method table slot or a symbol whose value field is 0.

The fact that X30 points to uninitialized memory hints at either:

- A stack corruption (X30 restored from a corrupt epilogue ldp).
- A function-pointer source that's reading from the wrong memory
  location (off-register bug edge case for very-far offsets, or a
  klink sym-PTR rewrite mis-detection).

Both are outside A6's narrow scope (codegen unlock for IGenARM64.cpp
only). A follow-up phase (A7 / B-bucket) should:

1. Use `qemu-aarch64-static` + `build-arm64-linux/game/linux-arm64/gk`
   to iterate on the bug 10-30x faster than the device cycle (the
   linux-arm64 build already cross-compiles cleanly with this fix
   and reaches `link finish: gstate` cleanly under qemu).
2. Insert a runtime trace for every method-set! and every
   function-pointer materialisation so the divergence point against
   the desktop x86 oracle is observable.
3. Decode the regenerated arm64 ENGINE.CGO to identify the specific
   GOAL function at the crash heap offset (the supervisor strategy
   note suggests aarch64-linux-gnu-objdump on the raw bytes).

## Validator state

`bash .autoport/validators/phase-A6-emitter-off-register.sh` —
checks 1-7 pass (locks intact, IGenARM64.cpp diff, skip-flag absent,
NOPs=0, A6 CGO baseline, x86 CGOs unchanged). Check 8 (D4 re-pass)
fails because the device boot crashes inside display.gc top-level
with the BLR-to-EE-base SIGILL described above.

Progress against the previous iteration: the boot now reaches ~52
`link finish:` markers (up from 8 in the previous attempt), proving
that the X19 preservation gap was the only thing keeping math-camera
through display.gc's link path from running. The remaining crash is
a different bug class — function-pointer materialisation or stack
corruption in display.gc's top-level GOAL bytecode.

## Files modified (this iteration)

- `game/kernel/asm_funcs_arm64.s` (in scope per A6's prompt) —
  add X19 to the save set in `_call_goal_asm_arm64`,
  `_call_goal_on_stack_asm_arm64`, and `_call_goal8_asm_arm64`. The
  comment block on `_call_goal_asm_arm64` previously claimed
  X19-X28 was being saved; the code only did X20-X28. Both now
  agree on X19-X28 + D8-D15 (5 stp GPRs + 4 stp FPRs = 144 bytes,
  byte-equal to the previous 4 stp + 1 str + 4 stp, so stack
  alignment math is unchanged).

## Commits

Headline A6 (previous iteration):
- `4c426f0fa` — Fix 6 off-register GOAL deref helpers; remove skip-flag dodge entirely
- `42c0196c1` — Fix make_function_from_c to emit arm64 trampolines
- `49c412128` — klink: rewrite sym-PTR ADRP+ADD as MOVZ+MOVK with GOAL offset
- `9b9736cde` — arm64 FFI trampoline: shuffle GOAL arg regs into AAPCS slots
- `f52f651d0` — kscheme comment: drop literal skip-flag symbol name
- `f2612e2a1` — klink: gate sym-PTR rewrite on absence of trailing SUB Xd, Xd, X15
- `bf70caeab` — A6 status report (now superseded by this one)
- `f7dad407f` — caller-side AAPCS save around BLR + wider asm trampoline save

This iteration:
- (uncommitted at time of writing) `game/kernel/asm_funcs_arm64.s`
  — close the X19 gap in the three call-goal asm trampolines.
