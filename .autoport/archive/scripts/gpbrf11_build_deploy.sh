#!/usr/bin/env bash
# gpbrf11_build_deploy.sh — Grecharged-pbr-realtime-fusion REOPEN#11.
# Delta this round (GOAL carousel wiring already shipped+verified in REOPEN#10, on device):
#   1. android-text overlay REGEN  -> fixes "Unknown ID 5924-5927" (the 4 PBR-ISOLATE option
#      strings were in the source JSON but a STALE out/jak1-android-text/*COMMON.TXT bank
#      (2026-07-23) overrode the fresh desktop bank in build_cgo_pack.sh -> device bank lacked
#      BOTH/NORMAL-MAP ONLY/PARALLAX ONLY/NEITHER).
#   2. libgk REBUILD               -> kmachine.cpp pc_set_pbr_isolate now WRITES the active
#      carousel index + resolved u_pbr_bisect mask to files/pbr_tan_diag.txt on each CHANGE
#      (proves the flip reaches the shader; Honor obscures logcat so a FILE is the channel).
# The 28 arm64 CGO/DGO are UNCHANGED (goal_src clean at HEAD == REOPEN#10 deployed set); we
# reuse out/jak1-arm64-full/iso and only repack with the fresh TXT. deploy_verify_assets proves
# the CGO set stays consistent (no mixed build).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gpbrf11 FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
timeout 60 "$ADB" -s $S wait-for-device || die "device not present"

say "1. regenerate android-text overlay (fix Unknown ID: 4 PBR-ISOLATE strings)"
bash .autoport/gtt_build_android_text.sh || die "android-text overlay rebuild failed"
for s in "NORMAL-MAP ONLY" "PARALLAX ONLY" "NEITHER"; do
  grep -q "$s" <(strings -a out/jak1-android-text/0COMMON.TXT) || die "android-text 0COMMON.TXT missing '$s' (regen did not pick up isolate strings)"
done
grep -q "LES DEUX" <(strings -a out/jak1-android-text/1COMMON.TXT) || die "android-text 1COMMON.TXT missing FR 'LES DEUX' (fr isolate strings)"
grep -q "HEMISPHERE" <(strings -a out/jak1-android-text/0COMMON.TXT) || die "android-text lost HEMISPHERE (regression)"
echo "  ok: android-text banks carry the 4 isolate strings (EN+FR) and keep HEMISPHERE"

say "2. rebuild cgo pack (same 28 arm64 CGO/DGO + fresh TXT)"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
[ "$n" -eq 28 ] || die "arm64 staging has $n CGO/DGO (expected 28) — run build_arm64_full_consistent.sh"
bash android/build_cgo_pack.sh jak1 || die "cgo pack rebuild failed"
grep -q "NORMAL-MAP ONLY" <(unzip -p android/app/src/jak1/assets-slim/bundle/jak1_cgo.zip 0COMMON.TXT | strings -a) || die "cgo pack 0COMMON.TXT still stale (no NORMAL-MAP ONLY)"
PACK_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
echo "  ok: cgo pack version=$PACK_VER carries the isolate strings"

say "3. build android libgk (kmachine pc_set_pbr_isolate diag write)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -12
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
ISO=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'pbr-isolate')
LBL=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'NORMAL-MAP ONLY')
echo "  libgk pbr-isolate-marker strings=$ISO  isolate-label strings=$LBL"
[ "$ISO" -gt 0 ] || die "libgk.so missing '[pbr-isolate] active' diag string (diag write not compiled in)"
[ "$LBL" -gt 0 ] || die "libgk.so missing 'NORMAL-MAP ONLY' label (diag write not compiled in)"

say "4. assemble APK (bundles fresh libgk + fresh cgo pack)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
BSHA=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)
ASHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)
echo "  libgk sha build=$BSHA apk=$ASHA"
[ "$BSHA" = "$ASHA" ] || die "APK libgk != build libgk (stale gradle cache)"

say "5. install APK + deploy_verify"
timeout 30 "$ADB" -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if timeout 30 "$ADB" -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
timeout 30 "$ADB" -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
timeout 30 "$ADB" -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
timeout 60 "$ADB" -s $S shell pm trim-caches 999G 2>/dev/null || true
timeout 300 "$ADB" -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify (libgk) failed"

say "6. ensure extraction, push fresh TXT banks into files/cgo overlay"
extract_done(){ [ "$(timeout 30 "$ADB" -s $S shell run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')" = "$PACK_VER" ] \
  && [ "$(timeout 30 "$ADB" -s $S shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$')" -ge 28 ]; }
if ! extract_done; then
  echo "  bundle stamp/CGOs missing -> boot once to extract (can take minutes)"
  timeout 30 "$ADB" -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 900 ]; do extract_done && break; sleep 10; done
  extract_done || die "asset bundle stamp/CGO set never appeared in 900s"
  timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
fi
push_txt_set(){ local SRC="$1" DST="$2" f b lsha dsha
  for f in "$SRC"/*.TXT; do
    b=$(basename "$f")
    lsha=$(sha256sum "$f" | cut -d' ' -f1)
    timeout 60 "$ADB" -s $S push "$f" /data/local/tmp/"$b" >/dev/null 2>&1 || die "push $b to tmp failed"
    timeout 30 "$ADB" -s $S shell "run-as $PKG sh -c 'cp /data/local/tmp/$b $DST/$b'" || die "cp $b -> $DST failed"
    dsha=$(timeout 30 "$ADB" -s $S shell "run-as $PKG sha256sum $DST/$b" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
    [ "$lsha" = "$dsha" ] || die "sha mismatch for $DST/$b (local $lsha device $dsha)"
    timeout 30 "$ADB" -s $S shell rm -f /data/local/tmp/"$b" >/dev/null 2>&1 || true
  done
}
if timeout 30 "$ADB" -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/GAME.CGO'" >/dev/null 2>&1; then
  for b in $(timeout 30 "$ADB" -s $S shell "run-as $PKG sh -c 'ls files/cgo/jak1/'" 2>/dev/null | tr -d '\r' | grep 'COMMON\.TXT$'); do
    [ -f "out/jak1-android-text/$b" ] || { echo "  removing stray overlay TXT: $b"; timeout 30 "$ADB" -s $S shell "run-as $PKG rm -f files/cgo/jak1/$b" >/dev/null 2>&1 || true; }
  done
  push_txt_set out/jak1-android-text files/cgo/jak1
  echo "  ok: $(ls out/jak1-android-text/*.TXT | wc -l) android TXT banks -> files/cgo/jak1 (sha-verified)"
fi
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify_assets failed"

say "7. relaunch: reach render, jak1 foreground, device 0COMMON carries the isolate strings"
timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gpbrf11-boot-logcat.log"; : > "$LOG"
( timeout 240 "$ADB" -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
timeout 30 "$ADB" -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 200 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
FOCUS=$(timeout 30 "$ADB" -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render (crash or hang)"
DEVSTR=$(timeout 30 "$ADB" -s $S shell "run-as $PKG cat files/cgo/jak1/0COMMON.TXT" 2>/dev/null | strings -a | grep -c 'NORMAL-MAP ONLY')
[ "$DEVSTR" -gt 0 ] || die "device overlay 0COMMON.TXT lacks 'NORMAL-MAP ONLY' after final boot (Unknown ID not fixed!)"
echo "  ok: device 0COMMON.TXT carries the isolate strings (Unknown ID FIXED)"
kill ${LCP:-0} 2>/dev/null || true
echo "[gpbrf11] DONE — isolate strings on device (real labels) + libgk diag write live, boots to render, deploy_verify + assets PASS."
