#!/usr/bin/env bash
# Gcamera-interp circle capture: drive Jak in a CIRCLE (left movement stick held at
# a fixed diagonal) on the open Geyser plateau so the FOLLOW CAMERA yaws
# continuously at a near-constant rate — no manual-pan limit, no camera cuts. At
# full render scale the device is sub-60 so the integer time-ratio k dithers; the
# per-frame camera-yaw irregularity is the judder. Captures caminterp=0 then =1.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="/home/emeric/Android/platform-tools/adb -s eae4df44"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
EV=.autoport/reports/Gcamera-smooth/evidence; mkdir -p "$EV"
SECS="${SECS:-22}"
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

# left movement stick ~0.155W; hold a fixed up-left diagonal => Jak curves => circle.
drive_circle(){
  local secs="$1"
  local WM RA RB DW DH
  WM=$($ADB shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
  RA=${WM%x*}; RB=${WM#*x}
  if [ "${RA:-0}" -ge "${RB:-0}" ]; then DW=$RA; DH=$RB; else DW=$RB; DH=$RA; fi
  [ "${DW:-0}" -gt 0 ] || { DW=2400; DH=1080; }
  local AX AY BX BY
  AX=$(( DW * 155 / 1000 )); AY=$(( DH * 60 / 100 ))       # left-stick anchor
  BX=$(( AX - DW * 7 / 100 )); BY=$(( AY - DH * 22 / 100 )) # hold UP-LEFT => circle
  echo "  circle: anchor=($AX,$AY) hold=($BX,$BY) display=${DW}x${DH} ${secs}s"
  $ADB shell log -t opengoal-gk "GCAM-PAN-BEGIN" >/dev/null 2>&1 || true
  ( $ADB shell "input motionevent DOWN $AX $AY; input motionevent MOVE $BX $BY" >/dev/null 2>&1 || true
    local i=0
    while [ $i -lt $(( secs / 2 )) ]; do sleep 2; $ADB shell "input motionevent MOVE $BX $BY" >/dev/null 2>&1 || true; i=$((i+1)); done
    $ADB shell "input motionevent UP $BX $BY" >/dev/null 2>&1 || true ) &
  CPID=$!
}

run_side(){
  local val="$1" label="$2"; local LOG="$EV/$label.log"
  echo "=== caminterp=$val -> $label ==="
  $ADB shell setprop debug.opengoal.caminterp "$val" >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.pace.measure 1 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.gspeed.measure 0 >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.render.scale 100 >/dev/null 2>&1 || true
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  $ADB logcat -c >/dev/null 2>&1 || true
  : > "$LOG"
  ( $ADB logcat -v threadtime opengoal-gk:I GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE 'PACE-EE|PACE-SWAP|GCAM-|A35-RENDER frame=|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
  local LCP=$!
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0=$(date +%s) fm=0
  while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
    sleep 5; fm=$(maxframe "$LOG"); fm=${fm:-0}
    [ "$fm" -ge 600 ] && break
    grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null && { echo "CRASH"; break; }
  done
  echo "  gameplay frame=$fm; settle 10s then circle"
  sleep 10
  drive_circle "$SECS"; wait "${CPID:-0}" 2>/dev/null || true
  sleep 1; $ADB shell log -t opengoal-gk "GCAM-PAN-END" >/dev/null 2>&1 || true
  sleep 1; kill ${LCP:-0} 2>/dev/null || true; pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true
  $ADB shell setprop debug.opengoal.pace.measure 0 >/dev/null 2>&1 || true
  echo "  captured $LOG (PACE-EE=$(grep -ac PACE-EE "$LOG"))"
  python3 .autoport/gci_analyze.py "$LOG" pan 2>&1
}

run_side 0 gci4_before
run_side 1 gci4_after
echo "=== DONE ==="
