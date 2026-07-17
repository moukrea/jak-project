#!/usr/bin/env bash
# gci_libgk_redeploy.sh — FAST libgk-only redeploy for the Gcamera-interp alpha-formula
# tweak (android/gk_android_main.cpp only; NO goal_src / CGO change). The device already
# runs the fixed 28-CGO set (ENGINE 9d7aed0d...); only libgk changes, so we skip the
# 30-min consistent CGO rebuild: rebuild gk -> reassemble APK (same bundled CGOs) ->
# reinstall (loader skips re-extract: asset bundle version unchanged) -> deploy_verify.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gci-libgk FAIL] $*" >&2; exit 1; }

say "1. rebuild libgk (C++ alpha-formula change) + reassemble APK"
touch android/gk_android_main.cpp game/kernel/common/kmachine.cpp
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "2. capture device ENGINE.CGO hash BEFORE reinstall (must be unchanged after)"
CGO_BEFORE=$($ADB -s $S shell run-as $PKG sha256sum files/cgo/jak1/ENGINE.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  ENGINE.CGO before: ${CGO_BEFORE:-<none>}"

say "3. install APK (keeps app data => fixed CGOs persist, loader skips re-extract)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. deploy_verify (build==APK==device libgk, built-after-source)"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -4 || die "deploy_verify FAILED"

say "5. confirm ENGINE.CGO UNCHANGED (this was a libgk-only change)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
sleep 8
CGO_AFTER=$($ADB -s $S shell run-as $PKG sha256sum files/cgo/jak1/ENGINE.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  ENGINE.CGO after:  ${CGO_AFTER:-<none>}"
if [ -n "$CGO_BEFORE" ] && [ "$CGO_BEFORE" != "$CGO_AFTER" ]; then
  die "ENGINE.CGO CHANGED across libgk reinstall ($CGO_BEFORE -> $CGO_AFTER) — CGOs got re-extracted; consistency risk"
fi
echo "[gci-libgk] DONE — new libgk deployed, CGOs unchanged ($CGO_AFTER)."
