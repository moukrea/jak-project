#!/usr/bin/env bash
# gpbrf_evidence.sh — Grecharged-pbr-realtime-fusion device evidence (clone of the
# gbt_evidence/rtl_device_capture machinery).
#
# Stages:
#   abset fused|bidon|rtonly|stock   configure settings.ini (force-stopped first)
#     fused   master+textures+pbr+realtime-lighting+load-custom-assets ON  -> NEW fused path
#     bidon   same but realtime-lighting OFF                               -> standalone PBR fallback
#     rtonly  master+textures+realtime-lighting ON, pbr OFF, lca OFF       -> accepted rt look
#     stock   master OFF                                                   -> vanilla
#   push full|noemis|emisback|glossy|matte|roughback|metal1|metal0|clean
#     manage the synthesized user maps in /storage/emulated/0/OpenGOAL/jak1/custom_assets
#     (flat, bare-name keys; USER wins over the bundled base/normal/rough/height set)
#   cap TAG [HOUR] [NSTRENGTH] [KEEPMP4]  boot to the owner sage-wall vantage
#     (village1-hut '-112.0 42.0 205.0'), pinned TOD, screenrecord -> device/TAG.png
#     (+ device/TAG.mp4 when KEEPMP4=1)
#   loadcheck   logcat of the last fused cap must show _specular/_emissive map loads +
#               material registered with S=1 E=1
#   measure     objective numbers -> device/metrics.txt
#   cleanup     clear props, remove user maps, force-stop
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
USER_DROP="/storage/emulated/0/OpenGOAL/jak1/custom_assets"
MAPS=/tmp/gpbrf_maps
TEX=vil1-sages-stonewall-01
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gpbrf-ev FAIL] $*" >&2; exit 1; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
fg_require(){ local f; f=$(fg); echo "  focus: $f"; case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground: $f";; esac }

set_kv(){ local f="$1" k="$2" v="$3"
  if grep -qE "^$k = " "$f"; then sed -i -E "s/^$k = .*/$v/" "$f"; else sed -i "/^\[secrets\]/i $v" "$f"; fi
}

settings_config(){ # fused | bidon | rtonly | stock
  adb shell am force-stop $PKG; sleep 2
  adb shell cat "$PCS" > /tmp/gpbrf_pcs.ini 2>/dev/null || die "cannot read $PCS"
  tr -d '\r' < /tmp/gpbrf_pcs.ini > /tmp/gpbrf_pcs2.ini && mv /tmp/gpbrf_pcs2.ini /tmp/gpbrf_pcs.ini
  grep -q 'static-pckernel-version 1 11 0 0' goal_src/jak1/pc/pckernel-impl.gc \
    || die "GOAL pckernel version no longer 1 11 0 0 — update the pinned hex below"
  set_kv /tmp/gpbrf_pcs.ini 'version' 'version = #x1000b00000000'
  # Baseline: every unrelated recharged feature off so the only diff source is under test.
  set_kv /tmp/gpbrf_pcs.ini 'recharged-grass\?' 'recharged-grass? = #f'
  set_kv /tmp/gpbrf_pcs.ini 'recharged-foliage-wind\?' 'recharged-foliage-wind? = #f'
  set_kv /tmp/gpbrf_pcs.ini 'ambient-occlusion' 'ambient-occlusion = 0'
  set_kv /tmp/gpbrf_pcs.ini 'recharged-enhanced-models\?' 'recharged-enhanced-models? = #f'
  case "$1" in
    fused)
      set_kv /tmp/gpbrf_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'recharged-textures\?' 'recharged-textures? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'pbr-materials\?' 'pbr-materials? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'load-custom-assets\?' 'load-custom-assets? = #t'
      ;;
    bidon)
      set_kv /tmp/gpbrf_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'recharged-textures\?' 'recharged-textures? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'pbr-materials\?' 'pbr-materials? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #f'
      set_kv /tmp/gpbrf_pcs.ini 'load-custom-assets\?' 'load-custom-assets? = #t'
      ;;
    rtonly)
      set_kv /tmp/gpbrf_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'recharged-textures\?' 'recharged-textures? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'pbr-materials\?' 'pbr-materials? = #f'
      set_kv /tmp/gpbrf_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #t'
      set_kv /tmp/gpbrf_pcs.ini 'load-custom-assets\?' 'load-custom-assets? = #f'
      ;;
    stock)
      set_kv /tmp/gpbrf_pcs.ini 'recharged-master\?' 'recharged-master? = #f'
      set_kv /tmp/gpbrf_pcs.ini 'recharged-textures\?' 'recharged-textures? = #f'
      set_kv /tmp/gpbrf_pcs.ini 'pbr-materials\?' 'pbr-materials? = #f'
      set_kv /tmp/gpbrf_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #f'
      set_kv /tmp/gpbrf_pcs.ini 'load-custom-assets\?' 'load-custom-assets? = #f'
      ;;
    *) die "unknown config $1";;
  esac
  adb push /tmp/gpbrf_pcs.ini /data/local/tmp/gpbrf_pcs.ini >/dev/null 2>&1 || die "push failed"
  adb shell cp /data/local/tmp/gpbrf_pcs.ini "$PCS" || die "cp to settings failed"
  adb shell cat "$PCS" | tr -d '\r' | grep -q '^version = #x1000b00000000$' || die "version pin did not land"
  echo "  config '$1' applied:"
  adb shell cat "$PCS" | grep -aE '^(version|recharged-master|recharged-textures|load-custom-assets|pbr-materials|realtime-lighting)' | sed 's/^/    /'
}

