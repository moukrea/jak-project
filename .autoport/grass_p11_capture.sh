#!/usr/bin/env bash
# grass_p11_capture.sh — POLISH#11 edge proof on device eae4df44.
# Owner: grass STILL overflowed platform rims (floating over the void) AND left bald holes near
# borders. Root fix (renderer): a rim is now strictly an edge used by ONE kept grass triangle
# (the rej_lip merge that hid real platform shoulders is removed) + the vertex shader HARD-CLAMPS
# each blade's total horizontal offset to rim_dist so no geometry can cross its nearest rim
# (full height kept -> no fringe). This harness:
#   (1) loads Geyser Rock (default ON), harvests the POLISH#11 PER-BLADE edge CLAMP placement line
#       (true-rim edge count back up, degenerate slivers, blades clamped),
#   (2) navigates to grassy-platform EDGES and captures a DENSE set of p11_edge_closeup_* stills at
#       many camera pitches/yaws + several positions, plus a slow rim-pan screenrecord -> extracted
#       edge frames, so the exact grass/rim boundary is visible for the supervisor to eyeball,
#   (3) MOVING screenrecord + DROPPED=0 chunk instrumentation (culling must NOT regress),
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
  ( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gp11_lc.pid )
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
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs11.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs11.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs11.gc
    $ADB push /tmp/pcs11.gc /data/local/tmp/pcs11.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs11.gc "$PCS"; $ADB shell rm -f /data/local/tmp/pcs11.gc >/dev/null 2>&1
  fi
  echo "  setting now: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"
}

# ============================ ON RUN ============================
say "ON RUN — load Geyser Rock (grass default ON)"
LOG_ON=/tmp/gp11_on.log
set_grass t
load_geyser "$LOG_ON"

say "STATIC placement + POLISH#11 PER-BLADE edge CLAMP + upness lines"
grep -aE 'recharged-grass\] training STATIC place' "$LOG_ON" | tail -1 | tee "$OUT/p11_static_place.txt"
grep -aE 'recharged-grass\] POLISH#11 PER-BLADE edge' "$LOG_ON" | tail -1 | tee "$OUT/p11_perblade_edge.txt"
grep -aE 'recharged-grass\] POLISH#8 EDGE upness'  "$LOG_ON" | tail -1 | tee -a "$OUT/p11_perblade_edge.txt"

cap p11_spawn_ON

# ---- Phase A: near spawn, pitch camera DOWN + orbit to frame the platform edge right by Jak ----
say "Phase A — spawn-platform edge, camera pitched down + orbited"
stick "ry=255"; sleep 1.4; cap p11_edge_closeup_a1; stick "neutral"; sleep 0.4
stick "ry=210"; sleep 1.0; cap p11_edge_closeup_a2; stick "neutral"; sleep 0.4
for yw in "rx=210" "rx=150" "rx=90" "rx=40"; do
  stick "$yw"; sleep 1.3; cap "p11_edge_closeup_a_${yw/=/_}"; stick "neutral"; sleep 0.4
done

# ---- Phase B: walk forward toward the rim/void, capture at several pitches ----
say "Phase B — walk to a rim, frame the grass/void boundary"
stick "ly=0"; sleep 1.3; cap p11_edge_closeup_b_walk1
sleep 1.3; cap p11_edge_closeup_b_walk2
stick "neutral"; sleep 0.4
stick "ry=255"; sleep 1.3; cap p11_edge_closeup_b_pitch1; stick "neutral"; sleep 0.4
stick "ry=200"; sleep 1.0; cap p11_edge_closeup_b_pitch2; stick "neutral"; sleep 0.4

# ---- Phase C: turn camera to look BACK at the grassy platform rim silhouetted against sky/void ----
say "Phase C — look back at a grassy platform rim (silhouette shows any floating grass)"
for yw in "rx=255" "rx=220" "rx=180"; do
  stick "$yw"; sleep 1.4; cap "p11_edge_closeup_c_${yw/=/_}"; stick "neutral"; sleep 0.4
done
stick "ry=60"; sleep 1.1; cap p11_edge_closeup_c_pitchup1; stick "neutral"; sleep 0.4
stick "ry=90"; sleep 1.0; cap p11_edge_closeup_c_pitchup2; stick "neutral"; sleep 0.4

