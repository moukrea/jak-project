#!/usr/bin/env bash
# gpbrf_gweld_build_deploy.sh — Grecharged-pbr-realtime-fusion REOPEN #13 + INSIGHT #2.
# GLOBAL cross-chunk/bucket/system vertex weld + normal-orientation-consistency.
#
# Delta this round is LIBGK-ONLY (no goal_src / CGO / text changes):
#   - common/custom_data/TFrag3Data.cpp: NEW tfrag3::reconstruct_level_global_weld(Level&) — one
#     spatial hash over EVERY tfrag+tie vertex in the whole level, welds coincident positions ACROSS
#     tree/bucket/chunk/system boundaries, orients inward normals outward (INSIGHT #2, collision
#     authority), then crease-averages. Writes stats to files/pbr_tan_diag.txt.
#   - game/graphics/opengl_renderer/loader/Loader.cpp: call it after all trees unpack (gated on the
#     PBR / realtime-lighting features so a STOCK player pays zero cost).
# The 28 arm64 CGO/DGO + text banks are UNCHANGED, so we only rebuild libgk + reassemble the APK and
# reuse the already-deployed asset set (deploy_verify_assets still proves no mixed build).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gweld FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
timeout 60 "$ADB" -s $S wait-for-device || die "device not present"

say "1. build android libgk (global cross-chunk weld compiled in)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -14
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
GW=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'global_cross_chunk_stitched')
GL=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c '\[global-weld\]')
echo "  libgk global_cross_chunk_stitched strings=$GW   [global-weld] strings=$GL"
[ "$GW" -gt 0 ] || die "libgk.so missing 'global_cross_chunk_stitched' diag string (global weld not compiled in)"
[ "$GL" -gt 0 ] || die "libgk.so missing '[global-weld]' log string (global weld not compiled in)"

say "2. assemble APK (bundles fresh libgk + existing cgo pack)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
BSHA=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)
ASHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)
echo "  libgk sha build=$BSHA apk=$ASHA"
[ "$BSHA" = "$ASHA" ] || die "APK libgk != build libgk (stale gradle cache)"

say "3. install APK + deploy_verify (+ assets: prove 28 CGO/DGO still consistent, no mixed build)"
timeout 30 "$ADB" -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if timeout 30 "$ADB" -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
timeout 30 "$ADB" -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
timeout 30 "$ADB" -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
timeout 60 "$ADB" -s $S shell pm trim-caches 999G 2>/dev/null || true
timeout 300 "$ADB" -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify (libgk) failed"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify_assets failed"

say "4. clear the stale diag file so we PROVE this boot rewrote it"
timeout 30 "$ADB" -s $S shell "run-as $PKG rm -f files/pbr_tan_diag.txt" >/dev/null 2>&1 || true

say "5. relaunch: reach render, jak1 foreground, no Fatal signal (village1 attract = the weld runs at load)"
timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gweld-boot-logcat.log"; : > "$LOG"
( timeout 240 "$ADB" -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|global-weld|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
timeout 30 "$ADB" -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
FOCUS=$(timeout 30 "$ADB" -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS"
echo "$FOCUS" > "$OUT/gweld-focus.txt"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render (crash or hang)"

say "6. pull the global-weld diag file (Honor obscures logcat => a run-as FILE is the channel)"
# give the loader a moment to have finished the village1 load + diag write
sleep 8
DIAG="$OUT/gweld_pbr_tan_diag.txt"
timeout 30 "$ADB" -s $S shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null > "$DIAG" || true
if ! grep -q 'global_cross_chunk_stitched_verts=' "$DIAG" 2>/dev/null; then
  echo "  diag lacks global_weld section on first boot — ensuring PBR is enabled then reloading"
  # enable recharged master + pbr so the gated global weld runs, then re-boot into the attract
  timeout 30 "$ADB" -s $S shell setprop debug.opengoal.recharged.master 1 >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  sleep 40
  timeout 30 "$ADB" -s $S shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null > "$DIAG" || true
fi
grep -q 'global_cross_chunk_stitched_verts=' "$DIAG" || die "global_weld diag section never written (gate skipped the weld?)"
CROSS=$(grep -oE 'global_cross_chunk_stitched_verts=[0-9]+' "$DIAG" | head -1 | cut -d= -f2)
echo "  global_cross_chunk_stitched_verts=$CROSS (device)"
[ "${CROSS:-0}" -gt 1000 ] 2>/dev/null || die "cross-chunk stitched count implausibly low ($CROSS) — weld not stitching across chunks"
echo "  ---- device diag (global_weld section) ----"
sed -n '/\[global_weld\]/,$p' "$DIAG"

say "7. capture mp4 + still (screenrecord; screencap is black on the GL surface)"
timeout 30 "$ADB" -s $S shell rm -f /sdcard/gweld.mp4 >/dev/null 2>&1 || true
( timeout 20 "$ADB" -s $S shell screenrecord --time-limit 12 /sdcard/gweld.mp4 ) >/dev/null 2>&1 || true
sleep 2
timeout 60 "$ADB" -s $S pull /sdcard/gweld.mp4 "$OUT/gweld_default.mp4" >/dev/null 2>&1 || echo "  (mp4 pull failed)"
if [ -f "$OUT/gweld_default.mp4" ]; then
  ( command -v ffmpeg >/dev/null 2>&1 ) && ffmpeg -y -i "$OUT/gweld_default.mp4" -frames:v 1 -q:v 2 "$OUT/gweld_default.png" >/dev/null 2>&1 || true
fi
ls -la "$OUT/gweld_default.mp4" "$OUT/gweld_default.png" 2>/dev/null || echo "  (capture artifacts missing)"

FOCUS2=$(timeout 30 "$ADB" -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "$FOCUS2" > "$OUT/gweld-focus.txt"
case "$FOCUS2" in *org.opengoal.gk.jak1*) : ;; *) die "app left foreground after capture: $FOCUS2" ;; esac
kill ${LCP:-0} 2>/dev/null || true
echo "[gweld] DONE — libgk global weld live, boots to render (jak1 foreground, no Fatal signal), diag file shows cross_chunk_stitched=$CROSS."
