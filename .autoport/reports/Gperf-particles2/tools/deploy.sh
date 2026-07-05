#!/usr/bin/env bash
# Gperf-particles2 consistent redeploy — libgk-only (renderer gating + tod.fast hook
# + sparticle ffp-contract; NO goalc/CGO/DGO/goal_src change, assets unchanged).
# Build gk -> reassemble APK -> install keep-data -> deploy_verify -> assert
# ENGINE.CGO unchanged. Mirrors the round4 deploy.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S="${ANDROID_SERIAL:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
die(){ echo "[gp2-deploy FAIL] $*" >&2; exit 1; }

echo "### 1. libgk fresh"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -3
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"

echo "### 2. reassemble APK (same CGOs, fresh libgk)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -4 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

echo "### 3. ENGINE.CGO hash BEFORE"
CGO_BEFORE=$($ADB -s $S shell run-as $PKG sha256sum files/iso_data/jak1/ENGINE.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  ENGINE.CGO before: ${CGO_BEFORE:-<none>}"

echo "### 4. install APK (keep data)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — owner unlock"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

echo "### 5. deploy_verify (build==APK==device)"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -5 || die "deploy_verify FAILED"

echo "### 6. confirm ENGINE.CGO unchanged (libgk-only)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
sleep 8
CGO_AFTER=$($ADB -s $S shell run-as $PKG sha256sum files/iso_data/jak1/ENGINE.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  ENGINE.CGO after:  ${CGO_AFTER:-<none>}"
[ -n "$CGO_BEFORE" ] && [ "$CGO_BEFORE" != "$CGO_AFTER" ] && die "ENGINE.CGO CHANGED — consistency risk"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[gp2-deploy] DONE — libgk deployed, CGOs unchanged."
