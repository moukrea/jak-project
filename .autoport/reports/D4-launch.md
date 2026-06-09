# Phase D4 — APK on-device launch report

_Generated: 2026-06-09T23:16:49+02:00_

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

**fail** — MainActivity never reached onCreate (app didn't start).

## Marker observations (from logcat capture)

```
(no matching markers)
```

## Next blocker (if any)

MainActivity never reached onCreate (app didn't start). App never reached MainActivity; the install or launch failed.
