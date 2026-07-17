#!/usr/bin/env bash
# grass_r14_walkedge.sh — ROUND#14 edge close-up via warp + WALK (camera pins to rock when Jak is
# stationary in a crevice; walking moves him onto the open outcrop top and toward its EDGE, camera
# following clears the rock). Screenrecord the traversal in several directions; the frames as Jak
# reaches/steps off the outcrop rim show grass stopping at the edge over the drop to the meadow.
# ON (fixed) + base-stub pass. Force-stops at the end.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
WARP_POS="-1296.8 55.0 987.2"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[r14we FAIL] $*" >&2; exit 1; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
dbg(){ $ADB shell setprop debug.opengoal.grass_dbg "$1"; sleep 1.0; }

set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcs14we.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs14we.gc 2>/dev/null; then
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #$1/" /tmp/pcs14we.gc
    $ADB push /tmp/pcs14we.gc /data/local/tmp/pcs14we.gc >/dev/null 2>&1
    $ADB shell cp /data/local/tmp/pcs14we.gc "$PCS" 2>/dev/null || true; $ADB shell rm -f /data/local/tmp/pcs14we.gc >/dev/null 2>&1
  fi
  echo "  grass now: $($ADB shell cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"; }

boot_warp(){ local LOG="$1"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr14we_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 160 ]; do grep -qa 'link finish: logo' "$LOG" && break; sleep 2; done
  local ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }; grep -qa 'LEVEL-WARP-FAIL' "$LOG" && break; sleep 3; done
  sleep 6; echo "  warp_ok=$ok"; }

record_walk(){ # $1 = tag ; records a multi-direction walk traversal
  local TAG="$1"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  ( $ADB shell screenrecord --time-limit 26 --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 ) & local REC=$!
  sleep 1
  stick "ry=238"; sleep 1.0                        # pitch camera down to frame the ground/edge ahead
  # traverse the outcrop toward its edges: walk-forward bursts, turning between to sweep directions
  for turn in "" "rx=170" "rx=170" "rx=170" "rx=170"; do
    [ -n "$turn" ] && { stick "$turn"; sleep 0.8; }
    stick "ly=0"; sleep 2.2                          # walk forward toward an edge
    stick "neutral"; sleep 0.9
    stick "ry=236"; sleep 0.4                         # keep camera down
  done
  stick "neutral"
  wait $REC 2>/dev/null || true; sleep 1
  $ADB pull /sdcard/${TAG}.mp4 "$OUT/${TAG}.mp4" >/dev/null 2>&1 && echo "  pulled ${TAG}.mp4 = $(stat -c %s "$OUT/${TAG}.mp4" 2>/dev/null)B"
  if command -v ffmpeg >/dev/null 2>&1 && [ -s "$OUT/${TAG}.mp4" ]; then
    ffmpeg -y -loglevel error -i "$OUT/${TAG}.mp4" -vf fps=4 "$F/${TAG}_%03d.png" 2>/dev/null
    echo "  extracted $(ls $F/${TAG}_*.png 2>/dev/null | wc -l) frames for ${TAG}"
  fi
}

say "0. install current APK + deploy_verify (libgk already assembled by prior run)"
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify FAIL"

say "1. ON — warp to outcrop, record WALK traversal (normal), then base-stubs"
set_grass t
boot_warp /tmp/gr14we_on.log
dbg 0; record_walk p14_walkedge_on
boot_warp /tmp/gr14we_on2.log
dbg 1; record_walk p14_walkedge_bases
FOCUS=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'); echo "  focus=$FOCUS"

say "2. restore default ON + FORCE-STOP (device hygiene)"
set_grass t
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr14we_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r14we] DONE — p14_walkedge_on_* / _bases_* frames in $F"
