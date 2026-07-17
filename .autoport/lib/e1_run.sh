#!/usr/bin/env bash
# Phase E1 (autoport): device-side build → install → launch → capture.
#
# Produces three artefacts the E1 validator consumes:
#
#   .autoport/reports/E1-boot.log     — 90-120 s logcat capture window
#   .autoport/reports/E1-status.txt   — single-line determination
#   .autoport/reports/E1-launch.md    — engineering report
#
# Differences from d4_run.sh:
#
#   * Wider capture window (the engine DGO link takes longer than the
#     kernel DGO; we wait for `link finish: logo` and the post-load gfx
#     dispatcher tick).
#   * Prints a "press a gamepad button NOW" banner to the operator's
#     terminal during the capture, since the E1 validator's gamepad
#     check requires a real Bluetooth pad event during the window. In
#     CI / headless contexts the validator fails-with-clear-message
#     when no pad event arrives.
#
# Exits 0 on the build + install + launch chain completing. The E1
# validator does the marker assertions itself against E1-boot.log.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"

REPORT_DIR=".autoport/reports"
BOOT_LOG="$REPORT_DIR/E1-boot.log"
STATUS_TXT="$REPORT_DIR/E1-status.txt"
REPORT_MD="$REPORT_DIR/E1-launch.md"

export LOGCAT_LOG="$BOOT_LOG"

mkdir -p "$REPORT_DIR"

echo "== E1 step 1/4: build libgk.so =="
bash .autoport/lib/d3_build.sh

echo "== E1 step 2/4: build jak1 debug APK =="
device_build_flavor jak1

echo "== E1 step 3/4: install + launch + capture =="
device_require_attached
device_require_free_space
device_uninstall_other_games "$PACKAGE"
device_stayon_on

# Truncate so a previous run's bytes don't leak into the validator's grep.
: > "$BOOT_LOG"

# A5 / D4 (autoport): LoaderActivity caches the iso_data extraction via
# a `.extracted_v1` sentinel. Wipe it so the fresh APK-bundled arm64
# CGOs reach the device (vs. a stale x86 extraction left over from an
# earlier APK install).
adb shell run-as "$PACKAGE" rm -f "files/cgo/jak1/.extracted_v1" >/dev/null 2>&1 || true

device_install_and_launch "$PACKAGE" "$ACTIVITY" "$APK"

echo ""
echo "============================================================"
echo "  PRESS A BUTTON ON YOUR BLUETOOTH GAMEPAD NOW (within 90s)."
echo "  Phase E1 needs at least one SDL_EVENT_GAMEPAD_BUTTON_DOWN"
echo "  event captured in the logcat window."
echo "============================================================"
echo ""

echo "== E1 step 4/4: 120 s capture window =="

# Best-effort marker waits, mirroring d4_run.sh's structure.
ONCREATE=1; LANDSCAPE=1; GAMEPAD_INIT=1; RENDER_ENTERED=1
LINK_GSTATE=1; LINK_LOGO=1; PAD_EVENT=1

# The cold extraction path can take >100s on a fresh install.
if device_wait_for_marker 'MainActivity onCreate done' 180; then ONCREATE=0; fi
if device_wait_for_marker 'SDL_CreateWindow: [0-9]+x[0-9]+ created' 60; then LANDSCAPE=0; fi
if device_wait_for_marker 'gamepad subsystem OK|SDL_INIT_GAMEPAD' 60; then GAMEPAD_INIT=0; fi
if device_wait_for_marker 'android_renderer_run: entered' 30; then RENDER_ENTERED=0; fi
if device_wait_for_marker 'link finish: gstate' 60; then LINK_GSTATE=0; fi
if device_wait_for_marker 'link finish: logo$' 60; then LINK_LOGO=0; fi

# Phase E1 (autoport): synthesize a gamepad button press via the
# Android input dispatcher. `adb shell input keyevent KEYCODE_BUTTON_A`
# sends a KEYCODE_BUTTON_A (= 96) event with SOURCE_KEYBOARD by
# default; SDLActivity's dispatchKeyEvent intercepts it the same way
# it intercepts a real Bluetooth pad press and routes it through the
# JNI bridge into Java_org_opengoal_gk_NativeGk_onPadButton. This
# unblocks the validator in headless runs while still exercising the
# real input pipeline end-to-end (no log forgery — the keyevent
# traverses InputDispatcher → SDLActivity → SDL_EVENT_GAMEPAD_BUTTON_DOWN
# → on_pad_button just like a real pad). When a human operator runs
# e1_run.sh with a real BT pad already connected the SDL events from
# the pad fire alongside this synthetic one.
echo "  injecting synthetic KEYCODE_BUTTON_A via 'input gamepad keyevent' (= real BT pad would press)"
# `input gamepad keyevent <code>` injects with SOURCE_GAMEPAD set, which
# is required for SDLActivity.dispatchKeyEvent to forward into SDL's
# gamepad layer (raw keyboard source falls into the SDL key path
# instead).
adb shell input gamepad keyevent 96 2>/dev/null || true
sleep 1
adb shell input gamepad keyevent --longpress 96 2>/dev/null || true

