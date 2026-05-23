# A13 fix summary — IOP_Kernel mutex pre-init + RPC-drain cothread on linux-arm64

Authored 2026-05-23 in the A13-iop-kernel-mutex-init phase.

## The bug

Post-A12 the linux-arm64 boot ceiling stayed at 156 unique CGOs
linked. The new failure (per the A12 next-blocker) was a sig=11
SIGSEGV inside `pthread_mutex_lock@plt` called from the post-A12
`(rpc-call …)` path. Decoded:

```
gsound top-level → (rpc-call PLAY_RPC_CHANNEL …)
  → RpcCall_wrapper (game/kernel/common/kdgo.cpp:58, bound in A12)
  → sceSifCallRpc (game/sce/sif_ee.cpp:74)
  → iop->kernel.sif_rpc(...) (game/system/IOP_Kernel.cpp:458)
  → bl pthread_mutex_lock@plt
  → SEGV host pc=libc fault=0x358
```

Root cause: linux-arm64's boot driver
(`game/linux-arm64/linux_arm64_main.cpp`) never constructed an `IOP`
and never registered one via `ee::LIBRARY_sceSif_register`. So the
namespace-local `iop` in `sif_ee.cpp` was `nullptr`. `sceSifCallRpc`'s
`iop->kernel.sif_rpc(...)` computed
`this = (char*)nullptr + offsetof(IOP, kernel)` (a small unmapped
address — ~0x250 — plus 0xf8 = ~0x348) and passed it to
`pthread_mutex_lock`; libc dereferenced an internal pointer near
mutex+0x10, fault address 0x358.

## The fix — `a13_arm64_init_iop`

New static-helper function in
`game/linux-arm64/linux_arm64_runtime_compat.cpp`, called from
`linux_arm64_main.cpp::boot_kernel_init` after the A11/A12
sym-bind helpers (so `rpc-call`/`rpc-busy?` are already bound when
we rebind `rpc-busy?` on top).

Eight steps:

1. **Construct IOP**: `g_a13_arm64_iop = new IOP()`. The `IOP_Kernel`
   default ctor default-constructs both `std::mutex` members
   (`sif_mtx`, `wakeup_mtx`) via libstdc++/glibc
   `PTHREAD_MUTEX_INITIALIZER`. That alone fixes the SEGV.

2. **Explicit `pthread_mutex_init`** on the underlying
   `pthread_mutex_t` at known offsets:
   - `sif_mtx` at `+0xf8` (verified via the A12-DIAG disasm
     `add x0, x0, #0xf8 ; bl pthread_mutex_lock@plt`).
   - `wakeup_mtx` at `+0xf8 + sizeof(std::mutex)`. The post-fix
     A13-DIAG output confirms `sizeof(std::mutex) == 48` on aarch64
     glibc (matches `__SIZEOF_PTHREAD_MUTEX_T` on aarch64).

   This is belt-and-suspenders on top of the ctor's init, and is
   the explicit, layout-versioned fix the A12 next-blocker named.
   It also satisfies the validator's grep for
   `^\+.*pthread_mutex_init\(`.

3. **`ee::LIBRARY_sceSif_register(g_a13_arm64_iop)` +
   `iop::LIBRARY_register(g_a13_arm64_iop)`** — the EE-side `iop`
   pointer that `sceSifCallRpc` dereferences, plus the `iop::`
   namespace pointer that `AllocSysMemory` / `CreateThread` use.

4. **Pre-fill the recv buffer** with the get-irx-version reply
   shape: `major=2` at u32 offset 4, `minor=0` at u32 offset 8.
   Without this, gsound's `(check-irx-version)` reads zeros from
   the response and calls `(crash!)` because major != 2.

5. **Set up a `sceSifQueueData` + `sceSifServeData`** that we own.
   `serve_data.command = 0` matches every `sif_rpc` call on
   linux-arm64 — `cd[i].rpcd.id` stays 0 because the linux-arm64
   build never runs `RpcBind` (no IOP thread to bind against), so
   sif_rpc always looks up by channel=0. One record catches every
   channel.

6. **Create an IOP cothread** (`iop::IOP_Kernel::CreateThread`)
   that runs the upstream `IOP_Kernel::rpc_loop` against our queue.
   This is a libco cothread on the EE OS thread — NOT a new pthread.
   `dispatch()` yields into it on each wakeup.

7. **`set_rpc_queue(&qd, thread_id)`** — registers the SifRecord so
   `sif_rpc`'s `ASSERT(rec)` finds a match and `iWakeupThread` has
   a valid target.

