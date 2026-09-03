#!/usr/bin/env bash
# Validator for phase 13: a REAL Android APK built with Gradle product
# flavors for per-game variants.
#
# This is the strict replacement for phase 11. The phase-11 fallback that
# zips up a stub manifest is explicitly rejected. To pass:
#
#   - android/gradlew dispatches to a real `gradle` (no shell fallback)
#   - product flavors jak1/jak2/jak3 are configured in app/build.gradle.kts
#   - `./gradlew assembleJak1Debug` succeeds against the real AGP
#   - The output APK at app/build/outputs/apk/jak1/debug/ is:
#     - structurally valid (aapt2 dump badging works)
#     - debug-signed (apksigner verify)
#     - contains lib/arm64-v8a/libgk.so >= MIN_LIBGK_SIZE_BYTES
#     - contains classes.dex
#     - applicationId is org.opengoal.gk.jak1
#
# Game data is NOT required at this phase — phases 14-16 populate it.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=../lib/android-env.sh
. .autoport/lib/android-env.sh

echo "== Phase 13 validator (real APK, product flavors) =="

MIN_LIBGK_SIZE_BYTES=$((2 * 1024 * 1024))
EXPECTED_PKG_PREFIX="org.opengoal.gk"

for tool in java gradle adb aapt2 apksigner unzip; do
    require_android_tool "$tool" \
        "Run ./scripts/install-android-toolchain.sh on the host first." \
        || exit 1
done

test -d android || { echo "FAIL: android/ directory missing"; exit 1; }
test -f android/app/build.gradle.kts || { echo "FAIL: android/app/build.gradle.kts missing"; exit 1; }

# 1. Reject the phase-11 shell-fallback gradlew.
if grep -q "fallback-assemble-debug" android/gradlew 2>/dev/null \
        && [ ! -f android/gradle/wrapper/gradle-wrapper.jar ]; then
    echo "FAIL: android/gradlew is still the autoport headless fallback."
    echo "      Phase 13 requires either a real Gradle wrapper (gradle wrapper)"
    echo "      or a gradlew that exec's the system gradle without the zip fallback."
    exit 1
fi

# 2. Require product flavors for jak1/jak2/jak3.
for flavor in jak1 jak2 jak3; do
    if ! grep -qE "create\(\"$flavor\"\)|productFlavors[^}]*\"$flavor\"" \
            android/app/build.gradle.kts; then
        echo "FAIL: product flavor '$flavor' not declared in app/build.gradle.kts."
        echo "      Phase 13 requires productFlavors { jak1; jak2; jak3 } under"
        echo "      flavorDimensions \"game\"."
        exit 1
    fi
done
echo "  flavors: jak1, jak2, jak3 declared"

cd android
GRADLE_CMD=$([ -f gradle/wrapper/gradle-wrapper.jar ] && [ -x gradlew ] \
    && echo "./gradlew" || echo "gradle")
echo "  using: $GRADLE_CMD"

# 3. Assemble jak1 flavor as the canary.
"$GRADLE_CMD" --no-daemon assembleJak1Debug > /tmp/gradle.log 2>&1 || {
    echo "FAIL: $GRADLE_CMD assembleJak1Debug"; tail -120 /tmp/gradle.log; exit 1
}

APK=$(find app/build/outputs/apk/jak1/debug -maxdepth 2 -name '*.apk' 2>/dev/null | head -1)
[ -n "$APK" ] || { echo "FAIL: no jak1 debug APK produced"; exit 1; }
echo "  apk:  $APK ($(stat -c%s "$APK") bytes)"

# 4. aapt2 dump badging — binary AndroidManifest is real.
BADGING=$(aapt2 dump badging "$APK" 2>/tmp/aapt2.err) || {
    echo "FAIL: aapt2 dump badging — APK has no valid binary manifest"
    cat /tmp/aapt2.err
    exit 1
}
PKG=$(echo "$BADGING" | grep "^package:" | head -1 \
        | sed -n "s/^package:[[:space:]]*name='\([^']*\)'.*/\1/p")
echo "  pkg:  $PKG"
case "$PKG" in
    "${EXPECTED_PKG_PREFIX}.jak1"|"${EXPECTED_PKG_PREFIX}")
        ;;
    *)
        echo "FAIL: package name '$PKG' doesn't match expected ${EXPECTED_PKG_PREFIX}[.jak1]"
        exit 1 ;;
esac

# 5. apksigner — debug-signed.
apksigner verify --print-certs "$APK" > /tmp/apksigner.log 2>&1 || {
    echo "FAIL: apksigner verify"; cat /tmp/apksigner.log; exit 1
}
echo "  signed: ok"

# 6. Structural inventory.
# Use here-strings (<<<) rather than `echo "$ZIPLS" | grep -q ...`. With
# `set -o pipefail`, a fast `grep -q` exits early and the upstream `echo`
# can hit SIGPIPE before the kernel has finished delivering the full
# buffer, which makes pipefail report a non-zero status even though the
# match succeeded. Here-strings feed grep through a temp file, with no
# pipe and no race.
ZIPLS=$(unzip -l "$APK")
grep -q "^[[:space:]]*[0-9]\+.* classes.dex$" <<< "$ZIPLS" \
    || { echo "FAIL: APK has no classes.dex"; exit 1; }
grep -q "AndroidManifest.xml" <<< "$ZIPLS" \
    || { echo "FAIL: APK has no AndroidManifest.xml"; exit 1; }
grep -q "lib/arm64-v8a/libgk.so" <<< "$ZIPLS" \
    || { echo "FAIL: APK is missing lib/arm64-v8a/libgk.so"; exit 1; }

# 7. libgk.so size inside the APK (uncompressed).
LIBGK_SIZE=$(awk '/lib\/arm64-v8a\/libgk\.so$/ {print $1; exit}' <<< "$ZIPLS")
echo "  libgk.so inside APK: $LIBGK_SIZE bytes"
if [ -z "$LIBGK_SIZE" ] || [ "$LIBGK_SIZE" -lt "$MIN_LIBGK_SIZE_BYTES" ]; then
    echo "FAIL: libgk.so inside APK is too small ($LIBGK_SIZE B). Confirm phase 12"
    echo "      produced a real runtime under build-android/lib/arm64-v8a/."
    exit 1
fi

# 8. Optional emulator smoke test.
if adb devices 2>/dev/null | grep -qE "(emulator-|device$)"; then
    echo "  emulator detected — installing"
    adb install -r "$APK" > /tmp/adb-install.log 2>&1 || {
        echo "FAIL: adb install"; cat /tmp/adb-install.log; exit 1
    }
    echo "  installed on emulator"
else
    echo "  (no emulator running — install/launch check skipped, APK structure verified)"
fi

echo "== Phase 13 validator PASSED =="
