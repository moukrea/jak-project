# Phase A14 — bind `__mem-move` on linux-arm64 / android-arm64

## First step — read the cookbook

Read `.autoport/CODEGEN_COOKBOOK.md` first. ~30 seconds vs 5–15
minutes of rediscovery.

## Status

**Authored 2026-05-23 by the supervisor** after A13 landed its
IOP_Kernel mutex init + RPC-drain cothread (commit 59090a9e3) and
the supervisor's SIGPIPE fix on `qemu_repro.sh` (a596e5798) let the
A13 validator complete end-to-end. Device-side boot now reaches
**158 link-finishes cleanly on the Redmi Note 9 Pro** (matches qemu
exactly — no arm64-vs-Android divergence). The new ceiling is a
sig=4 SIGILL via BLR-to-ee_base, with the A11-DIAG triplet scan
naming the unbound symbol as `__mem-move` (hash `0x9290899a`).

This follows the established A11 + A12 pattern: another deliberately-
unbound `pc-*` helper that desktop registers via
`init_common_pc_port_functions` but the Android compat override
skips. A14-a (per A13 attempt-3 next-blocker) is the smallest fix:
just bind this one symbol.

## Bucket

A — runtime/sym-binding.

## Motivation

Per `.autoport/reports/A13-attempt-3-next-blocker.md`:

```
GK-DIAG A11-DIAG texture-sym-zero: slot=0x720c1aea1c value=0x0
  info=0x720c1cea18 hash=0x9290899a str=0x4f14e4 name="__mem-move"
  in_sym_range=1
```

`__mem-move` has an existing C implementation: `pc_memmove` in
`game/kernel/common/kmachine.cpp`. Upstream registration:

```cpp
// game/kernel/common/kmachine.cpp:1095 (approx)
make_func_symbol_func("__mem-move", (void*)pc_memmove);
```

This call lives inside `init_common_pc_port_functions`, which the
Android override deliberately skips. A11 worked around
`__pc-get-mips2c` by adding `klink_a11_ensure_pc_mips2c_bound`; A12
did the same for the IOP RPC syms. A14 follows the identical pattern
for `__mem-move`.

## Goal (concrete, narrow)

In `game/kernel/common/klink.cpp`, add:

```cpp
void klink_a14_ensure_pc_memmove_bound() {
  static bool s_bound = false;
  if (s_bound) return;
  if (SymbolTable2.offset == 0) return;
  auto fn = jak1::make_function_symbol_from_c("__mem-move",
                                              (void*)pc_memmove);
  s_bound = true;
  std::fprintf(stderr,
               "A14-DIAG sym-bind-trace: bound __mem-move to pc_memmove "
               "(GOAL ptr 0x%x)\n", (unsigned)fn.offset);
}
```

Declare in `klink.h` alongside the A11/A12 helpers. Chain into the
pre-version-check hook in `linux_arm64_main.cpp` +
`gk_android_main.cpp` next to the A11/A12 calls.

## Scope (locks)

**UNLOCKED for A14 only:**

- `game/kernel/common/klink.cpp` — add the bind helper.
- `game/kernel/common/klink.h` — add the declaration.
- `game/linux-arm64/linux_arm64_main.cpp` — chain the call.
- `android/gk_android_main.cpp` — same.

**STILL LOCKED** (carried forward from A6–A13):

- All `goalc/emitter/*`, `goalc/compiler/IR.cpp`,
  `CodeGenerator.{cpp,h}`, classify_ir_arm64.py.
- `game/kernel/asm_funcs_arm64.s`.
- `game/kernel/common/kscheme.cpp` (A11's arg-bridge).
- `game/kernel/common/kmachine.cpp` (don't modify the upstream
  registration table; the Android override skip is intentional).
- `game/system/IOP_Kernel.{cpp,h}`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp` (A13's IOP
  init stands).
- `android/android_runtime_compat.cpp`.
- `.autoport/lib/*.sh`, `.autoport/lib/*.py`,
  `.autoport/validators/*.sh` (supervisor-owned).

## Anti-cheat invariants

Inherited from A6–A13 (see cookbook §6 + §11). Critical reminders:

- 0 dodges, no abort/weak/inline-stub/_stubs.cpp additions.
- 0 rename-evasion: `pc_memmove` is a REAL function in
  `kmachine.cpp` — bind to it, don't write a `_impl` / `_bound`
  wrapper that just `return 0;`s.
- 0 modifications to any locked file above.
- arm64 CGOs byte-identical to A11 baseline (no codegen change).
- x86 CGOs byte-identical to A2 baseline.
- Link-finish count regression check: ≥ 158 (A13 ceiling).
- Strict advance check: > 158.

## Required deliverables

1. `klink_a14_ensure_pc_memmove_bound` in klink.cpp + declaration in
   klink.h, wired into both boot drivers' pre-version-check hooks.
2. `bash .autoport/lib/qemu_repro.sh` — must reach > 158 link-finishes.
3. `bash .autoport/validators/phase-A14-pc-memmove-bind.sh` exits 0.
4. `.autoport/reports/A14-fix-summary.md`.

## Honest exit condition

If A14's bind lands but boot then hits yet another pc-* helper
(highly likely — dma-buffer's top-level probably uses
`__send-gfx-dma-chain` or similar next), commit the bind + write
`A14-attempt-N-next-blocker.md` naming the next unbound symbol +
recommending A15. The cascade may continue helper-by-helper or
the supervisor may pivot to A-bulk (bind all non-Display/non-Gfx
pc-* helpers at once).

## Cost expectation

~30-45 min. The fix is mechanical at this point — A11 and A12
already established the helper-pattern + chaining sites.

## Rate-budget caution

Weekly rate at 84% when this phase starts — **approaching 85% halt
threshold**. If A14 doesn't pass cleanly on attempt 1, honest-exit
fast with the next-blocker rather than spinning retries. The
supervisor will halt at 85% to preserve next-week budget.
