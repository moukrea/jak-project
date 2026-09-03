#!/usr/bin/env bash
# rhud2_build_deploy.sh — Grecharged-hud-jak1 full consistent build + deploy.
# gsfx/gci pattern: full consistent 28-CGO arm64 build + rebuilt libgk + REBUILT
# ASSET BUNDLE (v12: ships recharged_assets/*.png — the extra step vs gci) +
# repackaged APK + reinstall + push consistent CGOs + deploy_verify + boot gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-hud-jak1; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[rhud2-build FAIL] $*" >&2; exit 1; }

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"

say "2. rebuild asset bundle (v12 — recharged_assets PNGs enter the zip)"
bash android/build_asset_bundle.sh jak1 2>&1 | tail -8 || die "asset bundle failed"
grep -a "version" android/app/src/jak1/assets-bundled/bundle/manifest.properties || true
unzip -l android/app/src/jak1/assets-bundled/bundle/*.zip 2>/dev/null | grep -ac recharged_assets \
  | { read c; [ "$c" -ge 11 ] || die "bundle zip lacks the 11 recharged PNGs (got $c)"; echo "  bundle has $c recharged_assets entries"; }

say "3. build android libgk + assemble APK"
touch game/graphics/opengl_renderer/RechargedHudTextures.cpp
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
unzip -l "$APK" | grep -qa "bundle" || true

say "4. install APK + restore baseline + deploy_verify (build==APK==device libgk)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/restore_knowngood_device.sh 2>&1 | tail -3 || die "restore_knowngood failed"
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -4 || die "deploy_verify failed"

# Stages 5-6 live in rhud2_deploy_finish.sh with the CORRECT ordering: the CGO
# push needs LoaderActivity's .extracted_v1 marker, which only the first boot
# (v12 unpack) creates — boot/unpack/verify FIRST, then push, then attract gate.
bash .autoport/rhud2_deploy_finish.sh || die "deploy finish (unpack+CGO push+attract) failed"
echo "[rhud2-build] DONE — consistent RHUD build deployed, assets on device, attract boots."
