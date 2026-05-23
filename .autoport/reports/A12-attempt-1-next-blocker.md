# A12 attempt-1 — rpc-call binding landed; new next-blocker: IOP_Kernel mutex uninit'd on linux-arm64

Authored 2026-05-23 (post-A12 fix). Single item for the supervisor:
the new failure class beyond A12's sym-binding scope.

## What A12 closed

`rpc-call` (plus `rpc-busy?`, `test-load-dgo-c`) was unbound on
linux-arm64. The boot ceiling at 156 link-finishes was a sig=4
SIGILL via `BLR Xt` where Xt = `host(rpc-call-slot-value) = host(0)
= ee_base`. The fix mirrors A11's `klink_a11_ensure_pc_mips2c_bound`
pattern: a small `klink_a12_ensure_sound_rpc_bound` helper in
`game/kernel/common/klink.cpp` registers the same syms the upstream
`jak1::InitSoundScheme` (game/kernel/jak1/ksound.cpp:11) does, with
the same C function pointers from `game/kernel/common/kdgo.cpp`.

Post-fix the A12-DIAG backward-provenance chain produces the
specific name `rpc-call` (the existing A11 triplet scan also
already named it; A12 makes the chain explicit + machine-readable):

```
A12-DIAG sym-bind-trace: bound rpc-call to RpcCall_wrapper
   (value-arg GOAL ptr 0x1c57d4, stack-arg GOAL ptr 0x1c5994), …
```

After the fix the BLR target is a valid host function pointer; the
sig=4 SIGILL at ee_base is gone.

## The new ceiling — sig=11 SIGSEGV in pthread_mutex_lock

Boot still stalls at 156 link-finishes. The replacement crash:

```
GK-DIAG sig=11 fault=0x358 pc=0x7f3744891e24 lr=0x2bcb88
```

`addr2line -e build-arm64-linux/game/linux-arm64/gk 0x2bcb88` ⇒
`IOP_Kernel::sif_rpc(int, unsigned int, bool, void*, int, void*, int)`.

The disassembly of the function around the failing BL:

```
2bcb40 <_ZN10IOP_Kernel7sif_rpcEijbPviS0_i>:
  2bcb40:  sub  sp, sp, #0x80
  2bcb44:  stp  x29, x30, [sp, #48]
  2bcb48:  str  x25, [sp, #64]
  …
  2bcb6c:  add  x0, x0, #0xf8        ← x0 = this->mtx (IOP_Kernel field at +0xf8)
  …
  2bcb84:  bl   331da0 <pthread_mutex_lock@plt>   ← THE FAILING CALL
  2bcb88:  cbnz w0, …
```

The `pthread_mutex_lock@plt` call lands inside libc at PC
0x7f3744891e24 and SEGVs with fault=0x358 — the mutex object is
not a valid `pthread_mutex_t`.

### Why the mutex is invalid

linux-arm64's boot driver (`game/linux-arm64/linux_arm64_main.cpp`)
deliberately does NOT spawn the IOP system thread (no
`system_thread_run` / `iop_thread_run` / `IOP_Kernel` construction
+ init). The desktop runtime (`game/runtime.cpp::ee_runner` +
`SystemThreadManager` in `game/system/SystemThread.cpp`) is the
piece that constructs `IOP_Kernel` and initialises its
`pthread_mutex_t` members. Without that init the `iop` global's
kernel sits in zero-initialised state (BSS), and the mutex's
internal pointer at offset +0x358 is null → pthread_mutex_lock SEGVs
when it tries to access the mutex's owner queue.

### What gsound's top-level is doing

`gsound.gc`'s top-level invokes `(rpc-call PLAY_RPC_CHANNEL …)` to
register the play-thread RPC after the sound system layout is set
up. With the binding in place this now reaches `RpcCall_wrapper`
→ `sceSifCallRpc` → `iop->kernel.sif_rpc(...)`, which is the call
path that hits the bad mutex.

## Empirical confirmation from a probe experiment

Before recommending the unlock, the A12 attempt probed how far boot
gets if the mutex is made valid — *without* solving the full IOP
infrastructure problem. The probe (added then reverted in A12, see
the rationale below):

```cpp
// in linux_arm64_main.cpp::boot_kernel_init after the A11/A12 binds
static IOP s_a12_iop_for_arm64;
ee::LIBRARY_sceSif_register(&s_a12_iop_for_arm64);
```

With the static IOP registered, the std::mutex inside IOP_Kernel is
default-constructed and pthread_mutex_lock no longer SEGVs. Boot
gets past the mutex lock and into the rest of `IOP_Kernel::sif_rpc`,
which then asserts:

```
Failed to find handler for sif channel 0x0
[…die] Assertion failed: 'rec'
  Source: game/system/IOP_Kernel.cpp:477
  Function: void IOP_Kernel::sif_rpc(s32, u32, bool, void*, s32, void*, s32)
```

