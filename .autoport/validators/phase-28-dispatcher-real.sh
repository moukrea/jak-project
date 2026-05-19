#!/usr/bin/env bash
# Phase 28 validator: kStateSeq is gone; real dispatcher heartbeat runs;
# state transition timings don't match the hardcoded stub pattern.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/anti-stub.sh
. .autoport/lib/device-validate.sh

echo "== Phase 28 validator (real KernelCheckAndDispatch wired) =="

PACKAGE="org.opengoal.gk.jak1"

# 1. Source-tree forbid-list. This catches "stash kStateSeq behind a
# rename" workarounds because we also forbid the literal three state
# names as a fixed array.
echo "== source-tree anti-stub check =="
GOAL_MAIN=android/android_goal_main.cpp
test -f "$GOAL_MAIN" || { echo "FAIL: $GOAL_MAIN missing"; exit 1; }
anti_stub_forbid_strings "$GOAL_MAIN" \
    'kStateSeq' \
    'kSyntheticBootSequence' \
    'kStateSequence' \
    '"boot", 500' \
    '"load", 1500' \
    '"title", 2000' \
    || { echo "FAIL: kStateSeq-style stub still present in $GOAL_MAIN"; exit 1; }

# 2. The real KernelCheckAndDispatch call must be present.
if ! grep -qE 'KernelCheckAndDispatch[ ]*\(' "$GOAL_MAIN"; then
    echo "FAIL: $GOAL_MAIN does not call KernelCheckAndDispatch — real dispatcher not wired"
    exit 1
fi

# 3. The state log line must originate from game/kernel/, not android/.
if grep -rE 'engine: state=' android/*.cpp android/*.h 2>/dev/null | grep -v 'android_goal_main.cpp:[[:space:]]*//'; then
    echo "FAIL: 'engine: state=' log lines still come from android/ — must originate in game/kernel/"
    grep -rnE 'engine: state=' android/ | head -10
    exit 1
fi
if ! grep -qrE 'engine: state=' game/kernel/ 2>/dev/null; then
    echo "FAIL: no 'engine: state=' log emitter in game/kernel/ — gstate hook not wired"
    exit 1
fi

# 4. Build + on-device run.
device_require_attached
device_uninstall_other_games "$PACKAGE"
device_build_flavor jak1
device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"
device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 240 \
    || device_fail "loader transition broken"

# 5. Dispatcher heartbeat must strictly increase. The NativeGk.getDispatchHeartbeat
# JNI getter is queried via `am instrument` or a content provider. For
# the simplest plumbing, the runtime should also log heartbeat every N
# ticks (e.g., every 1000) — the validator polls those.
if ! device_wait_for_marker 'dispatch-heartbeat: [0-9]+' 60; then
    device_fail "no dispatch-heartbeat log lines — dispatcher loop not running"
fi

# Sample the heartbeat at two times 5s apart. Must increase by ≥10.
sleep 5
H1=$(grep -oE 'dispatch-heartbeat: [0-9]+' "$LOGCAT_LOG" | tail -1 | grep -oE '[0-9]+')
sleep 5
H2=$(grep -oE 'dispatch-heartbeat: [0-9]+' "$LOGCAT_LOG" | tail -1 | grep -oE '[0-9]+')
echo "  heartbeat samples: H1=$H1  H2=$H2"
if [ -z "$H1" ] || [ -z "$H2" ] || [ "$H2" -le "$H1" ]; then
    device_fail "heartbeat counter did not advance ($H1 → $H2) — dispatcher is idle/dead"
fi
if [ $((H2 - H1)) -lt 10 ]; then
    device_fail "heartbeat advanced only $((H2 - H1)) in 5s — too slow to be real dispatch"
fi

# 6. State transitions reach 'title'.
if ! device_wait_for_marker 'engine: state=title' 180; then
    device_fail "engine: state=title never reached"
fi

# 7. Anti-stub timing-jitter check: intervals between boot/load/title
# must NOT match the hardcoded 1500ms/2000ms.
if ! anti_stub_check_timing_jitter "$LOGCAT_LOG" 'engine: state='; then
    device_fail "engine: state= intervals match the kStateSeq hardcoded pattern"
fi

device_assert_no_crash "$PACKAGE" || device_fail "crash during dispatch window"

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 28 validator PASSED =="
echo "   kStateSeq removed, real KernelCheckAndDispatch advancing heartbeat"
echo "   ${H1}→${H2} in 5s, state=title reached via real gstate hook,"
echo "   timing-jitter check confirms not a hardcoded timer."