# ---- Phase D: strafe to a different edge and capture more ----
say "Phase D — strafe to another edge"
stick "lx=255 ly=0"; sleep 1.8; cap p11_edge_closeup_d_strafe1
stick "lx=0 ly=0";   sleep 1.8; cap p11_edge_closeup_d_strafe2
stick "neutral"; sleep 0.4
stick "ry=235"; sleep 1.2; cap p11_edge_closeup_d_pitch1; stick "neutral"; sleep 0.4

# ---- Phase E: slow rim-pan screenrecord -> extract close-up frames ----
say "Phase E — slow rim-pan screenrecord (edge frames extracted below)"
$ADB shell rm -f /sdcard/grass_p11.mp4 >/dev/null 2>&1
( $ADB shell screenrecord --time-limit 30 --bit-rate 12000000 /sdcard/grass_p11.mp4 >/dev/null 2>&1 ) &
REC=$!
sleep 1
stick "ry=235"; sleep 2
stick "rx=210"; sleep 4
stick "ly=0";   sleep 3
stick "rx=150"; sleep 4
stick "lx=255 ly=0"; sleep 3
stick "rx=90";  sleep 4
stick "ry=200"; sleep 3
stick "rx=255"; sleep 4
stick "neutral"
wait $REC 2>/dev/null || true
sleep 1
$ADB pull /sdcard/grass_p11.mp4 "$OUT/grass_p11.mp4" >/dev/null 2>&1 && \
  echo "  pulled grass_p11.mp4 = $(stat -c %s "$OUT/grass_p11.mp4" 2>/dev/null)B"
if command -v ffmpeg >/dev/null 2>&1 && [ -f "$OUT/grass_p11.mp4" ]; then
  for ts in 3 6 9 12 15 18 21 24 27; do
    ffmpeg -y -loglevel error -ss "$ts" -i "$OUT/grass_p11.mp4" -frames:v 1 "$F/p11_edge_closeup_move_t${ts}.png" 2>/dev/null
    echo "  p11_edge_closeup_move_t${ts}.png = $(stat -c %s "$F/p11_edge_closeup_move_t${ts}.png" 2>/dev/null)B"
  done
fi

say "CHUNK INSTRUMENTATION while moving (must show DROPPED=0)"
grep -aE 'recharged-grass\] frame .* moving=' "$LOG_ON" | tail -14 | tee "$OUT/p11_chunk_instr.txt"
mv=$(grep -acaE 'recharged-grass\] frame .* moving=1' "$LOG_ON")
dropnz=$(grep -aE 'recharged-grass\] frame ' "$LOG_ON" | grep -acaE 'DROPPED=[1-9]')
echo "  moving-frame lines=$mv, frames-with-DROPPED>0=$dropnz (want 0)" | tee -a "$OUT/p11_chunk_instr.txt"

say "fps ON (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_ON" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps ON = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee "$OUT/p11_fps.txt"
echo "  focus: $($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')" | tee -a "$OUT/p11_fps.txt"

# ============================ OFF RUN ============================
say "OFF RUN — settings toggle recharged-grass? #f (OFF == stock)"
LOG_OFF=/tmp/gp11_off.log
set_grass f
load_geyser "$LOG_OFF"
cap p11_spawn_OFF
gl=$(grep -acaE 'recharged-grass\] training STATIC place|recharged-grass\] frame |recharged-grass\] POLISH#11' "$LOG_OFF")
echo "  grass log lines with OFF = $gl (0 == renderer skipped / OFF==stock)" | tee "$OUT/p11_off_stock.txt"
say "fps OFF (idle 6s)"
stick "neutral"; sleep 6
grep -aE 'GK-DIAG F1D target-pos f=' "$LOG_OFF" | tail -40 | \
  awk '{ t=$2; gsub(/[:.]/," ",t); split(t,a," "); sec=a[1]*3600+a[2]*60+a[3]+a[4]/1000;
         f=$0; sub(/.*f=/,"",f); sub(/ .*/,"",f);
         if(NR==1){s0=sec; f0=f+0} sN=sec; fN=f+0 }
       END{ dt=sN-s0; df=fN-f0; if(dt>0) printf "  fps OFF = %.1f (frames=%d / %.2fs)\n", df/dt, df, dt }' | tee -a "$OUT/p11_fps.txt"

# ---- restore default ON + device hygiene ----
say "restore recharged-grass? #t, FORCE-STOP (device hygiene)"
set_grass t
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
kill $(cat /tmp/gp11_lc.pid 2>/dev/null) 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1
echo "  app force-stopped. setting restored to #t."
echo "DONE grass_p11_capture"
