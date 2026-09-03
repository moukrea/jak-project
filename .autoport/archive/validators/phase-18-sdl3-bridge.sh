#!/usr/bin/env bash
# Phase 18 validator: SDL3 is linked into libgk.so, MainActivity extends
# SDLActivity, and a GLES context is created on the Activity surface.
# Verified by launching on a USB device and grepping logcat for the SDL
# init→window→context→swap sequence.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/device-validate.sh

echo "== Phase 18 validator (SDL3 + EGL bridge, on-device) =="

PACKAGE="org.opengoal.gk.jak1"

device_require_attached
device_uninstall_other_games "$PACKAGE"
device_require_free_space
device_stayon_on

device_build_flavor jak1
test -f "$APK_JAK1" || device_fail "APK missing at $APK_JAK1"

# Sanity: libgk.so inside the APK exports SDL JNI symbols. Without these,
# the SDLActivity Java side cannot call into native; the app launches
# but stays at a black surface forever with no SDL events.
#
# Implementation note: don't pipe `llvm-nm | grep -q`. The producer side
# is ~2300 lines; `grep -q` exits at the first match, which raises
# SIGPIPE in llvm-nm and (under `set -o pipefail`) makes the pipeline
# look non-zero even when the symbol IS present. Materialise the symbol
# table on disk first, then grep the file — same strictness, no SIGPIPE.
TMP_APKDIR="$(mktemp -d)"
unzip -p "$APK_JAK1" lib/arm64-v8a/libgk.so > "$TMP_APKDIR/libgk.so"
"$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm \
    --defined-only -D "$TMP_APKDIR/libgk.so" 2>/dev/null \
    > "$TMP_APKDIR/symbols.txt"
SDL_JNI_COUNT=$(grep -cE 'Java_org_libsdl_app_SDLActivity' "$TMP_APKDIR/symbols.txt" || true)
if [ "${SDL_JNI_COUNT:-0}" -lt 1 ]; then
    rm -rf "$TMP_APKDIR"
    device_fail "libgk.so missing Java_org_libsdl_app_SDLActivity_* JNI symbols. SDL3 not linked, or --exclude-libs hid them."
fi
echo "  SDL JNI symbols exported by libgk.so: ${SDL_JNI_COUNT}"
rm -rf "$TMP_APKDIR"

# Install & launch through LoaderActivity (Loader will transition to
# MainActivity once iso_data is present, which it should be from phase 17).
device_install_and_launch "$PACKAGE" ".LoaderActivity" "$APK_JAK1"

# Loader → Main transition (give 240s in case extraction was wiped).
if ! device_wait_for_marker "iso_data present at /data/(user|data)/0/${PACKAGE}/files/iso_data/jak1" 240; then
    device_fail "MainActivity never observed iso_data — Loader/extract regression?"
fi

# Now the SDL bring-up sequence.
declare -a markers=(
    'gk_sdl_main: entered'
    'SDL_Init: video subsystem OK'
    'SDL_CreateWindow: [0-9]+x[0-9]+ created'
    'SDL_GL_CreateContext: ok'
    'eglMakeCurrent: success'
    'GL_RENDERER: '
    'eglSwapBuffers: ok'
)

for m in "${markers[@]}"; do
    if ! device_wait_for_marker "$m" 60; then
        device_fail "SDL marker not seen: '$m'"
    fi
done

# No crash within the bring-up window.
device_assert_no_crash "$PACKAGE" || device_fail "crash during SDL bring-up"

# Renderer line must mention Adreno (Redmi Note 9 Pro) OR Mali (other
# devices). Failing this means the EGL context was created on the
# wrong display / wrong surface.
if ! grep -qE 'GL_RENDERER: .*(Adreno|Mali|PowerVR|Xclipse)' "$LOGCAT_LOG"; then
    device_fail "GL_RENDERER line present but doesn't look like a real mobile GPU"
fi

kill ${LOGCAT_PID:-0} 2>/dev/null || true

device_assert_desktop_build

echo
echo "== Phase 18 validator PASSED =="
echo "   SDL3 statically linked into libgk.so, Java SDLActivity bridge"
echo "   wired, EGL/GLES context current on the Activity surface, first"
echo "   eglSwapBuffers fired. Desktop x86 build still green."