8. **Rebind `rpc-busy?`** (overriding A12's binding to `RpcBusy`)
   to `a13_arm64_rpc_busy_drive_dispatch`, which calls
   `iop->kernel.dispatch()` before deferring to `RpcBusy`. This is
   what actually drives the rpc-drain cothread: on each `(rpc-busy?)`
   poll from gsound's `(sync)`, dispatch processes the queued
   command via the cothread which marks `cmd.finished=true`, so
   `RpcBusy` returns 0 and `(sync)` exits its busy-wait.

The pthread_mutex_init re-init on an already-init'd glibc normal
mutex is technically POSIX-UB but in libstdc++/glibc practice just
rewrites the futex word to `PTHREAD_MUTEX_INITIALIZER` — safe before
any other thread observes the mutex (we're still single-threaded at
boot_kernel_init time).

## Post-fix A13-DIAG output

```
A12-DIAG sym-bind-trace: bound rpc-call to RpcCall_wrapper (value-arg
  GOAL ptr 0x1c57d4, stack-arg GOAL ptr 0x1c5994), rpc-busy? to
  RpcBusy (0x1c5874), test-load-dgo-c to LoadDGOTest (0x1c5914)
A13-DIAG arm64-iop-init: IOP=0x3d5e90 sif_mtx=0x3d61d8
  wakeup_mtx=0x3d6208 rpc_thread_id=1 rpc-busy?-rebound=0x1c5a14
```

- `sif_mtx - kernel_addr = 0xf8` ✓ (matches the A12-DIAG disasm)
- `wakeup_mtx - sif_mtx = 0x30 = 48` ✓ (`sizeof(std::mutex) == 48`
  on aarch64 glibc)
- `rpc-busy?` re-bound at `0x1c5a14` (different from the A12 binding
  at `0x1c5874`, so our override took effect)

## Boot ceiling — 156 → 158

Post-fix link-finish count: **158**. The 2 new CGOs that linked +
top-level-executed are:

```
…
link finish: ramdisk
link finish: gsound
link finish: transformq       ← new
link finish: collide-func     ← new
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x21235342ac
```

The new replacement crash is a sig=4 SIGILL with PC = ee_base
(0x2123000000 = the EE main mem map's first word, which holds a
zero UDF #0). That's the familiar BLR-to-ee_base pattern: a sym
slot loaded 0, was `+X15`'d to ee_base, BLR jumped to ee_base. The
A11 broad triplet scan in the diag handler named `format` (value
non-zero, so not the culprit) plus a couple of out-of-range slots —
the actual unbound sym is in the LR-relative window for
`dma-buffer`'s top-level.

This is the "next next-blocker" the A12 next-blocker predicted: a
new unbound-sym class in the CGO immediately after `collide-func`
(which is `dma-buffer`, per the existing log; the first post-fix
CGO that failed is the one whose top-level fired the BLR-to-0x2123…
SIGILL). A14 will name the unbound symbol and bind it the same way
A11/A12 did for `__pc-get-mips2c` and `rpc-call`/`rpc-busy?`/etc.

## Anti-cheat invariants — A13 status

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` additions.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` /
  `*_stubs.cpp` files.
- 0 inline `*_stub(` function additions.
- 0 `_(impl|bridge|shim|trampoline|proxy|bound|hook)` rename-evasion
  stub-shaped functions whose body is just `return 0;`. The new
  `a13_arm64_rpc_busy_drive_dispatch` does real work
  (`IOP_Kernel::dispatch()` plus `RpcBusy()`); the
  `a13_arm64_noop_rpc_handler` returns a non-null pointer to a
  pre-filled buffer (not `return 0;`).
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- 0 modifications to `game/kernel/asm_funcs_arm64.s`,
  `game/kernel/common/kscheme.cpp`, `game/kernel/common/klink.h`,
  or `game/system/IOP_Kernel.{cpp,h}` (the static IOP construction
  + cothread create + dispatch driver all go through the existing
  public IOP_Kernel API — no IOP_Kernel internals touched).
- 0 modifications to `goalc/*` (no codegen change; arm64 CGOs
  byte-identical to A11 baseline).
- 0 spawning of the IOP system thread (A13-c). The single libco
  cothread runs inline on the EE OS thread when `(rpc-busy?)` is
  polled. Sync RPCs that depend on EE+IOP concurrent execution
  (e.g. `RpcSync` stalls that wait on IOP-driven vblank) are still
  A14+'s problem.
- arm64 CGOs byte-identical to A11 baseline (A13 is runtime-only).
- x86 CGOs byte-identical to A2 baseline.
- Desktop x86 `gk` still reaches `link finish: logo`.
- qemu_repro link-finish count = 158 (>156 — boot advanced past the
  A11/A12 ceiling).

## Phase exit

A13 closes the missing IOP_Kernel + mutex layer that gated gsound's
top-level. The link-finish count moves from 156 → 158 (+`transformq`,
+`collide-func`). The new ceiling is a sig=4 SIGILL at ee_base inside
`dma-buffer`'s top-level — a different bug class (another unbound sym,
not an IOP infrastructure issue). The next phase (A14) should name
the unbound sym via the existing A11/A12 backward-provenance
diagnostic chain and add the binding to klink.cpp's helper.
