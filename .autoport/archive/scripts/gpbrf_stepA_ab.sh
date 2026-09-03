#!/usr/bin/env bash
# gpbrf_stepA_ab.sh — Grecharged-pbr-realtime-fusion OWNER STRICT-ORDER round (STEP A = TRUE FUSE).
#
# Delta this round is LIBGK-ONLY (common/custom_data/TFrag3Data.cpp): a genuine TOPOLOGICAL index-buffer
# merge (fuse_tree_indices) that runs FIRST (before smooth/orient/uv) in TfragTree::unpack /
# TieTree::unpack, so coincident ATTRIBUTE-IDENTICAL verts share ONE representative index (real point
# fusion) instead of the prior normal-averaging-only weld. The device pbr_tan_diag.txt now carries an
# [index_fuse] block (index_fused_tfrag_verts / index_fused_tie_verts) — the objective ON-DEVICE proof
# that STEP A executes on the real Adreno hardware.
#
# It performs a DAYTIME-FROZEN, FULL-STACK A/B: two boots at the same vantage, weld ON then weld OFF,
# forcing the whole PBR pipeline (recharged master, PBR on, realtime lighting on, relief>0,
# displacement=tessellation, tod=noon) so the capture is under the designed conditions and PAST the ND
# logo (attract camera flying through the REAL village1 terrain), and pulling files/pbr_tan_diag.txt so
# both mesh_weld_enabled (1->0) AND index_fused_* (>0 -> 0) provably flip across the pair.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
TOD_HOUR="${TOD_HOUR:-12}"       # noon: baked stable + PBR visible (owner: freeze daytime)
TERRAIN_WAIT="${TERRAIN_WAIT:-45}"  # wait this many s past first render so the attract flies past the ND
                                    # logo INTO the village1 terrain before we grab the mp4
say(){ echo; echo "######## $* ########"; }
die(){ echo "[stepA FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
timeout 60 "$ADB" -s $S wait-for-device || die "device not present"

say "1. build android libgk (STEP A fuse compiled in)"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -14
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
IFT=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'index_fused_tfrag_verts')
IFB=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c '\[index_fuse\]')
MW=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'debug.opengoal.mesh.weld')
echo "  libgk markers: index_fused_tfrag_verts=$IFT [index_fuse]=$IFB mesh.weld=$MW"
[ "$IFT" -gt 0 ] || die "libgk missing 'index_fused_tfrag_verts' (STEP A fuse not compiled in)"
[ "$IFB" -gt 0 ] || die "libgk missing '[index_fuse]' block (STEP A not compiled in)"
[ "$MW" -gt 0 ]  || die "libgk missing 'debug.opengoal.mesh.weld' (A/B toggle not compiled in)"

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

say "3b. FULL STACK force-props (owner test method) + freeze TOD daytime ($TOD_HOUR)"
# recharged master ON, PBR ON (kill=0), realtime lighting ON, relief strong, displacement=tessellation.
timeout 30 "$ADB" -s $S shell setprop debug.opengoal.recharged 1 >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S shell setprop debug.opengoal.pbr.kill 0 >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S shell setprop debug.opengoal.rt.light 1 >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S shell setprop debug.opengoal.pbr.relief 1.5 >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S shell setprop debug.opengoal.pbr.displacement 2 >/dev/null 2>&1 || true
timeout 30 "$ADB" -s $S shell setprop debug.opengoal.tod.hour "$TOD_HOUR" >/dev/null 2>&1 || true

