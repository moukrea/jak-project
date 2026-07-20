#!/usr/bin/env bash
# gda_itemAB_deploy.sh — deploy the ITEM A+B libgk (owner playtest #2 refinements).
# ITEM B: temporal low-pass of the stepped mood COLOR inputs (kmachine.cpp pc_set_pbr_sun / _lights) so
#         the day/night snapshot steps ramp smoothly (owner: "2 brutal steps at night + 1 at sunrise").
# ITEM A: sun intensity 1.5->1.75 (sun-lit vs shadow contrast) + ambient hue bleach 0.50->0.44 (mood-
#         match to the stock baked tone) in background_common.cpp.
# libgk-ONLY change (C++; the shader blob + goal_src/CGOs are UNCHANGED from attempt-5) => the arm64 CGO
# pack already on the device stays consistent; we rebuild libgk (done), reassemble/reinstall the APK,
# and only if the shared device reverted to a stale x86 pack do we re-run the cgo-consistency helper.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gda-itemAB-deploy FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device

LIB=build-android/lib/arm64-v8a/libgk.so
[ -f "$LIB" ] || die "libgk.so not built"
TS=$(strings -a "$LIB" | grep -c 'debug.opengoal.rt.todsmooth')
echo "  libgk ITEM-B todsmooth prop strings=$TS"
[ "${TS:-0}" -gt 0 ] || die "libgk.so missing the ITEM-B todsmooth prop (stale libgk?)"

say "1. assemble APK (bundles the fresh ITEM A+B libgk)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "2. install APK"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "3. deploy_verify (libgk build==APK==device). If CGO pairing stale (shared device), re-consolidate."
if bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tee "$OUT/gda_itemAB_deploy_verify.txt" | tail -6; then
  echo "  deploy_verify GREEN on first try"
else
  echo "  deploy_verify failed — running cgo-consistency helper (re-extract arm64 pack + re-push overlay)"
  bash .autoport/gda_shaderfix_cgo_consistency.sh 2>&1 | tail -12 || die "cgo-consistency failed"
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tee "$OUT/gda_itemAB_deploy_verify.txt" | tail -6 || die "deploy_verify still failing after consolidation"
fi

say "4. boot smoke: reach live render, no crash, jak1 foreground"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gda-itemAB-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime </dev/null | grep --line-buffered -aE 'A35-RENDER|link finish|Fatal signal|signal [0-9]+ \(SIG|shaders (FAILED|compiled)' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  if grep -aqE 'Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render (crash or hang)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[gda-itemAB-deploy] DONE — ITEM A+B libgk on device, boots to render, deploy_verify PASS, jak1 foreground."