So the boot is now blocked one layer deeper: the IOP_Kernel doesn't
have any `SifRecord` handlers registered (channel 0 =
PLAYER_RPC_CHANNEL). On desktop those are registered by the IOP
overlord-runner code path (`game/runtime.cpp::iop_runner` + the
overlord init chain that calls `set_rpc_queue` for each channel).

The link-finish count stayed at 156 — the assertion fires before
gsound's top-level can complete. So the probe doesn't actually
unblock the validator's check 8b, which is why the static IOP add
was REVERTED in A12 and the proper fix deferred to A13. The
empirical finding still narrows A13's scope: **the mutex SEGV is
not the real next-blocker; the missing SifRecord handler
registration is**. Whatever A13 does must register handlers, not
just init the mutex.

## Recommended A13 unlock + scope

Three candidates, in increasing scope:

### A13-a — static IOP + register null handlers for all 6 channels (smallest)

Combine the probe above with pre-registration of null `SifRecord`
handlers for the 6 RPC channels (PLAYER, LOADER, RAMDISK, DGO, STR,
PLAY). The handler functions can be no-op returning 0; that turns
sif_rpc's assertion into a successful queue-and-return.

Pros: small scope, no thread spawning, no libco coroutine
coordination. Works for every async rpc-call (mode=1) since the
GOAL-side `(when (nonzero? (rpc-busy? …)))` check would also need a
sif_busy that always returns 0 — easy if no handler dispatch
actually happens.

Cons: the null handlers DO NO ACTUAL WORK — any GOAL code that
depends on RPC results (e.g. dgo-load returning the loaded data)
won't work. Boot probably advances by several dozen CGOs before
hitting the first such dependency.

Risk: this is dangerously close to the stub-shaped anti-pattern.
The null handlers must be NAMED honestly and CLEARLY annotated as
"arm64 no-IOP-thread placeholder until A14 spawns the real IOP",
not silently silencing missing functionality.

Unlock: `linux_arm64_main.cpp`, `linux_arm64_runtime_compat.cpp`,
maybe `klink.cpp` for the helper.

### A13-b — synchronous direct-call sif_rpc on arm64 (medium)

Replace the `sceSifCallRpc` body's `iop->kernel.sif_rpc(...) ;
iop->signal_run_iop()` with a direct in-thread dispatch when the
IOP thread isn't spawned. This bypasses the whole IOP_Kernel
machinery on linux-arm64 and runs the RPC body inline (whichever
overlord function matches the channel + fno).

Pros: doesn't need libco / threading. Most RPCs are pure-compute
or trivial-state (e.g. dgo-load just walks a memory buffer). Sync
semantics: caller gets the result back immediately.

Cons: needs `sif_rpc` to know which overlord function corresponds
to which (channel, fno) tuple — duplicates `IOP_Kernel::sif_rpc`'s
dispatch table. Requires editing `game/sce/sif_ee.cpp` (currently
locked-by-implication; would need explicit unlock).

### A13-c — spawn the IOP system thread (largest)

Mirror desktop's `SystemThreadManager` setup: spawn an actual
pthread for the IOP kernel, do the full `iop_thread_run` /
overlord init / libco coroutine setup. The IOP thread serves
RPCs, signals the EE main thread when done, etc.

Pros: the most correct fix. Matches desktop behavior exactly.

Cons: large scope (~10+ files touched), libco interaction is
fragile (the IOP and EE both use libco for cooperative switching),
and on arm64 the libco backend may have its own crashes we haven't
exercised yet. High risk of cascade.

## Recommendation

**A13-a** (mutex pre-init only). It's the minimum that gets past
the pthread_mutex_lock SEGV, and the next next-blocker (the first
sync RPC that needs a real IOP thread) is a separate, narrowly-
named failure class that A14 can address with a similar honest-
exit. Rate-budget caution from A12 prompt favors smaller scopes.

## Anti-cheat invariants — A12 status

Same as A11; no new dodges. The new helper
`klink_a12_ensure_sound_rpc_bound` registers real existing C
functions (`RpcCall_wrapper` etc.), not return-0 stubs. Diff:

- `android/gk_android_main.cpp`        — A12 diag chain + hook chain extension
- `game/linux-arm64/linux_arm64_main.cpp` — A12 diag chain + A12 ensure-bound call
- `game/kernel/common/klink.cpp`       — A12 ensure-bound helper
- `game/kernel/common/klink.h`         — declaration
- `.autoport/reports/A12-fix-summary.md`
- `.autoport/reports/A12-attempt-1-next-blocker.md` (this file)
- `.autoport/reports/A11-baseline-arm64-cgo-hashes.txt` (baseline)

Codegen + asm trampoline + kscheme files: 0 lines changed.
