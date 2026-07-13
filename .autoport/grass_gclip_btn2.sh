#!/usr/bin/env bash
# grass_gclip_btn2.sh — Gclip button close-up RE-SHOT with the r22 orbit (camera tilts down onto
# the warp-gate-switch plate; the first gclip beat cropped the plate at the frame bottom).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-object-clip; F="$OUT/frames"; mkdir -p "$F"
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
rec(){ local TAG="$1" SECS="$2"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  mkdir -p /tmp/rec_$TAG; rm -f /tmp/rec_$TAG/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=2 /tmp/rec_$TAG/f_%03d.png 2>/dev/null
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls /tmp/rec_$TAG 2>/dev/null | wc -l) $(focus)"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1 </dev/null
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
    $ADB logcat -b all -c >/dev/null 2>&1 </dev/null
    kill "$(cat /tmp/gclip2_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gclip2_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 14; return 0; }
  done
  return 1; }

echo "BUTTON re-shot with r22 orbit — @ -1309.0 7.2 1060.5"
boot_warp_retry "-1309.0 7.2 1060.5" /tmp/gclip_btn2.log || { echo "[gclip2 FAIL] boot"; exit 1; }
sleep 4
( sleep 2; pulse "rx=205" 1.2 0.4; pulse "ry=225" 0.7 0.4; pulse "rx=205" 1.2 0.4; \
  pulse "rx=205" 1.2 0.4; pulse "ry=225" 0.5 0.4; pulse "rx=205" 1.2 0.4 ) &
ORB=$!
rec gclip_btn2 14
wait $ORB 2>/dev/null || true
for f in /tmp/rec_gclip_btn2/f_*.png; do i=$(basename "$f" .png | cut -d_ -f2)
  case "$i" in 004|008|012|016|020|024|028) cp "$f" "$F/gclip_btn2_$i.png";; esac; done
{ echo "=== A2-BUTTON re-shot (orbit onto the plate) ==="
  echo "--- focus: $(focus)"
  grep -aE 'R21OCC goal-publish' /tmp/gclip_btn2.log | tail -3
  grep -aE 'R19OCC frame=' /tmp/gclip_btn2.log | tail -3
} >> "$OUT/gclip_occ_proof.txt"

$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gclip2_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[gclip2] DONE"
