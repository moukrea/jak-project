#!/usr/bin/env bash
# Phase D4 (autoport): build → install → launch → capture.
#
# This is the device-execution side of D4. It produces three artefacts
# the D4 validator inspects:
#
#   .autoport/reports/D4-boot.log      — 60-90 s logcat capture
#   .autoport/reports/D4-status.txt    — single-line determination
#   .autoport/reports/D4-launch.md     — engineering report
#
# Steps:
#   1. Build libgk.so (via d3_build.sh; idempotent).
#   2. Build the jak1 debug APK (gradle assembleJak1Debug).
#   3. Install + launch on the attached device using the standard
#      device-validate.sh helpers (handles MIUI install dance +
#      unlock + logcat capture).
#   4. Wait for the boot markers we care about (entered the renderer,
#      sustained swap, real kmachine markers) within a 90 s window.
#   5. Stop the app + write the report files.
#
# Exits 0 on the build + install + launch chain completing. The D4
# validator does the marker assertions itself against the captured
# logcat — d4_run.sh's job is to *produce* the logcat, not to judge it.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"

REPORT_DIR=".autoport/reports"
BOOT_LOG="$REPORT_DIR/D4-boot.log"
STATUS_TXT="$REPORT_DIR/D4-status.txt"
REPORT_MD="$REPORT_DIR/D4-launch.md"

# device-validate.sh streams to LOGCAT_LOG. Override so the run lands at
# our well-known path; the validator reads the same file.
export LOGCAT_LOG="$BOOT_LOG"

mkdir -p "$REPORT_DIR"

echo "== D4 step 1/4: build libgk.so =="
bash .autoport/lib/d3_build.sh

echo "== D4 step 2/4: build jak1 debug APK =="
device_build_flavor jak1

echo "== D4 step 3/4: install + launch + capture =="
device_require_attached
device_require_free_space
device_uninstall_other_games "$PACKAGE"
device_stayon_on

# Truncate the boot log so a previous run's bytes don't leak into the
# validator's grep.
: > "$BOOT_LOG"

# A5: LoaderActivity caches iso_data extraction across launches via a
# `.extracted_v1` sentinel inside files/cgo/<game>. `pm install -r`
# preserves /data/data/<pkg>, so an APK whose bundled iso_data has been
# updated (e.g., A5 regenerated KERNEL.CGO as the arm64 variant) does
# NOT take effect on device — the launch sees the sentinel, skips
# extraction, and the runtime reads the older x86 KERNEL.CGO previously
# extracted from a stale APK. That decodes as illegal arm64 instructions
# the moment the post-A5 boot path actually executes the bytecode,
# producing a SIGILL inside the gcommon top-level.
#
# Invalidate the sentinel before install. LoaderActivity will see the
# missing sentinel, treat the existing target as a half-copy from a
# crashed run, wipe it, and re-extract the APK-bundled iso_data fresh.
# Best-effort `run-as` so a never-installed device path still proceeds.
adb shell run-as "$PACKAGE" rm -f "files/cgo/jak1/.extracted_v1" >/dev/null 2>&1 || true

device_install_and_launch "$PACKAGE" "$ACTIVITY" "$APK"

echo "== D4 step 4/4: 90 s capture window (sustained-swap + kmachine markers) =="

# Best-effort marker waits. Each device_wait_for_marker returns 0 on
# hit, 1 on miss; we don't fail fast — d4_run.sh's job is to gather
# evidence, the validator decides pass/fail.
ONCREATE=1; RENDER_ENTERED=1; SUSTAINED=1; KMACHINE=1

# A5 forces iso_data re-extraction on every install (the LoaderActivity
# `.extracted_v1` sentinel is wiped above so the APK-bundled arm64 CGOs
# actually reach the device runtime). The first launch after that wipe
# copies ~1.4 GB of game data from APK assets to filesDir; the previous
# 30 s ceiling for the onCreate marker was tuned to the warm-cache path
# (where extraction is a no-op) and trips spuriously when the cold cache
# path runs the actual file copy. Subsequent D4 launches in the same A5
# run reuse the freshly extracted iso_data so they hit the warm path.
if device_wait_for_marker 'MainActivity onCreate done' 180; then ONCREATE=0; fi
if device_wait_for_marker 'android_renderer_run: entered' 60; then RENDER_ENTERED=0; fi
if device_wait_for_marker 'android_renderer: sustained swap [0-9]+' 60; then SUSTAINED=0; fi
if device_wait_for_marker '(InitIOP OK|Initialized GOAL heap|Got DGO file header|link finish:)' 60; then KMACHINE=0; fi

# Drain a few more seconds of logcat so multi-marker greps see the full
# kmachine init sequence even if the first marker hit was early.
sleep 10

# Stop the app — we have the evidence we need. The trap in
# device_install_and_launch also stops logcat capture cleanly.
adb shell am force-stop "$PACKAGE" 2>/dev/null || true
sleep 2

