# A12 fix summary — gsound stack-loaded fn-ptr=0 SIGILL resolved at the named layer

Authored 2026-05-23 in the A12-gsound-stack-fnptr phase.

## The bug

Post-A11 the boot ceiling on linux-arm64 (and Android) sat at 156
unique CGOs linked, with sig=4 SIGILL just past `link finish: gsound`.
The failing PC was `0x2123000000` — the start of the EE memory map,
which holds the zero word (= UDF #0) — i.e. an indirect BLR through
a register that had been loaded with `host(0) = ee_base`.

The A11 attempt-3 follow-up triplet-scan diagnostic had already
named one candidate: an A5 sym-MEM far-reloc triplet
`ADRP X16, page ; ADD X16, X16, #0xacc ; LDR W9, [X16, #0]` at
lr-152..lr-144 dereferenced the slot at host 0x2123199acc whose
SymInfo trailer named the symbol `rpc-call` (value=0x0). But the
scan didn't *prove* that this slot's contents fed the failing BLR
— it could have been any unbound sym in the LR-relative window.

## The diagnostic — A12 backward-provenance chain

The new `dump_stack_fnptr_zero_chain` helper (added to
`game/linux-arm64/linux_arm64_main.cpp` and mirrored verbatim in
`android/gk_android_main.cpp`) walks the LR-relative window
backward and emits:

```
GK-DIAG A12-DIAG stack-fnptr-zero: blr-pc=<lr-4> ldr-pc=<…>
        blr-target=X<n> slot=[SP,#<N>] (current sp+<…> host=…) value=0
GK-DIAG A12-DIAG provenance-trace: stored-by=<pc> inst=STR X<s>,[SP,#<N>] source-reg=X<s>
GK-DIAG A12-DIAG provenance-trace: originating-load=<pc> inst=LDR W<s>,[X<b>,#<imm>]
GK-DIAG A12-DIAG provenance-trace: adrp-pc=<pc> adrp-target=<host> add-imm12=<…> ldr-imm12=<…> sym_slot=<…>
GK-DIAG A12-DIAG sym-walk-back:
GK-DIAG A11-DIAG texture-sym-zero: slot=<…> value=0 … name="rpc-call" in_sym_range=1
```

so the chain `(BLR target reg) → (LDR Xt,[SP,#N]) → (STR Xs,[SP,#N])
→ (LDR Ws,[Xb,#0]) → (ADRP+ADD Xb)` is named end to end. The
existing A11 broad triplet scan still runs after this and provides
a fallback when the shape doesn't match.

## The fix — bind `rpc-call`, `rpc-busy?`, `test-load-dgo-c`

Root cause: `linux_arm64_runtime_compat.cpp::jak1::InitMachineScheme`
(the linux-arm64 override) calls `InitMachineScheme_LinuxArm64Stubs`
which registers ~30 graphics/pad/SCF sym bindings, but does NOT call
`jak1::InitSoundScheme` (which lives in `game/kernel/jak1/ksound.cpp`
and registers the sound RPC syms). On Android the same gap was
historically present but is now closed by `android_runtime_compat.cpp`
delegating `jak1::InitMachineScheme` to the real
`game/kernel/jak1/kmachine.cpp` (which calls `InitSoundScheme`).

The fix mirrors the A11 pattern: a small helper
`klink_a12_ensure_sound_rpc_bound` in `game/kernel/common/klink.cpp`
registers the same syms `jak1::InitSoundScheme` does, with the same
C function pointers (`RpcCall_wrapper`, `RpcBusy`, `LoadDGOTest` from
`game/kernel/common/kdgo.cpp`), and the same duplicate stack-arg
`rpc-call` registration upstream issues second. Idempotent via
static-local guard plus a SymbolTable2-ready check.

Call sites:
- `game/linux-arm64/linux_arm64_main.cpp::boot_kernel_init` — right
  after `klink_a11_ensure_pc_mips2c_bound`.
- `android/gk_android_main.cpp::a11_install_pc_mips2c_hook_once` —
  chained alongside the A11 bind into the pre-kernel-version hook.
  Idempotent / redundant on Android (the real `InitMachineScheme`
  already binds rpc-call), but harmless and serves as belt-and-
  suspenders for the texture-sym-zero pattern.

Post-fix qemu_repro output confirms:

```
A12-DIAG sym-bind-trace: bound rpc-call to RpcCall_wrapper
  (value-arg GOAL ptr 0x1c57d4, stack-arg GOAL ptr 0x1c5994),
  rpc-busy? to RpcBusy (0x1c5874),
  test-load-dgo-c to LoadDGOTest (0x1c5914)
```

…and the original sig=4 SIGILL at ee_base no longer fires (the BLR
target is now a valid host function pointer).

## What the fix exposes — the new next-blocker for A13

The boot ceiling stays at 156 link-finishes because the *replacement*
crash class is `sig=11 SIGSEGV` inside the now-callable
`RpcCall_wrapper`. Decoded:

```
gsound top-level → (rpc-call …)
  → RpcCall_wrapper (game/kernel/common/kdgo.cpp:58)
  → sceSifCallRpc (game/sce/sif_ee.cpp:74)
  → iop->kernel.sif_rpc(...) (game/system/IOP_Kernel.cpp)
  → bl pthread_mutex_lock@plt (host libc)
  → SEGV at host PC 0x7f…libc fault=0x358 (mutex offset out of range)
```

The mutex is `IOP_Kernel::mtx` at this+0xf8; the SEGV in
pthread_mutex_lock means the mutex object hasn't been initialised by
`pthread_mutex_init`. linux-arm64's boot driver does not spawn the
IOP system thread (no `system_thread_run` / `iop_thread_run`), so the
`iop` global's kernel never had its members properly constructed.

This is a different bug class — *runtime infrastructure missing on
linux-arm64*, not a sym/codegen bug. Recommended A13 scope is one of:

1. **Init the IOP infrastructure on linux-arm64**: spawn the IOP
   system thread + libco coordination in `linux_arm64_main.cpp` so
   `iop->kernel.sif_rpc` runs on a real, mutex-initialised kernel.
   Probably the largest scope; matches what desktop runtime.cpp does.
2. **Synchronous direct-call sif_rpc on arm64**: replace
   `sceSifCallRpc` with a direct in-thread dispatch for the
   linux-arm64 / no-IOP-thread environment. Avoids spawning threads
   but needs careful semantics for fire-and-forget vs sync calls.
3. **Pre-init the IOP_Kernel mutex without spawning the thread**:
   call `pthread_mutex_init` (and any other init the kernel needs)
   from `init_all_globals` so at least the mutex is valid, even if
   the dispatch loop never runs. Smallest scope; works only if the
   gsound top-level's rpc-call is `async=true` (returns 0 without
   waiting), and only if no later CGO calls `RpcSync` / `RpcBusy`
   that actually need a serving IOP.

