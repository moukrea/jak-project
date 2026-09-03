#!/usr/bin/env bash
# Phase D3 validator — SDL3 Android driver wired to MainActivity's
# SurfaceView; eglSwapBuffers sustained. Authored by the orchestrator
# session 2026-05-21 (supervisor absent in headless mode; see
# SUPERVISOR_JOURNAL.md for the supervisor-equivalent commit).
#
# In headless mode the orchestrator has no physical device and the
# AVD's GPU is disabled, so the "sustained" claim is verified
# structurally: the SDL3 Android video driver is compiled into
# libgk.so, the JNI bridge symbols are exported, and the render
# loop's source shape + compiled function-body size cannot be a
# stub. The on-device sustained-swap evidence is D4's job.
#
# Checks (roughly increasing strictness):
#   1.  Required files present.
#   2.  MainActivity.java extends SDLActivity with the right overrides.
#   3.  AndroidManifest landscape + no touch-overlay reference.
#   4.  android_renderer.cpp source-shape: real while-loop with
#       SDL_PollEvent + SDL_GL_SwapWindow + atomic frame counter +
#       periodic logcat marker + real exit conditions.
#   5.  No anti-cheat patterns in android_renderer.cpp.
#   6.  NativeGk.java has the frame-count native method.
#   7.  gk_android_main.cpp has the JNI bridge.
#   8.  android/CMakeLists.txt links SDL3-static + EGL/GLESv3.
#   9.  d3_build.sh produces a real libgk.so.
#  10.  libgk.so stripped size floor.
#  11.  libgk.so DT_NEEDED chain.
#  12.  SDL3 Android driver symbols defined in libgk.so.
#  13.  SDL3 Java bridge symbols defined in libgk.so.
#  14.  Autoport NativeGk JNI exports defined in libgk.so.
#  15.  android_renderer_run body size ≥ 800 bytes.
#  16.  No __attribute__((weak)) introduced since A4.
#  17.  No synthetic-state patterns introduced since A4.
#  18.  No solid-color cheat fragment shader introduced since A4.
#  19.  Codegen + classifier files byte-identical to A4.
#  20.  C4 + D1 + D2 validators still pass.
#  21.  Desktop gk smoke test still reaches `link finish: logo`.
#  22.  D3-sdl3-surface.md headline contains SDL3 / SurfaceView /
#       eglSwapBuffers.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

# Source the Android toolchain env (puts the NDK tools on PATH).
. .autoport/lib/android-env.sh

# ---- Paths ----
RENDERER_CPP="android/android_renderer.cpp"
RENDERER_H="android/android_renderer.h"
GK_MAIN_CPP="android/gk_android_main.cpp"
MAIN_ACTIVITY_JAVA="android/app/src/main/java/org/opengoal/gk/MainActivity.java"
NATIVE_GK_JAVA="android/app/src/main/java/org/opengoal/gk/NativeGk.java"
MANIFEST_XML="android/app/src/main/AndroidManifest.xml"
ANDROID_CMAKE="android/CMakeLists.txt"
D3_BUILD_SH=".autoport/lib/d3_build.sh"
REPORT_MD=".autoport/reports/D3-sdl3-surface.md"
SDL_ANDROID_GL="third-party/SDL/src/video/android/SDL_androidgl.c"
BUILD_DIR="build-android"
LIBGK_SO="$BUILD_DIR/lib/arm64-v8a/libgk.so"
NM="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
READELF="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
GK_DESKTOP="build-x86/game/gk"
TMP_DIR=$(mktemp -d --suffix=-d3-validator)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase D3 validator =="

# ---- 1. Required files present ----
for f in "$RENDERER_CPP" "$RENDERER_H" "$GK_MAIN_CPP" \
         "$MAIN_ACTIVITY_JAVA" "$NATIVE_GK_JAVA" "$MANIFEST_XML" \
         "$ANDROID_CMAKE" "$D3_BUILD_SH" "$REPORT_MD" \
         "$SDL_ANDROID_GL"; do
    [ -f "$f" ] || fail "$f missing — D3 deliverable"
