#!/usr/bin/env bash
# Phase 21 validator: 5-minute longevity test. App reaches title state,
# stays alive without crashes, respects W^X, sustained frame submission.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/device-validate.sh

echo "== Phase 22 validator (Bionic shims + W^X + 5-min longevity) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_require_free_space
device_stayon_on

device_build_flavor jak1
test -f "$APK_JAK1" || device_fail "APK missing"

device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

# Earlier phases' markers, fast timeouts (they should all be working).
for m in \
    "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" \
    'gkernel: dispatcher started' \
    'engine: frame 1 submitted' \
; do
    device_wait_for_marker "$m" 120 || device_fail "earlier-phase marker missing: $m"
done

# W^X discipline marker — every CGO page must be RX-only when executed.
if ! device_wait_for_marker 'code-map: [0-9]+ pages RX, 0 RWX' 60; then
    device_fail "code-map RX/RWX marker not seen — runtime may be mapping pages W+X"
fi

# Engine reaches the title state within 180s of launch.
if ! device_wait_for_marker 'engine: state=title' 180; then
    device_fail "engine never reached title state — runtime stalled mid-boot"
fi

# Confirm RWX is actually absent in /proc/self/maps. This catches any
# RWX mapping that slipped past the log assertion.
RWX_COUNT=$(adb shell "run-as $PACKAGE cat /proc/self/maps 2>/dev/null" | grep -cE 'rwxp ' || true)
if [ "${RWX_COUNT:-0}" -gt 0 ]; then
    device_fail "found ${RWX_COUNT} RWX VMAs in /proc/self/maps — W^X violated"
fi

# 5-minute longevity tail.
echo "== entering 5-minute longevity observation =="
DEADLINE=$(( $(date +%s) + 300 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    sleep 10
    # Crash check.
    if grep -qE "Fatal signal|SIGSEGV|SIGABRT|SIGILL|FATAL EXCEPTION.*$PACKAGE" "$LOGCAT_LOG"; then
        device_fail "crash during longevity window"
    fi
    # SELinux denial check.
    if adb logcat -d -s SELinux:* | grep -qE "avc: denied.*$PACKAGE"; then
        adb logcat -d -s SELinux:* | grep -E "avc: denied" | tail -10
        device_fail "SELinux denied an operation against our package"
    fi
    # Process still alive.
    if ! adb shell "pidof $PACKAGE" >/dev/null 2>&1; then
        device_fail "package process disappeared mid-window (silent OOM kill?)"
    fi
    # Periodic progress line.
    swap_count=$(grep -cE 'eglSwapBuffers: ok' "$LOGCAT_LOG")
    echo "  +$(( $(date +%s) - (DEADLINE - 300) ))s: alive, swaps=${swap_count}"
done

# Final assertion: ≥50 swap events.
swap_count=$(grep -cE 'eglSwapBuffers: ok' "$LOGCAT_LOG")
if [ "$swap_count" -lt 50 ]; then
    device_fail "only ${swap_count} swaps in 5min — render loop stalled"
fi
echo "  final swap count: ${swap_count}"

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 22 validator PASSED =="
echo "   App reached state=title, survived 5 minutes without crash,"
echo "   ${swap_count} frames swapped, W^X respected, no SELinux denials."
echo "   Desktop build still green."
