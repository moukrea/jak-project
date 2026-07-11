#!/usr/bin/env bash
# grass_polish9_capture.sh — POLISH#9 proof on device eae4df44.
# Reuses the working culling-fix harness (load Geyser Rock via cpad_inject, sweep, DROPPED=0,
# OFF==stock, force-stop) and ADDS the two POLISH#9 proofs:
#   (1) precise per-triangle EDGE clip active  -> harvest "POLISH#9 EDGE clip" line
#   (2) DYNAMIC GROUND baked-light active      -> harvest "POLISH#9 LIGHT upload #N" lines
#       (upload count grows over a long idle == the light is re-sampled as the TOD advances;
#        per-tri baked luma min..max == per-LOCATION variation the grass is multiplied by).
# Also captures ON stills + a MOVING sweep video + OFF==stock A/B. Force-stops at the end.
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
  ( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gp9_lc.pid )
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

# ============================ ON RUN ============================
say "ON RUN — load Geyser Rock (grass default ON)"
LOG_ON=/tmp/gp9_on.log
$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell run-as $PKG cat "$PCS" > /tmp/pcs_now.gc 2>/dev/null || true
if grep -q 'recharged-grass?' /tmp/pcs_now.gc 2>/dev/null; then
  sed -i 's/(recharged-grass? #[tf])/(recharged-grass? #t)/' /tmp/pcs_now.gc
  $ADB push /tmp/pcs_now.gc /data/local/tmp/pcs_now.gc >/dev/null 2>&1
  $ADB shell run-as $PKG cp /data/local/tmp/pcs_now.gc "$PCS"; $ADB shell rm -f /data/local/tmp/pcs_now.gc >/dev/null 2>&1
fi
load_geyser "$LOG_ON"

say "STATIC placement + POLISH#9 EDGE clip + POLISH#9 LIGHT (first upload)"
grep -aE 'recharged-grass\] training STATIC place' "$LOG_ON" | tail -1 | tee "$OUT/p9_static_place.txt"
grep -aE 'recharged-grass\] POLISH#9 EDGE clip'    "$LOG_ON" | tail -1 | tee "$OUT/p9_edge_clip.txt"
grep -aE 'recharged-grass\] POLISH#8 EDGE upness'  "$LOG_ON" | tail -1 | tee -a "$OUT/p9_edge_clip.txt"
grep -aE 'recharged-grass\] POLISH#9 LIGHT upload' "$LOG_ON" | tail -3 | tee "$OUT/p9_light.txt"

cap p9_geyser_ON
sleep 1; cap p9_lookahead_ON

say "SCREENRECORD a sustained MOVING sweep (~27s) + harvest chunk instrumentation (DROPPED=0)"
$ADB shell rm -f /sdcard/grass_p9.mp4 >/dev/null 2>&1
( $ADB shell screenrecord --time-limit 27 --bit-rate 10000000 /sdcard/grass_p9.mp4 >/dev/null 2>&1 ) &
REC=$!
sleep 1
stick "ly=0";           sleep 4
stick "ly=0 rx=205";    sleep 4
stick "ly=255";         sleep 3
stick "lx=255 ly=0";    sleep 3
stick "lx=0 ly=0";      sleep 3
stick "rx=45";          sleep 3
stick "ly=0";           sleep 4
stick "neutral"
wait $REC 2>/dev/null || true
sleep 1
$ADB pull /sdcard/grass_p9.mp4 "$OUT/grass_p9.mp4" >/dev/null 2>&1 && \
  echo "  pulled grass_p9.mp4 = $(stat -c %s "$OUT/grass_p9.mp4" 2>/dev/null)B"

say "CHUNK INSTRUMENTATION while moving (must show DROPPED=0)"
grep -aE 'recharged-grass\] frame .* moving=' "$LOG_ON" | tail -12 | tee "$OUT/p9_chunk_instr.txt"
mv=$(grep -acaE 'recharged-grass\] frame .* moving=1' "$LOG_ON")
dropnz=$(grep -aE 'recharged-grass\] frame ' "$LOG_ON" | grep -acaE 'DROPPED=[1-9]')
echo "  moving-frame lines=$mv, frames-with-DROPPED>0=$dropnz (want 0)" | tee -a "$OUT/p9_chunk_instr.txt"

