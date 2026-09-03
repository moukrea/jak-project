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

# 4a. Weak-bridge integrity check.
# Phase 28's first pass shipped a regression: android_runtime_full.cpp
# declared `weak_jak1_InitMachine` and `weak_jak1_KernelCheckAndDispatch`
# as weak externs, the runtime's dispatcher branched on whether they
# were null, and they were NEVER defined anywhere. The fallback (timer-
# driven `engine: state=` markers + heartbeat tick) satisfied every log-
# based check below, so phase 28 looked passing while no GOAL bytecode
# was actually running. Phase 30's input-reactivity check then could
# not pass because the GOAL kernel was never listening for input.
#
# This sub-check inspects libgk.so in the *built* APK and demands both
# symbols be present AS DEFINED (capital W = weak with body, T/t/D/d =
# strong), not as undefined weak references (lowercase w / U). It is
# strictly a physical-artifact check; a stub that prints the right log
# strings cannot defeat it because nm reads the symbol table directly.
TMP_LIB=$(mktemp -d)
trap "rm -rf $TMP_LIB" RETURN
unzip -p "$APK_JAK1" lib/arm64-v8a/libgk.so > "$TMP_LIB/libgk.so" 2>/dev/null
NMBIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
[ -x "$NMBIN" ] || NMBIN=$(command -v llvm-nm)
[ -x "$NMBIN" ] || NMBIN=$(command -v nm)
NMOUT=$("$NMBIN" --defined-only "$TMP_LIB/libgk.so" 2>/dev/null)
for sym in weak_jak1_InitMachine weak_jak1_KernelCheckAndDispatch; do
    if [[ "$NMOUT" != *"$sym"* ]]; then
        echo "FAIL: $sym is NOT defined in libgk.so (only weakly declared);"
        echo "      add a bridge under game/kernel/jak1/ that defines it"
        echo "      and delegates to the real jak1 entry point. Without"
        echo "      this, android_runtime_full.cpp's dispatcher branch"
        echo "      takes the fallback path and no GOAL bytecode runs."
        exit 1
    fi
done
echo "  weak_jak1_InitMachine + weak_jak1_KernelCheckAndDispatch both defined ✓"

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

# 5a. The fallback-path canary. android_runtime_full.cpp logs a SPECIFIC
# string when the weak symbols are null and the runtime takes the
# timer-only path: 'InitMachine: jak1 backend absent; bootstrap-only
# path complete'. If that line appears in logcat, phase 28 did NOT
# actually wire the real dispatcher — it just made the fallback walk
# the same engine-state log sequence. Fail loudly.
if grep -qE 'InitMachine: jak1 backend absent|bootstrap-only path' "$LOGCAT_LOG"; then
    grep -E 'bootstrap-only|backend absent' "$LOGCAT_LOG" | head -5 >&2
    device_fail "fallback dispatcher fired; real jak1::InitMachine never ran"
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
