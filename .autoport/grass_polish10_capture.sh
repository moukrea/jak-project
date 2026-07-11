#!/usr/bin/env bash
# grass_polish10_capture.sh — POLISH#10 proof on device eae4df44.
# Owner ask: the per-triangle edge test is now PER-BLADE (each instance judged by its OWN base),
# so grass hugs the exact platform edge — no blade overflowing past the rim, no bald flat-texture
# margin inside it. This harness:
#   (1) loads Geyser Rock (default ON), harvests the "POLISH#10 PER-BLADE edge" placement line
#       (boundary rim edges found / rim slivers dropped individually / near-rim blades leaned inward)
#       — objective proof the per-blade edge path is active and doing work,
#   (2) walks toward the platform edges and captures a DENSE set of border stills at several camera
#       pitches so the exact grass/edge boundary is visible for inspection,
#   (3) a MOVING screenrecord + DROPPED=0 chunk instrumentation (culling must NOT regress),
#   (4) fps ON, then OFF==stock A/B (0 grass log lines with the toggle off) + fps OFF,
#   (5) restores default ON and FORCE-STOPS the app (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc
F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }

load_geyser(){
  local LOG="$1"
  $ADB shell am force-stop $PKG >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
  $ADB logcat -c >/dev/null 2>&1
  ( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gp10_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  waiting for title..."
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 120 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
  sleep 4
  pulse "start" 0.4 2.0
  pulse "down" 0.35 0.8
  pulse "x" 0.4 2.0
  pulse "x" 0.4 2.0
  pulse "x" 0.4 2.0
  echo "  waiting for training gameplay..."
  local got=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
    mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1)
    [ "$mm" = "master-mode=game" ] && { got=1; break; }
    sleep 3
  done
  sleep 4; echo "  got_game=$got"
}

set_grass(){ # $1 = t|f
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs10.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs10.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs10.gc
    $ADB push /tmp/pcs10.gc /data/local/tmp/pcs10.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs10.gc "$PCS"; $ADB shell rm -f /data/local/tmp/pcs10.gc >/dev/null 2>&1
  fi
  echo "  setting now: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"
}

# ============================ ON RUN ============================
say "ON RUN — load Geyser Rock (grass default ON)"
LOG_ON=/tmp/gp10_on.log
set_grass t
load_geyser "$LOG_ON"

say "STATIC placement + POLISH#10 PER-BLADE edge + upness lines"
grep -aE 'recharged-grass\] training STATIC place' "$LOG_ON" | tail -1 | tee "$OUT/p10_static_place.txt"
grep -aE 'recharged-grass\] POLISH#10 PER-BLADE edge' "$LOG_ON" | tail -1 | tee "$OUT/p10_perblade_edge.txt"
grep -aE 'recharged-grass\] POLISH#8 EDGE upness'  "$LOG_ON" | tail -1 | tee -a "$OUT/p10_perblade_edge.txt"

cap p10_spawn_ON

say "WALK toward platform edges + DENSE border stills at several camera pitches"
# forward toward the rim, capturing along the way
stick "ly=0"; sleep 1.2; cap p10_walk_a
sleep 1.2; cap p10_walk_b
sleep 1.2; cap p10_walk_c
stick "neutral"; sleep 0.5
# pitch the camera down to frame the ground/edge boundary, capture at a few pitches
stick "ry=255"; sleep 1.5; cap p10_edge_pitchdown1; stick "neutral"; sleep 0.5
stick "ry=200"; sleep 1.0; cap p10_edge_pitchdown2; stick "neutral"; sleep 0.5
# orbit the camera to look ALONG a rim, capture the grass/edge boundary from several yaws
for yaw in "rx=205" "rx=170" "rx=85" "rx=45"; do
  stick "$yaw"; sleep 1.3; cap "p10_edge_${yaw/=/_}"; stick "neutral"; sleep 0.5
done
# strafe to a different edge and repeat a couple of shots
stick "lx=255 ly=0"; sleep 1.6; cap p10_edge_strafe1
stick "lx=0 ly=0";   sleep 1.6; cap p10_edge_strafe2
stick "neutral"; sleep 0.5

say "SCREENRECORD a MOVING sweep (~24s) for DROPPED=0 + a border pass"
$ADB shell rm -f /sdcard/grass_p10.mp4 >/dev/null 2>&1
( $ADB shell screenrecord --time-limit 24 --bit-rate 10000000 /sdcard/grass_p10.mp4 >/dev/null 2>&1 ) &
REC=$!
sleep 1
stick "ly=0";           sleep 4
stick "ly=0 rx=205";    sleep 4
stick "ly=255";         sleep 3
stick "lx=255 ly=0";    sleep 3
stick "lx=0 ly=0";      sleep 3
stick "rx=45";          sleep 3
stick "ly=0";           sleep 3
stick "neutral"
wait $REC 2>/dev/null || true
sleep 1
$ADB pull /sdcard/grass_p10.mp4 "$OUT/grass_p10.mp4" >/dev/null 2>&1 && \
  echo "  pulled grass_p10.mp4 = $(stat -c %s "$OUT/grass_p10.mp4" 2>/dev/null)B"

say "CHUNK INSTRUMENTATION while moving (must show DROPPED=0)"
grep -aE 'recharged-grass\] frame .* moving=' "$LOG_ON" | tail -12 | tee "$OUT/p10_chunk_instr.txt"
mv=$(grep -acaE 'recharged-grass\] frame .* moving=1' "$LOG_ON")
dropnz=$(grep -aE 'recharged-grass\] frame ' "$LOG_ON" | grep -acaE 'DROPPED=[1-9]')
echo "  moving-frame lines=$mv, frames-with-DROPPED>0=$dropnz (want 0)" | tee -a "$OUT/p10_chunk_instr.txt"

say "extract border stills from the moving video"
if command -v ffmpeg >/dev/null 2>&1 && [ -f "$OUT/grass_p10.mp4" ]; then
  for ts in 3 7 11 15 19 22; do
    ffmpeg -y -loglevel error -ss "$ts" -i "$OUT/grass_p10.mp4" -frames:v 1 "$F/p10_move_t${ts}.png" 2>/dev/null
    echo "  p10_move_t${ts}.png = $(stat -c %s "$F/p10_move_t${ts}.png" 2>/dev/null)B"
  done
fi

say "fps ON (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_ON" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps ON = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee "$OUT/p10_fps.txt"
echo "  focus: $($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')" | tee -a "$OUT/p10_fps.txt"

# ============================ OFF RUN ============================
say "OFF RUN — settings toggle recharged-grass? #f (OFF == stock)"
LOG_OFF=/tmp/gp10_off.log
set_grass f
load_geyser "$LOG_OFF"
cap p10_spawn_OFF
gl=$(grep -acaE 'recharged-grass\] training STATIC place|recharged-grass\] frame |recharged-grass\] POLISH#10' "$LOG_OFF")
echo "  grass log lines with OFF = $gl (0 == renderer skipped / OFF==stock)" | tee "$OUT/p10_off_stock.txt"
say "fps OFF (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_OFF" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps OFF = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee -a "$OUT/p10_fps.txt"

# ---- restore default ON + device hygiene ----
say "restore recharged-grass? #t, FORCE-STOP (device hygiene)"
set_grass t
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
kill $(cat /tmp/gp10_lc.pid 2>/dev/null) 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1
echo "  app force-stopped. setting restored to #t."
echo "DONE grass_polish10_capture"
