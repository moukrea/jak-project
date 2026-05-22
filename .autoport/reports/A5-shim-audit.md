# Phase A5 — shim audit

Authored 2026-05-22 during phase A5. The A5 phase narrowly unlocked
`goalc/emitter/IGenARM64.cpp` + `goalc/emitter/ObjectGenerator.cpp` to
emit a 3-instruction ADRP+ADD+LDR/STR (X16-scratch) far-reloc sequence
for every GOAL symbol-table memory access. The old single-instruction
`LDR/STR Wt, [X14, #imm12_scaled4]` encoding capped the s7-relative
range at 16 KB (W-form); symbols past that overflowed and the runtime
klink dispatcher in `game/kernel/common/klink.cpp` substituted a NOP.
C4's boot histogram reported 691 such NOPs on the pre-A5 KERNEL.CGO.

After A5 the corresponding runtime counter dropped to 0 (re-run of
`c4_run.sh` against the regenerated arm64 CGOs):

```
linux-arm64: klink-arm64 patch histogram \
  ADRP: 1415, ADD imm12: 1415, LDR imm12: 0, STR imm12: 0, \
  LDR-literal: 10, raw u32: 400, unhandled: 0, out-of-range: 0
```

The 691-NOP gap is closed. The follow-up question this report answers
is: now that the bytecode actually executes its sym-mem accesses, can
the D4-era dodge shims in `android/android_runtime_compat.cpp` +
`android/android_runtime_full.cpp` be removed without regressing the
device-side D4 marker scoreboard?

## D4-era dodge sites (full.cpp)

D4 added two co-dependent dodges to `android/android_runtime_full.cpp`
to route the boot path around the pre-A5 691-NOP'd GOAL bytecode:

1. `InitMachine` step 6.6 writes `g_android_skip_goal_call = 1`, arming
   the early-return in `_call_goal_asm_arm64` /
   `_call_goal_on_stack_asm_arm64` (the trampolines in
   `game/kernel/asm_funcs_arm64.s` that asm-link C++ → GOAL).
2. `KernelCheckAndDispatch` checks the same flag and enters a passive
   `sleep_for(50ms)` loop instead of forwarding into
   `jak1::KernelCheckAndDispatch`, because the upstream dispatcher
   immediately dereferences `ListenerFunction->value` — a symbol that
   only exists after the post-link top-level execution. The pre-A5
   dodge skipped that top-level execution, so the dispatcher had to
   skip too or it asserted on a null Ptr.

Both sites were honestly documented at D4 close (see the comments in
`android_runtime_full.cpp` around lines 215-226 and 257-271).

## Disposition

- DELETE: `g_android_skip_goal_call` storage definition (was
  `android/android_runtime_compat.cpp` line 118 at D4 close). Moved to
  `game/kernel/asm_funcs_arm64.s` so both the Android build and the
  linux-arm64 cross build (which doesn't link
  `android_runtime_compat.cpp`) resolve the symbol from a single
  authoritative location. Removing the duplicate definition unblocked
  C4's re-run (the linker error `undefined symbol:
  g_android_skip_goal_call` in `game/linux-arm64/gk` was caused by D4
  defining it only in the Android compat translation unit).

- KEEP: `InitMachine` step 6.6 — the `g_android_skip_goal_call = 1`
  write in `android/android_runtime_full.cpp`. _Originally tagged
  DELETE during A5 design, restored to KEEP after the first device
  validation surfaced a SECOND distinct emitter bug._
  **Why kept:** A5's emitter unlock fixed the imm12-overflow leg of
  the goalc-arm64 bug surface (the 691-NOP gap is closed and the
  patcher histogram shows out-of-range=0). But the device boot
  uncovered a separate, structurally similar bug in the GOAL pointer
  dereference helpers `load_goal_gpr` / `store_goal_gpr` /
  `load_goal_xmm32` / `load_goal_xmm128` / `store_goal_xmm32` /
  `store_goal_vf` in `goalc/emitter/IGenARM64.cpp`: each function
  receives the EE-offset register as `Register off` and then does
  `(void)off;` — the EE base is dropped from every emitted
  `LDR/STR Wt, [Xbase, #imm12]` and the GOAL pointer (a 32-bit
  EE-relative offset) is dereferenced as a raw 64-bit host address.
  On x86 the same helpers fold off into the SIB byte
  (`[base + r15 + imm]`), so desktop x86 was never affected. On
  arm64 with EE memory at a high VA, the first field deref produced
  by the post-A5 bytecode SIGSEGVs (fault addr 0x17fd34,
  `x9=0x17fd24` — a GOAL pointer zero-extended from a Wt load that
  should have been `LDR Wt, [Xbase, X15]`).
  **How to apply:** keep this dodge armed until a follow-up phase
  expands the off-register IGenARM64 helpers to either the
  register-form `LDR/STR Wt, [Xn, Xm, LSL #amount]` (zero-offset
  case) or a 2-instruction `ADD Xtmp, Xbase, Xoff; LDR/STR Wt,
  [Xtmp, #imm]` (non-zero-offset case) via the same X16-scratch
  sentinel mechanism A5 introduced for sym-mem.

