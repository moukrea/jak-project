#!/usr/bin/env bash
# Gframerate-variable VERIFY — state-anchored constant-real-time-speed at >=3 fps
# regimes + free fps + zero black flicker.
#
# Method (owner's rule: state-anchored, not frame-indexed): warp to Geyser Rock,
# then at a FIXED in-game location (idle camera, identical game content) drive 3
# DISTINCT render loads via debug.opengoal.render.scale so the device renders at
# 3 different fps. For each, the a35_read_ee_timer GSPEED probe logs, per real
# frame:  dt_ms (real wall-clock per frame -> fps), float_tr, time_ratio (the
# integer the engine uses), game_units_per_real_sec = time_ratio/real_dt_sec.
#   * CONSTANT game_units_per_real_sec (~60) across the 3 regimes == constant
#     real-time game speed regardless of fps  (the FIX).
#   * dt_ms (=fps) DIFFERS across regimes == fps is FREE (not capped 30/60).
#   * small per-regime game_units spread == no slow<->fast flap.
# Then a screenrecord across a regime transition is scanned frame-by-frame for
# black/near-black frames (flicker regression guard on 8b330f996).
#
# Exits 2 if PIN-locked. Read-only measurement (no goal_src/CGO changes).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
SERIAL="${ANDROID_SERIAL:-eae4df44}"; export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
OUT=".autoport/reports/Gframerate-variable"; mkdir -p "$OUT"
SETUP_LOG="$OUT/verify-setup.log"
GREP='GSPEED |GFPS-VSYNC|Gd1-VBLANK|link finish:|Adding level training|training-vis|Fatal signal|signal (11|6|4) \(SIG'

A() { "$ADB" -s "$SERIAL" "$@"; }
device_locked() { A shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }

A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if device_locked; then echo "DEVICE_LOCKED"; exit 2; fi
device_stayon_on || true

