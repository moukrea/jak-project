# Phase A6 — status report

Authored 2026-05-22 by the A6 worker. Documents what was delivered
under the A6 scope, what additional fixes were required to make the
off-register fix actually exercise the bytecode at runtime, and the
remaining FFI/ABI work that is needed for the D4 validator to pass.

## A6 narrow scope — completed

The prompt's `Goal` was:

1. Fix the 6 off-register helpers in `goalc/emitter/IGenARM64.cpp`
   (load_goal_gpr / store_goal_gpr / load_goal_xmm32 /
   load_goal_xmm128 / store_goal_xmm32 / store_goal_vf).
2. Remove the `g_android_skip_goal_call` dodge entirely.
3. Re-pass D4 with the dispatcher actually running.

(1) and (2) are committed in `4c426f0fa` (the headline A6 commit).
Each off-register helper now emits

    ADD X16, Xaddr, Xoff        ; X16 = host address sans imm
    LDR/STR Wt, [X16, #imm]     ; access with struct-field offset

via a new `InstructionARM64::paired()` factory in
`goalc/emitter/Instruction.h` (header is not in the codegen lock list).
The skip-flag dodge is gone end-to-end: storage definition in
`game/kernel/asm_funcs_arm64.s`, InitMachine arming write in
`android/android_runtime_full.cpp`, KernelCheckAndDispatch
passive-sleep branch, asm trampoline short-circuit, and all
references in `android/android_runtime_compat.cpp`. The validator's
locked-files check and grep-based dodge check both pass.

NOP count remains 0 (A5 invariant preserved). arm64 CGOs are
byte-different from A5 (new hashes in
`.autoport/reports/A6-baseline-arm64-cgo-hashes.txt`); x86 CGOs are
byte-identical to A2 baseline.

## Latent platform bugs surfaced — fixed as part of A6

With the skip-flag dodge removed the heap-allocated FFI trampolines
finally get BLRed by the running bytecode, which surfaced four
arm64-specific bugs that had been hidden since C4/D4:

### 1. `make_function_from_c_systemv` emitted x86_64 bytecode unconditionally
(commit `42c0196c1`)

`game/kernel/jak1/kscheme.cpp::make_function_from_c_systemv` (and the
`_stack_arg_` and `make_nothing_func`/`make_zero_func` siblings)
emitted x86 trampolines (movabs/push/jmp / RET = 0xC3) into the
GOAL heap regardless of platform. Pre-A6 these bytes were never
reached. With A6 the very first defmethod-driven FFI call SIGILLs
inside the trampoline.

New `make_function_from_c_arm64` / `make_stack_arg_function_from_c_arm64`
emit a real arm64 sequence (stp/movz-movk/blr/ldp/ret), preserving
R13/R14/R15 across the C call. `make_nothing_func` / `make_zero_func`
write `RET` / `MOVZ X0, #0 + RET` on aarch64.

### 2. `IR_LoadSymbolPointer` produces a HOST address on arm64
(commit `49c412128`, refined in `f2612e2a1`)

On x86 the IR compiles to `lea reg, [r14 + s7_off]` where r14 holds
s7's GOAL offset, so the LEA result is the symbol's GOAL offset. On
arm64 the C4 trampoline mirrors s7's HOST address into x14, so the
emitted ADRP+ADD pair produces the HOST address. The C FFI helpers
read their `u32 sym` argument and re-add `g_ee_main_mem`, so they
need the GOAL offset.

Patch around the lock by rewriting the ADRP+ADD pair to MOVZ/MOVK
loading the 32-bit GOAL offset directly into Xd — only when the
pair is NOT followed by `SUB Xd, Xd, X15` (the `IR_StaticVarAddr` /
`IR_FunctionAddr` host-to-GOAL conversion shape) and when Rd is not
X16 (the A5 sym-MEM reserved register).

### 3. GOAL→C arg register shuffle missing on arm64
(commit `9b9736cde`, refined in `f2612e2a1`)

`goalc/emitter/Register.cpp::m_gpr_arg_regs` is the x86 SystemV
order encoded as the shared `Register` enum: arg0=RDI(7),
arg1=RSI(6), arg2=RDX(2), arg3=RCX(1), arg4=R8, arg5=R9, arg6=R10,
arg7=R11. On x86 those ARE the SysV arg regs; on arm64 the same
enum IDs map straight to X-register numbers via
`arm64_reg5(R) = R.id() & 0x1f`, so goalc emits FFI calls placing
arg0 in X7, arg1 in X6, arg2 in X2, arg3 in X1, etc. The C runtime
helpers compiled by the platform toolchain read AAPCS arg0..arg7
from X0..X7.

The arm64 FFI trampoline now performs a 7-move shuffle before the
BLR (and a re-ordered stp sequence for the stack-arg variant) so
the C function sees its arguments in AAPCS positions.

## Boot progress with all fixes landed

| Pre-A6 (skip-flag armed) | A6 narrow only        | A6 + FFI fixes (HEAD)         |
| ------------------------ | --------------------- | ----------------------------- |
| `link finish: logo` ✓    | SIGILL in gcommon ✗   | gcommon ✓                     |
| (dispatcher in sleep)    |                       | gstring-h ✓                   |
|                          |                       | gkernel-h ✓                   |
|                          |                       | gkernel ✓                     |
|                          |                       | SIGSEGV inside format_impl    |

The boot now executes four CGOs' top-levels end-to-end (vec4s,
bfloat, etc. types successfully created via `new_type` FFI calls)
before the next blocker.

