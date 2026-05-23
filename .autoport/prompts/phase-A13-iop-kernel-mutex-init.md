# Phase A13 — IOP_Kernel mutex pre-init on linux-arm64 / android-arm64

## First step — read the cookbook

Read `.autoport/CODEGEN_COOKBOOK.md` first. It has the encoding
helpers, lock structure, build+test cycle, GK-DIAG decoder,
anti-cheat enumeration, per-phase yield log. ~30 seconds vs
5–15 minutes of rediscovery.

## Status

**Authored 2026-05-23 by the supervisor** after A12 landed its
rpc-call binding (commit 5423d2433) + finalized next-blocker
(905f5c29a). A12 closed the gsound stack-fnptr=0 SIGILL at the
named sym layer but exposed a deeper infrastructure issue: the
IOP_Kernel's `pthread_mutex_t` member is uninitialised on
linux-arm64 / android-arm64, so the first `rpc-call`-driven
`IOP_Kernel::sif_rpc()` SEGVs inside `pthread_mutex_lock@plt`.

This is the **smallest A13 candidate** per claude's analysis (the
A12-attempt-1 next-blocker enumerates A13-a/b/c with increasing
scope). A13-a is just the mutex init — no thread spawning, no IOP
dispatch table rewrite.

## Bucket

A — runtime/init (game/system layer).

## Motivation

Per `.autoport/reports/A12-attempt-1-next-blocker.md`:

```
GK-DIAG sig=11 fault=0x358 pc=0x7f3744891e24 lr=0x2bcb88
```

`addr2line` resolves the lr to
`IOP_Kernel::sif_rpc(int, unsigned int, bool, void*, int, void*, int)`,
which the disassembly shows is in turn calling `pthread_mutex_lock@plt`
on a mutex at `iop->kernel + 0xf8`. The mutex object is
zero-initialised (BSS) because the linux-arm64 boot driver
deliberately doesn't spawn the IOP system thread the way desktop
does (`game/runtime.cpp::ee_runner` + `SystemThreadManager` in
`game/system/SystemThread.cpp`).

Without the IOP thread, the mutex is never `pthread_mutex_init`d,
and `pthread_mutex_lock` on a zero-initialised mutex SEGVs when it
dereferences its internal pointer at offset +0x358.

## Goal (concrete, narrow)

In an arm64-only init path (likely
`game/linux-arm64/linux_arm64_runtime_compat.cpp` and/or
`android/android_runtime_compat.cpp`), call
`pthread_mutex_init(&iop->kernel.<mutex_field>, nullptr)` and
zero-init any other IOP_Kernel state required for `sif_rpc` to
work in async-only mode (which is what gsound's top-level uses).

**Do not spawn the IOP thread.** That's A13-c (largest scope) and
is out of scope here.

**Do not stub `sif_rpc` to return 0.** That's a stub-shaped cheat
even if renamed. The mutex MUST be initialised so the lock/unlock
calls actually function; just route async RPCs through the
existing `IOP_Kernel::sif_rpc` body which queues but doesn't wait.

## Scope (locks)

**UNLOCKED for A13 only:**

- `game/linux-arm64/linux_arm64_runtime_compat.cpp` — add the
  arm64 init for IOP_Kernel mutex(es).
- `android/android_runtime_compat.cpp` — mirror.
- `game/linux-arm64/linux_arm64_main.cpp` — call the init at the
  right boot ordinal (after IOP_Kernel construction, before
  any `RpcCall_wrapper` invocation).
- `android/gk_android_main.cpp` — mirror.
- `game/kernel/common/klink.cpp` — only if the init hook needs to
  live there (preferable to keep it in runtime_compat though).

**STILL LOCKED** (carried forward from A6–A12):

- All `goalc/emitter/*`, `goalc/compiler/IR.cpp`,
  `CodeGenerator.{cpp,h}`, classify_ir_arm64.py.
- `game/kernel/asm_funcs_arm64.s`.
- `game/kernel/common/kscheme.cpp` (A11's arg-bridge stands).
- `game/kernel/common/klink.h` (A12 declarations stand).
- `game/system/IOP_Kernel.cpp/.h` — IOP kernel itself locked;
  don't modify the kernel's own logic, only initialise its
  arm64-side state from outside.
- `.autoport/lib/*.sh`, `.autoport/lib/*.py`,
  `.autoport/validators/*.sh` (supervisor-owned).

## Anti-cheat invariants

Inherited from A6–A12 (see cookbook §6):

- 0 dodges, 0 abort/weak additions, 0 new `_stubs.cpp`, 0 inline
  `_stub(` additions.
- 0 rename-evasion: no `_(impl|bridge|shim|trampoline|proxy|bound|hook)`
  suffix function whose body reduces to `return 0;` (validator's
  Python heredoc scan).
- 0 modifications to `.autoport/lib/*`, `.autoport/validators/*`,
  `game/kernel/asm_funcs_arm64.s`, `game/kernel/common/kscheme.cpp`,
  `game/system/IOP_Kernel.cpp/.h`.
- D4 hardened SDL/GL check (≥3/5 markers, no dodge).
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-identical to A11 baseline (no codegen change).
- Desktop x86 `gk` smoke still reaches `link finish: logo`.
- Link-finish count regression check: ≥ 156 (A11/A12 ceiling).

## Required deliverables

1. The arm64 init that calls `pthread_mutex_init` on IOP_Kernel's
   mutex member(s), wired into the boot ordinal between
   `IOP_Kernel`'s construction (zero-init in BSS) and the first
   `RpcCall_wrapper` invocation.
2. `bash .autoport/lib/qemu_repro.sh` — must reach `link finish: logo`
   OR `link finish: loader` OR `engine: state=`. (Goal: advance
   past the 156 ceiling.)
3. `bash .autoport/validators/phase-A13-iop-kernel-mutex-init.sh`
   exits 0.
4. `.autoport/reports/A13-fix-summary.md` — names the mutex field(s)
   initialised, where the init is wired, and the post-fix
   link-finish count.

## Honest exit condition

If A13-a's mutex init lands but boot then hits a different IOP
infrastructure issue (e.g. a synchronous RPC needing a real IOP
thread, per A12 next-blocker's "next next-blocker" prediction),
commit the mutex init + write `A13-attempt-N-next-blocker.md`
analysing the new failure with the same A13-b/c framework. The
supervisor will author A14.

## Cost expectation

~60 min / $20-40. The fix is mechanical (pthread_mutex_init call
on a known-uninit'd mutex) once the field is found via
disassembly + cross-reference to `IOP_Kernel.h`.

## Rate-budget caution

Weekly rate at 82% when this phase starts. **Approaching the 85%
halt threshold.** If A13-a hits unexpected complexity, honest-exit
fast with a next-blocker rather than spinning multiple retries.