push_maps(){ # full|noemis|emisback|glossy|matte|roughback|metal1|metal0|clean
  case "$1" in
    full)
      for sfx in _ao _metallic _specular _emissive; do
        adb push "$MAPS/${TEX}${sfx}.png" "$USER_DROP/${TEX}${sfx}.png" >/dev/null || die "push $sfx failed"
      done
      echo "  user maps: $(adb shell ls "$USER_DROP" | tr -d '\r' | grep -c "^${TEX}_")x ${TEX}_* pushed";;
    noemis)   adb shell rm -f "$USER_DROP/${TEX}_emissive.png"; echo "  user _emissive removed";;
    emisback) adb push "$MAPS/${TEX}_emissive.png" "$USER_DROP/${TEX}_emissive.png" >/dev/null; echo "  user _emissive restored";;
    glossy)   adb push "$MAPS/ROUGH_GLOSSY_${TEX}_roughness.png" "$USER_DROP/${TEX}_roughness.png" >/dev/null; echo "  user _roughness = GLOSSY(40)";;
    matte)    adb push "$MAPS/ROUGH_MATTE_${TEX}_roughness.png" "$USER_DROP/${TEX}_roughness.png" >/dev/null; echo "  user _roughness = MATTE(230)";;
    roughback) adb shell rm -f "$USER_DROP/${TEX}_roughness.png"; echo "  user _roughness removed (bundled resumes)";;
    metal1)   adb push "$MAPS/METAL_WHITE_${TEX}_metallic.png" "$USER_DROP/${TEX}_metallic.png" >/dev/null; echo "  user _metallic = WHITE";;
    metal0)   adb push "$MAPS/${TEX}_metallic.png" "$USER_DROP/${TEX}_metallic.png" >/dev/null; echo "  user _metallic = BLACK";;
    clean)    adb shell "rm -f $USER_DROP/${TEX}_ao.png $USER_DROP/${TEX}_metallic.png $USER_DROP/${TEX}_specular.png $USER_DROP/${TEX}_emissive.png $USER_DROP/${TEX}_roughness.png"; echo "  user maps removed";;
    *) die "unknown push op $1";;
  esac
}

