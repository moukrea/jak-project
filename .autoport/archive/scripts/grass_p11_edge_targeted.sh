#!/usr/bin/env bash
# grass_p11_edge_targeted.sh — a TIGHT platform-rim close-up (supervisor eyeball gate).
# Single ON boot. Approaches the spawn grass-platform edge in small forward steps with the camera
# pitched down, capturing a still after every step so one frame lands with Jak AT the grass rim and
# the camera framing where the 3D grass carpet ends at the platform edge (grass must stop exactly at
# the rim: no blade floating past it, no bald flat-texture margin inside it). Also records a slow
# edge-crawl and extracts dense frames. Force-stops at the end (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }

LOG=/tmp/gp11e.log
$ADB shell am force-stop $PKG >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
$ADB logcat -c >/dev/null 2>&1
( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gp11e_lc.pid )
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
say "boot -> title -> training"
t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 120 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
sleep 4
pulse "start" 0.4 2.0; pulse "down" 0.35 0.8; pulse "x" 0.4 2.0; pulse "x" 0.4 2.0; pulse "x" 0.4 2.0
got=0; t0=$(date +%s)
while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
  mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1); [ "$mm" = "master-mode=game" ] && { got=1; break; }; sleep 3
done
sleep 4; echo "  got_game=$got"

say "pitch the camera DOWN to frame the ground ahead of Jak"
stick "ry=255"; sleep 1.6; stick "neutral"; sleep 0.5
cap p11_edge_closeup_tgt_00

say "step toward the platform edge, capture after each small step (grass carpet -> rim)"
for i in $(seq 1 10); do
  pulse "ly=0" 0.28 0.6           # small forward step
  stick "ry=255"; sleep 0.5; stick "neutral"; sleep 0.3   # keep camera down
  cap "p11_edge_closeup_tgt_$(printf %02d $i)"
done

say "orbit slightly at the edge for a few side-on rim angles"
for yw in "rx=210" "rx=170" "rx=95"; do
  stick "$yw"; sleep 1.1; stick "neutral"; sleep 0.3
  stick "ry=245"; sleep 0.6; stick "neutral"; sleep 0.3
  cap "p11_edge_closeup_tgt_${yw/=/_}"
done

say "slow edge-crawl screenrecord (12s) + dense frame extraction"
$ADB shell rm -f /sdcard/grass_p11e.mp4 >/dev/null 2>&1
( $ADB shell screenrecord --time-limit 14 --bit-rate 12000000 /sdcard/grass_p11e.mp4 >/dev/null 2>&1 ) &
REC=$!
sleep 1
stick "ry=250"; sleep 1
for i in 1 2 3 4 5 6 7 8; do pulse "ly=0" 0.22 0.5; done
stick "rx=180"; sleep 2
stick "neutral"
wait $REC 2>/dev/null || true; sleep 1
$ADB pull /sdcard/grass_p11e.mp4 "$OUT/grass_p11e.mp4" >/dev/null 2>&1 && echo "  pulled grass_p11e.mp4 = $(stat -c %s "$OUT/grass_p11e.mp4" 2>/dev/null)B"
if command -v ffmpeg >/dev/null 2>&1 && [ -f "$OUT/grass_p11e.mp4" ]; then
  ffmpeg -y -loglevel error -i "$OUT/grass_p11e.mp4" -vf fps=4 "$F/p11_edge_closeup_crawl_%03d.png" 2>/dev/null
  echo "  extracted $(ls $F/p11_edge_closeup_crawl_*.png 2>/dev/null | wc -l) crawl frames"
fi

say "restore neutral + FORCE-STOP (device hygiene)"
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
kill $(cat /tmp/gp11e_lc.pid 2>/dev/null) 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1
echo "  focus: $($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')"
echo "DONE grass_p11_edge_targeted"
