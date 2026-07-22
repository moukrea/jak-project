#!/usr/bin/env bash
# gbt_build_deploy.sh — Grecharged-bundled-textures full consistent build + deploy.
# Clone of glp_build_deploy.sh. Rebuilds in one consistent pass:
#   * 28 arm64 CGO/DGO  (goal_src: RECHARGED TEXTURES menu row + pckernel field/persist +
#                        pc-set-recharged-textures! push)
#   * libgk.so          (two-index replacement scanner, bundled dir resolver, Loader seed)
#   * custom pack       (build_custom_pack.sh now stages custom_assets/jak1/recharged_textures/**
#                        — the owner's 28 first-party PNGs ship IN the APK)
#   * APK               (bundles fresh libgk + the fattened custom pack)
# deploy_verify + deploy_verify_assets prove the device runs fresh HEAD; step 5c proves the
# LoaderActivity extracted the bundled textures to the app-private custom dir (install-only,
# NO manual push).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-bundled-textures/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gbt-build FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device
echo "  device /data free:"; $ADB -s $S shell df -h /data | tail -1

say "0b. settings-seed version drift gate (Loader.cpp mirror vs GOAL pckernel)"
grep -q 'static-pckernel-version 1 11 0 0' goal_src/jak1/pc/pckernel-impl.gc \
  || die "GOAL pckernel version != 1 11 0 0 — update Loader.cpp mirrors + gbt_evidence pin"
grep -q 'kGoalPckernelVersionMajor = 1' game/graphics/opengl_renderer/loader/Loader.cpp \
  || die "Loader.cpp kGoalPckernelVersionMajor drifted"
grep -q 'kGoalPckernelVersionMinor = 11' game/graphics/opengl_renderer/loader/Loader.cpp \
  || die "Loader.cpp kGoalPckernelVersionMinor drifted"

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed (GOAL error?)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"

say "1b. regenerate android-text overlay + cgo pack (a stale pack re-extracts over pushed TXT)"
bash .autoport/gtt_build_android_text.sh || die "android-text overlay rebuild failed"
bash android/build_cgo_pack.sh jak1 || die "cgo pack rebuild failed"

say "1c. custom pack — bundled recharged textures enter the APK here"
bash android/build_custom_pack.sh jak1 || die "custom pack rebuild failed"
CPZ=android/app/src/jak1/assets-slim/bundle/jak1_custom.zip
NRT=$(unzip -l "$CPZ" | grep -c 'recharged_textures/.*\.png' || true)
[ "$NRT" -eq 28 ] || die "custom pack has $NRT recharged_textures PNGs, expected 28"
grep -E '^file_count=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties
echo "  custom pack recharged_textures members: $NRT"

say "2. build android libgk (two-index scanner + bundled dir + seed enter the runtime)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
BRT=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'recharged_textures' || true)
BPM=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'custom pbr map ({})' || true)
BSD=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'recharged-textures? = #f' || true)
echo "  libgk bundled-dir strings=$BRT  tagged-pbr-log strings=$BPM  seed-key strings=$BSD"
[ "$BRT" -gt 0 ] || die "libgk.so missing 'recharged_textures' (bundled dir resolver not compiled in)"
[ "$BSD" -gt 0 ] || die "libgk.so missing the settings-seed key literal (Loader seed not compiled in)"

say "3. assemble APK"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
ls -la "$APK"

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
CUST_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
extract_done(){ [ "$($ADB -s $S shell run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')" = "$PACK_VER" ] \
  && [ "$($ADB -s $S shell run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r')" = "$CUST_VER" ] \
  && [ "$($ADB -s $S shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$')" -ge 28 ]; }
if ! extract_done; then
  echo "  bundle stamps/CGOs missing -> boot once to extract (can take minutes)"
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 900 ]; do extract_done && break; sleep 10; done
  extract_done || die "asset bundle stamps/CGO set never appeared in 900s"
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
fi
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -5 || die "CGO push failed"

say "5b. push rebuilt text banks into files/cgo overlay"
push_txt_set(){ local SRC="$1" DST="$2" f b lsha dsha
  for f in "$SRC"/*.TXT; do
    b=$(basename "$f"); lsha=$(sha256sum "$f" | cut -d' ' -f1)
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

say "5c. verify the 28 bundled textures shipped IN the APK (custom pack) — install-only, NO push"
NDEV=$($ADB -s $S shell "run-as $PKG sh -c 'find files/custom/jak1/recharged_textures -name \"*.png\" 2>/dev/null | wc -l'" | tr -d '\r ')
echo "  device recharged_textures PNGs: ${NDEV:-0} (want 28)"
[ "${NDEV:-0}" = "28" ] || die "APK did not deliver 28 recharged textures to the custom dir (got '${NDEV:-0}')"
REF=custom_assets/jak1/recharged_textures/village1-vis-tfrag/vil-hut-roof-tile-01/vil-hut-roof-tile-01.png
LSHA=$(sha256sum "$REF" | cut -d' ' -f1)
DSHA=$($ADB -s $S shell "run-as $PKG sha256sum files/custom/jak1/recharged_textures/village1-vis-tfrag/vil-hut-roof-tile-01/vil-hut-roof-tile-01.png" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
echo "  sha chain vil-hut-roof-tile-01.png: committed=$LSHA device=$DSHA"
[ "$LSHA" = "$DSHA" ] || die "device bundled texture sha != committed sha"

say "6. relaunch: reach live render, no crash, jak1 foreground"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gbt-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|custom texture replacement|custom pbr|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
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
echo "  scanner lines seen at boot:"; grep -a 'custom texture replacement' "$LOG" | head -5
echo "[gbt-build] DONE — bundled textures in APK + extracted on device (28/28, sha-verified), boots to render, deploy_verify + assets PASS."
