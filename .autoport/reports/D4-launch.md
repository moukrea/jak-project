# Phase D4 — APK on-device launch report

_Generated: 2026-05-21T23:16:09+02:00_

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

**pass**

## Marker observations (from logcat capture)

```
05-21 23:15:53.150 25119 25119 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=1
05-21 23:15:53.583 25119 25417 I opengoal-gk: goal_main: calling InitMachine()
05-21 23:15:53.583 25119 25417 I opengoal-gk-full: InitMachine: entered (top-level wrapper)
05-21 23:15:53.583 25119 25417 I opengoal-gk-full: InitMachine: kglobalheap base=0x13fd20 end=0x3eb82e0 size=64456128 (61.47 MB)
05-21 23:15:53.728 25119 25417 I opengoal-gk-full: InitMachine: kglobalheap initialized, used=0
05-21 23:15:53.728 25119 25417 I opengoal-gk-full: InitMachine: kdebugheap base=0x5000000 end=0x7ff0000 size=50266112 (47.94 MB)
05-21 23:15:53.805 25119 25417 I opengoal-gk-full: InitMachine: init_output()
05-21 23:15:53.806 25119 25417 I opengoal-gk-full: InitMachine: print/output buffers reset
05-21 23:15:53.806 25119 25417 I opengoal-gk-full: InitMachine: InitListenerConnect / InitCheckListener
05-21 23:15:53.806 25119 25417 I opengoal-gk-full: InitMachine: MasterUseKernel=1 MasterDebug=1
05-21 23:15:53.806 25119 25417 I opengoal-gk-full: InitMachine: spawning IOP worker thread
05-21 23:15:53.806 25119 25417 I opengoal-gk-full: InitMachine: Deci2Server registered (port=8112, no listener)
05-21 23:15:53.806 25119 25417 I opengoal-gk-full: InitMachine: g_android_skip_goal_call=1 (trampoline returns 0 instead of running GOAL bytecode — see SUPERVISOR_JOURNAL.md for the R14/R15 ABI gap)
05-21 23:15:53.806 25119 25417 I opengoal-gk-full: InitMachine: delegating to jak1::InitMachine
05-21 23:15:53.844 25119 25417 I opengoal-gk: InitIOP OK
05-21 23:15:53.844 25119 25417 I opengoal-gk: Initialized GOAL heap in 0.11 ms
05-21 23:15:53.845 25119 25457 I opengoal-gk: [Overlord DGO] Got DGO file header for KERNEL.CGO with 8 objects
05-21 23:15:53.846 25119 25417 D opengoal-gk: link finish: gcommon
05-21 23:15:53.847 25119 25417 D opengoal-gk: link finish: gstring-h
05-21 23:15:53.847 25119 25417 D opengoal-gk: link finish: gkernel-h
05-21 23:15:53.847 25119 25417 D opengoal-gk: link finish: gkernel
05-21 23:15:53.848 25119 25417 D opengoal-gk: link finish: pskernel
05-21 23:15:53.848 25119 25417 D opengoal-gk: link finish: gstring
05-21 23:15:53.849 25119 25417 D opengoal-gk: link finish: dgo-h
05-21 23:15:53.849 25119 25417 D opengoal-gk: link finish: gstate
05-21 23:15:53.849 25119 25417 I opengoal-gk-full: InitMachine: jak1::InitMachine returned -1
05-21 23:15:53.849 25119 25417 I opengoal-gk: goal_main: InitMachine returned -1
05-21 23:15:53.849 25119 25417 I opengoal-gk: android_renderer_run: entered
05-21 23:15:55.510 25119 25417 I opengoal-gk: android_renderer: sustained swap 60
05-21 23:15:56.614 25119 25417 I opengoal-gk: android_renderer: sustained swap 120
05-21 23:15:57.719 25119 25417 I opengoal-gk: android_renderer: sustained swap 180
05-21 23:15:58.839 25119 25417 I opengoal-gk: android_renderer: sustained swap 240
05-21 23:15:59.969 25119 25417 I opengoal-gk: android_renderer: sustained swap 300
05-21 23:16:01.086 25119 25417 I opengoal-gk: android_renderer: sustained swap 360
05-21 23:16:02.224 25119 25417 I opengoal-gk: android_renderer: sustained swap 420
05-21 23:16:03.378 25119 25417 I opengoal-gk: android_renderer: sustained swap 480
05-21 23:16:04.538 25119 25417 I opengoal-gk: android_renderer: sustained swap 540
05-21 23:16:05.704 25119 25417 I opengoal-gk: android_renderer: sustained swap 600
05-21 23:16:06.896 25119 25417 I opengoal-gk: android_renderer: sustained swap 660
```

## Next blocker (if any)

None — D4 markers were all observed. Ready for D5+.
