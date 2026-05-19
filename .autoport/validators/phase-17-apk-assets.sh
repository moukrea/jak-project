#!/usr/bin/env bash
# Phase 17 validator: jak1 APK extracts its bundled assets to filesDir on
# first launch and uses the fast-path on subsequent launches. Tested on
# a USB-attached real device (no emulator).
#
# Strict — none of these checks are structural-only. Every pass condition
# requires evidence from the runtime via logcat.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/device-validate.sh

echo "== Phase 17 validator (APK-bundled assets, on-device) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_require_free_space
device_stayon_on

# Build. AGP must still produce the APK.
device_build_flavor jak1
test -f "$APK_JAK1" || device_fail "expected APK not present at $APK_JAK1"

# Fresh slate: uninstall to guarantee first-launch path.
echo "== uninstalling any prior $PACKAGE =="
adb uninstall "$PACKAGE" >/dev/null 2>&1 || true

# --- first launch: expect extraction ---
device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

# Wait up to 240s for the extract marker. Allow generous time — 1.4 GB on
# eMMC can take a while.
if ! device_wait_for_marker 'iso_data extract: [0-9]+ files, [0-9]+ bytes in [0-9]+ms' 240; then
    device_fail "first-launch extraction marker not observed (LoaderActivity didn't extract)"
fi

# Pull and verify the numbers from that line: files ≥ 300, bytes > 1 GB.
hit_line=$(grep -m1 -E 'iso_data extract: [0-9]+ files, [0-9]+ bytes in [0-9]+ms' "$LOGCAT_LOG")
files=$(echo "$hit_line" | grep -oE 'extract: [0-9]+' | grep -oE '[0-9]+')
bytes=$(echo "$hit_line" | grep -oE '[0-9]+ bytes' | grep -oE '[0-9]+')
echo "  parsed: files=$files bytes=$bytes"
if [ "${files:-0}" -lt 300 ]; then
    device_fail "extraction reported only ${files} files; expected ≥300 for jak1"
fi
if [ "${bytes:-0}" -lt 1000000000 ]; then
    device_fail "extraction reported only ${bytes} bytes; expected >1 GB for jak1"
fi

# Now wait for the MainActivity's "iso_data present at …" marker so we
# know the Loader→Main transition actually happened.
if ! device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 60; then
    device_fail "MainActivity didn't observe iso_data after extraction (Loader transition broken?)"
fi

# The "Missing data" toast must NOT appear at all in this run.
if grep -qE 'Missing jak1 data' "$LOGCAT_LOG"; then
    device_fail "'Missing jak1 data' toast still fired — Loader extraction is being bypassed"
fi

device_assert_no_crash "$PACKAGE" || device_fail "app crashed on first launch"

# Stop logcat tail before re-launching so the second-launch log is clean.
kill ${LOGCAT_PID:-0} 2>/dev/null || true
sleep 1

# --- second launch: expect fast-path skip ---
echo "== relaunching to verify sentinel fast-path =="
adb shell am force-stop "$PACKAGE"
adb logcat -c
adb logcat -v threadtime > "$LOGCAT_LOG" 2>&1 &
LOGCAT_PID=$!
adb shell am start -W -n "${PACKAGE}/.LoaderActivity" >/dev/null

if ! device_wait_for_marker 'iso_data already extracted' 15; then
    device_fail "second-launch fast-path missing: sentinel was not respected"
fi

# And the extraction marker must NOT fire again.
if grep -qE 'iso_data extract: [0-9]+ files' "$LOGCAT_LOG"; then
    device_fail "second launch re-ran extraction despite sentinel"
fi

device_assert_no_crash "$PACKAGE" || device_fail "app crashed on second launch"

# Stop logcat.
kill ${LOGCAT_PID:-0} 2>/dev/null || true

# Desktop x86 build still works.
device_assert_desktop_build

echo
echo "== Phase 17 validator PASSED =="
echo "   APK-bundled assets extracted automatically on first launch,"
echo "   sentinel fast-path works on re-launch, no crashes, desktop x86"
echo "   build still green."