The A13 next-blocker report
(`.autoport/reports/A12-attempt-1-next-blocker.md`) names this
crash with the addr2line output + the pthread_mutex_lock PLT entry
that addr2line resolved (`build-arm64-linux/game/linux-arm64/gk`
disassembly of `_ZN10IOP_Kernel7sif_rpcEijbPviS0_i+0x44`).

## Anti-cheat invariants — A12 status

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` additions.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` /
  `*_stubs.cpp` / inline `_stub(` additions.
- 0 new `_impl|_bridge|_shim|_trampoline|_proxy|_bound|_hook`
  rename-evasion stub-shaped functions returning 0 (the new helper
  `klink_a12_ensure_sound_rpc_bound` registers real existing C
  functions, not stubs).
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- 0 modifications to `game/kernel/asm_funcs_arm64.s` (FFI trampoline
  codegen-owned).
- 0 modifications to `game/kernel/common/kscheme.cpp` (A11-touched;
  the runtime FFI bridge stands as-is).
- arm64 CGOs byte-identical to `.autoport/reports/A11-baseline-arm64-cgo-hashes.txt`
  (which equals A10 baseline; A11+A12 are both runtime-only).
- x86 CGOs byte-identical to A2 baseline.
- 0 CBZ-Xt,+40 cheat-fingerprint bytes in ENGINE.CGO.
- Desktop x86 `gk` reaches `link finish: logo` cleanly (453
  link-finishes total in the smoke run).
- qemu_repro link-finish count = 156 (≥156, no regression vs A11).
  The count doesn't advance because the named A12 fix unblocks the
  unbound-sym layer but exposes the IOP-infra-missing next layer.

## Phase exit

A12 closes the narrow sym-binding angle that gated the gsound boot
ceiling. The link-finish count doesn't move (the replacement crash
is in C wrapper code, not GOAL bytecode), but the boot path beyond
the BLR-to-ee_base layer is now reachable, with the new failure
named for A13 in
`.autoport/reports/A12-attempt-1-next-blocker.md`.
