#!/usr/bin/env bash
# dbg_drive.sh — supervisor debug harness: warp + DRIVE Jak/camera + capture.
# Usage: dbg_drive.sh <tag> [hour] [relief] [displacement] [extra_props...]
set -uo pipefail
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=org.opengoal.gk.MainActivity
ADB="$HOME/Android/platform-tools/adb"
TAG="${1:-dbg}"; HOUR="${2:-12}"; RELIEF="${3:-1.5}"; DISP="${4:-1}"
OUT=/tmp/dbg_drive; mkdir -p "$OUT"
A(){ "$ADB" -s $S "$@"; }
INJ="/data/data/$PKG/files/cpad_inject"
inject(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJ'" >/dev/null 2>&1; }
hold(){ inject "$1"; sleep "${2:-1.0}"; inject ""; sleep 0.3; }
shot(){ A exec-out screencap -p > "$OUT/${TAG}_$1.png" 2>/dev/null; echo "  shot $1: $(stat -c%s "$OUT/${TAG}_$1.png" 2>/dev/null)"; }
A shell am force-stop $PKG >/dev/null 2>&1; sleep 2
inject ""
A shell setprop debug.opengoal.level.warp village1-hut >/dev/null 2>&1
A shell "setprop debug.opengoal.level.warp.pos '-112.0 42.0 205.0'" >/dev/null 2>&1
A shell setprop debug.opengoal.tod.hour "$HOUR" >/dev/null 2>&1
A shell "setprop debug.opengoal.tod.fast ''" >/dev/null 2>&1
A shell setprop debug.opengoal.pbr.relief "$RELIEF" >/dev/null 2>&1
A shell setprop debug.opengoal.pbr.displacement "$DISP" >/dev/null 2>&1
shift 4 2>/dev/null || true
for kv in "$@"; do A shell "setprop ${kv%%=*} ${kv#*=}" >/dev/null 2>&1; done
LOG="$OUT/${TAG}_lc.txt"; : > "$LOG"
( timeout 200 A logcat -v threadtime GK_STDOUT:I opengoal-gk:I '*:S' | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|A35-RENDER frame=' >> "$LOG" ) & LCP=$!
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
ok=0; t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 130 ]; do
  grep -aq 'LEVEL-WARP-SPAWN' "$LOG" && { ok=1; break; }; sleep 3
done
kill $LCP 2>/dev/null
echo "[dbg] spawn=$ok"
sleep 36   # past ND logo into gameplay
shot 00_spawn
echo "[dbg] drive: avance 2s"
hold "ly=40" 2.0
shot 01_moved
echo "[dbg] camera: pivote"
hold "rx=210" 1.2
shot 02_cam