- KEEP: `KernelCheckAndDispatch` skip-flag branch — the
  `if (g_android_skip_goal_call) { passive sleep loop }` branch in
  `android/android_runtime_full.cpp`. _Originally tagged DELETE,
  restored to KEEP for the same reason as step 6.6 above._
  **Why kept:** with the skip-flag armed (per step 6.6) the GOAL
  kernel top-level never runs, so `ListenerFunction` is never
  populated by gkernel and `jak1::KernelCheckAndDispatch`'s deref
  of `ListenerFunction->value` asserts on a null Ptr. The passive
  sleep loop holds the dispatcher thread alive without entering
  the upstream dispatcher; the renderer thread keeps iterating
  frames so D4's swap-loop markers still fire.
  **How to apply:** keep this branch in lock-step with the
  step-6.6 dodge. Once the off-register emitter bug is fixed,
  both should be removed in the same change so the runtime no
  longer needs the skip-flag at all.

## Retained as Bionic / runtime adapters (compat.cpp)

The following compat.cpp shims are NOT dodge-only — they're real
implementations of upstream symbols whose desktop definitions either
don't exist on Bionic or live in translation units the Android build
deliberately excludes. They remain in place independent of A5.

- KEEP: `g_ee_main_mem` storage. Owns the 256 MB GOAL EE main memory
  arena. Upstream defines this in `game/runtime.cpp` which is
  excluded from the Android build (SDL3/ImGui/discord entanglement).
- KEEP: `g_game_version`, `g_main_thread_id`, `g_server_port`,
  `g_background_worker`. Same rationale — upstream owners are in
  `game/runtime.cpp`.
- KEEP: `lg::internal::log_message` / `log_print` / `log_vprintf` +
  the `lg::*` configuration no-ops. Route the upstream `lg::log/info/
  warn/print` templates into `__android_log_print` so output reaches
  `adb logcat`. The upstream `common/log/log.cpp` writes to stdout
  via `fmt::color`, which Bionic cuts off and which logcat doesn't
  read.
- KEEP: `compat_mallinfo` / `opengoal_compat_mallinfo`. Bionic
  reshaped `mallinfo()` to a different struct; a zero-filled adapter
  is safer than abort.
- KEEP: `backtrace`, `backtrace_symbols`, `backtrace_symbols_fd`
  no-ops. `<execinfo.h>` is unavailable on the API 29 target
  (Bionic ships it from API 33). The desktop callers are diagnostic
  only; aborting without frames is correct behaviour.
- KEEP: `CacheFlush`. PS2-EE `FlushCache` syscall surrogate; arm64
  uses `__builtin___clear_cache` under the hood for the same purpose.
- KEEP: `LinkedFunctionTable::reg` stub. JIT-debugger feature
  deliberately disabled on Android.
- KEEP: `GlobalProfiler::*` stubs. Profiler is off on Android (no UI
  to dump-to-json into).
- KEEP: `set_current_thread_name`. Bionic's `pthread_setname_np` only
  takes one argument vs glibc's two; the adapter delegates to the
  single-arg form.

## kmachine support shims (compat.cpp) — KEEP

The kmachine helpers added in D4 (kmachine_init_globals_common,
InitCD, InitVideo, init_common_pc_port_functions, CPadOpen/CPadGetData,
InstallHandler, InstallDebugHandler, klength/kseek/kread/kwrite/kclose/
kmkdir, dma_to_iop, Decode\* (Language/Aspect/Volume/Territory/Timeout/
InactiveTimeout/Time), offset_of_s7, vif_interrupt_callback,
sceGsResetPath, sceGsResetGraph, sceGsSyncV, sceGsSyncPath,
InputModifiers ctor, GetCurrentRenderer/Init/Exit/vsync/sync_path/Loop,
register/clear_vsync_callback, CollisionRendererSetMode,
GetMainDisplay, KillDisplay, InitMainDisplay) are real implementations
of upstream extern declarations that the Android build needs because
their canonical definitions live in `game/runtime.cpp` /
`game/system/Gfx.cpp` / `game/system/Display.cpp` — all excluded from
the Android build for the same SDL3/ImGui/discord reason as
`g_ee_main_mem` above.

- KEEP: all of the kmachine support shims listed above. They are not
  bytecode dodges — they are platform glue. If they were deleted,
  `game/kernel/jak1/kmachine.cpp` (which the Android build does
  compile, per the D4 wiring) would fail to link.

