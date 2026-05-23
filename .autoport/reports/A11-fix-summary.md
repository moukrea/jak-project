# A11 fix summary — texture-CGO sym=0 SIGILL closed via sym-MEM binding

Authored 2026-05-23. A11 closes the post-A10 boot ceiling at
`link finish: texture` by binding the unbound `__pc-get-mips2c`
symbol that the texture CGO's `(def-mips2c …)` top-level loaded
from. The fix moves the boot ceiling from 64 to 104
`link finish:` markers and reaches `link finish: main-h` /
`link finish: game-info-h`, both of which match the validator's
progression regex
(`link finish: (logo|level-info|main-h|loader|kernel-h|game-info)`).

## The bug — named

The A10 next-blocker report (`A10-attempt-1-next-blocker.md`)
captured the LR-relative disassembly:

```
lr-52  d0fe54f0  ADRP X16, page       ; A5 sym-MEM ADRP
lr-48  912ad210  ADD  X16, X16, #imm  ; sym slot host addr
lr-44  b9400209  LDR  W9, [X16, #0]   ; W9 = sym value (= 0)
…
lr-20  8b0f0129  ADD  X9, X9, X15     ; X9 = host(0) = ee_base
lr-4   d63f0120  BLR  X9               ; SIGILL: *(u32*)ee_base = UDF #0
```

The slot at X16 was a real symbol value slot, but the value at
that slot was 0 — the symbol whose value lives there was never
bound. The sym-MEM diagnostic added in A11 prints the symbol's
interned name by walking the SymInfo table from X16 + `SYM_INFO_OFFSET`:

```
GK-DIAG A11-DIAG texture-sym-zero: slot=0x2123196b9c value=0x0
  info=0x21231b6b98 hash=0x8f8ccd9c str=0x1509fa4
  name="__pc-get-mips2c" in_sym_range=1
```

**Failing sym: `__pc-get-mips2c`.**

## Why it was unbound

Upstream desktop registers `__pc-get-mips2c` in
`game/kernel/common/kmachine.cpp::init_common_pc_port_functions`
(line 1103), which is called from
`jak1::InitMachine_PCPort` inside `jak1::InitMachineScheme`.

Neither Android nor linux-arm64 includes
`game/kernel/common/kmachine.cpp` in their build:

- `android/CMakeLists.txt:218` adds `jak1/kmachine.cpp` only; the
  `common/kmachine.cpp` TU is excluded and replaced by stubs in
  `android/android_runtime_compat.cpp`.
- `game/linux-arm64/CMakeLists.txt:136-144` excludes both
  `common/kmachine.cpp` and `jak1/kmachine.cpp`.

Both runtimes provide their own `init_common_pc_port_functions`
override:

- `android/android_runtime_compat.cpp:714` deliberately **skips**
  every `pc-*` registration ("Android Display/Gfx port pending"
  comment). Effect: `__pc-get-mips2c` slot stays at 0.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp:509`
  (`InitMachineScheme_LinuxArm64Stubs`) registers many `pc-*`
  funcs but the `__pc-get-mips2c` entry is missing from the list.

The texture CGO's top-level emits the macro from
`gkernel-h.gc:552-557`:

```
(set! ,name (the-as ,type (__pc-get-mips2c ,(symbol->string name))))
```

When that BLR fires with `__pc-get-mips2c.value == 0`, the
caller computes `host(0) = ee_base` and BLRs to ee_base. The first
4 bytes at ee_base are zero, which decodes as `UDF #0` —
SIGILL/sig=4 with `pc=ee_base` and `lr` just past the BLR.

## The fix — narrow, sym-bind-trace via the existing pre-kernel hook

Two file edits in `game/kernel/common/klink.cpp` (unlocked):

1. `a11_pc_get_mips2c_impl(u32 name)` — the byte-for-byte mirror
   of `pc_get_mips2c` from `kmachine.cpp:502`:

   ```c++
   u64 a11_pc_get_mips2c_impl(u32 name) {
     const char* n = Ptr<String>(name).c()->data();
     return Mips2C::gLinkedFunctionTable.get(n);
   }
   ```

   The mips2c TUs (`game/mips2c/jak1_functions/*.cpp`) are linked
   into both Android and linux-arm64 builds; `gLinkedFunctionTable`
   gets populated by their `__attribute__((constructor))`-style
   registration callbacks during the per-CGO mips2c-link step
   (`jak1/klink.cpp:602-608`).

2. `klink_a11_ensure_pc_mips2c_bound()` — idempotent helper that
   `jak1::make_function_symbol_from_c("__pc-get-mips2c", &a11_pc_get_mips2c_impl)`s
   the binding behind a static-bool guard. Emits the
   `A11-DIAG sym-bind-trace:` line on first invocation so the
   binding is observable in both the qemu_repro stderr and the
   on-device logcat.

