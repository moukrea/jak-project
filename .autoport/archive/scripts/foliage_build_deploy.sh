#!/usr/bin/env bash
# foliage_build_deploy.sh — Grecharged-foliage-wind full consistent build + deploy.
# Adapted from grass_build_deploy.sh. Rebuilds, in one consistent pass:
#   * 28 arm64 CGO/DGO   (new jak1 GOAL: recharged-foliage-wind? pc-setting + menu row +
#                         persistence + the update-to-os -> pc-set-foliage-wind! bridge)
#   * libgk.so           (Tie3.cpp palm-wind boost + Shrub.cpp/shrub.vert shrub sway + gfx.h field
#                         + kmachine pc-set-foliage-wind! symbol; shrub.vert re-embeds via the
#                         android shader blob custom-command DEPENDS)
#   * APK                (bundles the fresh libgk)
# No new PNG/texture assets -> asset bundle reused; -r install preserves files/cgo, then the
# fresh consistent CGO set is pushed over it. deploy_verify + deploy_verify_assets prove the device
# runs fresh HEAD.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-foliage-wind; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[foliage-build FAIL] $*" >&2; exit 1; }

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed (GOAL error?)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"

say "2. build android libgk (Tie3 boost + Shrub sway + shrub.vert re-embed enter the blob)"
touch game/graphics/opengl_renderer/background/Tie3.cpp \
      game/graphics/opengl_renderer/background/Shrub.cpp \
      game/graphics/opengl_renderer/background/Shrub.h \
      game/graphics/opengl_renderer/shaders/shrub.vert \
      game/graphics/gfx.h \
      game/kernel/jak1/kmachine.cpp \
      game/graphics/opengl_renderer/OpenGLRenderer.cpp \
      android/android_opengl_renderer.cpp
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
# dual verification the new code + shader actually entered the blob:
SYM=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'pc-set-foliage-wind')
SHD=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'u_wind_strength|u_wind_ymin')
echo "  libgk foliage symbol strings=${SYM:-0}  shader-uniform strings=${SHD:-0}"
[ "${SYM:-0}" -gt 0 ] || die "libgk.so missing pc-set-foliage-wind! (kmachine not compiled in)"
[ "${SHD:-0}" -gt 0 ] || die "libgk.so missing shrub wind uniforms (shrub.vert not re-embedded)"

say "3. assemble APK"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "4. install APK + deploy_verify (build==APK==device libgk)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify (libgk) failed"

say "5. ensure extraction done (boot once if needed) then push consistent CGOs"
extract_done(){ $ADB -s $S shell run-as $PKG ls files/.asset_bundle_stamp >/dev/null 2>&1 \
  && [ "$($ADB -s $S shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$')" -ge 28 ]; }
if ! extract_done; then
  echo "  bundle stamp/CGOs missing -> boot once to extract (can take minutes)"
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
    extract_done && break
    sleep 10
  done
  extract_done || die "asset bundle stamp/CGO set never appeared in 900s"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
fi
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -5 || die "CGO push failed"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify_assets failed"

say "6. relaunch: reach live render, no crash, jak1 foreground"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/foliage-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'foliage|A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render (crash or hang)"
echo "[foliage-build] DONE — foliage-wind build on device, boots to render, deploy_verify + assets PASS."
