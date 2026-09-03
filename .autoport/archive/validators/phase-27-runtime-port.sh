#!/usr/bin/env bash
# Phase 27 validator: libgk.so includes the full runtime, not just kernel
# scaffolding. Checks symbol presence, body sizes, and total .so size.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/anti-stub.sh
. .autoport/lib/device-validate.sh

echo "== Phase 27 validator (full runtime cross-built into libgk.so) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_build_flavor jak1

# Locate libgk.so inside the APK.
APK="$APK_JAK1"
test -f "$APK" || { echo "FAIL: APK missing"; exit 1; }
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
unzip -p "$APK" lib/arm64-v8a/libgk.so > "$TMP/libgk.so" 2>/dev/null
if [ ! -s "$TMP/libgk.so" ]; then
    echo "FAIL: libgk.so missing from APK"; exit 1
fi

LIBGK_SIZE=$(stat -c %s "$TMP/libgk.so")
LIBGK_MB=$(( LIBGK_SIZE / 1048576 ))
echo "  libgk.so size: ${LIBGK_MB} MB ($LIBGK_SIZE bytes)"
if [ "$LIBGK_MB" -lt 15 ]; then
    echo "FAIL: libgk.so is only ${LIBGK_MB} MB stripped; expected ≥15 MB after full runtime port"
    exit 1
fi

# Symbol presence + body-size checks. The exact mangled forms vary, so
# match on demangled names via `c++filt`. The list below names the
# functions whose presence proves real runtime code was linked.
NM_OUT=$(mktemp)
"$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm \
    --defined-only -D --demangle "$TMP/libgk.so" > "$NM_OUT" 2>/dev/null

REQUIRED_PATTERNS=(
    'InitMachine'
    'KernelCheckAndDispatch'
    'call_goal_on_stack'
    'Listener'
    'OverlordTest|kdgo_init|MakeOverlordThread|VblankInterruptHandler'
    'MakeIopThread|make_iop_thread|iop::start'
    'set_master_state|MasterUseKernel|RuntimeExitStatus'
    'gfx_dispatcher|gl_main_loop|render_loop'
)

MISSING=0
for pat in "${REQUIRED_PATTERNS[@]}"; do
    if ! grep -qE " $pat" "$NM_OUT" && ! grep -qE "$pat\(" "$NM_OUT" ; then
        echo "  MISSING: no symbol matching '$pat' in libgk.so"
        MISSING=$((MISSING + 1))
    else
        # Sample the first symbol matching the pattern; check its body.
        hit=$(grep -m1 -E "($pat)" "$NM_OUT" | awk '{$1=$1; print}')
        echo "  found: $hit"
    fi
done

if [ "$MISSING" -gt 0 ]; then
    echo "FAIL: $MISSING required runtime symbol patterns missing"
    exit 1
fi

# Function body sizes: a stub like `int InitMachine() { log("..."); return 0; }`
# compiles to <100 bytes. Real code is much larger. Sample one symbol.
echo "== body-size check (InitMachine) =="
INITMACHINE_SYM=$(grep -E ' InitMachine' "$NM_OUT" | head -1 | awk '{print $NF}')
if [ -n "$INITMACHINE_SYM" ]; then
    anti_stub_check_symbol_body_size "$TMP/libgk.so" "$INITMACHINE_SYM" 500 \
        || { echo "FAIL: InitMachine body is too small to be the real one"; exit 1; }
fi

# APK-vs-disk freshness: rebuild must have produced the APK we're testing.
# Anyone (e.g., a stub fix) editing only the test fixtures and skipping
# the build would have a stale APK. Anchor on state.json's
# phase_started_at (matches the project's validator time-anchor rule —
# the orchestrator creates validator-NN.txt BEFORE this script runs, so
# we cannot use that as a fence). Build artifacts under
# android/app/build/ and android/.gradle/ are excluded — gradle touches
# output-metadata.json + fileHashes.lock *after* writing the APK, so a
# find -newer "$APK" sweep over android/ flags those legitimate build
# outputs as suspicious sources.
APK_MT=$(stat -c %Y "$APK")
PHASE_START=$(python3 -c "
import json,sys
try:
    s = json.load(open('.autoport/state.json'))
    print(int(s.get('phase_started_at', {}).get('27-runtime-port', 0)))
except Exception:
    print(0)
")
if [ "$APK_MT" -lt "$PHASE_START" ]; then
    echo "FAIL: APK ($APK_MT) older than phase start ($PHASE_START) — rebuild was skipped"
    exit 1
fi
SRC_MT=$(find android/ game/kernel game/system game/overlord game/runtime.cpp \
    -type f -newer "$APK" \
    -not -path 'android/app/build/*' \
    -not -path 'android/.gradle/*' \
    -not -path 'android/build/*' \
    2>/dev/null | head -5)
if [ -n "$SRC_MT" ]; then
    echo "FAIL: sources newer than APK (rebuild was skipped):"
    echo "$SRC_MT" | sed 's/^/    /'
    exit 1
fi

# Install on device and confirm libgk.so loads + InitMachine is reachable
# at runtime (the symbol is in the loaded image's dynsym).
device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK"
device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 240 \
    || device_fail "loader didn't reach MainActivity"
device_wait_for_marker 'libgk.so loaded' 30 \
    || device_fail "libgk.so didn't log its load — JNI bridge regression?"
device_assert_no_crash "$PACKAGE" \
    || device_fail "app crashed on launch (Bionic shim missing?)"

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 27 validator PASSED =="
echo "   libgk.so is ${LIBGK_MB} MB stripped with full runtime symbols"
echo "   (InitMachine, KernelCheckAndDispatch, Overlord, Listener, …)"
echo "   and loads cleanly on device without Bionic crashes."
