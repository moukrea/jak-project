# Phase D4 — APK on-device launch report

_Generated: 2026-06-10T14:44:00+02:00_

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
06-10 14:41:47.289 25590 25590 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=2
06-10 14:41:51.260 25590 25655 I opengoal-gk: goal_main: calling InitMachine()
06-10 14:41:51.260 25590 25655 I opengoal-gk-full: InitMachine: entered (top-level wrapper)
06-10 14:41:51.261 25590 25655 I opengoal-gk-full: InitMachine: kglobalheap base=0x13fd20 end=0x3eb82e0 size=64456128 (61.47 MB)
06-10 14:41:51.288 25590 25655 I opengoal-gk-full: InitMachine: kglobalheap initialized, used=0
06-10 14:41:51.288 25590 25655 I opengoal-gk-full: InitMachine: kdebugheap base=0x5000000 end=0x7ff0000 size=50266112 (47.94 MB)
06-10 14:41:51.314 25590 25655 I opengoal-gk-full: InitMachine: init_output()
06-10 14:41:51.315 25590 25655 I opengoal-gk-full: InitMachine: print/output buffers reset
06-10 14:41:51.315 25590 25655 I opengoal-gk-full: InitMachine: InitListenerConnect / InitCheckListener
06-10 14:41:51.315 25590 25655 I opengoal-gk-full: InitMachine: MasterUseKernel=1 MasterDebug=1
06-10 14:41:51.315 25590 25655 I opengoal-gk-full: InitMachine: spawning IOP worker thread
06-10 14:41:51.317 25590 25655 I opengoal-gk-full: InitMachine: Deci2Server registered (port=8112, no listener)
06-10 14:41:51.317 25590 25655 I opengoal-gk-full: InitMachine: delegating to jak1::InitMachine
06-10 14:41:51.413 25590 25655 I opengoal-gk: InitIOP OK
06-10 14:41:51.418 25590 25655 I opengoal-gk: Initialized GOAL heap in 2.5 ms
06-10 14:41:51.420 25590 25658 I opengoal-gk: [Overlord DGO] Got DGO file header for KERNEL.CGO with 8 objects
06-10 14:41:51.423 25590 25655 D opengoal-gk: link finish: gcommon
06-10 14:41:51.428 25590 25655 D opengoal-gk: link finish: gstring-h
06-10 14:41:51.431 25590 25655 D opengoal-gk: link finish: gkernel-h
06-10 14:41:51.435 25590 25655 D opengoal-gk: link finish: gkernel
06-10 14:41:51.445 25590 25655 D opengoal-gk: link finish: pskernel
06-10 14:41:51.446 25590 25655 D opengoal-gk: link finish: gstring
06-10 14:41:51.447 25590 25655 D opengoal-gk: link finish: dgo-h
06-10 14:41:51.447 25590 25655 D opengoal-gk: link finish: gstate
06-10 14:41:51.449 25590 25655 I opengoal-gk: A17-DIAG sym-bind-trace: bound the pc-* helper surface (~80 helpers + A32: __pc-texture-upload-now, __read-ee-timer, __send-gfx-dma-chain) to a17_pc_default no-op so pckernel-h/common top-level + (play) reset chain + the tpage-463 top-level texture upload don't SIGILL on unbound symbols
06-10 14:41:51.456 25590 25658 I opengoal-gk: [Overlord DGO] Got DGO file header for GAME.CGO with 346 objects
06-10 14:41:51.457 25590 25655 D opengoal-gk: link finish: types-h
06-10 14:41:51.458 25590 25655 D opengoal-gk: link finish: vu1-macros
06-10 14:41:51.459 25590 25655 D opengoal-gk: link finish: math
```

## Next blocker (if any)

App started but renderer never entered (likely stuck before InitMachine returned). See .autoport/reports/D4-boot.log tail for context.