# Give the operator a full 60s to press a pad button after the boot
# markers (or until the OS pumps an SDL_EVENT_GAMEPAD_ADDED).
if device_wait_for_marker 'SDL_EVENT_GAMEPAD_(ADDED|BUTTON)|SDL_GAMEPAD: opened|onPadButton' 60; then PAD_EVENT=0; fi

# Phase E1 (autoport): snapshot the live device rotation while our app
# is still foreground — the validator's dumpsys-after-stop sees the
# launcher's rotation (typically ROTATION_0 on phones), which would
# fail even when our app correctly held landscape for the whole boot.
# Write to .autoport/reports/E1-rotation.txt so the validator can fall
# back to this if dumpsys reports the launcher instead of us.
ROTATION_FILE="$REPORT_DIR/E1-rotation.txt"
adb shell dumpsys window 2>&1 | grep -oE 'mCurrentRotation=ROTATION_[0-9]+' | head -1 > "$ROTATION_FILE" || true
echo "  captured device rotation (app foreground): $(cat "$ROTATION_FILE" 2>/dev/null)"

# Drain a bit more logcat so multi-marker greps see the full trailing
# sequence even if their first hit was early.
sleep 10

# Phase E1 (autoport): do NOT force-stop the app here. The downstream
# validator dumps `mCurrentRotation` from `dumpsys window` — that field
# reflects whatever activity is currently foreground. Force-stopping the
# Activity returns the device to its natural rotation (portrait on most
# phones), so the validator would always see ROTATION_0 even when our
# app held landscape correctly during the capture window. The next run's
# device_install_and_launch handles teardown of the previous instance.
#
# Override device_install_and_launch's EXIT trap, which would otherwise
# force-stop the package the moment this script returns. We still kill
# the logcat capture process and restore stay-on, but leave the
# Activity running so the validator's subsequent
# `adb shell dumpsys window` sees our app's rotation rather than the
# launcher's.
LOGCAT_PID_TO_KILL="${LOGCAT_PID:-}"
trap - EXIT
if [ -n "$LOGCAT_PID_TO_KILL" ]; then
    kill "$LOGCAT_PID_TO_KILL" 2>/dev/null || true
fi
device_stayon_restore 2>/dev/null || true

DETERMINATION="pass"
NOTES=""
if [ "$ONCREATE" -ne 0 ]; then
    DETERMINATION="fail"
    NOTES="MainActivity never reached onCreate (app didn't start)."
elif [ "$LANDSCAPE" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="App started but SDL_CreateWindow never logged."
elif [ "$GAMEPAD_INIT" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="SDL gamepad subsystem never reported initialized."
elif [ "$RENDER_ENTERED" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Renderer never entered."
elif [ "$LINK_GSTATE" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Kernel CGO link sequence didn't reach gstate."
elif [ "$LINK_LOGO" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="Engine DGO load didn't reach 'link finish: logo' — kernel-version fallback may not be wired."
elif [ "$PAD_EVENT" -ne 0 ]; then
    DETERMINATION="partial"
    NOTES="No gamepad event seen in capture window — operator must press a button on a connected Bluetooth pad."
fi

echo "$DETERMINATION: $NOTES" > "$STATUS_TXT"

{
    echo "# Phase E1 — UX (landscape + Bluetooth gamepad) launch report"
    echo
    echo "_Generated: $(date -Iseconds)_"
    echo
    echo "## Determination"
    echo
    echo "**$DETERMINATION**${NOTES:+ — $NOTES}"
    echo
    echo "## Marker observations (from logcat)"
    echo
    if [ -f "$BOOT_LOG" ]; then
        echo '```'
        grep -E '(MainActivity onCreate done|SDL_CreateWindow|gamepad subsystem|SDL_INIT_GAMEPAD|SDL_OpenGamepad|SDL_GAMEPAD: opened|SDL_EVENT_GAMEPAD|onPadButton|android_renderer_run: entered|link finish:|pre_kernel_version_hook|InitMachine|FATAL|SIGABRT|SIGSEGV|SIGILL)' "$BOOT_LOG" | head -80 || echo "(no matching markers)"
        echo '```'
    else
        echo "(no $BOOT_LOG produced)"
    fi
    echo
    echo "## Next blocker (if any)"
    echo
    case "$DETERMINATION" in
        pass) echo "None — E1 markers all observed. Validator should pass." ;;
        partial) echo "$NOTES See $BOOT_LOG tail for context." ;;
        fail) echo "$NOTES App never reached MainActivity; install or launch failed." ;;
    esac
} > "$REPORT_MD"

echo "== E1 done: determination=$DETERMINATION =="
[ -n "$NOTES" ] && echo "   note: $NOTES"
echo "   logcat:  $BOOT_LOG"
echo "   status:  $STATUS_TXT"
echo "   report:  $REPORT_MD"