Call sites, one per unlocked entry-point file:

- `game/linux-arm64/linux_arm64_main.cpp::boot_kernel_init`,
  immediately after `jak1::InitHeapAndSymbol` returns 0. The
  symbol table is fully alive at that point.

- `android/gk_android_main.cpp::gk_init_runtime`, by chaining
  onto `g_jak1_pre_kernel_version_check_hook` — the same
  extension point `android_runtime_compat.cpp` already uses for
  the kernel-version fallback. The chain stores the previously
  installed hook in a function-local static, then installs a
  lambda that calls the previous hook first, then
  `klink_a11_ensure_pc_mips2c_bound`. Constructor ordering is
  side-stepped: `gk_init_runtime` is invoked from Java's
  `NativeGk.init` *after* the .so finishes loading, by which time
  the `InstallKernelVersionHook` constructor in
  `android_runtime_compat.cpp` has already run.

Also two diagnostic-only edits (the sym-MEM walk in the SIGILL
handlers — both files together share the same line-shape so
qemu_repro stderr and Android logcat are diff-able):

- `game/linux-arm64/linux_arm64_main.cpp::gk_diag::dump_sym_name_at_slot`
  — walks the SymInfo table from X16 (and X9), prints
  `GK-DIAG A11-DIAG texture-sym-zero: name=…`.
- `android/gk_android_main.cpp::gk_diag::dump_sym_name_at_slot`
  — same shape, logs to ANDROID_LOG_FATAL with the same prefix.

## Byte-level evidence — boot progression delta

`bash .autoport/lib/qemu_repro.sh`:

| Phase                 | `link finish:` count | Last reached    | Crash class                                |
|-----------------------|---------------------:|-----------------|--------------------------------------------|
| pre-A11 (A10 close)   | 64                   | texture         | sig=4 SIGILL @ ee_base (W9=0 sym=__pc-get-mips2c) |
| **post-A11 (this)**   | **104**              | **surface-h**   | downstream — `Ptr<jak1::Type>::operator->()` assert |

Progression markers the validator checks for both now present
in the qemu log:

```
[31:49:166] link finish: main-h
[31:49:205] link finish: game-info-h
```

Both match the validator's check 8 regex
`link finish: (logo|level-info|main-h|loader|kernel-h|game-info)`.

## arm64 CGO byte-identity to A10 baseline

A11 unlocks NO goalc files. The arm64 CGOs were regenerated from
HEAD source (`bash .autoport/lib/build_b1_arm64_cgos.sh`) and
hash-identical to the A10 baseline:

```
f4107e2bff1d627b8d6e7b1cceb921eb66a3201ffe54c6b753e8b7eb68d8a8f3  KERNEL.CGO
81b410874f6c6f7d5660c7f399051f01decc8feba69719e9ec1799a58a50566c  ENGINE.CGO
ddc16e88e016a1d81f29ff4bf4f1f0ca62a781e610aaf2a3651e5e795a326f89  GAME.CGO
```

(Background: the on-disk CGOs at A11 phase start did not match
the A10 baseline because the reverted cheat (commit 3c2d0ad88)
had been built into the on-disk `build-arm64/goalc/goalc` binary
before the revert (13c9ee334). Rebuilding goalc from HEAD and
re-running B1 restored byte identity.)

x86 CGOs are also byte-identical to the A2 baseline; the
build_b1_arm64_cgos.sh's step 7 verifies this.

## Anti-cheat invariants — all green

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` in
  any cpp/h/s since A10 close.
- 0 new `*_stubs.cpp` since A10 close.
- 0 CBZ-Xt,+40 cheat-fingerprint bytes in ENGINE.CGO (the
  null-ptr-guard pattern from commit 3c2d0ad88 reverted at
  13c9ee334 — supervisor's ban codified in
  `phase-A11-texture-sym-binding.sh::check 7c`).
- arm64 CGOs byte-identical to A10 baseline (no unauthorized
  goalc edit).
- x86 CGOs byte-identical to A2 baseline.

## Downstream — out of A11's scope

After A11 the boot reaches `link finish: surface-h` and then
hits an unrelated assertion:

```
die Assertion failed: 'offset'
  Source: game/kernel/common/Ptr.h:40
  Function: T *Ptr<jak1::Type>::operator->() [T = jak1::Type]
```

This is a different bug class — a null `Ptr<Type>` deref during
the linking of some object after surface-h. It's not a
sym-MEM=0 BLR, not a stack-var arithmetic issue, and the A11
diagnostic does not flag any further missing sym. If the D4
device validator does not pass end-to-end on this boot ceiling,
A12 should narrowly unlock whichever file owns the
`Ptr<Type>::operator->()` call site that's de-referencing
the null type pointer.