## discord / iso support shims (compat.cpp) — KEEP

- KEEP: discord-rpc C ABI stubs (`Discord_*`), `gDiscordRpcEnabled`,
  `init_discord_rpc`, `set_discord_rpc`, `handleDiscord*`. Android
  build doesn't ship libdiscord-rpc; the stubs satisfy the linker
  while the rich-presence calls become no-ops.
- KEEP: `init_types`, `isodrv`, `modsrc`, `reboot_iop`,
  `pad_dma_buf`, `vif1_interrupt_handler`,
  `vblank_interrupt_handler`, `ee_clock_timer`, `g_pc_port_funcs`,
  `masterConfig`, `MasterDebug`, `MasterUseKernel`,
  `DiskBootMode`, etc. Upstream-owned globals normally defined by
  `game/runtime.cpp` or `game/kernel/common/kmachine.cpp`'s
  `init_globals` chain, exposed here at the same default values the
  upstream init functions would write.

## Net effect on compat.cpp

The single dodge-only definition this audit removes from compat.cpp
(`extern "C" u32 g_android_skip_goal_call = 0;` plus its 12-line
comment block) is the only line removable without breaking the
Android build. Every other line in compat.cpp is either a Bionic
adapter or a real implementation of an upstream symbol; deleting any
of them would surface as an undefined-reference at link time, not as
a behavioural regression.

The two pure-dodge sites in `android_runtime_full.cpp` (Step 6.6 +
the KernelCheckAndDispatch skip-flag branch) were initially removed
by this audit, but the post-removal D4 re-run on device surfaced a
second arm64 emitter bug (the off-register drop in
`load_goal_gpr`/`store_goal_gpr` and friends — see the KEEP entries
in the Disposition section above). Both dodges are restored here in
lock-step, with the dispositions revised to KEEP-WITH-JUSTIFICATION,
exactly per the supervisor's prompt fallback ("If D4 fails at this
step, restore the shims that were needed; the validator will then
require an explicit justification in the audit report for each
retained shim").

A follow-up phase is responsible for fixing the off-register bug at
the emitter level and removing both dodges in the same change.

## Follow-up — off-register emitter bug discovered during A5

This is the engineering finding that A5 did NOT close but DID
surface. Recorded here so the next phase has the exact shape and
location of the bug:

- **Where**: `goalc/emitter/IGenARM64.cpp`, the family of helpers
  that take a `Register off` parameter and immediately discard it
  via `(void)off;`:
  - `load_goal_gpr` (size in {1,2,4,8}, signed/unsigned)
  - `store_goal_gpr` (size in {1,2,4,8})
  - `load_goal_xmm32`, `store_goal_xmm32`
  - `load_goal_xmm128`, `store_goal_vf`
  - `load{8,16,32,64}{s,u}_gpr64_gpr64_plus_gpr64_plus_s32`
  - `store{8,16,32,64}_gpr64_gpr64_plus_gpr64_plus_s32`
- **What's wrong**: each helper drops the EE-offset register
  (mapped to `x15` on arm64 by the trampolines in
  `game/kernel/asm_funcs_arm64.s`). The emitted single-instruction
  `LDR/STR Wt, [Xbase, #imm12]` accesses host address
  `(uint64_t)Xbase + imm12` instead of the intended
  `(uint64_t)X15 + Xbase + imm12`.
- **Why x86 doesn't see it**: the x86 helpers take a `Register off`
  too, but they fold it into the SIB byte:
  `mov [Rbase + R15 + imm32], Rsrc` — the EE base is part of the
  effective address. The arm64 single-immediate `LDR/STR` has no
  equivalent 3-operand encoding.
- **Suggested fix shape**: expand each helper to a 2-instruction
  sequence inside `ObjectGenerator::add_instr` using a sentinel
  marker (same mechanism as A5's sym-mem far-reloc expansion):
  - `ADD X16, Xbase, X15`  (X16 = host address sans imm)
  - `LDR/STR Wt, [X16, #imm12]`
  The X16 scratch is already reserved by A5 (the goalc register
  allocator caps at id 9 / R10 and never assigns X16/X17 to a live
  value).
- **Symptoms observed**: SIGSEGV with `fault addr 0x17fd34` during
  the first gcommon top-level execution; `x9` holds a zero-extended
  32-bit GOAL pointer (`0x17fd24`) that should have been added to
  `x15` (= EE base `0x720aa2a000` on the user's Redmi Note 9 Pro)
  before the deref.

## Verification

The post-audit D4 re-run captures the final state of the boot path
under A5's wider unlock. See `.autoport/reports/D4-boot.log` and
`.autoport/reports/D4-launch.md` for the latest device-side evidence.
