# Phase A6 — emitter off-register fix + skip-flag dodge removal

## Status

**Authored 2026-05-22 by the supervisor** in response to F1's
blocker analysis (`.autoport/reports/F1-blocker-analysis.md`). The
F1 worker diagnosed precisely why the GOAL VM has not actually been
running on Android since D4 closed: a 6-function off-register bug in
`goalc/emitter/IGenARM64.cpp` that drops the EE-base register from
every GOAL pointer dereference. D4/A5/E1/E2/E3 all "passed" with the
`g_android_skip_goal_call` dodge still armed (dispatcher in passive
50 ms sleep loop) — that's why F1 can't reach gameplay.

A6 is a narrow codegen unlock for the one file containing the fix.
After A6, the skip-flag dodge gets **completely removed** (storage
def, InitMachine arming, KernelCheckAndDispatch branch, asm trampoline
short-circuit), so it can never silently re-arm.

## Bucket

A — emitter / linker (codegen layer).

## Goal (precise, diagnosis-driven)

1. Fix 6 functions in `goalc/emitter/IGenARM64.cpp`
   (lines ~940-1080 per F1-blocker-analysis.md):
   - `load_goal_gpr`
   - `store_goal_gpr`
   - `load_goal_xmm32`
   - `load_goal_xmm128`
   - `store_goal_xmm32`
   - `store_goal_vf`
   Each currently does `(void)off;` and emits `LDR/STR Wt, [Xn, #imm12]`,
   dropping the EE-base offset register. Fix: emit
   `ADD X16, Xaddr, X15` followed by `LDR/STR Wt, [X16, #imm12]`,
   where X15 holds the EE base. X16 is the existing scratch
   reserved by A5 (regalloc caps at R10 / X9; X16/X17 are free).
2. Regenerate CGOs (same pipeline A5 used).
3. Delete the skip-flag dodge **entirely**:
   - Remove storage definition of `g_android_skip_goal_call` from
     `game/kernel/asm_funcs_arm64.s` (the A5 audit moved it there).
   - Remove the InitMachine arming write in
     `android/android_runtime_full.cpp` (currently around line 244).
   - Remove the `KernelCheckAndDispatch` skip-flag branch in
     `android/android_runtime_full.cpp` (currently around line 313 —
     the `if (g_android_skip_goal_call) { passive sleep loop }`).
   - Remove the asm trampoline short-circuit in
     `game/kernel/asm_funcs_arm64.s` (currently ~lines 178-190 —
     the `cbnz w10, _ret_zero_call_goal` block reading the flag).
   - Any header decls / externs.
4. Re-run D4 validator: must PASS with the dispatcher actually
   running. New markers will now appear past `link finish: logo`
   (e.g. `engine: state=` / `kernel-dispatcher tick` /
   `(load 'kernel-dispatcher) returned`).

## Scope (locks)

**UNLOCKED for A6 only:**

- `goalc/emitter/IGenARM64.cpp` (the bug)
- `game/kernel/asm_funcs_arm64.s` (skip-flag short-circuit removal)
- `android/android_runtime_full.cpp` (skip-flag arming + branch removal)

After A6 commits, these files revert to byte-identical-to-A6-close.

**STILL LOCKED:**

- `goalc/compiler/IR.cpp`
- `goalc/emitter/IGenARM64.h`
- `goalc/emitter/ObjectGenerator.h`
- `goalc/emitter/ObjectGenerator.cpp` (stays at A5-close)
- `goalc/compiler/CodeGenerator.cpp` / `CodeGenerator.h`
- `.autoport/lib/classify_ir_arm64.py`

## Anti-cheat invariants

- The classifier byte-identical to A1.
- The remaining locked goalc files byte-identical to A4 (or A5 for
  ObjectGenerator.cpp / IGenARM64.cpp's A5 sections which now move
  again — the lock anchor for IGenARM64.cpp specifically shifts to
  A6-close).
- x86 CGOs byte-identical to A2 baseline. The IGenARM64 emitter is
  arm64-only.
- arm64 CGOs change byte-for-byte (the whole point); save new
  `.autoport/reports/A6-baseline-arm64-cgo-hashes.txt`.
- 0 NOPs in post-emit patcher report (the A5 invariant continues).
- 0 `*_stubs.cpp` added since D3.
- 0 `abort()` / `std::abort()` in `.cpp` / `.h` / `.s` since D3.
- 0 `__attribute__((weak))` since D3.
- **`g_android_skip_goal_call` symbol must NOT exist anywhere in the
  codebase after A6** — neither in `nm libgk.so` output, nor as a
  source reference, nor as a header extern. Forbidden vestige.
- Desktop x86 `build-x86/game/gk` still reaches `link finish: logo`.

## Reality check toolkit

- `nm --defined-only build-android/lib/arm64-v8a/libgk.so | grep skip_goal_call`
  → must produce ZERO output.
- `grep -rn 'g_android_skip_goal_call\|skip-flag armed' android/ game/`
  → must produce ZERO output.
- `objdump -d` on the regenerated arm64 KERNEL.CGO at a sym-mem call
  site to verify the `ADD X16, Xn, X15; LDR/STR Wt, [X16, ...]` shape.
- D4 validator (existing one) re-passes with the dispatcher running
  (will now see `link finish:` lines past `logo`, e.g.
  `link finish: kernel-dispatcher` if that's what the desktop oracle
  shows).
- E1/E2/E3 validators (existing) re-pass (they'll naturally extend
  past the dispatcher-start milestone since the runtime is
  honestly executing now).

## Cost expectation

Narrow, diagnosis-driven. Probably 1-2 hours / $20-40. The hard part
(diagnosis) is done; A6 is mostly typing.
