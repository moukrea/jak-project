#!/usr/bin/env bash
# gpbrf_fullspec_ab.sh — Grecharged-pbr-realtime-fusion OWNER FULL SPEC round (REOPEN #14).
#
# Delta this round is LIBGK-ONLY (common/custom_data/TFrag3Data.cpp + a comment in TFragment.cpp):
#   - NEW debug.opengoal.mesh.weld A/B toggle (mesh_weld_enabled()) that DISABLES the whole per-tree +
#     global weld/orient/smooth pass at runtime — the owner-mandated on-device A/B so the supervisor can
#     prove the remaining seams come from the geometry pass (weld ON vs weld OFF at a fixed daytime hour).
#   - UV-smoothing at welded seams (global_uv_snapped_seam_verts) — conservative hairline-crack close.
#   - crease default 45 -> 60 deg so gentle terrain/grass seams smooth to a nuance, sharp corners stay.
# The 28 arm64 CGO/DGO + text banks are UNCHANGED, so we only rebuild libgk + reassemble the APK.
#
# It performs a DAYTIME-FROZEN (debug.opengoal.tod.hour) A/B: two boots at the same vantage, weld ON then
# weld OFF, capturing mp4+png for each and pulling files/pbr_tan_diag.txt so the mesh_weld_enabled= line
# provably flips 1->0 across the pair (device proof the toggle applies).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
TOD_HOUR="${TOD_HOUR:-12}"   # noon: baked stable + PBR visible (owner FULL SPEC: freeze daytime)
say(){ echo; echo "######## $* ########"; }
die(){ echo "[fullspec FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
timeout 60 "$ADB" -s $S wait-for-device || die "device not present"

say "1. build android libgk (mesh.weld toggle + UV-smooth + crease60 compiled in)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -14
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
MW=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'debug.opengoal.mesh.weld')
UV=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'global_uv_snapped_seam_verts')
GL=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c '\[global-weld\]')
echo "  libgk markers: mesh.weld=$MW uv_snapped=$UV [global-weld]=$GL"
[ "$MW" -gt 0 ] || die "libgk missing 'debug.opengoal.mesh.weld' (A/B toggle not compiled in)"
[ "$UV" -gt 0 ] || die "libgk missing 'global_uv_snapped_seam_verts' (UV-smooth not compiled in)"
[ "$GL" -gt 0 ] || die "libgk missing '[global-weld]' (global weld not compiled in)"

say "2. assemble APK (bundles fresh libgk + existing cgo pack)"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -8 ) || die "gradle assemble failed"
[ -f "$APK" ] || die "APK not produced"
BSHA=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)
ASHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)
echo "  libgk sha build=$BSHA apk=$ASHA"
[ "$BSHA" = "$ASHA" ] || die "APK libgk != build libgk (stale gradle cache)"

say "3. install APK + deploy_verify"
timeout 30 "$ADB" -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if timeout 30 "$ADB" -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
timeout 30 "$ADB" -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
timeout 30 "$ADB" -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
timeout 60 "$ADB" -s $S shell pm trim-caches 999G 2>/dev/null || true
timeout 300 "$ADB" -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4 || die "deploy_verify (libgk) failed"

say "3b. freeze TOD to a DAYTIME hour ($TOD_HOUR) so the baked is stable and PBR is visible"
timeout 30 "$ADB" -s $S shell setprop debug.opengoal.tod.hour "$TOD_HOUR" >/dev/null 2>&1 || true

