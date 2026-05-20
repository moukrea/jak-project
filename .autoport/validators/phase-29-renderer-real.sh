#!/usr/bin/env bash
# Phase 29 validator: real renderer chain ported; ≥10 shaders compile;
# framebuffer pixel content is diverse (not a solid-color clear loop).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/anti-stub.sh
. .autoport/lib/device-validate.sh

echo "== Phase 29 validator (real renderer chain, on-device pixel check) =="

PACKAGE="org.opengoal.gk.jak1"

# 1. nm check: renderer classes must be linked.
device_require_attached
device_uninstall_other_games "$PACKAGE"
device_build_flavor jak1

TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
unzip -p "$APK_JAK1" lib/arm64-v8a/libgk.so > "$TMP/libgk.so" 2>/dev/null
NM="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
[ -x "$NM" ] || NM=$(command -v llvm-nm)
NM_OUT=$($NM --defined-only -D --demangle "$TMP/libgk.so" 2>/dev/null)

REQUIRED=(TfragRenderer TieRenderer MercRenderer SpriteRenderer SkyRenderer ShadowRenderer DirectRenderer)
# Phase 29 (autoport) fix: use a bash substring check rather than
# `echo "$NM_OUT" | grep -qE`. With nm-output now ~300 KB (phase 27
# widened libgk.so dramatically), `grep -q` closes the pipe after the
# first match and SIGPIPE-kills the echo, which combined with the
# script's `set -o pipefail` propagates as a false "not present"
# negative even when the symbol *is* in NM_OUT.
for pat in "${REQUIRED[@]}"; do
    if [[ "$NM_OUT" != *"$pat"* ]]; then
        echo "FAIL: renderer class '$pat' not present in libgk.so"
        exit 1
    fi
done
echo "  all required renderer classes present"

# 2. android_renderer.cpp placeholder gone.
RFILE=android/android_renderer.cpp
if [ -f "$RFILE" ]; then
    anti_stub_forbid_strings "$RFILE" \
        'solid-color clear loop' \
        'placeholder render' \
        'kSolidColorOnly' \
        || { echo "FAIL: $RFILE still contains placeholder render loop"; exit 1; }
fi

# 3. Install + launch.
device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"
device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 240 \
    || device_fail "loader broken"
device_wait_for_marker 'engine: state=title' 240 \
    || device_fail "kernel never reached title state"

# Give the renderer ~5s after state=title to settle.
sleep 5

# 4. ≥10 distinct shader names compiled OK.
SHADER_LINES=$(grep -E 'shader: [A-Za-z_0-9-]+ compiled OK' "$LOGCAT_LOG" | grep -oE 'shader: [A-Za-z_0-9-]+' | sort -u)
SHADER_N=$(echo "$SHADER_LINES" | grep -c .)
echo "  distinct shaders compiled: $SHADER_N"
echo "$SHADER_LINES" | sed 's/^/    /'
if [ "$SHADER_N" -lt 10 ]; then
    device_fail "only $SHADER_N distinct shaders compiled; expected ≥10"
fi

# 5. Pixel-content check on a screencap of the device.
SCREEN_PNG=$(mktemp --suffix=.png)
adb shell screencap -p > "$SCREEN_PNG" 2>/dev/null
test -s "$SCREEN_PNG" || device_fail "screencap produced empty file"
echo "  screencap saved: $SCREEN_PNG ($(stat -c %s "$SCREEN_PNG") bytes)"

if ! anti_stub_count_pixel_diversity "$SCREEN_PNG" 2>&1; then
    device_fail "framebuffer pixel content fails the diversity check (looks like a solid color clear)"
fi

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 29 validator PASSED =="
echo "   $SHADER_N shaders compiled, all renderer classes linked, framebuffer"
echo "   has ≥50 distinct RGB values in the central region (real rendering"
echo "   is happening, not a glClear loop)."