cap(){ # TAG [HOUR=8] [NSTRENGTH=] [KEEPMP4=0]
  local TAG=${1:?tag} HOUR=${2:-8} NST=${3:-} KEEP=${4:-0}
  adb shell am force-stop $PKG; sleep 2
  pkill -f "$ADB -s $S logcat" 2>/dev/null; sleep 1
  adb logcat -c 2>/dev/null || true
  adb shell "setprop debug.opengoal.cpad_inject neutral"
  adb shell setprop debug.opengoal.level.warp village1-hut
  adb shell "setprop debug.opengoal.level.warp.pos '-112.0 42.0 205.0'"
  adb shell "setprop debug.opengoal.tod.hour '$HOUR'"
  adb shell "setprop debug.opengoal.tod.fast ''"
  adb shell setprop debug.opengoal.renderscale.native 1
  adb shell "setprop debug.opengoal.pbr.debug ''"
  adb shell "setprop debug.opengoal.pbr.nstrength '${NST}'"
  # rt path via the SETTINGS row (menu contract), not the prop override:
  adb shell "setprop debug.opengoal.rt.light ''"
  adb shell "setprop debug.opengoal.rt.sunelev ''"
  adb shell "setprop debug.opengoal.pbr.shadowmap 1"
  LOG="$OUT/logcat-$TAG.log"; : > "$LOG"
  ( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|custom texture replacement|custom pbr|PC [Kk]ernel version|Fatal signal|GK-DIAG sig=|shader.*[Ee]rror|link.*[Ff]ail' >> "$LOG" ) 2>/dev/null &
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
    grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && break; sleep 5
  done
  grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" || die "no LEVEL-WARP-SPAWN in 300s ($TAG)"
  grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during $TAG boot"
  echo "  spawned; settling 20s (static camera, TOD=$HOUR nstrength='${NST:-def}')"; sleep 20
  fg_require
  adb shell screenrecord --time-limit 6 --bit-rate 8000000 /sdcard/gpbrf_$TAG.mp4
  adb pull /sdcard/gpbrf_$TAG.mp4 /tmp/gpbrf_$TAG.mp4 >/dev/null 2>&1 || die "pull rec failed"
  adb shell rm -f /sdcard/gpbrf_$TAG.mp4
  rm -rf /tmp/gpbrf_frames_$TAG; mkdir -p /tmp/gpbrf_frames_$TAG
  ffmpeg -y -loglevel error -i /tmp/gpbrf_$TAG.mp4 -vf fps=2 /tmp/gpbrf_frames_$TAG/f_%03d.png
  local last; last=$(ls /tmp/gpbrf_frames_$TAG/f_*.png | tail -1)
  [ -n "$last" ] || die "no frames for $TAG"
  cp "$last" "$OUT/$TAG.png"; echo "  frame -> $OUT/$TAG.png"
  [ "$KEEP" = 1 ] && { cp /tmp/gpbrf_$TAG.mp4 "$OUT/$TAG.mp4"; echo "  video -> $OUT/$TAG.mp4"; }
  rm -rf /tmp/gpbrf_frames_$TAG /tmp/gpbrf_$TAG.mp4
  adb shell am force-stop $PKG
}

case "${1:?stage}" in
abset) settings_config "${2:?fused|bidon|rtonly|stock}";;
push) push_maps "${2:?op}";;
cap) cap "${2:?tag}" "${3:-8}" "${4:-}" "${5:-0}";;
loadcheck)
  L="$OUT/logcat-${2:-fused_h8}.log"
  [ -f "$L" ] || die "no $L"
  for sfx in _normal _roughness _height _ao _metallic _specular _emissive; do
    grep -aq "custom pbr map .*${TEX}${sfx}" "$L" || die "no ${sfx} map load in $L"
    echo "  ${sfx}: $(grep -ac "custom pbr map .*${TEX}${sfx}" "$L") loads ($(grep -am1 "custom pbr map .*${TEX}${sfx}" "$L" | grep -aoE '\((user|bundled)\)'))"
  done
  grep -aq "custom pbr material registered: ${TEX} (N=1 R=1 M=1 AO=1 H=1 S=1 E=1)" "$L" \
    || die "material not registered with all 7 maps"
  echo "  registered: $(grep -a "custom pbr material registered: ${TEX}" "$L" | head -1)"
  echo "[gpbrf-ev loadcheck] PASS"
  ;;
cleanup)
  push_maps clean
  for p in level.warp level.warp.pos tod.hour tod.fast renderscale.native pbr.nstrength pbr.debug rt.light rt.sunelev; do
    adb shell "setprop debug.opengoal.$p ''"; done
  adb shell am force-stop $PKG
  echo "[gpbrf-ev] cleaned"
  ;;
*) die "unknown stage $1";;
esac