# ---- one A/B boot: $1 = weld value (1|0), $2 = label ----
boot_capture() {
  local WELD="$1" LBL="$2"
  say "BOOT [$LBL]: debug.opengoal.mesh.weld=$WELD  (tod.hour=$TOD_HOUR)"
  timeout 30 "$ADB" -s $S shell setprop debug.opengoal.mesh.weld "$WELD" >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S shell "run-as $PKG rm -f files/pbr_tan_diag.txt" >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S logcat -c >/dev/null 2>&1 || true
  local LOG="$OUT/fullspec_${LBL}_logcat.log"; : > "$LOG"
  ( timeout 240 "$ADB" -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'A35-RENDER frame=|link finish|global-weld|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
  local LCP=$!
  timeout 30 "$ADB" -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0 ok=0; t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 200 ]; do
    if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot [$LBL]"; break; fi
    local rf; rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
    [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
    sleep 3
  done
  local FOCUS; FOCUS=$(timeout 30 "$ADB" -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
  echo "  reached_render=$ok focus=$FOCUS"
  echo "$FOCUS" > "$OUT/fullspec_${LBL}_focus.txt"
  kill ${LCP:-0} 2>/dev/null || true
  case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground [$LBL]: $FOCUS" ;; esac
  [ "$ok" = 1 ] || die "did not reach render [$LBL] (crash or hang)"

  # give the loader time to finish the village1 load + diag write
  sleep 10
  local DIAG="$OUT/fullspec_${LBL}_diag.txt"
  timeout 30 "$ADB" -s $S shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null > "$DIAG" || true
  echo "  ---- diag [$LBL]: toggle + weld stats ----"
  grep -E 'mesh_weld_enabled=|global_cross_chunk_stitched_verts=|global_uv_snapped_seam_verts=|crease_threshold_deg=' "$DIAG" 2>/dev/null || echo "  (diag section missing)"

  # capture mp4 + still (screenrecord; screencap is black on the GL surface)
  timeout 30 "$ADB" -s $S shell rm -f /sdcard/fs_$LBL.mp4 >/dev/null 2>&1 || true
  ( timeout 20 "$ADB" -s $S shell screenrecord --time-limit 10 /sdcard/fs_$LBL.mp4 ) >/dev/null 2>&1 || true
  sleep 2
  timeout 60 "$ADB" -s $S pull /sdcard/fs_$LBL.mp4 "$OUT/fullspec_${LBL}.mp4" >/dev/null 2>&1 || echo "  (mp4 pull failed)"
  if [ -f "$OUT/fullspec_${LBL}.mp4" ] && command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -i "$OUT/fullspec_${LBL}.mp4" -frames:v 1 -q:v 2 "$OUT/fullspec_${LBL}.png" >/dev/null 2>&1 || true
  fi
  ls -la "$OUT/fullspec_${LBL}.mp4" "$OUT/fullspec_${LBL}.png" 2>/dev/null || echo "  (capture artifacts missing [$LBL])"
}

say "4. A/B: weld ON (the shipped default) then weld OFF (the seamy baseline)"
boot_capture 1 weldon
boot_capture 0 weldoff

say "5. A/B PROOF — mesh_weld_enabled must flip 1 (ON) -> 0 (OFF) across the pair"
ON=$(grep -oE 'mesh_weld_enabled=[0-9]+' "$OUT/fullspec_weldon_diag.txt"  2>/dev/null | head -1 | cut -d= -f2)
OFF=$(grep -oE 'mesh_weld_enabled=[0-9]+' "$OUT/fullspec_weldoff_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
CROSS=$(grep -oE 'global_cross_chunk_stitched_verts=[0-9]+' "$OUT/fullspec_weldon_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
UVS=$(grep -oE 'global_uv_snapped_seam_verts=[0-9]+' "$OUT/fullspec_weldon_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
echo "  weld-ON mesh_weld_enabled=$ON  weld-OFF mesh_weld_enabled=$OFF  (ON cross_chunk_stitched=$CROSS uv_snapped=$UVS)"
[ "${ON:-x}" = "1" ]  || die "weld-ON boot did not report mesh_weld_enabled=1 (toggle not applied)"
[ "${OFF:-x}" = "0" ] || die "weld-OFF boot did not report mesh_weld_enabled=0 (toggle not applied)"
[ "${CROSS:-0}" -gt 1000 ] 2>/dev/null || die "weld-ON cross-chunk stitched count implausibly low ($CROSS)"
echo "[fullspec] DONE — daytime(hour=$TOD_HOUR) A/B captured: weld-ON (cross=$CROSS uv_snapped=$UVS) vs weld-OFF (pass disabled), jak1 foreground both boots, no Fatal signal. Toggle provably flips on device."
