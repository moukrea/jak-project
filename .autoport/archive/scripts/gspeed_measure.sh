#!/usr/bin/env bash
# Gspeed-device: STATE-ANCHORED measurement of game-logic-speed-vs-render-speed.
#
# The owner reports game LOGIC speed varies (not framerate smoothness): game-time
# / Jak / animation advance is inconsistent on arm64. Root hypothesis: the engine
# game-clock time-ratio (drawable.gc:978) is computed from the wall-clock elapsed
# between display-frame-start calls, and display-frame-start is gated by vsync()
# which blocks on the variable RENDER swap. So game-time-per-real-second tracks
# render time instead of staying a constant 60 Hz.
#
# This run arms the GSPEED probe in android_gfx.cpp::vsync() (prop
# debug.opengoal.gspeed.measure=1), warps to Geyser Rock, then drives a LIGHT
# (idle, few draws -> fast render) phase and a HEAVY (full camera pan over the
# whole level -> slow render) phase. For each it logs per-logic-frame:
#   dt_ms (wall-clock per logic frame), float_tr, time_ratio (the integer GOAL
#   uses), game_units_per_real_sec (= time_ratio/dt; CONSTANT 60 == correct,
#   VARYING == the bug). Render swap cadence is the F3 CSV in parallel.
#
# Exits 2 if PIN-locked. Read-only measurement; no goal_src / CGO changes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
SERIAL="${ANDROID_SERIAL:-eae4df44}"; export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=".autoport/reports/Gspeed-device"; mkdir -p "$OUT"
SETUP_LOG="$OUT/setup.log"
GREP='GSPEED |A35-RENDER frame=|Gd1-VBLANK display tick|link finish:|Adding level training|training-vis|Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig='

A() { "$ADB" -s "$SERIAL" "$@"; }
inject() { printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }
device_locked() { A shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }

A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if device_locked; then echo "DEVICE_LOCKED"; exit 2; fi
device_stayon_on || true

echo "== build current-HEAD libgk (GSPEED probe in android_gfx.cpp::vsync) =="
touch android/android_gfx.cpp
bash .autoport/lib/d3_build.sh

echo "== build SLIM jak1 debug APK (libgk-only; DGOs already on device) =="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 12 ) \
    || { echo "FAIL: gradle slim build"; exit 1; }
[ -f "$APK" ] || { echo "FAIL: no APK"; exit 1; }

echo "== install + deploy_verify =="
device_miui_unblock_install || true
STAGE="/data/local/tmp/$(basename "$APK")"
A push "$APK" "$STAGE" >/tmp/gspeed-push.out 2>&1 || { cat /tmp/gspeed-push.out; exit 1; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gspeed-pm.out 2>&1 || { cat /tmp/gspeed-pm.out; exit 1; }
grep -q Success /tmp/gspeed-pm.out || { cat /tmp/gspeed-pm.out; echo "FAIL pm install"; exit 1; }
A shell rm -f "$STAGE" >/dev/null 2>&1 || true
bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL deploy_verify"; exit 1; }

echo "== warp to Geyser Rock =="
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f3.measure 0 >/dev/null 2>&1 || true
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
clear_inject
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true
: > "$SETUP_LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$SETUP_LOG" 2>&1 &
SETUP_PID=$!
cleanup() { kill "$SETUP_PID" 2>/dev/null||true; kill "${WIN_PID:-}" 2>/dev/null||true
  A shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1||true
  clear_inject; A shell am force-stop "$PKG" >/dev/null 2>&1||true; device_stayon_restore 2>/dev/null||true; }
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
echo "  settle 20s..."; sleep 20

run_phase() { # $1=label $2=seconds $3=inject-state(empty=idle)
  local label="$1" secs="$2" state="${3:-}"
  echo "== PHASE $label (${secs}s) =="
  A logcat -c >/dev/null 2>&1 || true
  : > "$OUT/$label.log"
  A logcat -v threadtime opengoal-gk:I GK_STDOUT:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE "$GREP" >> "$OUT/$label.log" &
  WIN_PID=$!
  A shell setprop debug.opengoal.gspeed.measure 1 >/dev/null 2>&1 || true
  if [ -n "$state" ]; then
    # hold a heavy camera-pan sweep across the level for the whole window
    local t0=$SECONDS
    while [ $(( SECONDS - t0 )) -lt "$secs" ]; do inject "$state"; sleep 2; done
  else
    clear_inject; sleep "$secs"
  fi
  A shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
  clear_inject
  kill "$WIN_PID" 2>/dev/null || true; WIN_PID=""
  sleep 1
}

# LIGHT: idle, camera mostly static -> fewest draws -> fastest render
run_phase light 30 ""
# HEAVY: continuous full camera pan + walk -> whole level in frustum -> slow render
run_phase heavy 30 "ly=35 rx=205"

ENDFOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "== focus_at_end: $ENDFOC =="

analyze() { # $1=label
  local f="$OUT/$1.log"
  [ -s "$f" ] || { echo "  [$1] no log"; return; }
  echo "  --- $1 ---"
  grep -aE 'GSPEED ' "$f" | awk '
    {for(i=1;i<=NF;i++){
       if($i ~ /^dt_ms=/){split($i,a,"=");dt=a[2]}
       if($i ~ /^float_tr=/){split($i,a,"=");ftr=a[2]}
       if($i ~ /^time_ratio=/){split($i,a,"=");tr=a[2]}
       if($i ~ /game_units_per_real_sec=/){split($i,a,"=");g=a[2]}}
     n++; sdt+=dt; sg+=g; str+=tr;
     if(g<ming||n==1)ming=g; if(g>maxg)maxg=g;
     if(dt<mindt||n==1)mindt=dt; if(dt>maxdt)maxdt=dt;
     trc[int(tr+0.5)]++ }
    END{ if(n==0){print "    (no GSPEED samples)";exit}
      printf "    frames=%d  dt_ms[min/avg/max]=%.1f/%.1f/%.1f\n",n,mindt,sdt/n,maxdt;
      printf "    time_ratio avg=%.2f  histogram:",str/n; for(k=1;k<=4;k++)if(trc[k])printf " tr%d=%d",k,trc[k]; printf "\n";
      printf "    game_units_per_real_sec[min/avg/max]=%.1f/%.1f/%.1f  (60.0==correct, spread==the bug)\n",ming,sg/n,maxg }'
}
echo "============ Gspeed RESULTS ============"
analyze light
analyze heavy
echo "========================================"
