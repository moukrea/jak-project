#!/usr/bin/env bash
# Phase 20 validator: GLES-ported shaders compile and at least one
# game frame is submitted + swapped on the device.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/device-validate.sh

echo "== Phase 21 validator (GLES shaders + first rendered frame) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_require_free_space
device_stayon_on

device_build_flavor jak1
test -f "$APK_JAK1" || device_fail "APK missing"

device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

# Boot chain prereqs from earlier phases.
if ! device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 60; then
    device_fail "iso_data path missing (phase 17 regression)"
fi
if ! device_wait_for_marker 'gkernel: dispatcher started' 90; then
    device_fail "kernel didn't boot (phase 20 regression)"
fi

# Critical negative: any shader compile failure means the renderer is
# silently broken. Fail immediately if seen.
if grep -qE 'shader: .* (compile|link) FAILED|GL_ERROR' "$LOGCAT_LOG"; then
    grep -E 'shader: .* FAILED|GL_ERROR' "$LOGCAT_LOG" | head -10 >&2
    device_fail "shader compile/link failure observed"
fi

# Positive: at least one shader compile OK marker (proves the path runs).
if ! device_wait_for_marker 'shader: [A-Za-z_0-9-]+ compiled OK' 60; then
    device_fail "no shader-compile-OK markers — renderer didn't load shaders"
fi

# First-frame markers within 120s of launch.
if ! device_wait_for_marker 'engine: frame 1 submitted' 120; then
    device_fail "engine: frame 1 was never submitted — renderer stalled"
fi
if ! device_wait_for_marker 'eglSwapBuffers: ok' 30; then
    device_fail "no eglSwapBuffers after frame 1 — context lost / surface unbound?"
fi

# Count subsequent swaps in the 10s after frame 1, so we have evidence
# of a *sustained* render loop, not a one-shot bring-up.
echo "  observing 10s of additional swaps..."
sleep 10
swap_count=$(grep -cE 'eglSwapBuffers: ok' "$LOGCAT_LOG")
if [ "$swap_count" -lt 5 ]; then
    device_fail "only ${swap_count} eglSwapBuffers after frame 1; render loop not sustained"
fi
echo "  swap count in window: ${swap_count}"

if ! device_assert_no_crash "$PACKAGE"; then
    device_fail "crash during rendering"
fi

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 21 validator PASSED =="
echo "   GLES shaders compile, engine submitted ≥1 frame, render loop"
echo "   sustained for 10s (${swap_count} swaps). Desktop build still green."
