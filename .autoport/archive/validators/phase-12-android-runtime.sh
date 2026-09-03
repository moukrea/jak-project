#!/usr/bin/env bash
# Validator for phase 12: the FULL OpenGOAL runtime is cross-compiled into
# libgk.so via the NDK. Distinguishes a real link from the phase-10 scaffold
# stub by enforcing size + dependency + symbol checks.
#
# Pass conditions:
#   - cmake reconfigure + build succeed against the NDK toolchain
#   - libgk.so exists at build-android/lib/arm64-v8a/libgk.so
#   - file(1) confirms ARM aarch64 shared object
#   - size >= MIN_LIBGK_SIZE_MB (the scaffold is ~50 KB; real link is multi-MB)
#   - DT_NEEDED entries include core Android system libs (liblog, libdl, libc)
#   - DT_NEEDED entries reference at least one of SDL / GLES (proves the
#     real runtime stack was linked, not just JNI glue)
#   - exported symbols include OpenGOAL-internal markers (goal_main /
#     kernel-context / JIT entry) — proves the GOAL VM is inside the .so
#
# The size threshold is deliberately conservative: 2 MB. A fully-stripped
# release build of the gk runtime on desktop is ~12 MB; with debug info and
# game data subsystems linked it is much larger. 2 MB is a generous floor
# that no plausible stub can meet.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=../lib/android-env.sh
. .autoport/lib/android-env.sh

echo "== Phase 12 validator (real Android runtime in libgk.so) =="

MIN_LIBGK_SIZE_BYTES=$((2 * 1024 * 1024))

[ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ] \
    || { echo "FAIL: ANDROID_NDK_HOME not set or invalid"; exit 1; }

# Reconfigure cleanly to avoid cached scaffold state.
rm -rf build-android
cmake -B build-android -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-29 \
    -DGOALC_BACKEND=arm64 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    > /tmp/cmake-android.log 2>&1 || {
    echo "FAIL: cmake configure"; tail -80 /tmp/cmake-android.log; exit 1
}

cmake --build build-android --target gk > /tmp/build-android.log 2>&1 || {
    echo "FAIL: cmake --build gk"; tail -120 /tmp/build-android.log; exit 1
}

LIBGK=""
for cand in \
    build-android/lib/arm64-v8a/libgk.so \
    build-android/game/libgk.so \
    build-android/libgk.so; do
    if [ -f "$cand" ]; then LIBGK="$cand"; break; fi
done
[ -n "$LIBGK" ] || { echo "FAIL: libgk.so not produced under build-android/"; exit 1; }
echo "  found: $LIBGK"

# 1. Architecture check
FILE_INFO=$(file "$LIBGK")
echo "  file: $FILE_INFO"
echo "$FILE_INFO" | grep -qiE "aarch64|arm aarch" \
    || { echo "FAIL: libgk.so is not aarch64"; exit 1; }
echo "$FILE_INFO" | grep -qi "shared object" \
    || { echo "FAIL: libgk.so is not a shared object"; exit 1; }

# 2. Size check — the scaffold was ~50 KB. Real link is multi-MB.
SIZE=$(stat -c%s "$LIBGK")
echo "  size: $SIZE bytes (floor: $MIN_LIBGK_SIZE_BYTES)"
if [ "$SIZE" -lt "$MIN_LIBGK_SIZE_BYTES" ]; then
    echo "FAIL: libgk.so is too small ($SIZE B). The phase-10 scaffold was ~50 KB;"
    echo "      a real cross-build of the GOAL runtime is multi-MB. Did the build"
    echo "      actually link in game/, common/, goalc/ sources and the third-party deps?"
    exit 1
fi

# 3. DT_NEEDED — pick the NDK readelf since the host one may not understand aarch64.
READELF=$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -name 'llvm-readelf' 2>/dev/null | head -1)
[ -x "$READELF" ] || READELF=$(command -v llvm-readelf || command -v readelf)
NEEDED=$("$READELF" -d "$LIBGK" 2>/dev/null | grep -E 'NEEDED' || true)
echo "  DT_NEEDED:"
echo "$NEEDED" | sed 's/^/    /'

for must in liblog libc libdl libm; do
    echo "$NEEDED" | grep -q "$must" \
        || { echo "FAIL: libgk.so does not link against $must (NDK system lib)"; exit 1; }
done

# Must link against either SDL2/SDL3 OR have audio/graphics deps. Otherwise
# we know the renderer / SDL layer was never wired up.
if ! echo "$NEEDED" | grep -qiE "SDL|GLES|EGL|OpenAL|openal"; then
    echo "FAIL: libgk.so does not link against any of SDL/GLES/EGL/OpenAL."
    echo "      The real runtime stack (graphics + audio) was not cross-built."
    exit 1
fi

# 4. Symbol check — look for OpenGOAL-internal C++ symbols. We grep loosely
# because mangling varies; the goal is to prove the GOAL VM is inside,
# not a hand-rolled stub.
NM=$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -name 'llvm-nm' 2>/dev/null | head -1)
[ -x "$NM" ] || NM=$(command -v llvm-nm || command -v nm)
SYMS=$("$NM" -D --defined-only "$LIBGK" 2>/dev/null || "$NM" --defined-only "$LIBGK" 2>/dev/null || true)
echo "  exported symbol count: $(echo "$SYMS" | wc -l)"

# Look for any of the well-known runtime entry points.
GOAL_MARKERS='goal_main|InitMachine|InitMachineScheme|init_output|kheap_alloc|exec_dgo|InitListenerConnect|kernel_main'
if ! echo "$SYMS" | grep -qE "$GOAL_MARKERS"; then
    # Fallback: strings(1) for the same markers — some symbols may be local-only.
    STRINGS=$(command -v llvm-strings || command -v strings)
    if ! "$STRINGS" "$LIBGK" 2>/dev/null | grep -qE "$GOAL_MARKERS"; then
        echo "FAIL: libgk.so lacks any recognizable GOAL runtime marker symbol or string"
        echo "      (expected one of: $GOAL_MARKERS)"
        exit 1
    else
        echo "  GOAL runtime markers found in strings (symbols may be hidden)"
    fi
else
    echo "  GOAL runtime markers found in exported symbols"
fi

echo "== Phase 12 validator PASSED =="
