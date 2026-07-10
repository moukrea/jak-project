#!/usr/bin/env bash
# grass_fast_redeploy.sh — libgk-only redeploy (BASE_H length + grass.vert width).
# GOAL/CGOs unchanged (already 28/28 consistent on device) and the asset bundle is
# unchanged (bundle version stays 12 -> stamp matches -> NO device re-extraction),
# so this only rebuilds libgk + APK, reinstalls, and deploy_verifies. Fast.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
say(){ echo; echo "######## $* ########"; }
die(){ echo "[fast-redeploy FAIL] $*" >&2; exit 1; }

say "1. x86 gk compile-check (phase lock: x86 must still build)"
cmake --build build --target gk -j"$(nproc)" 2>&1 | grep -iE 'GrassRenderer|error:|Error|Built target gk|ninja: build stopped' | head -20
[ -x build/game/gk ] || die "x86 gk missing"

say "2. build android libgk (BASE_H + grass.vert width enter the blob)"
touch game/graphics/opengl_renderer/GrassRenderer.cpp \
      game/graphics/opengl_renderer/shaders/grass.vert
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
GH=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'recharged.?grass|grass.?blade|grass_inst|g_grass')
echo "  libgk grass strings: ${GH:-0}"; [ "${GH:-0}" -gt 0 ] || die "libgk has no grass strings"

say "3. assemble APK"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle failed"
[ -f "$APK" ] || die "APK missing"

say "4. install -r (keeps data + stamp=12 -> no re-extract) + deploy_verify"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4 || die "deploy_verify failed"
echo "[fast-redeploy] DONE — device runs fresh libgk; CGOs already consistent; no re-extraction."
