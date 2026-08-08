#!/usr/bin/env bash
# crisplogo_build_deploy.sh — Grecharged-title-logo-fullres full consistent build + deploy.
# Adapted from foliage_build_deploy.sh. Rebuilds, in one consistent pass:
#   * 28 arm64 CGO/DGO   (new jak1 GOAL: crisp-title-logo? pc-setting + menu row + persistence +
#                         the update-to-os -> pc-set-crisp-title-logo! bridge)
#   * libgk.so           (Merc2 native-overlay deferral + begin_ui_pass replay in
#                         android_opengl_renderer.cpp + gfx.h field + kmachine symbol)
#   * APK                (bundles the fresh libgk)
# No new PNG/texture assets -> asset bundle reused; -r install preserves files/cgo, then the fresh
# consistent CGO set is pushed over it. deploy_verify + deploy_verify_assets prove fresh HEAD.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-title-logo-fullres; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[crisplogo-build FAIL] $*" >&2; exit 1; }

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed (GOAL error?)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"

say "2. build android libgk (Merc2 deferral + orchestrator replay + kmachine symbol)"
touch game/graphics/opengl_renderer/foreground/Merc2.cpp \
      game/graphics/opengl_renderer/foreground/Merc2.h \
      game/graphics/gfx.h \
      game/kernel/jak1/kmachine.cpp \
      game/graphics/opengl_renderer/OpenGLRenderer.cpp \
      android/android_opengl_renderer.cpp
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
# physical-artifact verification the new code actually entered the blob (nm/strings, not greps
# over source): the GOAL->C++ symbol AND the renderer's activity-gate format string.
SYM=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'pc-set-crisp-title-logo')
GATE=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'crisp-logo\] native replay')
NAMES=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c '^logo-volumes-english-lod0$')
echo "  libgk crisp symbol strings=${SYM:-0}  activity-gate strings=${GATE:-0}  logo-name strings=${NAMES:-0}"
[ "${SYM:-0}" -gt 0 ]   || die "libgk.so missing pc-set-crisp-title-logo! (kmachine not compiled in)"
[ "${GATE:-0}" -gt 0 ]  || die "libgk.so missing the [crisp-logo] native replay gate (Merc2 stale)"
[ "${NAMES:-0}" -gt 0 ] || die "libgk.so missing the logo model-name table (Merc2 stale)"

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

say "BUILD+DEPLOY OK — device runs fresh HEAD ($(git rev-parse --short HEAD))"