# Compute determination.
DETERMINATION="pass"
NOTES=""
if [ "$ONCREATE" -ne 0 ]; then
    DETERMINATION="fail"
    NOTES="MainActivity never reached onCreate (app didn't start)."
elif [ "$RENDER_ENTERED" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="App started but renderer never entered (likely stuck before InitMachine returned)."
elif [ "$SUSTAINED" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Renderer entered but no sustained-swap heartbeat in 60 s."
elif [ "$KMACHINE" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Render loop runs but no real kmachine markers seen (kmachine may be silently no-oping)."
fi

echo "$DETERMINATION: $NOTES" > "$STATUS_TXT"

# Engineering report. Captures what was attempted + the most recent
# evidence the validator will see. Lives under .autoport/reports/ so
# the next phase has easy access.
{
    echo "# Phase D4 — APK on-device launch report"
    echo
    echo "_Generated: $(date -Iseconds)_"
    echo
    echo "## What was wired"
    echo
    echo "- \`android/android_jak1_kernel_stubs.cpp\` deleted (D3 abort-stub removed)."
    echo "- \`android/CMakeLists.txt\` now compiles:"
    echo "  - \`game/kernel/jak1/kmachine.cpp\` (jak1::InitMachine, InitIOP, InitMachineScheme, InitParms, ShutdownMachine, kopen, PutDisplayEnv, update_discord_rpc, pc_set_levels)"
    echo "  - \`game/kernel/jak1/kboot.cpp\` (jak1::goal_main, KernelCheckAndDispatch, KernelShutdown, kboot_init_globals, BootVideoMode)"
    echo "- \`android/android_runtime_compat.cpp\` extended with real-body shims for:"
    echo "  - common/kmachine helpers: kmachine_init_globals_common, InitCD, InitVideo, init_common_pc_port_functions, CPadOpen/CPadGetData, InstallHandler, InstallDebugHandler, klength/kseek/kread/kwrite/kclose/kmkdir, dma_to_iop, Decode\* (Language/Aspect/Volume/Territory/Timeout/InactiveTimeout/Time), offset_of_s7, vif_interrupt_callback"
    echo "  - common/kmachine globals: isodrv, modsrc, reboot_iop, init_types, pad_dma_buf, vif1/vblank_interrupt_handler, ee_clock_timer, g_pc_port_funcs"
    echo "  - discord (external + jak1): gDiscordRpcEnabled, gStartTime, init_discord_rpc, set_discord_rpc, get_full_level_name, get_base_level_name, indoors, get_time_of_day, handleDiscord*, jak1::level_names/level_name_remap/indoor_levels/time_of_day_str, libdiscord-rpc C ABI (Discord_Initialize/Shutdown/RunCallbacks/UpdatePresence/ClearPresence/Respond/UpdateHandlers/UpdateConnection)"
    echo "  - Gfx accessors: GetCurrentRenderer (returns nullptr), g_debug_settings, g_splash, Init/Exit/Loop, vsync/sync_path, CollisionRenderer*"
    echo "  - Display::g_displays + GetMainDisplay (nullptr) + InitMainDisplay/Kill*"
    echo "  - SCE libgraph: ee::sceGsResetPath, ee::sceGsResetGraph, sceGsSyncV, sceGsSyncPath (global ns)"
    echo "  - InputModifiers ctor (pulled by DebugSettings default ctor)"
    echo
    echo "## Determination"
    echo
    echo "**$DETERMINATION**${NOTES:+ — $NOTES}"
    echo
    echo "## Marker observations (from logcat capture)"
    echo
    if [ -f "$BOOT_LOG" ]; then
        echo '```'
        grep -E '(MainActivity onCreate done|android_renderer_run: entered|android_renderer: sustained swap|InitIOP OK|Initialized GOAL heap|Got DGO file header|link finish:|InitMachine|jak1::InitMachine|jak1::KernelCheckAndDispatch|fatal|FATAL|ABORT|SIGABRT|SIGSEGV|SIGILL)' "$BOOT_LOG" | head -50 || echo "(no matching markers)"
        echo '```'
    else
        echo "(no $BOOT_LOG produced)"
    fi
    echo
    echo "## Next blocker (if any)"
    echo
    case "$DETERMINATION" in
        pass) echo "None — D4 markers were all observed. Ready for D5+." ;;
        partial) echo "$NOTES See $BOOT_LOG tail for context." ;;
        fail) echo "$NOTES App never reached MainActivity; the install or launch failed." ;;
    esac
} > "$REPORT_MD"

echo "== D4 done: determination=$DETERMINATION =="
[ -n "$NOTES" ] && echo "   note: $NOTES"
echo "   logcat:  $BOOT_LOG"
echo "   status:  $STATUS_TXT"
echo "   report:  $REPORT_MD"