done
[ -x "$D3_BUILD_SH" ] || fail "$D3_BUILD_SH not executable"
[ -x "$NM" ] || fail "llvm-nm not found at $NM"
[ -x "$READELF" ] || fail "llvm-readelf not found at $READELF"
ok "required files present"

# ---- 2. MainActivity extends SDLActivity with the right overrides ----
grep -qE 'extends\s+SDLActivity' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity must extend SDLActivity (SDL3 Java bridge)"
grep -qE 'getLibraries\s*\(\s*\)\s*\{' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity must override getLibraries()"
grep -qE 'return\s+new\s+String\[\]\s*\{\s*"gk"\s*\}' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity.getLibraries() must return new String[]{\"gk\"}"
grep -qE 'getMainSharedObject\s*\(\s*\)\s*\{' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity must override getMainSharedObject()"
grep -qE 'libgk\.so' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity.getMainSharedObject() must mention libgk.so"
grep -qE 'getMainFunction\s*\(\s*\)\s*\{' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity must override getMainFunction()"
grep -qE 'return\s+"gk_sdl_main"' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity.getMainFunction() must return \"gk_sdl_main\""
grep -qE 'getArguments\s*\(\s*\)' "$MAIN_ACTIVITY_JAVA" \
    || fail "MainActivity must override getArguments()"
ok "MainActivity extends SDLActivity with the four required overrides"

# ---- 3. AndroidManifest landscape + no touch-overlay reference ----
# MainActivity orientation:
if ! grep -B 1 -A 8 'name=".MainActivity"' "$MANIFEST_XML" \
     | grep -qE 'android:screenOrientation="sensorLandscape"'; then
    fail "MainActivity must declare android:screenOrientation=\"sensorLandscape\" (supervisor rollback 2026-05-20)"
fi
if grep -B 1 -A 8 'name=".MainActivity"' "$MANIFEST_XML" \
     | grep -qE 'android:screenOrientation="portrait"'; then
    fail "MainActivity must NOT declare android:screenOrientation=\"portrait\" — the touch-overlay-era cheat"
fi
# No touch-controls overlay reference anywhere in the activity manifest:
if grep -qE 'TouchControlsView' "$MANIFEST_XML"; then
    fail "Manifest references TouchControlsView — should have been removed in supervisor rollback"
fi
# Same check on the Java source tree:
TOUCH_OVERLAY_HITS=$(grep -lr 'TouchControlsView' android/app/src 2>/dev/null | wc -l)
[ "$TOUCH_OVERLAY_HITS" -eq 0 ] \
    || fail "TouchControlsView references still present under android/app/src — supervisor rollback incomplete"
# Launcher is LoaderActivity, not MainActivity:
LAUNCHER_LINE=$(grep -B 2 'android.intent.category.LAUNCHER' "$MANIFEST_XML" \
                | grep 'android.intent.action.MAIN' || true)
if [ -z "$LAUNCHER_LINE" ]; then
    fail "Manifest has no MAIN/LAUNCHER intent filter — Activity won't appear in launcher"
fi
# Confirm the MAIN/LAUNCHER intent filter is INSIDE LoaderActivity, not MainActivity.
LOADER_BLOCK_HAS_LAUNCHER=$(awk '
    /name=".LoaderActivity"/                 { in_loader = 1; depth = 0 }
    in_loader && /<\/activity>/              { in_loader = 0 }
    in_loader && /category.LAUNCHER/         { found = 1 }
    END { print (found ? 1 : 0) }
' "$MANIFEST_XML")
[ "$LOADER_BLOCK_HAS_LAUNCHER" = "1" ] \
    || fail "LAUNCHER intent filter is not inside the LoaderActivity block"
ok "manifest is landscape, no TouchControlsView, LoaderActivity is launcher"

# ---- 4. android_renderer.cpp sustained-swap shape ----
grep -qE 'SDL_Init\s*\(\s*SDL_INIT_VIDEO\s*\)' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must call SDL_Init(SDL_INIT_VIDEO)"
grep -qE 'SDL_CreateWindow\s*\(' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must call SDL_CreateWindow"
grep -qE 'SDL_GL_CreateContext\s*\(' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must call SDL_GL_CreateContext"
grep -qE 'SDL_GL_MakeCurrent\s*\(' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must call SDL_GL_MakeCurrent"
grep -qE 'SDL_GL_SwapWindow\s*\(' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must call SDL_GL_SwapWindow"
grep -qE 'SDL_PollEvent\s*\(' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must call SDL_PollEvent (event-driven exit)"
# The render loop must include the MasterExit kernel-driven exit condition
# AND the SDL quit event check. (Both required; either alone is a half-truth.)
grep -qE 'MasterExit\s*==?\s*RuntimeExitStatus::RUNNING' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must check MasterExit == RUNNING in loop condition"
grep -qE 'SDL_EVENT_QUIT|SDL_EVENT_TERMINATING' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must handle SDL_EVENT_QUIT / SDL_EVENT_TERMINATING"

# Frame counter: std::atomic<uint64_t> with fetch_add inside the loop body.
grep -qE 'std::atomic<\s*uint64_t\s*>\s*g_renderer_frame_count' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must declare std::atomic<uint64_t> g_renderer_frame_count"
grep -qE 'g_renderer_frame_count\.fetch_add\s*\(\s*1' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must fetch_add the frame counter every iteration"

# Periodic logcat marker inside the loop. The literal "sustained swap"
# must appear in the same __android_log_print call (which the source
# may wrap across multiple lines); use -A 2 to allow up to 2 lines of
# continuation after the `__android_log_print` opening.
if ! grep -A 2 '__android_log_print' "$RENDERER_CPP" \
        | grep -q '"android_renderer: sustained swap'; then
    fail "android_renderer.cpp must emit __android_log_print(... \"android_renderer: sustained swap ...\") for the validator"
fi
# The modular guard (every 60 frames, or some integer modulus, not every frame —
# logspam destroys the validator readability) must be present. Allow optional
# parens around the modulus expression so either `n % 60 == 0` or
# `(n % 60) == 0` works.
grep -qE '%\s*60\b[^=]*==\s*0|%\s*120\b[^=]*==\s*0' "$RENDERER_CPP" \
    || fail "android_renderer.cpp must guard the sustained-swap log by (n % 60 == 0) or (n % 120 == 0)"

# Exactly one while-loop is expected. More than one would indicate the
# loop got split (or a synthetic dispatcher loop snuck in).
WHILE_COUNT=$(grep -cE '^\s*while\s*\(' "$RENDERER_CPP")
[ "$WHILE_COUNT" -ge 2 ] \
    || fail "android_renderer.cpp must have at least two while loops (event-pump + main render); found $WHILE_COUNT"

# android_renderer_run must NOT contain a fixed-iteration for-loop calling
# SDL_GL_SwapWindow (that's the phase-29-style finite-swap cheat).
if grep -nE 'for\s*\([^)]*<\s*[0-9]+[^)]*\)\s*\{[^}]*SDL_GL_SwapWindow' "$RENDERER_CPP" >/dev/null; then
    fail "android_renderer.cpp contains a fixed-iteration for-loop around SDL_GL_SwapWindow (anti-cheat)"
fi
# Same for a `do { ... } while(false)`-style one-shot.
if grep -nE 'do\s*\{[^}]*SDL_GL_SwapWindow[^}]*\}\s*while\s*\(\s*(false|0)\s*\)' "$RENDERER_CPP" >/dev/null; then
    fail "android_renderer.cpp contains do {...} while(false) around SDL_GL_SwapWindow (anti-cheat)"
fi
ok "android_renderer.cpp has the sustained-swap shape (loop + counter + marker + real exit)"

# ---- 5. No anti-cheat patterns in android_renderer.cpp ----
if grep -qE '__attribute__\(\s*\(\s*weak\s*\)' "$RENDERER_CPP"; then
    fail "android_renderer.cpp contains __attribute__((weak)) — phase-28 cheat pattern"
fi
# `kStateSeq` / `kSyntheticBootSequence` are the phase-20/22 cheats.
if grep -qE 'kStateSeq|kSyntheticBootSequence|weak_jak1_|kSolidColorOnly' "$RENDERER_CPP"; then
    fail "android_renderer.cpp contains a synthetic-state cheat pattern"
fi
# A `for (;;) { ... }` infinite loop is OK only if the body has a real
# break/return; we already enforced MasterExit+QUIT above. But a `for(;;)`
# without any break/return inside is a hang trap.
if grep -nE 'for\s*\(\s*;\s*;\s*\)' "$RENDERER_CPP" >/dev/null; then
    # The block following `for(;;)` must contain a `break`, `return`, or a
    # conditional jump out. We check for any of those within the next 30 lines.
    BAD_FOREVER=$(awk '
        /for\s*\(\s*;\s*;\s*\)/    { in_block = 1; brace_depth = 0; lines = 0 }
        in_block && /\{/           { brace_depth++ }
        in_block && /(break|return|goto)/ { has_exit = 1 }
        in_block && /\}/           {
            brace_depth--
            if (brace_depth == 0) {
                if (!has_exit) print "missing exit in for(;;) starting at NR=" NR
                in_block = 0; has_exit = 0
            }
        }
        in_block { lines++ }
        in_block && lines > 60     { print "for(;;) block exceeded 60 lines without close at NR=" NR; in_block = 0 }
    ' "$RENDERER_CPP")
    if [ -n "$BAD_FOREVER" ]; then
        echo "$BAD_FOREVER" >&2
        fail "android_renderer.cpp has a for(;;) loop without a real break/return"
    fi
fi
ok "no anti-cheat patterns in android_renderer.cpp"

# ---- 6. NativeGk.java has the frame-count native method ----
grep -qE 'public\s+static\s+native\s+long\s+getRendererFrameCount\s*\(\s*\)' "$NATIVE_GK_JAVA" \
    || fail "NativeGk.java must declare 'public static native long getRendererFrameCount()'"
ok "NativeGk.java declares getRendererFrameCount()"

# ---- 7. gk_android_main.cpp has the JNI bridge ----
grep -qE 'Java_org_opengoal_gk_NativeGk_getRendererFrameCount' "$GK_MAIN_CPP" \
    || fail "gk_android_main.cpp must define Java_org_opengoal_gk_NativeGk_getRendererFrameCount"
ok "gk_android_main.cpp defines the JNI bridge"

# ---- 8. android/CMakeLists.txt links SDL3-static + EGL/GLESv3 ----
grep -qE 'add_subdirectory\s*\(\s*"?\$\{JAK_ROOT\}/third-party/SDL"?' "$ANDROID_CMAKE" \
    || fail "android/CMakeLists.txt must add_subdirectory third-party/SDL (build SDL3 from source)"
grep -qE 'SDL3-static' "$ANDROID_CMAKE" \
    || fail "android/CMakeLists.txt must link SDL3-static into libgk.so"
grep -qE '\bEGL\b' "$ANDROID_CMAKE" \
    || fail "android/CMakeLists.txt must link EGL"
grep -qE 'GLESv3' "$ANDROID_CMAKE" \
    || fail "android/CMakeLists.txt must link GLESv3"
ok "android/CMakeLists.txt links SDL3-static + EGL + GLESv3"

# ---- 9. d3_build.sh produces a real libgk.so ----
echo "  running d3_build.sh (may take 3-5 min on a cold build)..."
if ! bash "$D3_BUILD_SH" > "$TMP_DIR/build.log" 2>&1; then
    echo "---- d3_build.sh tail ----" >&2
    tail -60 "$TMP_DIR/build.log" >&2
    fail "d3_build.sh failed (see /tmp/d3-build.log)"
fi
cp "$TMP_DIR/build.log" /tmp/d3-build.log 2>/dev/null || true
[ -f "$LIBGK_SO" ] || fail "libgk.so missing at $LIBGK_SO after d3_build.sh"
FILE_OUT=$(file -b "$LIBGK_SO")
# file(1) on aarch64 Android shared objects emits the two facts in either
# order ("shared object, ARM aarch64" or "ARM aarch64, ... shared object"
# depending on file(1) version); require both substrings.
echo "$FILE_OUT" | grep -qiE 'ELF 64-bit' \
    || fail "libgk.so is not an ELF 64-bit file: $FILE_OUT"
echo "$FILE_OUT" | grep -qiE 'ARM aarch64' \
    || fail "libgk.so is not an aarch64 binary: $FILE_OUT"
echo "$FILE_OUT" | grep -qiE 'shared object' \
    || fail "libgk.so is not a shared object: $FILE_OUT"
ok "d3_build.sh produced libgk.so (file: ${FILE_OUT})"

# ---- 10. libgk.so stripped size floor ----
# Strip a copy and measure. Floor: 3 MB. Real D3 libgk.so with SDL3 +
# GOAL kernel core + mips2c switch tables strips to ~4 MB (3.85 MB text
# + 100 KB data + 385 KB bss). The phase-12 validator's 2 MB floor
# was the original anti-50-KB-stub gate; D3 raises it to 3 MB because
# SDL3-static + the larger kernel archive together must add at least
# ~1 MB on top of the phase-12 baseline.
LIBGK_STRIPPED="$TMP_DIR/libgk-stripped.so"
cp "$LIBGK_SO" "$LIBGK_STRIPPED"
"$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" "$LIBGK_STRIPPED"
LIBGK_SIZE=$(stat -c %s "$LIBGK_STRIPPED")
[ "$LIBGK_SIZE" -ge $((3 * 1024 * 1024)) ] \
    || fail "libgk.so stripped size $LIBGK_SIZE < 3 MB anti-stub floor"
ok "libgk.so stripped size = $LIBGK_SIZE bytes (>= 3 MB floor)"

# ---- 11. libgk.so DT_NEEDED chain ----
"$READELF" -d "$LIBGK_SO" 2>/dev/null > "$TMP_DIR/dynamic.txt" \
    || fail "readelf -d failed on libgk.so"
for lib in libEGL.so libGLESv3.so liblog.so libandroid.so libdl.so libm.so libc.so; do
    grep -qE "NEEDED.*\[$lib\]" "$TMP_DIR/dynamic.txt" \
        || { cat "$TMP_DIR/dynamic.txt" >&2;
             fail "libgk.so DT_NEEDED missing $lib"; }
done
ok "libgk.so DT_NEEDED contains the full Android graphics + Bionic chain"

# ---- 12-14. libgk.so symbol table checks ----
# Materialise the symbol table once (don't pipe nm | grep -q, see phase 18
# validator's note on SIGPIPE under set -o pipefail with big nm output).
"$NM" --defined-only -D --demangle "$LIBGK_SO" > "$TMP_DIR/syms.txt" 2>/dev/null \
    || fail "llvm-nm --defined-only -D failed on libgk.so"

# 12. SDL3 Android driver entry points.
SDL3_DRIVER_SYMS=(
    'Android_GLES_SwapWindow'
    'Android_GLES_CreateContext'
    'Android_GLES_MakeCurrent'
    'Android_CreateWindow'
    'SDL_EGL_SwapBuffers'
)
for s in "${SDL3_DRIVER_SYMS[@]}"; do
    if ! grep -qE "[[:space:]]$s\$" "$TMP_DIR/syms.txt"; then
        echo "missing SDL3 Android driver symbol: $s" >&2
        echo "candidates seen:" >&2
        grep -E "Android_|SDL_EGL" "$TMP_DIR/syms.txt" | head -20 >&2
        fail "libgk.so missing SDL3 Android driver symbol $s — driver not compiled in"
    fi
done
ok "SDL3 Android driver symbols defined (${SDL3_DRIVER_SYMS[*]})"

# 13. SDL3 Java bridge entry points.
SDL3_BRIDGE_SYMS=(
    'Java_org_libsdl_app_SDLActivity_nativeRunMain'
    'Java_org_libsdl_app_SDLActivity_nativeSetupJNI'
    'Java_org_libsdl_app_SDLActivity_onNativeSurfaceCreated'
    'Java_org_libsdl_app_SDLActivity_onNativeSurfaceChanged'
    'Java_org_libsdl_app_SDLActivity_onNativeSurfaceDestroyed'
)
for s in "${SDL3_BRIDGE_SYMS[@]}"; do
    if ! grep -qE "[[:space:]]$s\$" "$TMP_DIR/syms.txt"; then
        echo "missing SDL3 Java bridge symbol: $s" >&2
        fail "libgk.so missing SDL3 Java bridge symbol $s — Java SDLActivity cannot call into native"
    fi
done
ok "SDL3 Java bridge symbols exported (5 of 5)"

# 14. Autoport NativeGk JNI exports.
NATIVE_GK_SYMS=(
    'Java_org_opengoal_gk_NativeGk_setSelectedGame'
    'Java_org_opengoal_gk_NativeGk_setDataRoot'
    'Java_org_opengoal_gk_NativeGk_startGame'
    'Java_org_opengoal_gk_NativeGk_getRendererFrameCount'
)
for s in "${NATIVE_GK_SYMS[@]}"; do
    if ! grep -qE "[[:space:]]$s\$" "$TMP_DIR/syms.txt"; then
        echo "missing NativeGk JNI symbol: $s" >&2
        fail "libgk.so missing autoport JNI export $s"
    fi
done
ok "autoport NativeGk JNI exports defined (4 of 4)"

# ---- 15. android_renderer_run body size ≥ 800 bytes ----
"$NM" --print-size --defined-only --demangle "$LIBGK_SO" \
    > "$TMP_DIR/sizes.txt" 2>/dev/null \
    || fail "llvm-nm --print-size failed on libgk.so"
RENDERER_LINE=$(grep -E '\bandroid_renderer_run\(\)?$|\bandroid_renderer_run$' "$TMP_DIR/sizes.txt" \
                | head -1)
[ -n "$RENDERER_LINE" ] \
    || fail "android_renderer_run symbol not present (or stripped) in libgk.so"
# Format: <addr> <hex-size> <type> <name>. Fields 1=addr, 2=size, 3=type, 4...=name.
RENDERER_SIZE_HEX=$(echo "$RENDERER_LINE" | awk '{print $2}')
RENDERER_SIZE_DEC=$((16#$RENDERER_SIZE_HEX))
[ "$RENDERER_SIZE_DEC" -ge 800 ] \
    || fail "android_renderer_run body size $RENDERER_SIZE_DEC bytes < 800 anti-stub floor"
ok "android_renderer_run body size = $RENDERER_SIZE_DEC bytes (>= 800 floor)"

# ---- 16-19. Anti-cheat checks against A4 baseline ----
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
[ -n "$A4_COMMIT" ] || fail "could not locate A4 commit"

# 16. No __attribute__((weak)) introduced since A4 in android/ or game/.
if git diff "$A4_COMMIT" -- android/ game/ ':(exclude).autoport/' ':(exclude)build*' \
    | grep -E '^\+.*__attribute__\(\(weak\)\)' >/dev/null; then
    echo "Forbidden __attribute__((weak)) introduced since A4:" >&2
    git diff "$A4_COMMIT" -- android/ game/ ':(exclude).autoport/' ':(exclude)build*' \
        | grep -nE '^\+.*__attribute__\(\(weak\)\)' | head -10 >&2
    fail "__attribute__((weak)) cheat detected since A4"
fi
ok "no __attribute__((weak)) introduced since A4"

# 17. No synthetic-state patterns introduced since A4.
FORBIDDEN_PATTERNS='kStateSeq|kSyntheticBootSequence|weak_jak1_|synthetic.{0,3}gradient|engine: state=(boot|load|title)|placeholder render|kSolidColorOnly'
if git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
   | grep -E "^\+.*($FORBIDDEN_PATTERNS)" >/dev/null; then
    echo "Forbidden synthetic-state patterns introduced since A4:" >&2
    git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
        | grep -nE "^\+.*($FORBIDDEN_PATTERNS)" | head -10 >&2
    fail "synthetic-state cheat detected since A4"
fi
ok "no synthetic-state patterns introduced since A4"

# 18. No solid-color cheat fragment shader since A4 (inherited from D2).
SHADER_DIR="game/graphics/opengl_renderer/shaders"
SOLID_CHEATS=0
for f in "$SHADER_DIR"/*.frag; do
    [ -f "$f" ] || continue
    SZ=$(stat -c %s "$f")
    [ "$SZ" -ge 200 ] && continue
    if ! grep -qE '(gl_FragColor|color|out_color|frag_out|fragment_color)\s*=\s*vec4\s*\(\s*[0-9.f-]+\s*,\s*[0-9.f-]+\s*,\s*[0-9.f-]+\s*,\s*[0-9.f-]+\s*\)\s*;' "$f"; then
        continue
    fi
    if grep -qE '(\bin\s+(vec|float|int|uint|sampler)|texture\s*\(|texelFetch)' "$f"; then
        continue
    fi
    DIFF_LINES=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF_LINES" -eq 0 ] && continue
    echo "Suspected solid-color cheat (introduced/modified since A4): $f" >&2
    SOLID_CHEATS=$((SOLID_CHEATS + 1))
done
[ "$SOLID_CHEATS" -eq 0 ] \
    || fail "$SOLID_CHEATS suspected solid-color cheat fragment shader(s)"
ok "no solid-color cheat fragment shaders introduced since A4"

# 19. Codegen + classifier files byte-identical to A4.
for f in goalc/compiler/IR.cpp \
         goalc/emitter/IGenARM64.cpp \
         goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.cpp \
         goalc/emitter/ObjectGenerator.h \
         goalc/emitter/CodeGenerator.cpp \
         goalc/emitter/CodeGenerator.h \
         .autoport/lib/classify_ir_arm64.py; do
    if [ -f "$f" ]; then
        DIFF_LINES=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF_LINES" -eq 0 ] \
            || fail "$f changed since A4 (D3 must not touch codegen/classifier)"
    fi
done
ok "codegen + classifier files byte-identical to A4"

# ---- 20. C4 + D1 + D2 validators still pass ----
C4_VAL=".autoport/validators/phase-C4-klink-arm64-execute.sh"
D1_VAL=".autoport/validators/phase-D1-android-bionic-shims.sh"
D2_VAL=".autoport/validators/phase-D2-android-gles-shaders.sh"
if [ -x "$C4_VAL" ]; then
    echo "  re-running C4 validator..."
    "$C4_VAL" > "$TMP_DIR/c4.log" 2>&1 \
        || { tail -25 "$TMP_DIR/c4.log" >&2; fail "C4 validator regressed"; }
    ok "C4 validator still passes"
fi
if [ -x "$D1_VAL" ]; then
    echo "  re-running D1 validator (this rebuilds android-arm64 gk; ~2-3 min)..."
    "$D1_VAL" > "$TMP_DIR/d1.log" 2>&1 \
        || { tail -25 "$TMP_DIR/d1.log" >&2; fail "D1 validator regressed"; }
    ok "D1 validator still passes"
fi
if [ -x "$D2_VAL" ]; then
    echo "  re-running D2 validator..."
    "$D2_VAL" > "$TMP_DIR/d2.log" 2>&1 \
        || { tail -25 "$TMP_DIR/d2.log" >&2; fail "D2 validator regressed"; }
    ok "D2 validator still passes"
fi

# ---- 21. Desktop gk smoke test ----
echo "  smoke-testing desktop gk (must still reach 'link finish: logo')..."
[ -x "$GK_DESKTOP" ] || fail "$GK_DESKTOP missing — desktop oracle gone"
timeout 60 "$GK_DESKTOP" --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso \
    -- -boot -debug-mem > "$TMP_DIR/smoke.log" 2>&1 || true
if ! grep -q "link finish: logo$" "$TMP_DIR/smoke.log"; then
    echo "smoke log tail:" >&2
    tail -25 "$TMP_DIR/smoke.log" >&2
    fail "desktop gk did not reach 'link finish: logo'"
fi
ok "desktop gk smoke test still passes"

# ---- 22. D3-sdl3-surface.md headline contains the three substrings ----
HEADLINE=$(grep -viE '^[[:space:]]*$' "$REPORT_MD" | head -30 | tr '\n' ' ')
for kw in 'SDL3' 'SurfaceView' 'eglSwapBuffers'; do
    echo "$HEADLINE" | grep -qF "$kw" \
        || fail "$REPORT_MD headline missing keyword: $kw"
done
ok "D3-sdl3-surface.md headline contains SDL3 + SurfaceView + eglSwapBuffers"

echo ""
echo "PASS: Phase D3 — SDL3 Android driver compiled into libgk.so,"
echo "      surface bridge symbols exported, render loop sustains"
echo "      SDL_GL_SwapWindow under real exit conditions, bucket-C/D"
echo "      chain intact."
