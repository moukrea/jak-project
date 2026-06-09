# Phase D4 — APK on-device launch report

_Generated: 2026-05-24T05:15:20+02:00_

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
05-24 05:13:07.401  4937  4937 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=2
05-24 05:13:07.731  4937  5179 I opengoal-gk: goal_main: calling InitMachine()
05-24 05:13:07.731  4937  5179 I opengoal-gk-full: InitMachine: entered (top-level wrapper)
05-24 05:13:07.731  4937  5179 I opengoal-gk-full: InitMachine: kglobalheap base=0x13fd20 end=0x3eb82e0 size=64456128 (61.47 MB)
05-24 05:13:07.766  4937  5179 I opengoal-gk-full: InitMachine: kglobalheap initialized, used=0
05-24 05:13:07.766  4937  5179 I opengoal-gk-full: InitMachine: kdebugheap base=0x5000000 end=0x7ff0000 size=50266112 (47.94 MB)
05-24 05:13:07.794  4937  5179 I opengoal-gk-full: InitMachine: init_output()
05-24 05:13:07.794  4937  5179 I opengoal-gk-full: InitMachine: print/output buffers reset
05-24 05:13:07.794  4937  5179 I opengoal-gk-full: InitMachine: InitListenerConnect / InitCheckListener
05-24 05:13:07.794  4937  5179 I opengoal-gk-full: InitMachine: MasterUseKernel=1 MasterDebug=1
05-24 05:13:07.794  4937  5179 I opengoal-gk-full: InitMachine: spawning IOP worker thread
05-24 05:13:07.794  4937  5179 I opengoal-gk-full: InitMachine: Deci2Server registered (port=8112, no listener)
05-24 05:13:07.794  4937  5179 I opengoal-gk-full: InitMachine: delegating to jak1::InitMachine
05-24 05:13:07.813  4937  5179 I opengoal-gk: InitIOP OK
05-24 05:13:07.813  4937  5179 I opengoal-gk: Initialized GOAL heap in 0.072 ms
05-24 05:13:07.813  4937  5191 I opengoal-gk: [Overlord DGO] Got DGO file header for KERNEL.CGO with 8 objects
05-24 05:13:07.813  4937  5179 D opengoal-gk: link finish: gcommon
05-24 05:13:07.814  4937  5179 D opengoal-gk: link finish: gstring-h
05-24 05:13:07.814  4937  5179 D opengoal-gk: link finish: gkernel-h
05-24 05:13:07.815  4937  5179 D opengoal-gk: link finish: gkernel
05-24 05:13:07.817  4937  5179 D opengoal-gk: link finish: pskernel
05-24 05:13:07.817  4937  5179 D opengoal-gk: link finish: gstring
05-24 05:13:07.817  4937  5179 D opengoal-gk: link finish: dgo-h
05-24 05:13:07.818  4937  5179 D opengoal-gk: link finish: gstate
05-24 05:13:07.818  4937  5179 I opengoal-gk: A17-DIAG sym-bind-trace: bound the pc-* helper surface (~80 helpers) to a17_pc_default no-op so pckernel-h/common top-level + (play) reset chain don't SIGILL on unbound symbols
05-24 05:13:07.819  4937  5191 I opengoal-gk: [Overlord DGO] Got DGO file header for GAME.CGO with 346 objects
05-24 05:13:07.820  4937  5179 D opengoal-gk: link finish: types-h
05-24 05:13:07.820  4937  5179 D opengoal-gk: link finish: vu1-macros
05-24 05:13:07.820  4937  5179 D opengoal-gk: link finish: math
05-24 05:13:07.821  4937  5179 D opengoal-gk: link finish: vector-h
05-24 05:13:07.822  4937  5179 D opengoal-gk: link finish: gravity-h
05-24 05:13:07.822  4937  5179 D opengoal-gk: link finish: bounding-box-h
05-24 05:13:07.823  4937  5179 D opengoal-gk: link finish: matrix-h
05-24 05:13:07.823  4937  5179 D opengoal-gk: link finish: quaternion-h
05-24 05:13:07.823  4937  5179 D opengoal-gk: link finish: euler-h
05-24 05:13:07.823  4937  5179 D opengoal-gk: link finish: transform-h
05-24 05:13:07.823  4937  5179 D opengoal-gk: link finish: geometry-h
05-24 05:13:07.824  4937  5179 D opengoal-gk: link finish: trigonometry-h
05-24 05:13:07.824  4937  5179 D opengoal-gk: link finish: transformq-h
05-24 05:13:07.824  4937  5179 D opengoal-gk: link finish: bounding-box
05-24 05:13:07.825  4937  5179 D opengoal-gk: link finish: matrix
05-24 05:13:07.825  4937  5179 D opengoal-gk: link finish: transform
05-24 05:13:07.825  4937  5179 D opengoal-gk: link finish: quaternion
05-24 05:13:07.826  4937  5179 D opengoal-gk: link finish: euler
05-24 05:13:07.826  4937  5179 D opengoal-gk: link finish: geometry
05-24 05:13:07.826  4937  5179 D opengoal-gk: link finish: trigonometry
05-24 05:13:07.826  4937  5179 D opengoal-gk: link finish: gsound-h
05-24 05:13:07.828  4937  5179 D opengoal-gk: link finish: timer-h
05-24 05:13:07.828  4937  5179 D opengoal-gk: link finish: timer
05-24 05:13:07.828  4937  5179 D opengoal-gk: link finish: vif-h
(no matching markers)
```

## Next blocker (if any)

App started but renderer never entered (likely stuck before InitMachine returned). See .autoport/reports/D4-boot.log tail for context.
