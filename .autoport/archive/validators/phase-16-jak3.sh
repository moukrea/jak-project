#!/usr/bin/env bash
# Validator for phase 16: Jak 3 game data compiles cleanly with the arm64
# backend and lands in the jak3 product flavor's APK.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=../lib/android-env.sh
. .autoport/lib/android-env.sh

GAME="jak3"
FLAVOR_NAME="Jak3"
echo "== Phase 16 validator (Jak 3: compile + bundle into app-${GAME}-debug.apk) =="

if [ -z "$(ls -A iso_data/$GAME 2>/dev/null)" ]; then
    cat <<EOF
FAIL: iso_data/$GAME/ is empty.

Place your extracted Jak 3 PS2 disc contents under:
    $(pwd)/iso_data/$GAME/
EOF
    exit 1
fi

GOALC=$(find build -name goalc -type f -executable | head -1)
DECOMP=$(find build -name decompiler -type f -executable | head -1)
[ -n "$GOALC" ] || { echo "FAIL: host goalc missing — phase 14 should have built it"; exit 1; }
[ -n "$DECOMP" ] || { echo "FAIL: host decompiler missing"; exit 1; }

if [ ! -d decompiler_out/$GAME ] || [ -z "$(ls -A decompiler_out/$GAME 2>/dev/null)" ]; then
    echo "  running decompiler for $GAME…"
    "$DECOMP" "decompiler/config/${GAME}/${GAME}_config.jsonc" \
        ./iso_data ./decompiler_out > /tmp/decomp-${GAME}.log 2>&1 || {
        echo "FAIL: decompiler $GAME"; tail -120 /tmp/decomp-${GAME}.log; exit 1
    }
fi

echo "  running goalc on goal_src/$GAME…"
"$GOALC" --auto-lt --startup-cmd "(mi)(:exit)" \
    --game "$GAME" \
    > /tmp/goalc-${GAME}.log 2>&1 || {
    echo "FAIL: goalc compile $GAME"; tail -120 /tmp/goalc-${GAME}.log; exit 1
}

OUT_DIR="out/$GAME/iso"
test -d "$OUT_DIR" || { echo "FAIL: $OUT_DIR not produced"; exit 1; }
N_CGO=$(find "$OUT_DIR" -iname '*.CGO' 2>/dev/null | wc -l)
echo "  $OUT_DIR: $N_CGO CGO"
[ "$N_CGO" -gt 0 ] || { echo "FAIL: no CGO files produced for $GAME"; exit 1; }

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
# Use grep -c (drains stdin) rather than grep -q here. The Jak 3 APK is
# ~3.7 GB and `unzip -l` produces a huge listing, so `grep -q` exits on
# the first match and the resulting SIGPIPE on unzip trips `set -o pipefail`.
N_IN_APK=$(unzip -l "$APK" | grep -c "assets/iso_data/${GAME}/" || true)
if [ "$N_IN_APK" -eq 0 ]; then
    echo "FAIL: APK does not contain assets/iso_data/${GAME}/ — flavor source set mis-wired?"
    exit 1
fi
echo "  apk contains $N_IN_APK files under assets/iso_data/${GAME}/"

cd ..
echo "== Phase 16 validator PASSED =="