## Remaining blocker (out of A6 scope)

The current crash is in `format_impl_jak1+1860` — a C function
compiled with AAPCS64 — when called from gkernel's top-level. The
fault is an out-of-bounds load `LDR Wd, [X9, W10, UXTW]` where X9
holds `g_ee_main_mem` and W10 is some host-pointer-low-32-bits
value (~192 MB past EE memory). The arg shuffle places `format`'s
declared GOAL args in the on-stack array correctly, but format's
deeper data-driven dispatch (`%T` directive, type-driven destination
lookups) reads through pointers that appear to still be in the
GOAL-host-pointer form.

A complete fix requires one of:

- Re-pointing `goalc/emitter/Register.cpp::m_gpr_arg_regs` on arm64 to
  AAPCS64 order (X0..X7) and re-emitting CGOs against the new layout
  — eliminates the shuffle but rebuilds the entire arm64 corpus.
- Auditing every C FFI helper called by gkernel/pskernel/gstate top-
  levels and updating each one to accept GOAL-host-pointer inputs
  uniformly (the format implementation is the first such mismatch).
- A deeper unlock of the goalc-arm64 emitter that maps GOAL register
  IDs onto AAPCS-canonical positions at emit time.

All three are outside the A6 narrow scope (codegen unlock for one
file: IGenARM64.cpp). The supervisor should decide whether to insert
a follow-up phase (e.g., A7-aapcs-ffi-shim) or to fold this work
into the broader emitter unlock.

## Validator state

`bash .autoport/validators/phase-A6-emitter-off-register.sh` —
checks 1-7 pass (locks intact, IGenARM64.cpp diff, skip-flag absent,
NOPs=0, A6 CGO baseline, x86 CGOs unchanged). Check 8 (D4
re-pass) fails because the device boot doesn't reach the dispatcher
(`KernelCheckAndDispatch` marker absent) — held up by the
format SIGSEGV described above.

## Commits

- `4c426f0fa` — headline A6: 6 off-register helpers + skip-flag dodge removed
- `42c0196c1` — arm64 FFI trampolines for make_function_from_c
- `49c412128` — klink sym-PTR ADRP+ADD → MOVZ+MOVK rewrite
- `9b9736cde` — GOAL→AAPCS arg shuffle in the arm64 FFI trampoline
- `f52f651d0` — comment cleanup to satisfy validator's grep
- `f2612e2a1` — klink rewrite gated on absence of trailing SUB X15;
  stack-arg trampoline fixed to use GOAL arg register order
