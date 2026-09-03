#!/usr/bin/env bash
# gda_deploy_fixed.sh — deploy the CONSISTENT android-arm64 build produced by
#   ./build.sh android-arm64 --pbr --no-cache
# onto the device, in the CORRECT ORDER: install -> FORCE re-extract the fresh
# arm64 pack -> push the exact 28 staged CGOs -> THEN deploy_verify. The canonical
# gda_build_deploy_full.sh ran deploy_verify BEFORE re-extraction, so it checked the
# STALE device CGO (linux-x86_64) and false-failed; this fixes that ordering.
# Preconditions: build.sh android-arm64 already produced the APK + out/jak1-arm64-full/iso.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gda-deploy FAIL] $*" >&2; exit 1; }

[ -f "$APK" ] || die "APK missing ($APK) — run ./build.sh android-arm64 --pbr first"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"
# Pre-flight: the staged set + APK-bundled pack MUST be android-arm64 (else the fix didn't take).
SMARK=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' out/jak1-arm64-full/iso/GAME.CGO | head -1)
[ "$SMARK" = "ogflags:465b53fe1394:android-arm64" ] || die "staged GAME.CGO marker '$SMARK' != android-arm64 — flag regen failed"
echo "  ok: staged CGO marker $SMARK"

say "0. adb server refresh"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi

say "1. install APK (android-arm64 libgk + android-arm64 CGO pack)"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"

say "2. FORCE re-extraction of the fresh arm64 pack (delete stale stamp + CGOs, boot to extract)"
PACK_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
echo "  target pack version: $PACK_VER"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell "run-as $PKG sh -c 'rm -f files/.cgo_pack_stamp_jak1; rm -rf files/cgo/jak1'" 2>/dev/null || true
extract_done(){ [ "$($ADB -s $S shell run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')" = "$PACK_VER" ] \
  && [ "$($ADB -s $S shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$')" -ge 28 ]; }
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 900 ]; do extract_done && break; sleep 10; done
extract_done || die "asset pack stamp/CGO set never appeared in 900s (extraction failed)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "  ok: device extracted pack $PACK_VER ($($ADB -s $S shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)') CGO/DGO)"

say "3. push the exact 28 consistent HEAD arm64 CGO/DGO (sha256-verified)"
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -5 || die "CGO push failed"

say "3b. push rebuilt android text banks (HEMISPHERE/SH/IBL) into files/cgo overlay"
if [ -d out/jak1-android-text ] && $ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/GAME.CGO'" >/dev/null 2>&1; then
  for b in $($ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/'" 2>/dev/null | tr -d '\r' | grep 'COMMON\.TXT$'); do
    [ -f "out/jak1-android-text/$b" ] || { $ADB -s $S shell "run-as $PKG rm -f files/cgo/jak1/$b" >/dev/null 2>&1 || true; }
  done
  for f in out/jak1-android-text/*.TXT; do
    b=$(basename "$f"); lsha=$(sha256sum "$f" | cut -d' ' -f1)
    $ADB -s $S push "$f" /data/local/tmp/"$b" >/dev/null 2>&1 || die "push $b failed"
    $ADB -s $S shell "run-as $PKG sh -c 'cp /data/local/tmp/$b files/cgo/jak1/$b'" || die "cp $b failed"
    dsha=$($ADB -s $S shell "run-as $PKG sha256sum files/cgo/jak1/$b" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
    [ "$lsha" = "$dsha" ] || die "sha mismatch $b (local $lsha device $dsha)"
    $ADB -s $S shell rm -f /data/local/tmp/"$b" >/dev/null 2>&1 || true
  done
  echo "  ok: android TXT banks pushed (sha-verified)"
fi

say "4. deploy_verify + deploy_verify_assets (device provably runs fresh consistent HEAD)"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -8 || die "deploy_verify failed"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify_assets failed"

say "5. relaunch: reach live render, no crash, jak1 foreground"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gda-deploy-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
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
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[gda-deploy] DONE — device runs the fresh consistent android-arm64 build (contrast 1.0), deploy_verify + assets PASS."
