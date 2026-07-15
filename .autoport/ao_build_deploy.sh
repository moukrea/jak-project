#!/usr/bin/env bash
# ao_build_deploy.sh — Grecharged-ambient-occlusion full consistent build + deploy.
# Adapted from foliage_build_deploy.sh. Rebuilds, in one consistent pass:
#   * 28 arm64 CGO/DGO   (new jak1 GOAL: ambient-occlusion/ao-quality pc-settings + two
#                         Recharged menu carousell rows + persistence + the update-to-os
#                         -> pc-set-ambient-occlusion! bridge + pc-text-* text ids)
#   * game text TXT      (game_custom_text_*.json ids #x1708-#x170f -> *COMMON.TXT; text is
#                         arch-independent data, pushed alongside the CGOs — the carousell
#                         VALUE strings SSAO/HBAO/GTAO/LOW/MEDIUM/HIGH live in the text bank)
#   * libgk.so           (AmbientOcclusion.{h,cpp} 3-pass AO + Fbo depth-texture support +
#                         OpenGLRenderer hook/make_fbo + 10 ao_* shaders in the GLES blob +
#                         kmachine pc-set-ambient-occlusion! + android_renderer AOPERF line)
#   * APK                (bundles the fresh libgk)
# deploy_verify + deploy_verify_assets prove the device runs fresh HEAD.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-ambient-occlusion; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[ao-build FAIL] $*" >&2; exit 1; }

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed (GOAL error?)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"
# the x86 restore pass regenerates out/jak1/iso incl. the text banks with the AO ids
grep -q "HBAO" <(strings -a out/jak1/iso/0COMMON.TXT) || die "0COMMON.TXT missing AO strings (text not rebuilt)"

say "2. build android libgk (AO pass + shaders enter the GLES blob)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
SYM=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'pc-set-ambient-occlusion')
SHD=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'u_inv_camera')
PRF=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'AOPERF')
echo "  libgk AO symbol strings=${SYM:-0}  ao-shader-uniform strings=${SHD:-0}  AOPERF strings=${PRF:-0}"
[ "${SYM:-0}" -gt 0 ] || die "libgk.so missing pc-set-ambient-occlusion! (kmachine not compiled in)"
[ "${SHD:-0}" -gt 0 ] || die "libgk.so missing AO shader uniforms (ao_* not embedded in blob)"
[ "${PRF:-0}" -gt 0 ] || die "libgk.so missing AOPERF telemetry (android_renderer not rebuilt)"

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

say "5. ensure extraction done (boot once if needed) then push consistent CGOs + text"
extract_done(){ $ADB -s $S shell run-as $PKG ls files/.asset_bundle_stamp >/dev/null 2>&1 \
  && [ "$($ADB -s $S shell run-as $PKG ls files/iso_data/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$')" -ge 28 ]; }
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

say "5b. push rebuilt text banks (AO value strings) to the active overlay dir(s)"
DEST_DIRS="files/iso_data/jak1"
if $ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/GAME.CGO'" >/dev/null 2>&1; then
  DEST_DIRS="files/cgo/jak1 files/iso_data/jak1"
fi
for f in out/jak1/iso/*.TXT; do
  b=$(basename "$f")
  lsha=$(sha256sum "$f" | cut -d' ' -f1)
  $ADB -s $S push "$f" /data/local/tmp/"$b" >/dev/null 2>&1 || die "push $b to tmp failed"
  for d in $DEST_DIRS; do
    $ADB -s $S shell "run-as $PKG sh -c 'cp /data/local/tmp/$b $d/$b'" || die "cp $b -> $d failed"
    dsha=$($ADB -s $S shell "run-as $PKG sha256sum $d/$b" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
    [ "$lsha" = "$dsha" ] || die "sha mismatch for $d/$b (local $lsha device $dsha)"
  done
  $ADB -s $S shell rm -f /data/local/tmp/"$b" >/dev/null 2>&1 || true
done
echo "  ok: $(ls out/jak1/iso/*.TXT | wc -l) TXT banks pushed + sha-verified to: $DEST_DIRS"

say "6. relaunch: reach live render, no crash, jak1 foreground"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/ao-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'recharged-ao|AOPERF|A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
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
echo "[ao-build] DONE — AO build on device, boots to render, deploy_verify + assets + text PASS."
