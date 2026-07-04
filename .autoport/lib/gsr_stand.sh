#!/usr/bin/env bash
# gsr_stand.sh — Gcrash-swamp-real diagnostic: warp village2-dock, optional pos override,
# close task 33 (raise pontoons), then STAND STILL (no cpad input) and log Jak's Y for
# OBS seconds to determine if the pontoon under the spawn is SOLID (Y stays near deck
# ~543 raw / 0.13 m) or NOT (Y falls to water ~ -5000..-8000). No target.drive.
# Usage: gsr_stand.sh <tag> "<posm x y z | empty>" [obs_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-stand1}"; POSM="${2-}"; OBS="${3:-30}"
OUT=.autoport/reports/Gcrash-swamp-real; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/$TAG-logcat.log"; RES="$OUT/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
posln(){ grep -a 'F1D target-pos' "$LOG" 2>/dev/null | tail -1 | sed -nE 's/.*=\(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\).*/x=\1 y=\2 z=\3/p'; }
crash_seen(){ grep -qaE 'Fatal signal|GK-DIAG sig=(4|6|11)' "$LOG"; }

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell setprop debug.opengoal.level.warp village2-dock >/dev/null 2>&1
if [ -n "$POSM" ]; then A shell "setprop debug.opengoal.level.warp.pos '$POSM'" >/dev/null 2>&1
else A shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1; fi
A shell "setprop debug.opengoal.task.close '33'" >/dev/null 2>&1
# make sure no stale input is held and no drive hook armed
A shell "run-as $PKG sh -c 'printf \"\" > /data/data/$PKG/files/cpad_inject'" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.target.drive '""' >/dev/null 2>&1 || true

A shell am force-stop "$PKG" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true; : > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
cleanup(){ kill "$LOGPID" 2>/dev/null || true
  for p in level.warp level.warp.pos task.close; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done; }
trap cleanup EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "  waiting title+warp (posm='$POSM')..."
for i in $(seq 1 160); do grep -qa "LEVEL-WARP-SPAWN name=village2-dock" "$LOG" && { echo "  warp ~${i}s"; break; }; crash_seen && break; sleep 1; done
grep -a 'LEVEL-WARP-POS\|TASK-CLOSE task=' "$LOG" | tail -2
echo "  standing still, logging Y for ${OBS}s (NO input)..."
for i in $(seq 1 "$OBS"); do
  P=$(posln); [ -n "$P" ] && echo "  t=${i}s $P"
  crash_seen && { echo "  CRASH while standing ~${i}s"; break; }
  sleep 1
done
A exec-out screencap -p > "$OUT/$TAG-end.png" 2>/dev/null || true
{
  echo "=== gsr_stand $TAG posm='$POSM' $(date -Is) ==="
  echo "--- Y trace (raw; deck~543=0.13m, water~ -5000..-8000) ---"
  grep -a 'F1D target-pos' "$LOG" | sed -nE 's/.*f=([0-9]+).*=\(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\).*/f=\1 x=\2 y=\3 z=\4/p' | tail -25
  echo "--- crash ---"; grep -aE 'GK-DIAG sig=|Fatal signal [0-9]' "$LOG" | tail -3
} | tee "$RES"
kill "$LOGPID" 2>/dev/null || true; trap - EXIT
for p in level.warp level.warp.pos task.close; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
echo "== $TAG done =="
