#!/usr/bin/env bash
# gpbrf_build_deploy.sh — Grecharged-pbr-realtime-fusion build + deploy.
# Changes are C++ (loader/binder/uniforms) + tfrag3.frag (embedded in the android
# shader blob at libgk build) ONLY — no GOAL, no CGO/text/custom-pack rebuild.
# Steps: desktop compile-check -> android libgk -> APK -> install -> deploy_verify
# -> boot to live render with a shader-compile-error logcat gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf-build FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device

say "1. DESKTOP compile-check (OG_FEAT_PBR=ON cache) — C++ only, shaders are runtime-compiled"
cmake --build build --target gk -j"$(nproc)" 2>&1 | tail -8
[ "${PIPESTATUS[0]}" -eq 0 ] || die "desktop gk build failed"

say "2. android libgk (regenerates shaders_android_blob.h from the .frag glob)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -8
[ "${PIPESTATUS[0]}" -eq 0 ] || die "android gk build failed"
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
SPE=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'tex_PBR_S' || true)
EMI=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'u_pbr_emissive_str' || true)
echo "  libgk fusion symbols: tex_PBR_S=$SPE u_pbr_emissive_str=$EMI"
[ "$SPE" -gt 0 ] || die "libgk.so missing tex_PBR_S (specular sampler not compiled in)"
[ "$EMI" -gt 0 ] || die "libgk.so missing u_pbr_emissive_str (emissive uniform not compiled in)"

say "3. assemble + install APK"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "4. deploy_verify (build==APK==device libgk)"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify failed"

say "5. boot to live render; gate on shader-compile errors in logcat"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gpbrf-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aiE 'A35-RENDER frame=|link finish|shader|compil|custom pbr|custom texture replacement|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
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
if grep -aiqE 'shader.*(error|fail)|compil.*(error|fail)' "$LOG" 2>/dev/null; then
  echo "  SHADER COMPILE ERRORS:"; grep -aiE 'shader.*(error|fail)|compil.*(error|fail)' "$LOG" | head -10
  die "shader compile error on device"
fi
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render (crash or hang)"
echo "[gpbrf-build] DONE — fused build on device, boots to render, no shader errors, deploy_verify PASS."