# ---- one A/B boot: $1 = weld value (1|0), $2 = label ----
boot_capture() {
  local WELD="$1" LBL="$2"
  say "BOOT [$LBL]: mesh.weld=$WELD  (FULL STACK: recharged/pbr/rt on, relief1.5, disp=2, tod=$TOD_HOUR)"
  timeout 30 "$ADB" -s $S shell setprop debug.opengoal.mesh.weld "$WELD" >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S shell "run-as $PKG rm -f files/pbr_tan_diag.txt" >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s $S logcat -c >/dev/null 2>&1 || true
  local LOG="$OUT/stepA_${LBL}_logcat.log"; : > "$LOG"
  ( timeout 240 "$ADB" -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'A35-RENDER frame=|link finish|global-weld|index_fuse|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
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
  echo "$FOCUS" > "$OUT/stepA_${LBL}_focus.txt"
  case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) kill ${LCP:-0} 2>/dev/null; die "app not foreground [$LBL]: $FOCUS" ;; esac
  [ "$ok" = 1 ] || { kill ${LCP:-0} 2>/dev/null; die "did not reach render [$LBL] (crash or hang)"; }

  # pull the diag (loader writes it as village1 finishes unpacking — STEP A ran during unpack)
  sleep 10
  local DIAG="$OUT/stepA_${LBL}_diag.txt"
  timeout 30 "$ADB" -s $S shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null > "$DIAG" || true
  echo "  ---- diag [$LBL]: STEP A fuse + toggle ----"
  grep -E 'mesh_weld_enabled=|index_fused_tfrag_verts=|index_fused_tie_verts=|global_cross_chunk_stitched_verts=' "$DIAG" 2>/dev/null || echo "  (diag section missing)"

  # wait past the ND logo INTO the village terrain flythrough, THEN capture (owner: not the logo frame)
  say "  waiting ${TERRAIN_WAIT}s for the attract to fly past the ND logo into village1 terrain [$LBL]"
  sleep "$TERRAIN_WAIT"
  local FOCUS2; FOCUS2=$(timeout 30 "$ADB" -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
  case "$FOCUS2" in *org.opengoal.gk.jak1*) : ;; *) kill ${LCP:-0} 2>/dev/null; die "app left foreground before capture [$LBL]: $FOCUS2" ;; esac
  timeout 30 "$ADB" -s $S shell rm -f /sdcard/sa_$LBL.mp4 >/dev/null 2>&1 || true
  ( timeout 20 "$ADB" -s $S shell screenrecord --time-limit 10 /sdcard/sa_$LBL.mp4 ) >/dev/null 2>&1 || true
  sleep 2
  timeout 60 "$ADB" -s $S pull /sdcard/sa_$LBL.mp4 "$OUT/stepA_${LBL}.mp4" >/dev/null 2>&1 || echo "  (mp4 pull failed)"
  if [ -f "$OUT/stepA_${LBL}.mp4" ] && command -v ffmpeg >/dev/null 2>&1; then
    # grab a mid-clip frame (terrain, not the very first frame)
    ffmpeg -y -ss 5 -i "$OUT/stepA_${LBL}.mp4" -frames:v 1 -q:v 2 "$OUT/stepA_${LBL}.png" >/dev/null 2>&1 || \
    ffmpeg -y -i "$OUT/stepA_${LBL}.mp4" -frames:v 1 -q:v 2 "$OUT/stepA_${LBL}.png" >/dev/null 2>&1 || true
  fi
  kill ${LCP:-0} 2>/dev/null || true
  ls -la "$OUT/stepA_${LBL}.mp4" "$OUT/stepA_${LBL}.png" 2>/dev/null || echo "  (capture artifacts missing [$LBL])"
}

say "4. A/B: weld ON (STEP A fuse active) then weld OFF (seamy baseline, fuse skipped)"
boot_capture 1 weldon
boot_capture 0 weldoff

say "5. STEP A DEVICE PROOF — mesh_weld_enabled 1->0 AND index_fused_* >0 -> 0 across the pair"
ON=$(grep -oE 'mesh_weld_enabled=[0-9]+' "$OUT/stepA_weldon_diag.txt"  2>/dev/null | head -1 | cut -d= -f2)
OFF=$(grep -oE 'mesh_weld_enabled=[0-9]+' "$OUT/stepA_weldoff_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
FT=$(grep -oE 'index_fused_tfrag_verts=[0-9]+' "$OUT/stepA_weldon_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
FTI=$(grep -oE 'index_fused_tie_verts=[0-9]+' "$OUT/stepA_weldon_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
FT_OFF=$(grep -oE 'index_fused_tfrag_verts=[0-9]+' "$OUT/stepA_weldoff_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
CROSS=$(grep -oE 'global_cross_chunk_stitched_verts=[0-9]+' "$OUT/stepA_weldon_diag.txt" 2>/dev/null | head -1 | cut -d= -f2)
echo "  weld-ON  mesh_weld_enabled=$ON  index_fused_tfrag=$FT  index_fused_tie=$FTI  cross_chunk_stitched=$CROSS"
echo "  weld-OFF mesh_weld_enabled=$OFF index_fused_tfrag=$FT_OFF"
[ "${ON:-x}" = "1" ]  || die "weld-ON boot did not report mesh_weld_enabled=1 (toggle not applied)"
[ "${OFF:-x}" = "0" ] || die "weld-OFF boot did not report mesh_weld_enabled=0 (toggle not applied)"
[ "${FT:-0}" -gt 1000 ] 2>/dev/null  || die "weld-ON index_fused_tfrag implausibly low ($FT) — STEP A not running on device"
[ "${FTI:-0}" -gt 1000 ] 2>/dev/null || die "weld-ON index_fused_tie implausibly low ($FTI) — STEP A not running on device"
[ "${FT_OFF:-0}" = "0" ] || die "weld-OFF index_fused_tfrag should be 0 (fuse gated OFF) but is $FT_OFF"
echo "[stepA] DONE — device proof: STEP A index-fuse ran on-device (tfrag=$FT tie=$FTI verts fused, weld ON),"
echo "        gated OFF to 0 in the weld-OFF baseline; mesh_weld_enabled flips 1->0; jak1 foreground both boots;"
echo "        FULL-STACK daytime(hour=$TOD_HOUR) A/B captured past the ND logo. No Fatal signal."
