#!/usr/bin/env bash
# Probe a level's warp safety + fire-regime fps/particle load, held pose (no input).
# Usage: probe_level.sh <continue-name> <tag>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CONT="${1:?continue}"; TAG="${2:?tag}"
OUT=.autoport/reports/Gperf-particles/round4; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/lvl-$TAG-logcat.txt"
A(){ "$ADB" -s "$S" "$@"; }
A shell svc power stayon true >/dev/null 2>&1||true; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true' && { echo PIN-LOCKED; exit 2; }
# fixes ON, perf dump on, warp
for s in nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec; do A shell setprop "debug.opengoal.perf.$s" 0 >/dev/null 2>&1; done
A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1
A shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
A shell am force-stop "$PKG" >/dev/null 2>&1||true
A logcat -G 128M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LPID=$!; trap 'kill $LPID 2>/dev/null; A shell setprop debug.opengoal.level.warp "\"\"" >/dev/null' EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
echo "[$TAG] warm+warp $CONT (<=180s)"
OK=0
for i in $(seq 1 180); do
  grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { echo "  warp fired ~${i}s"; OK=1; break; }
  grep -qa "LEVEL-WARP-FAIL name=$CONT" "$LOG" && { echo "  WARP-FAIL (continue not found)"; break; }
  grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && { echo "  CRASH pre-warp ~${i}s"; break; }
  sleep 1
done
[ "$OK" = 1 ] || { echo "[$TAG] NO WARP -> abort"; exit 3; }
echo "  settle+hold 45s (no input)"; sleep 45
CR=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|SIGSEGV|SIGILL' "$LOG")
FOC=no; A shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|grep -q "$PKG" && FOC=yes
A exec-out screencap -p > "$OUT/lvl-$TAG.png" 2>/dev/null||true
echo "[$TAG] crash_lines=$CR focus=$FOC screenshot=$OUT/lvl-$TAG.png"
kill $LPID 2>/dev/null; trap - EXIT
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
echo "[$TAG] logcat=$LOG"
