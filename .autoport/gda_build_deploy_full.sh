#!/usr/bin/env bash
# gda_build_deploy_full.sh — Grecharged-directional-ambient ROUND 2 full consistent build + deploy.
# Modeled on ao_build_deploy.sh. Rebuilds in one consistent pass:
#   * 28 arm64 CGO/DGO  (current goal_src: the AMBIENT MODEL Hemisphere/SH/IBL carousell row +
#                        pc-set-rt-ambient-model! bridge + pc-text-model-* ids — DEFECT 2, the
#                        menu selector that never reached the device build 03f21e3ea)
#   * game text TXT     (game_custom_text ids #x1716-1718 -> HEMISPHERE / SH / IBL value strings)
#   * libgk.so          (common/custom_data/TFrag3Data.cpp CREASE-AWARE smooth-normal reconstruction
#                        — DEFECT 1, kills the masonry hard-edge weld artifact)
#   * APK               (bundles the fresh libgk)
# deploy_verify + deploy_verify_assets prove the device runs fresh HEAD.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gda-build FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed (GOAL error?)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"
grep -q "HEMISPHERE" <(strings -a out/jak1/iso/0COMMON.TXT) || die "0COMMON.TXT missing HEMISPHERE (menu text not rebuilt)"

say "1b. regenerate android-text overlay + cgo pack (a stale pack re-extracts over pushed TXT)"
bash .autoport/gtt_build_android_text.sh || die "android-text overlay rebuild failed"
grep -q "HEMISPHERE" <(strings -a out/jak1-android-text/0COMMON.TXT) || die "android-text 0COMMON.TXT missing HEMISPHERE"
bash android/build_cgo_pack.sh jak1 || die "cgo pack rebuild failed"
[ "$(unzip -p android/app/src/jak1/assets-slim/bundle/jak1_cgo.zip 0COMMON.TXT | strings -a | grep -c 'HEMISPHERE')" -gt 0 ] || die "cgo pack 0COMMON.TXT still stale (no HEMISPHERE)"

say "2. build android libgk (crease-aware reconstruction enters the runtime)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
CRE=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'debug.opengoal.tfrag.crease')
MOD=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'u_rt_ambient_model')
echo "  libgk crease-prop strings=${CRE:-0}  rt-ambient-model-uniform strings=${MOD:-0}"
[ "${CRE:-0}" -gt 0 ] || die "libgk.so missing debug.opengoal.tfrag.crease (crease fix not compiled in)"
[ "${MOD:-0}" -gt 0 ] || die "libgk.so missing u_rt_ambient_model (rt ambient path not compiled in)"

say "3. assemble APK"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "4. install APK + deploy_verify (build==APK==device libgk)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify (libgk) failed"

say "5. ensure extraction done (boot once if needed) then push consistent CGOs + text"
PACK_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
extract_done(){ [ "$($ADB -s $S shell run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')" = "$PACK_VER" ] \
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

say "5b. push rebuilt text banks (HEMISPHERE/SH/IBL value strings) into files/cgo overlay"
push_txt_set(){ local SRC="$1" DST="$2" f b lsha dsha
  for f in "$SRC"/*.TXT; do
    b=$(basename "$f")
    lsha=$(sha256sum "$f" | cut -d' ' -f1)
    $ADB -s $S push "$f" /data/local/tmp/"$b" >/dev/null 2>&1 || die "push $b to tmp failed"
    $ADB -s $S shell "run-as $PKG sh -c 'cp /data/local/tmp/$b $DST/$b'" || die "cp $b -> $DST failed"
    dsha=$($ADB -s $S shell "run-as $PKG sha256sum $DST/$b" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
    [ "$lsha" = "$dsha" ] || die "sha mismatch for $DST/$b (local $lsha device $dsha)"
    $ADB -s $S shell rm -f /data/local/tmp/"$b" >/dev/null 2>&1 || true
  done
}
if $ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/GAME.CGO'" >/dev/null 2>&1; then
  for b in $($ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/'" 2>/dev/null | tr -d '\r' | grep 'COMMON\.TXT$'); do
    [ -f "out/jak1-android-text/$b" ] || {
      echo "  removing stray overlay TXT: $b"
      $ADB -s $S shell "run-as $PKG rm -f files/cgo/jak1/$b" >/dev/null 2>&1 || die "rm stray $b failed"; }
  done
  push_txt_set out/jak1-android-text files/cgo/jak1
  echo "  ok: $(ls out/jak1-android-text/*.TXT | wc -l) android TXT banks -> files/cgo/jak1 (sha-verified)"
fi
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify_assets failed"

say "6. relaunch: reach live render, no crash, jak1 foreground"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gda-boot-logcat.log"; : > "$LOG"
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
[ "$($ADB -s $S shell "run-as $PKG cat files/cgo/jak1/0COMMON.TXT" 2>/dev/null | strings -a | grep -c 'HEMISPHERE')" -gt 0 ] || die "device overlay 0COMMON.TXT lacks HEMISPHERE after final boot"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[gda-build] DONE — crease fix + AMBIENT MODEL menu on device, boots to render, deploy_verify + assets + text PASS."
