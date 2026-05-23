# Phase D4 — APK on-device launch report

_Generated: 2026-05-23T12:10:16+02:00_

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
05-23 12:08:03.875  7213  7213 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=2
05-23 12:08:04.237  7213  7376 I opengoal-gk: goal_main: calling InitMachine()
05-23 12:08:04.237  7213  7376 I opengoal-gk-full: InitMachine: entered (top-level wrapper)
05-23 12:08:04.237  7213  7376 I opengoal-gk-full: InitMachine: kglobalheap base=0x13fd20 end=0x3eb82e0 size=64456128 (61.47 MB)
05-23 12:08:04.271  7213  7376 I opengoal-gk-full: InitMachine: kglobalheap initialized, used=0
05-23 12:08:04.271  7213  7376 I opengoal-gk-full: InitMachine: kdebugheap base=0x5000000 end=0x7ff0000 size=50266112 (47.94 MB)
05-23 12:08:04.317  7213  7376 I opengoal-gk-full: InitMachine: init_output()
05-23 12:08:04.317  7213  7376 I opengoal-gk-full: InitMachine: print/output buffers reset
05-23 12:08:04.317  7213  7376 I opengoal-gk-full: InitMachine: InitListenerConnect / InitCheckListener
05-23 12:08:04.317  7213  7376 I opengoal-gk-full: InitMachine: MasterUseKernel=1 MasterDebug=1
05-23 12:08:04.317  7213  7376 I opengoal-gk-full: InitMachine: spawning IOP worker thread
05-23 12:08:04.317  7213  7376 I opengoal-gk-full: InitMachine: Deci2Server registered (port=8112, no listener)
05-23 12:08:04.317  7213  7376 I opengoal-gk-full: InitMachine: delegating to jak1::InitMachine
05-23 12:08:04.339  7213  7376 I opengoal-gk: InitIOP OK
05-23 12:08:04.339  7213  7376 I opengoal-gk: Initialized GOAL heap in 0.087 ms
05-23 12:08:04.340  7213  7386 I opengoal-gk: [Overlord DGO] Got DGO file header for KERNEL.CGO with 8 objects
05-23 12:08:04.340  7213  7376 D opengoal-gk: link finish: gcommon
05-23 12:08:04.341  7213  7376 D opengoal-gk: link finish: gstring-h
05-23 12:08:04.341  7213  7376 D opengoal-gk: link finish: gkernel-h
05-23 12:08:04.342  7213  7376 D opengoal-gk: link finish: gkernel
05-23 12:08:04.343  7213  7376 D opengoal-gk: link finish: pskernel
05-23 12:08:04.344  7213  7376 D opengoal-gk: link finish: gstring
05-23 12:08:04.344  7213  7376 D opengoal-gk: link finish: dgo-h
05-23 12:08:04.344  7213  7376 D opengoal-gk: link finish: gstate
05-23 12:08:04.347  7213  7386 I opengoal-gk: [Overlord DGO] Got DGO file header for GAME.CGO with 346 objects
05-23 12:08:04.347  7213  7376 D opengoal-gk: link finish: types-h
05-23 12:08:04.348  7213  7376 D opengoal-gk: link finish: vu1-macros
05-23 12:08:04.348  7213  7376 D opengoal-gk: link finish: math
05-23 12:08:04.349  7213  7376 D opengoal-gk: link finish: vector-h
05-23 12:08:04.350  7213  7376 D opengoal-gk: link finish: gravity-h
05-23 12:08:04.350  7213  7376 D opengoal-gk: link finish: bounding-box-h
05-23 12:08:04.351  7213  7376 D opengoal-gk: link finish: matrix-h
05-23 12:08:04.351  7213  7376 D opengoal-gk: link finish: quaternion-h
05-23 12:08:04.351  7213  7376 D opengoal-gk: link finish: euler-h
05-23 12:08:04.352  7213  7376 D opengoal-gk: link finish: transform-h
05-23 12:08:04.352  7213  7376 D opengoal-gk: link finish: geometry-h
05-23 12:08:04.352  7213  7376 D opengoal-gk: link finish: trigonometry-h
05-23 12:08:04.352  7213  7376 D opengoal-gk: link finish: transformq-h
05-23 12:08:04.353  7213  7376 D opengoal-gk: link finish: bounding-box
05-23 12:08:04.353  7213  7376 D opengoal-gk: link finish: matrix
05-23 12:08:04.354  7213  7376 D opengoal-gk: link finish: transform
05-23 12:08:04.354  7213  7376 D opengoal-gk: link finish: quaternion
05-23 12:08:04.354  7213  7376 D opengoal-gk: link finish: euler
05-23 12:08:04.355  7213  7376 D opengoal-gk: link finish: geometry
05-23 12:08:04.355  7213  7376 D opengoal-gk: link finish: trigonometry
05-23 12:08:04.355  7213  7376 D opengoal-gk: link finish: gsound-h
05-23 12:08:04.357  7213  7376 D opengoal-gk: link finish: timer-h
05-23 12:08:04.357  7213  7376 D opengoal-gk: link finish: timer
05-23 12:08:04.358  7213  7376 D opengoal-gk: link finish: vif-h
05-23 12:08:04.358  7213  7376 D opengoal-gk: link finish: dma-h
(no matching markers)
```

## Next blocker (if any)

App started but renderer never entered (likely stuck before InitMachine returned). See .autoport/reports/D4-boot.log tail for context.
