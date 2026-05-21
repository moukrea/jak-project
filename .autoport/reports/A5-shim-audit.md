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

- DELETE: `InitMachine` step 6.6 — the `g_android_skip_goal_call = 1`
  write in `android/android_runtime_full.cpp`. After A5 closes the
  691-NOP gap, the GOAL trampolines can actually run the post-link
  top-level execution; arming the skip-flag would defeat the whole
  point of A5. The flag's storage stays in `asm_funcs_arm64.s` (as a
  zero-initialised data word) so any future need to arm it from C++
  remains a one-line write rather than a re-introduction of the
  symbol definition.

- DELETE: `KernelCheckAndDispatch` skip-flag branch — the
  `if (g_android_skip_goal_call) { passive sleep loop }` branch in
  `android/android_runtime_full.cpp`. With A5's bytecode executing,
  `ListenerFunction` is populated by the gkernel top-level and
  `jak1::KernelCheckAndDispatch` can be called directly.

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
the KernelCheckAndDispatch skip-flag branch) are removed by this
audit. Their removal exposes the post-A5 GOAL execution path to the
device runtime — which is the entire point of A5. If the device-side
D4 re-run fails after their removal, the dispositions above are
revised to KEEP-WITH-JUSTIFICATION and a follow-up phase tracks the
remaining bytecode bug that's still blocking real GOAL execution on
Android.

## Verification

The post-audit D4 re-run captures the final state of the boot path
under A5's wider unlock. See `.autoport/reports/D4-boot.log` and
`.autoport/reports/D4-launch.md` for the latest device-side evidence.
