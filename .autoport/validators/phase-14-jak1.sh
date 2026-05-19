#!/usr/bin/env bash
# Validator for phase 14: Jak 1 game data compiles cleanly with the arm64
# backend and lands in the jak1 product flavor's APK.
#
# Pass conditions:
#   - User-supplied PS2 ISO contents under iso_data/jak1/
#   - Host build of goalc + decompiler succeeds with GOALC_BACKEND=arm64
#   - decompiler produces decompiler_out/jak1/
#   - goalc compiles goal_src/jak1/ end-to-end to out/jak1/iso/*.CGO
#   - Assets staged to android/app/src/jak1/assets/iso_data/jak1/
#   - assembleJak1Debug rebuilds APK and the APK contains the assets

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=../lib/android-env.sh
. .autoport/lib/android-env.sh

GAME="jak1"
FLAVOR_NAME="Jak1"  # capitalized form used in Gradle task names
echo "== Phase 14 validator (Jak 1: compile + bundle into app-${GAME}-debug.apk) =="

if [ -z "$(ls -A iso_data/$GAME 2>/dev/null)" ]; then
    cat <<EOF
FAIL: iso_data/$GAME/ is empty.

Place your extracted Jak & Daxter PS2 disc contents under:
    $(pwd)/iso_data/$GAME/
EOF
    exit 1
fi

# 1. Host build with arm64 backend.
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGOALC_BACKEND=arm64 \
    > /tmp/cmake-host.log 2>&1 || {
    echo "FAIL: cmake configure host"; tail -80 /tmp/cmake-host.log; exit 1
}
cmake --build build --target goalc --target decompiler > /tmp/build-host.log 2>&1 || {
    echo "FAIL: build goalc/decompiler"; tail -120 /tmp/build-host.log; exit 1
}

GOALC=$(find build -name goalc -type f -executable | head -1)
DECOMP=$(find build -name decompiler -type f -executable | head -1)
[ -n "$GOALC" ]  || { echo "FAIL: goalc binary missing"; exit 1; }
[ -n "$DECOMP" ] || { echo "FAIL: decompiler binary missing"; exit 1; }

# 2. Decompile if needed (cached otherwise).
if [ ! -d decompiler_out/$GAME ] || [ -z "$(ls -A decompiler_out/$GAME 2>/dev/null)" ]; then
    echo "  running decompiler for $GAME…"
    "$DECOMP" "decompiler/config/${GAME}/${GAME}_config.jsonc" \
        ./iso_data ./decompiler_out > /tmp/decomp-${GAME}.log 2>&1 || {
        echo "FAIL: decompiler $GAME"; tail -120 /tmp/decomp-${GAME}.log; exit 1
    }
fi

# 3. Compile GOAL source.
echo "  running goalc on goal_src/$GAME…"
"$GOALC" --auto-lt --startup-cmd "(mi)(:exit)" \
    --game "$GAME" \
    > /tmp/goalc-${GAME}.log 2>&1 || {
    echo "FAIL: goalc compile $GAME"; tail -120 /tmp/goalc-${GAME}.log; exit 1
}

# 4. Outputs present.
OUT_DIR="out/$GAME/iso"
test -d "$OUT_DIR" || { echo "FAIL: $OUT_DIR not produced"; exit 1; }
N_CGO=$(find "$OUT_DIR" -iname '*.CGO' 2>/dev/null | wc -l)
N_STR=$(find "$OUT_DIR" -iname '*.STR' 2>/dev/null | wc -l)
echo "  $OUT_DIR: $N_CGO CGO, $N_STR STR"
[ "$N_CGO" -gt 0 ] || { echo "FAIL: no CGO files produced — goalc emitted nothing"; exit 1; }

# 5. Stage into per-flavor assets dir (NOT src/main/, so other flavors don't ship it).
STAGE_DIR="android/app/src/${GAME}/assets/iso_data/${GAME}"
mkdir -p "$STAGE_DIR"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$OUT_DIR/" "$STAGE_DIR/"
else
    rm -rf "$STAGE_DIR"; mkdir -p "$STAGE_DIR"
    cp -r "$OUT_DIR/." "$STAGE_DIR/"
fi
N_STAGED=$(find "$STAGE_DIR" -type f | wc -l)
echo "  staged $N_STAGED files under $STAGE_DIR"
[ "$N_STAGED" -gt 0 ] || { echo "FAIL: nothing staged"; exit 1; }

# 6. Rebuild the jak1 APK and confirm assets land inside.
cd android
GRADLE_CMD=$([ -f gradle/wrapper/gradle-wrapper.jar ] && [ -x gradlew ] \
    && echo "./gradlew" || echo "gradle")
"$GRADLE_CMD" --no-daemon "assemble${FLAVOR_NAME}Debug" > /tmp/gradle-${GAME}.log 2>&1 || {
    echo "FAIL: ${GRADLE_CMD} assemble${FLAVOR_NAME}Debug"
    tail -120 /tmp/gradle-${GAME}.log
    exit 1
}

APK=$(find "app/build/outputs/apk/${GAME}/debug" -maxdepth 2 -name '*.apk' 2>/dev/null | head -1)
[ -n "$APK" ] || { echo "FAIL: no ${GAME} debug APK produced"; exit 1; }
echo "  apk: $APK ($(stat -c%s "$APK") bytes)"

# Confirm the APK actually shipped the staged data.
# Use grep -c (drains stdin) rather than grep -q here. The Jak 1 APK is
# ~1.1 GB and `unzip -l` produces a huge listing, so `grep -q` exits on
# the first match and the resulting SIGPIPE on unzip trips `set -o pipefail`.
N_IN_APK=$(unzip -l "$APK" | grep -c "assets/iso_data/${GAME}/" || true)
if [ "$N_IN_APK" -eq 0 ]; then
    echo "FAIL: APK does not contain assets/iso_data/${GAME}/ — flavor source set mis-wired?"
    exit 1
fi
echo "  apk contains $N_IN_APK files under assets/iso_data/${GAME}/"

# 7. Optional emulator smoke.
if adb devices 2>/dev/null | grep -qE "(emulator-|device$)"; then
    adb install -r "$APK" > /tmp/adb-install-${GAME}.log 2>&1 || true
    adb logcat -c || true
    adb shell am start -n "org.opengoal.gk.${GAME}/org.opengoal.gk.MainActivity" \
        > /tmp/launch-${GAME}.log 2>&1 || true
    sleep 30
    if adb logcat -d 2>&1 | grep -qE "loading kernel\.cgo|level zero loaded|target started|kernel: target online|gk \(.* started"; then
        echo "  emulator smoke ok: engine init line observed"
    else
        echo "  (emulator launched but no engine-init line — non-fatal at this phase)"
    fi
else
    echo "  (no emulator running — host compile + APK structure verified)"
fi

cd ..
echo "== Phase 14 validator PASSED =="
