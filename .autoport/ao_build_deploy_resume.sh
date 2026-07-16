#!/usr/bin/env bash
# ao_build_deploy_resume.sh — resume ao_build_deploy.sh from step 3 (APK assembly).
# Attempt 4 was killed AFTER step 2: the consistent arm64 CGO set (out/jak1-arm64-full/iso,
# 10:29), android-text overlay + cgo pack (10:31, version in the committed manifest) and
# libgk.so (10:32) are all built from HEAD — only the APK/install/push/boot steps remain.
# Preconditions are re-verified here instead of rebuilt; steps 3-6 are verbatim from
# ao_build_deploy.sh.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-ambient-occlusion; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[ao-build FAIL] $*" >&2; exit 1; }

say "0. resume preconditions: staged artifacts fresh + consistent with HEAD"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"
grep -q "HBAO" <(strings -a out/jak1/iso/0COMMON.TXT) || die "0COMMON.TXT missing AO strings"
grep -q "HBAO" <(strings -a out/jak1-android-text/0COMMON.TXT) || die "android-text 0COMMON.TXT missing AO strings"
[ "$(unzip -p android/app/src/jak1/assets-slim/bundle/jak1_cgo.zip 0COMMON.TXT | strings -a | grep -c 'HBAO')" -gt 0 ] || die "cgo pack 0COMMON.TXT stale"
# staged CGOs must be newer than the newest goal_src edit (no source drift since the build)
NEWEST_GC=$(find goal_src/jak1 -name '*.gc' -printf '%T@\n' | sort -rn | head -1 | cut -d. -f1)
CGO_T=$(stat -c %Y out/jak1-arm64-full/iso/GAME.CGO)
[ "$CGO_T" -ge "$NEWEST_GC" ] || die "staged GAME.CGO older than newest goal_src — rerun the FULL script"
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
SYM=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'pc-set-ambient-occlusion')
SHD=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'u_inv_camera')
PRF=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'AOPERF')
echo "  libgk AO symbol strings=${SYM:-0}  ao-shader-uniform strings=${SHD:-0}  AOPERF strings=${PRF:-0}"
[ "${SYM:-0}" -gt 0 ] || die "libgk.so missing pc-set-ambient-occlusion!"
[ "${SHD:-0}" -gt 0 ] || die "libgk.so missing AO shader uniforms"
[ "${PRF:-0}" -gt 0 ] || die "libgk.so missing AOPERF telemetry"
NEWEST_SRC=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
SO_T=$(stat -c %Y build-android/lib/arm64-v8a/libgk.so)
[ "$SO_T" -ge "$NEWEST_SRC" ] || die "libgk.so older than newest C++/shader source — rerun the FULL script"
echo "  ok: staged CGO set, text overlay, cgo pack, libgk all fresh vs HEAD sources"

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
PACK_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
extract_done(){ [ "$($ADB -s $S shell run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')" = "$PACK_VER" ] \
  && $ADB -s $S shell run-as $PKG ls files/.asset_bundle_stamp >/dev/null 2>&1 \
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

say "5b. push rebuilt text banks (AO value strings) — SPLIT per read path"
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
push_txt_set out/jak1/iso files/iso_data/jak1
echo "  ok: $(ls out/jak1/iso/*.TXT | wc -l) desktop TXT banks -> files/iso_data/jak1 (sha-verified)"
if $ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/GAME.CGO'" >/dev/null 2>&1; then
  for b in $($ADB -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/'" 2>/dev/null | tr -d '\r' | grep 'COMMON\.TXT$'); do
    [ -f "out/jak1-android-text/$b" ] || {
      echo "  removing stray overlay TXT: $b"
      $ADB -s $S shell "run-as $PKG rm -f files/cgo/jak1/$b" >/dev/null 2>&1 || die "rm stray $b failed"; }
  done
  push_txt_set out/jak1-android-text files/cgo/jak1
  echo "  ok: $(ls out/jak1-android-text/*.TXT | wc -l) android TXT banks -> files/cgo/jak1 (sha-verified, strays removed)"
fi
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify_assets failed"

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
[ "$($ADB -s $S shell "run-as $PKG cat files/cgo/jak1/0COMMON.TXT" 2>/dev/null | strings -a | grep -c 'HBAO')" -gt 0 ] || die "device overlay 0COMMON.TXT lacks AO strings after final boot"
echo "[ao-build] DONE — AO build on device, boots to render, deploy_verify + assets + text PASS."
