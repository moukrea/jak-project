#!/usr/bin/env bash
# emulator_fallback.sh — start an Android arm64 emulator when no real phone
# is attached, so the orchestrator can keep iterating offline.
#
# Authored 2026-05-22 by the supervisor. The AVD `opengoal_arm64` was
# already created in an earlier phase with the android-34 google_apis
# arm64-v8a system image (matches the APK's targetSdk=34).
#
# Usage from validators / d4_run.sh:
#   source .autoport/lib/emulator_fallback.sh
#   ensure_device_or_emulator   # exports DEVICE_SERIAL with what to use
#
# When a real device is attached, returns its serial. Otherwise, ensures
# the emulator is running (cold-starting it if needed) and returns
# emulator-5554. Times out after 300s waiting for emulator boot.

set +e  # never fail caller on a transient adb hiccup

EMU_AVD="opengoal_arm64"
EMU_SERIAL="emulator-5554"
EMU_BOOT_TIMEOUT="${EMU_BOOT_TIMEOUT:-300}"
ANDROID_HOME="${ANDROID_HOME:-/home/emeric/Android}"
EMU_BIN="${ANDROID_HOME}/emulator/emulator"
ADB="${ADB:-${ANDROID_HOME}/platform-tools/adb}"

# Pick the device the orchestrator should target this run.
# Prefers real device (faster, real GPU) over emulator (slow, software GL).
# Sets DEVICE_SERIAL to the chosen serial. Returns 0 on success, 1 on
# total failure (no device + emulator boot timed out).
ensure_device_or_emulator() {
    # 1. Real device attached?
    REAL=$("$ADB" devices 2>/dev/null | awk '/\tdevice$/ {print $1; exit}' \
        | grep -vE '^emulator-')
    if [ -n "$REAL" ]; then
        export DEVICE_SERIAL="$REAL"
        echo "  emulator_fallback: real device $REAL detected — using it"
        return 0
    fi

    # 2. Emulator already running?
    if "$ADB" devices 2>/dev/null | awk '/\tdevice$/ {print $1}' \
            | grep -q '^emulator-'; then
        SER=$("$ADB" devices 2>/dev/null \
            | awk '/\tdevice$/ {print $1}' | grep '^emulator-' | head -1)
        export DEVICE_SERIAL="$SER"
        echo "  emulator_fallback: emulator $SER already running"
        # Wait for boot completion just in case
        _wait_for_emu_boot "$SER" 30 && return 0
    fi

    # 3. Cold-start the emulator
    echo "  emulator_fallback: no device attached; cold-starting $EMU_AVD"
    if ! [ -d "$HOME/.android/avd/${EMU_AVD}.avd" ]; then
        echo "  emulator_fallback: AVD $EMU_AVD missing at $HOME/.android/avd/" >&2
        return 1
    fi
    # Launch in background, no display/audio, allow snapshot persistence
    # so subsequent starts are faster.
    nohup "$EMU_BIN" -avd "$EMU_AVD" \
        -no-window -no-audio -no-boot-anim \
        -netdelay none -netspeed full \
        -gpu swiftshader_indirect \
        > /tmp/emu-${EMU_AVD}.log 2>&1 &
    EMU_PID=$!
    echo "  emulator_fallback: emulator PID $EMU_PID; waiting up to ${EMU_BOOT_TIMEOUT}s for boot..."

    _wait_for_emu_boot "$EMU_SERIAL" "$EMU_BOOT_TIMEOUT"
}

# Wait until adb -s <serial> shell getprop sys.boot_completed returns 1.
# Args: serial, timeout-seconds.
_wait_for_emu_boot() {
    local serial="$1"
    local timeout="$2"
    local started=$SECONDS
    while [ $((SECONDS - started)) -lt "$timeout" ]; do
        if "$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null \
                | tr -d '\r\n' | grep -q '^1$'; then
            export DEVICE_SERIAL="$serial"
            echo "  emulator_fallback: $serial booted (${SECONDS} - ${started}s)"
            return 0
        fi
        sleep 5
    done
    echo "  emulator_fallback: TIMEOUT waiting for $serial boot" >&2
    return 1
}

# Kill the running emulator (called from cleanup paths).
stop_emulator() {
    "$ADB" -s "$EMU_SERIAL" emu kill 2>/dev/null
    sleep 2
    pkill -f "emulator.*${EMU_AVD}" 2>/dev/null
}
