#!/usr/bin/env bash
# grass_moving_capture.sh — Grecharged-grass-poc culling-fix proof.
# 1) ON run: load Geyser Rock, confirm the STATIC whole-level placement line,
#    capture the spawn still, then SCREENRECORD a sustained MOVING sweep while
#    harvesting the per-frame chunk in-range-vs-drawn instrumentation (proves no
#    zone de-instances while walking). Extract stills. Measure fps ON.
# 2) OFF run: settings-file toggle recharged-grass? #f, same spawn viewpoint,
#    prove ZERO grass instance lines (OFF == stock). Restore #t. fps OFF.
# 3) force-stop the app at the end (device-hygiene rule).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-poc
F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }

load_geyser(){  # $1 = logfile
  local LOG="$1"
  $ADB shell am force-stop $PKG >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
  $ADB logcat -c >/dev/null 2>&1
  ( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gmc_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  waiting for title..."
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 120 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
  sleep 4
  pulse "start" 0.4 2.0        # title -> main menu
  pulse "down" 0.35 0.8        # New Game -> Load Game
  pulse "x" 0.4 2.0            # enter load list
  pulse "x" 0.4 2.0            # select top save (ROCHER DU GEYSER)
  pulse "x" 0.4 2.0            # confirm
  echo "  waiting for training gameplay..."
  local got=0
  t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
    mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1)
    [ "$mm" = "master-mode=game" ] && { got=1; break; }
    sleep 3
  done
  sleep 4
  echo "  got_game=$got"
}

# ============================ ON RUN ============================
say "ON RUN — load Geyser Rock (grass default ON)"
LOG_ON=/tmp/gmc_on.log
# ensure the setting is ON for this run
$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell cat "$PCS" > /tmp/pcs_now.gc 2>/dev/null || true
if grep -q 'recharged-grass?' /tmp/pcs_now.gc 2>/dev/null; then
  sed -i 's/^recharged-grass? = #[tf]/recharged-grass? = #t/' /tmp/pcs_now.gc
  $ADB push /tmp/pcs_now.gc /data/local/tmp/pcs_now.gc >/dev/null 2>&1
  $ADB shell cp /data/local/tmp/pcs_now.gc "$PCS"; $ADB shell rm -f /data/local/tmp/pcs_now.gc >/dev/null 2>&1
fi
load_geyser "$LOG_ON"

say "STATIC placement diagnostic (whole-level, camera-independent)"
grep -aE 'recharged-grass\] training STATIC place' "$LOG_ON" | tail -2 | tee "$OUT/static_place_line.txt"

cap AB_geyser_ON            # spawn viewpoint, grass ON (A/B partner)
sleep 1; cap cards_distance_ON  # a second still (look-ahead shows mid cards + far)

say "SCREENRECORD a sustained MOVING sweep (~26s) + harvest chunk instrumentation"
$ADB shell rm -f /sdcard/grass_moving.mp4 >/dev/null 2>&1
( $ADB shell screenrecord --time-limit 27 --bit-rate 10000000 /sdcard/grass_moving.mp4 >/dev/null 2>&1 ) &
REC=$!
sleep 1
# sustained holds so the CAMERA translates through the whole field.
stick "ly=0";           sleep 4      # walk forward
stick "ly=0 rx=205";    sleep 4      # forward + pan camera right
stick "ly=255";         sleep 3      # walk back
stick "lx=255 ly=0";    sleep 3      # forward-right diagonal
stick "lx=0 ly=0";      sleep 3      # forward-left diagonal
stick "rx=45";          sleep 3      # spin camera left (no walk)
stick "ly=0";           sleep 4      # walk forward again
stick "neutral"
wait $REC 2>/dev/null || true
sleep 1
$ADB pull /sdcard/grass_moving.mp4 "$OUT/grass_moving.mp4" >/dev/null 2>&1 && \
  echo "  pulled grass_moving.mp4 = $(stat -c %s "$OUT/grass_moving.mp4" 2>/dev/null)B"

say "CHUNK INSTRUMENTATION while moving (must show DROPPED=0)"
grep -aE 'recharged-grass\] frame .* moving=' "$LOG_ON" | tail -40 | tee "$OUT/chunk_instrumentation.txt"
echo "  --- moving-frame summary ---"
mv=$(grep -acaE 'recharged-grass\] frame .* moving=1' "$LOG_ON")
dropnz=$(grep -aE 'recharged-grass\] frame ' "$LOG_ON" | grep -acaE 'DROPPED=[1-9]')
echo "  moving-frame log lines=$mv, frames-with-DROPPED>0=$dropnz (want 0)"

say "extract stills from the moving video"
if command -v ffmpeg >/dev/null 2>&1 && [ -f "$OUT/grass_moving.mp4" ]; then
  for ts in 2 8 14 20 25; do
    ffmpeg -y -loglevel error -ss "$ts" -i "$OUT/grass_moving.mp4" -frames:v 1 "$F/move_t${ts}.png" 2>/dev/null
    echo "  move_t${ts}.png = $(stat -c %s "$F/move_t${ts}.png" 2>/dev/null)B"
  done
fi

say "fps ON (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_ON" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps ON = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }'
echo "  focus: $($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')"

# ============================ OFF RUN ============================
say "OFF RUN — settings-file toggle recharged-grass? #f (OFF == stock)"
LOG_OFF=/tmp/gmc_off.log
$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell cat "$PCS" > /tmp/pcs_off.gc 2>/dev/null
sed -i 's/^recharged-grass? = #[tf]/recharged-grass? = #f/' /tmp/pcs_off.gc
$ADB push /tmp/pcs_off.gc /data/local/tmp/pcs_off.gc >/dev/null 2>&1
$ADB shell cp /tmp/pcs_off.gc "$PCS" 2>/dev/null || \
  $ADB shell cp /data/local/tmp/pcs_off.gc "$PCS"
$ADB shell rm -f /data/local/tmp/pcs_off.gc >/dev/null 2>&1
echo "  setting now: $($ADB shell cat "$PCS" | grep recharged-grass | tr -d '\r')"
load_geyser "$LOG_OFF"
cap AB_geyser_OFF           # SAME spawn viewpoint, grass OFF
gl=$(grep -acaE 'recharged-grass\] training STATIC place|recharged-grass\] frame ' "$LOG_OFF")
echo "  grass log lines with OFF = $gl (0 == renderer skipped / OFF==stock)"
say "fps OFF (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_OFF" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps OFF = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }'

# ---- restore default ON + device hygiene ----
say "restore recharged-grass? #t, FORCE-STOP (device hygiene)"
$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell cat "$PCS" > /tmp/pcs_on.gc 2>/dev/null
sed -i 's/^recharged-grass? = #[tf]/recharged-grass? = #t/' /tmp/pcs_on.gc
$ADB push /tmp/pcs_on.gc /data/local/tmp/pcs_on.gc >/dev/null 2>&1
$ADB shell cp /data/local/tmp/pcs_on.gc "$PCS" 2>/dev/null || true
$ADB shell rm -f /data/local/tmp/pcs_on.gc >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
kill $(cat /tmp/gmc_lc.pid 2>/dev/null) 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1
echo "  app force-stopped. setting restored to #t."
echo "DONE grass_moving_capture"
