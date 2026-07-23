#!/usr/bin/env bash
# gpbrf3_bisect.sh — REOPEN #3 TERM BISECTION (owner: plastic sheen SURVIVES specular=0,
# so it is NOT the slider-scaled specular sum — zero ONE fused-path term at a time on
# device and find the capture where the sheen dies).
#
# Uses the gpbrf_evidence.sh vantage (village1-hut '-112.0 42.0 205.0', TOD 8 = day,
# sage stonewall + ground in frame). Boots ONCE, then sweeps debug.opengoal.pbr.bisect
# LIVE (props are re-read every frame in first_tfrag_draw_setup) — one screenrecord per
# mask. Also reproduces the owner's datapoint: bisect=0 + specint=0 (sheen survives?).
#
# Masks (tfrag3.frag u_pbr_bisect):
#   0    baseline (full fused path)
#   1    yellow-sun GGX specular OFF     2    green-sun GGX specular OFF
#   4    ambient/IBL specular OFF        8    Fresnel-on-diffuse kd darkening OFF
#   16   _specular-map F0 OFF            32   emissive OFF
#   64   normal-map perturbation OFF     128  parallax/POM OFF
#   256  detail-relight ratio OFF        512  baked-modulation fmod OFF
#   1024 C1 shoulder tone map OFF (linear clamp)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gpbrf3-bisect FAIL] $*" >&2; exit 1; }
fg_require(){ local f; f=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  echo "  focus: $f"; case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground: $f";; esac }

MASKS="${MASKS:-0 1 2 4 8 16 32 64 128 256 512 1024}"
HOUR="${HOUR:-8}"
# boot vantage override (verify run uses the beach-grazing ground vantage too)
WARP_POS="${WARP_POS:--112.0 42.0 205.0}"

case "${1:?stage (boot|sweep|spec0|metrics|cleanup)}" in
boot)
  adb shell am force-stop $PKG; sleep 2
  pkill -f "$ADB -s $S logcat" 2>/dev/null; sleep 1
  adb logcat -c 2>/dev/null || true
  adb shell "setprop debug.opengoal.cpad_inject neutral"
  adb shell setprop debug.opengoal.level.warp village1-hut
  adb shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'"
  adb shell "setprop debug.opengoal.tod.hour '$HOUR'"
  adb shell "setprop debug.opengoal.tod.fast ''"
  adb shell setprop debug.opengoal.renderscale.native 1
  adb shell "setprop debug.opengoal.pbr.debug ''"
  adb shell "setprop debug.opengoal.pbr.nstrength ''"
  adb shell "setprop debug.opengoal.pbr.specint ''"
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  adb shell "setprop debug.opengoal.rt.light ''"
  adb shell "setprop debug.opengoal.rt.sunelev ''"
  adb shell "setprop debug.opengoal.pbr.shadowmap 1"
  adb shell "setprop debug.opengoal.pbr.kill 0"
  LOG="$OUT/logcat-bisect.log"; : > "$LOG"
  ( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|pbr binding|custom pbr|Fatal signal|GK-DIAG sig=|shader.*[Ee]rror|link.*[Ff]ail' >> "$LOG" ) 2>/dev/null &
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
    grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && break; sleep 5
  done
  grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" || die "no LEVEL-WARP-SPAWN in 300s"
  grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot"
  echo "  spawned; settling 20s"; sleep 20
  fg_require
  echo "[gpbrf3-bisect boot] OK — app at vantage, bisect=0"
  ;;
sweep)
  for m in $MASKS; do
    adb shell "setprop debug.opengoal.pbr.bisect $m"
    sleep 3
    adb shell screenrecord --time-limit 3 --bit-rate 8000000 /sdcard/gpbrf3_m$m.mp4 || die "screenrecord m=$m"
    adb pull /sdcard/gpbrf3_m$m.mp4 /tmp/gpbrf3_m$m.mp4 >/dev/null 2>&1 || die "pull m=$m"
    adb shell rm -f /sdcard/gpbrf3_m$m.mp4
    rm -rf /tmp/gpbrf3_fr; mkdir -p /tmp/gpbrf3_fr
    ffmpeg -y -loglevel error -i /tmp/gpbrf3_m$m.mp4 -vf fps=2 /tmp/gpbrf3_fr/f_%03d.png
    last=$(ls /tmp/gpbrf3_fr/f_*.png | tail -1); [ -n "$last" ] || die "no frames m=$m"
    cp "$last" "$OUT/bisect_m$m.png"; echo "  mask $m -> $OUT/bisect_m$m.png"
    rm -rf /tmp/gpbrf3_fr /tmp/gpbrf3_m$m.mp4
  done
  fg_require
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  echo "[gpbrf3-bisect sweep] OK — $(echo $MASKS | wc -w) captures"
  ;;
spec0)  # the owner's datapoint: full path, specular-intensity slider forced 0
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  adb shell "setprop debug.opengoal.pbr.specint 0"
  sleep 3
  adb shell screenrecord --time-limit 3 --bit-rate 8000000 /sdcard/gpbrf3_spec0.mp4
  adb pull /sdcard/gpbrf3_spec0.mp4 /tmp/gpbrf3_spec0.mp4 >/dev/null 2>&1 || die "pull spec0"
  adb shell rm -f /sdcard/gpbrf3_spec0.mp4
  rm -rf /tmp/gpbrf3_fr; mkdir -p /tmp/gpbrf3_fr
  ffmpeg -y -loglevel error -i /tmp/gpbrf3_spec0.mp4 -vf fps=2 /tmp/gpbrf3_fr/f_%03d.png
  cp "$(ls /tmp/gpbrf3_fr/f_*.png | tail -1)" "$OUT/bisect_spec0.png"
  rm -rf /tmp/gpbrf3_fr /tmp/gpbrf3_spec0.mp4
  adb shell "setprop debug.opengoal.pbr.specint ''"
  fg_require
  echo "  spec0 -> $OUT/bisect_spec0.png"
  ;;
metrics)
  python3 .autoport/gpbrf3_bisect_metrics.py "$OUT" $MASKS | tee "$OUT/bisect_matrix.txt"
  ;;
cleanup)
  adb shell "setprop debug.opengoal.pbr.bisect 0"
  adb shell "setprop debug.opengoal.pbr.specint ''"
  adb shell am force-stop $PKG
  echo "[gpbrf3-bisect] cleaned (bisect=0)"
  ;;
*) die "unknown stage $1";;
esac
