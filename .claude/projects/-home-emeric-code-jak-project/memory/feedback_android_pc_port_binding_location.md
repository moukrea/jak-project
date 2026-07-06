---
name: feedback_android_pc_port_binding_location
description: Android pc-* port functions are bound in a17_bind_pc_helpers() (gk_android_main.cpp), NOT common/kmachine.cpp — any new pc-port fn the shared GOAL menu calls MUST be bound there or it SIGILLs on device.
metadata:
  type: feedback
---

On Android, `game/kernel/common/kmachine.cpp` is **NOT compiled** (android/CMakeLists.txt excludes it;
`init_common_pc_port_functions` resolves to a NO-OP stub in android_runtime_compat.cpp that registers
ZERO pc-* functions). Android's real pc-* table is **`a17_bind_pc_helpers()` in
`android/gk_android_main.cpp`** (~line 899): a hand-maintained list binding each `pc-*` symbol, most to
the `a17_pc_default` no-op, some to real `a35_*` bodies (pc-set-display-mode!, pc-set-fps-counter, etc.).
`game/settings/settings.cpp` is also not linked on Android (only `DebugSettings` exists there;
`DisplaySettings::load/save_settings` are undefined).

**Why:** a GOAL menu is shared source compiled into BOTH the x86 CGOs and the Android APK DGOs. If the
menu calls a pc-port function that you registered ONLY in common/kmachine.cpp, that symbol's value slot
is 0 on Android → `BLR EE_BASE` → **SIGILL** the moment the menu fires it (same class as the A32
tpage-463 crash). It works on x86 but crashes on the owner's device.

**How to apply:** any time you add a `pc-*`/`__pc-*` pc-port function that GOAL (especially a menu) can
call, register it in BOTH places: `init_common_pc_port_functions` (desktop) AND `a17_bind_pc_helpers()`
(Android). If the Android runtime can't honor it, bind it to `a17_pc_default` (a safe no-op) — that's
enough to prevent the SIGILL; the GOAL-side state can still persist via pc-settings.gc. Gvulkan-option
hit this with `pc-set-gfx-renderer!`. See [[project_gvulkan_option_state]], [[feedback_linux_arm64_to_android_backport_gap]].
