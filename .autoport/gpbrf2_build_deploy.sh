#!/usr/bin/env bash
# gpbrf2_build_deploy.sh — Grecharged-pbr-realtime-fusion REOPEN #2 full consistent build + deploy.
# Modeled on gda_build_deploy_full.sh (goal_src changed => full 28-CGO rebuild + pack + push).
# This attempt's changes:
#   * GOAL (pckernel/progress-pc/hud): TEXTURE RELIEF + SPECULAR INTENSITY menu sliders
#   * C++ (loader/binder/kmachine/gfx): same-source PBR map pairing, per-texture binding log,
#     debug.opengoal.pbr.kill A/B killswitch, relief/specint plumbing
#   * tfrag3.frag: missing-roughness=0.9, u_pbr_spec_intensity (embedded in android shader blob)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf2-build FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device

say "1. FULL consistent arm64 build (28 CGO/DGO) + x86 oracle restore"
bash .autoport/build_arm64_full_consistent.sh || die "full arm64 build failed (GOAL error?)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "expected 28 staged arm64 files, got $n"
# un-stubbable: the new slider labels + setter symbols must be in the arm64 GOAL set
TRL=$(strings -a out/jak1-arm64-full/iso/GAME.CGO | grep -c 'TEXTURE RELIEF' || true)
SPL=$(strings -a out/jak1-arm64-full/iso/GAME.CGO | grep -c 'SPECULAR INTENSITY' || true)
SET=$(strings -a out/jak1-arm64-full/iso/GAME.CGO | grep -c 'pc-set-pbr-texture-relief!' || true)
echo "  GAME.CGO slider strings: TEXTURE RELIEF=$TRL SPECULAR INTENSITY=$SPL setter=$SET"
[ "$TRL" -gt 0 ] || die "GAME.CGO missing TEXTURE RELIEF label (menu rows not compiled in)"
[ "$SPL" -gt 0 ] || die "GAME.CGO missing SPECULAR INTENSITY label"
[ "$SET" -gt 0 ] || die "GAME.CGO missing pc-set-pbr-texture-relief! symbol"

say "1b. regenerate android-text overlay + cgo pack (a stale pack re-extracts over pushed TXT)"
bash .autoport/gtt_build_android_text.sh || die "android-text overlay rebuild failed"
bash android/build_cgo_pack.sh jak1 || die "cgo pack rebuild failed"

say "2. DESKTOP compile-check (OG_FEAT_PBR=ON cache)"
cmake --build build --target gk -j"$(nproc)" 2>&1 | tail -6
[ "${PIPESTATUS[0]}" -eq 0 ] || die "desktop gk build failed"

say "3. android libgk (regenerates shaders_android_blob.h from the .frag glob)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -8
[ "${PIPESTATUS[0]}" -eq 0 ] || die "android gk build failed"
LIB=build-android/lib/arm64-v8a/libgk.so
KIL=$(strings -a "$LIB" | grep -c 'debug.opengoal.pbr.kill' || true)
SPI=$(strings -a "$LIB" | grep -c 'u_pbr_spec_intensity' || true)
REL=$(strings -a "$LIB" | grep -c 'debug.opengoal.pbr.relief' || true)
BLG=$(strings -a "$LIB" | grep -c 'pbr binding: ' || true)
STR=$(strings -a "$LIB" | grep -c 'pc-set-pbr-specular-intensity!' || true)
echo "  libgk REOPEN#2 symbols: kill=$KIL specint_uniform=$SPI relief_prop=$REL bindlog=$BLG setter=$STR"
[ "$KIL" -gt 0 ] || die "libgk missing debug.opengoal.pbr.kill (killswitch not compiled in)"
[ "$SPI" -gt 0 ] || die "libgk missing u_pbr_spec_intensity"
[ "$REL" -gt 0 ] || die "libgk missing debug.opengoal.pbr.relief"
[ "$BLG" -gt 0 ] || die "libgk missing 'pbr binding: ' per-texture log"
[ "$STR" -gt 0 ] || die "libgk missing pc-set-pbr-specular-intensity! registration"

say "4. assemble APK"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"

say "5. install APK + deploy_verify (build==APK==device libgk)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify (libgk) failed"

say "6. ensure extraction done (boot once if needed) then push consistent CGOs + text"
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

say "6b. push android text banks into files/cgo overlay (unchanged content, keeps overlay == pack)"
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

say "7. relaunch: reach live render, no crash, jak1 foreground, binding log live"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S shell setprop debug.opengoal.pbr.kill 0 2>/dev/null || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gpbrf2-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aiE 'A35-RENDER frame=|link finish|shader|compil|pbr binding|custom pbr|custom texture replacement|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
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
grep -aq 'compile.*error\|ERROR.*shader' "$LOG" && die "shader compile error in logcat"
BL=$(grep -ac 'pbr binding:' "$LOG" || true)
echo "  pbr-binding log lines during boot: $BL"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[gpbrf2-build] DONE — REOPEN#2 build on device (sliders in GAME.CGO, killswitch+log in libgk), boots to render, deploy_verify + assets PASS."
