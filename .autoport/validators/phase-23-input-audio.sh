#!/usr/bin/env bash
# Phase 22 validator: tap-bot drives the d-pad overlay; pad events reach
# the kernel. Audio device opens and the SDL callback fires periodically.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/device-validate.sh

echo "== Phase 23 validator (input bridge + audio) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_require_free_space
device_stayon_on

device_build_flavor jak1
test -f "$APK_JAK1" || device_fail "APK missing"

device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

# Boot prereqs (everything 17-21 must already work).
for m in \
    "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" \
    'gkernel: dispatcher started' \
    'engine: state=title' \
; do
    device_wait_for_marker "$m" 240 || device_fail "earlier-phase marker missing: $m"
done

# Audio subsystem opened.
if ! device_wait_for_marker "SDL_audio: opened device='[^']+' freq=[0-9]+ channels=[0-9]+" 60; then
    device_fail "SDL_audio device never opened"
fi

# Audio callback firing (at least one within 60s of title state).
if ! device_wait_for_marker "SDL_audio: callback fired, [0-9]+ samples" 60; then
    device_fail "SDL_audio callback never fired — no audio output"
fi

# --- input drive ---
echo "== driving d-pad and face buttons via adb shell input tap =="
# Discover the screen size to compute overlay coordinates. The
# TouchControlsView lays the d-pad in the bottom-left quadrant and
# the face buttons in the bottom-right. Coords below are 1080x2300-ish;
# adjust ratios so the test isn't device-specific.
read SCREEN_W SCREEN_H <<<"$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1 | tr 'x' ' ')"
SCREEN_W=${SCREEN_W:-1080}
SCREEN_H=${SCREEN_H:-2300}
echo "  screen: ${SCREEN_W}x${SCREEN_H}"
DPAD_RIGHT_X=$(( SCREEN_W * 25 / 100 ))   # 25% from left
DPAD_RIGHT_Y=$(( SCREEN_H * 80 / 100 ))   # 80% from top
A_X=$(( SCREEN_W * 80 / 100 ))            # 80% from left
A_Y=$(( SCREEN_H * 80 / 100 ))
Y_X=$(( SCREEN_W * 75 / 100 ))
Y_Y=$(( SCREEN_H * 70 / 100 ))

# Three taps with short pauses; expect three pad-down events.
for px in "dpad_right ${DPAD_RIGHT_X} ${DPAD_RIGHT_Y}" \
          "south ${A_X} ${A_Y}" \
          "north ${Y_X} ${Y_Y}"; do
    set -- $px
    name="$1"; x="$2"; y="$3"
    # Clear marker side-effects.
    : > /tmp/tap-mark
    adb shell input tap "$x" "$y"
    if ! device_wait_for_marker "kernel: pad: ${name} pressed" 5; then
        device_fail "tap on ${name} (${x},${y}) did not produce a kernel pad event"
    fi
done

# Audio callback should still be firing at the end.
callback_count=$(grep -cE 'SDL_audio: callback fired' "$LOGCAT_LOG")
echo "  audio callbacks observed: ${callback_count}"
if [ "$callback_count" -lt 10 ]; then
    device_fail "audio callback only fired ${callback_count} times — driver may have stalled"
fi

if ! device_assert_no_crash "$PACKAGE"; then
    device_fail "crash during input/audio phase"
fi

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 23 validator PASSED =="
echo "   3 pad events delivered, audio device open, ≥${callback_count} callbacks."
echo "   Desktop build still green."