# ---- skip build/install if SKIP_DEPLOY=1 (deploy already done) ----
if [ "${SKIP_DEPLOY:-0}" != "1" ]; then
  echo "== build current-HEAD libgk =="
  bash .autoport/lib/d3_build.sh
  echo "== build SLIM jak1 debug APK (libgk-only; DGOs already on device) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 8 ) || { echo "FAIL gradle"; exit 1; }
  APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
  [ -f "$APK" ] || { echo "FAIL no APK"; exit 1; }
  echo "== install + deploy_verify =="
  device_miui_unblock_install || true
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/dev/null 2>&1 || { echo "FAIL push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gfps-pm.out 2>&1 || { cat /tmp/gfps-pm.out; exit 1; }
  grep -q Success /tmp/gfps-pm.out || { cat /tmp/gfps-pm.out; echo "FAIL pm"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
fi
bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL deploy_verify"; exit 1; }

echo "== warp to Geyser Rock =="
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.render.scale 100 >/dev/null 2>&1 || true
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true
: > "$SETUP_LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$SETUP_LOG" 2>&1 &
SETUP_PID=$!
cleanup() { kill "$SETUP_PID" 2>/dev/null||true; kill "${WIN_PID:-}" 2>/dev/null||true
  A shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1||true
  A shell setprop debug.opengoal.render.scale 100 >/dev/null 2>&1||true
  A shell am force-stop "$PKG" >/dev/null 2>&1||true; device_stayon_restore 2>/dev/null||true; }
trap cleanup EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

for i in $(seq 1 150); do grep -qa "link finish: logo" "$SETUP_LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done
TRAIN_OK=0; T1=$(( 9*60/5 ))
for ((i=1;i<=T1;i++)); do sleep 5
  if grep -qaE "Adding level training|link finish: training-vis" "$SETUP_LOG"; then echo "  Geyser Rock loaded ~$((i*5))s"; TRAIN_OK=1; break; fi
  grep -qaE 'Fatal signal|signal (11|6|4) \(SIG' "$SETUP_LOG" && { echo "  crash before load"; break; }
  (( i % 6 == 0 )) && echo "  [load ${i}/${T1}]"
done
[ "$TRAIN_OK" = 1 ] || { echo "FAIL: never reached Geyser Rock"; tail -25 "$SETUP_LOG"; exit 1; }
echo "  settle 15s..."; sleep 15

run_regime() { # $1=label $2=render.scale $3=seconds
  local label="$1" scale="$2" secs="$3"
  echo "== REGIME $label (render.scale=$scale, ${secs}s) =="
  A shell setprop debug.opengoal.render.scale "$scale" >/dev/null 2>&1 || true
  sleep 4   # let the FBO resize + cadence settle
  A logcat -c >/dev/null 2>&1 || true
  : > "$OUT/regime-$label.log"
  A logcat -v threadtime opengoal-gk:I GK_STDOUT:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE "$GREP" >> "$OUT/regime-$label.log" &
  WIN_PID=$!
  A shell setprop debug.opengoal.gspeed.measure 1 >/dev/null 2>&1 || true
  sleep "$secs"
  A shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
  kill "$WIN_PID" 2>/dev/null || true; WIN_PID=""
  sleep 1
}

# 3 DISTINCT render loads -> 3 distinct fps regimes, identical game content/location.
run_regime light 50  25
run_regime mid   150 25
run_regime heavy 300 25

# ---- flicker: screenrecord across a regime transition, scan for black frames ----
echo "== flicker check: screenrecord across render.scale transition =="
A shell setprop debug.opengoal.render.scale 60 >/dev/null 2>&1 || true; sleep 2
( A shell screenrecord --time-limit 10 --bit-rate 8000000 /data/local/tmp/gfps-flick.mp4 ) &
REC_PID=$!
sleep 1; A shell setprop debug.opengoal.render.scale 250 >/dev/null 2>&1 || true
sleep 3; A shell setprop debug.opengoal.render.scale 60 >/dev/null 2>&1 || true
wait "$REC_PID" 2>/dev/null || true; sleep 1
A pull /data/local/tmp/gfps-flick.mp4 "$OUT/flicker.mp4" >/dev/null 2>&1 || true

ENDFOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "== focus_at_end: $ENDFOC =="

analyze() { # $1=label
  local f="$OUT/regime-$1.log"
  [ -s "$f" ] || { echo "  [$1] NO LOG (no GSPEED samples)"; return; }
  grep -aE 'GSPEED ' "$f" | awk -v L="$1" '
    {for(i=1;i<=NF;i++){
       if($i ~ /^dt_ms=/){split($i,a,"=");dt=a[2]}
       if($i ~ /^float_tr=/){split($i,a,"=");ftr=a[2]}
       if($i ~ /^time_ratio=/){split($i,a,"=");tr=a[2]}
       if($i ~ /game_units_per_real_sec=/){split($i,a,"=");g=a[2]}}
     n++; sdt+=dt; sg+=g; str+=tr;
     if(g<ming||n==1)ming=g; if(g>maxg)maxg=g;
     if(dt<mindt||n==1)mindt=dt; if(dt>maxdt)maxdt=dt;
     trc[int(tr+0.5)]++ }
    END{ if(n==0){printf "  [%s] (no GSPEED samples)\n",L;exit}
      printf "  --- %s ---\n",L;
      printf "    frames=%d  dt_ms[min/avg/max]=%.1f/%.1f/%.1f  => fps~%.1f\n",n,mindt,sdt/n,maxdt,1000.0/(sdt/n);
      printf "    time_ratio avg=%.2f  hist:",str/n; for(k=1;k<=4;k++)if(trc[k])printf " tr%d=%d",k,trc[k]; printf "\n";
      printf "    game_units_per_real_sec[min/avg/max]=%.1f/%.1f/%.1f  (60.0==real-time; flat across regimes==FIX)\n",ming,sg/n,maxg }'
}
echo "============ Gframerate-variable RESULTS ============"
analyze light
analyze mid
analyze heavy
echo "===================================================="
# crash sanity
if grep -qaE 'Fatal signal|signal (11|6|4) \(SIG' "$OUT"/regime-*.log "$SETUP_LOG" 2>/dev/null; then
  echo "WARNING: signal seen in logs (verify it's not our app — cross-ref PID)"
fi
echo "flicker.mp4 -> $OUT/flicker.mp4 (scan frame-by-frame for black/near-black)"