say "DYNAMIC LIGHT — idle 20s, count POLISH#9 LIGHT uploads (grows == TOD tracked)"
stick "neutral"; sleep 20
grep -aE 'recharged-grass\] POLISH#9 LIGHT upload' "$LOG_ON" | tail -6 | tee "$OUT/p9_light_dynamic.txt"
NUP=$(grep -acaE 'recharged-grass\] POLISH#9 LIGHT upload' "$LOG_ON")
echo "  total POLISH#9 LIGHT uploads so far = $NUP (>1 == re-sampled as TOD advanced; 1 == fixed-TOD level)" | tee -a "$OUT/p9_light_dynamic.txt"

say "extract stills from the moving video"
if command -v ffmpeg >/dev/null 2>&1 && [ -f "$OUT/grass_p9.mp4" ]; then
  for ts in 2 8 14 20 25; do
    ffmpeg -y -loglevel error -ss "$ts" -i "$OUT/grass_p9.mp4" -frames:v 1 "$F/p9_move_t${ts}.png" 2>/dev/null
    echo "  p9_move_t${ts}.png = $(stat -c %s "$F/p9_move_t${ts}.png" 2>/dev/null)B"
  done
fi

say "fps ON (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_ON" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps ON = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee "$OUT/p9_fps.txt"
echo "  focus: $($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')" | tee -a "$OUT/p9_fps.txt"

# ============================ OFF RUN ============================
say "OFF RUN — settings toggle recharged-grass? #f (OFF == stock)"
LOG_OFF=/tmp/gp9_off.log
$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell run-as $PKG cat "$PCS" > /tmp/pcs_off.gc 2>/dev/null
sed -i 's/(recharged-grass? #[tf])/(recharged-grass? #f)/' /tmp/pcs_off.gc
$ADB push /tmp/pcs_off.gc /data/local/tmp/pcs_off.gc >/dev/null 2>&1
$ADB shell run-as $PKG cp /data/local/tmp/pcs_off.gc "$PCS" 2>/dev/null || \
  $ADB shell run-as $PKG cp /data/local/tmp/pcs_off.gc "$PCS"
$ADB shell rm -f /data/local/tmp/pcs_off.gc >/dev/null 2>&1
echo "  setting now: $($ADB shell run-as $PKG cat "$PCS" | grep recharged-grass | tr -d '\r')"
load_geyser "$LOG_OFF"
cap p9_geyser_OFF
gl=$(grep -acaE 'recharged-grass\] training STATIC place|recharged-grass\] frame |recharged-grass\] POLISH#9' "$LOG_OFF")
echo "  grass log lines with OFF = $gl (0 == renderer skipped / OFF==stock)" | tee "$OUT/p9_off_stock.txt"
say "fps OFF (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_OFF" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps OFF = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee -a "$OUT/p9_fps.txt"

# ---- restore default ON + device hygiene ----
say "restore recharged-grass? #t, FORCE-STOP (device hygiene)"
$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell run-as $PKG cat "$PCS" > /tmp/pcs_on.gc 2>/dev/null
sed -i 's/(recharged-grass? #[tf])/(recharged-grass? #t)/' /tmp/pcs_on.gc
$ADB push /tmp/pcs_on.gc /data/local/tmp/pcs_on.gc >/dev/null 2>&1
$ADB shell run-as $PKG cp /data/local/tmp/pcs_on.gc "$PCS" 2>/dev/null || true
$ADB shell rm -f /data/local/tmp/pcs_on.gc >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
kill $(cat /tmp/gp9_lc.pid 2>/dev/null) 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1
echo "  app force-stopped. setting restored to #t."
echo "DONE grass_polish9_capture"
