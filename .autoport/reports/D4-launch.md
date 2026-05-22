# Phase D4 — APK on-device launch report

_Generated: 2026-05-22T07:06:21+02:00_

## What was wired

- `android/android_jak1_kernel_stubs.cpp` deleted (D3 abort-stub removed).
- `android/CMakeLists.txt` now compiles:
  - `game/kernel/jak1/kmachine.cpp` (jak1::InitMachine, InitIOP, InitMachineScheme, InitParms, ShutdownMachine, kopen, PutDisplayEnv, update_discord_rpc, pc_set_levels)
  - `game/kernel/jak1/kboot.cpp` (jak1::goal_main, KernelCheckAndDispatch, KernelShutdown, kboot_init_globals, BootVideoMode)
- `android/android_runtime_compat.cpp` extended with real-body shims for:
  - common/kmachine helpers: kmachine_init_globals_common, InitCD, InitVideo, init_common_pc_port_functions, CPadOpen/CPadGetData, InstallHandler, InstallDebugHandler, klength/kseek/kread/kwrite/kclose/kmkdir, dma_to_iop, Decode\* (Language/Aspect/Volume/Territory/Timeout/InactiveTimeout/Time), offset_of_s7, vif_interrupt_callback
  - common/kmachine globals: isodrv, modsrc, reboot_iop, init_types, pad_dma_buf, vif1/vblank_interrupt_handler, ee_clock_timer, g_pc_port_funcs
  - discord (external + jak1): gDiscordRpcEnabled, gStartTime, init_discord_rpc, set_discord_rpc, get_full_level_name, get_base_level_name, indoors, get_time_of_day, handleDiscord*, jak1::level_names/level_name_remap/indoor_levels/time_of_day_str, libdiscord-rpc C ABI (Discord_Initialize/Shutdown/RunCallbacks/UpdatePresence/ClearPresence/Respond/UpdateHandlers/UpdateConnection)
  - Gfx accessors: GetCurrentRenderer (returns nullptr), g_debug_settings, g_splash, Init/Exit/Loop, vsync/sync_path, CollisionRenderer*
  - Display::g_displays + GetMainDisplay (nullptr) + InitMainDisplay/Kill*
  - SCE libgraph: ee::sceGsResetPath, ee::sceGsResetGraph, sceGsSyncV, sceGsSyncPath (global ns)
  - InputModifiers ctor (pulled by DebugSettings default ctor)

## Determination

**partial** — App started but renderer never entered (likely stuck before InitMachine returned).

## Marker observations (from logcat capture)

```
05-22 07:04:07.849 19002 19002 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=2
05-22 07:04:08.272 19002 19493 I opengoal-gk: goal_main: calling InitMachine()
05-22 07:04:08.272 19002 19493 I opengoal-gk-full: InitMachine: entered (top-level wrapper)
05-22 07:04:08.272 19002 19493 I opengoal-gk-full: InitMachine: kglobalheap base=0x13fd20 end=0x3eb82e0 size=64456128 (61.47 MB)
05-22 07:04:08.321 19002 19493 I opengoal-gk-full: InitMachine: kglobalheap initialized, used=0
05-22 07:04:08.322 19002 19493 I opengoal-gk-full: InitMachine: kdebugheap base=0x5000000 end=0x7ff0000 size=50266112 (47.94 MB)
05-22 07:04:08.350 19002 19493 I opengoal-gk-full: InitMachine: init_output()
05-22 07:04:08.351 19002 19493 I opengoal-gk-full: InitMachine: print/output buffers reset
05-22 07:04:08.351 19002 19493 I opengoal-gk-full: InitMachine: InitListenerConnect / InitCheckListener
05-22 07:04:08.351 19002 19493 I opengoal-gk-full: InitMachine: MasterUseKernel=1 MasterDebug=1
05-22 07:04:08.351 19002 19493 I opengoal-gk-full: InitMachine: spawning IOP worker thread
05-22 07:04:08.351 19002 19493 I opengoal-gk-full: InitMachine: Deci2Server registered (port=8112, no listener)
05-22 07:04:08.351 19002 19493 I opengoal-gk-full: InitMachine: delegating to jak1::InitMachine
05-22 07:04:08.379 19002 19493 I opengoal-gk: InitIOP OK
05-22 07:04:08.380 19002 19493 I opengoal-gk: Initialized GOAL heap in 0.063 ms
05-22 07:04:08.381 19002 19515 I opengoal-gk: [Overlord DGO] Got DGO file header for KERNEL.CGO with 8 objects
05-22 07:04:08.381 19002 19493 D opengoal-gk: link finish: gcommon
05-22 07:04:08.383 19002 19493 F libc    : Fatal signal 4 (SIGILL), code 1 (ILL_ILLOPC), fault addr 0x7208223674 in tid 19493 (SDLThread), pid 19002 (SDLActivity)
05-22 07:04:09.905 19534 19534 F DEBUG   : signal 4 (SIGILL), code 1 (ILL_ILLOPC), fault addr 0x7208223674
```

## Next blocker (if any)

App started but renderer never entered (likely stuck before InitMachine returned). See .autoport/reports/D4-boot.log tail for context.
