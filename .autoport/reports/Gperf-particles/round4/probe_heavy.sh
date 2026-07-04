#!/usr/bin/env bash
# Probe: does a heavier particle regime (natural fire vs fire+eco-spawn density)
# give a robust >=20% old->fix ratio in Rock Village? Measures particle load
# (A35-SPART 2d it) and fps for 4 short windows in ONE boot.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gperf-particles/round4
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/probe-logcat.txt"; MK="$OUT/probe-markers.txt"
A(){ "$ADB" -s "$S" "$@"; }
SW=(nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec)
setall(){ for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$1" >/dev/null 2>&1; done; }
now(){ date +%H:%M:%S; }
: > "$MK"
A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true' && { echo PIN-LOCKED|tee "$OUT/PROBE-ABORT.txt"; exit 2; }

setall 0
A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
A shell setprop debug.opengoal.level.warp village2-start >/dev/null 2>&1
A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
A logcat -G 128M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LPID=$!; trap 'kill $LPID 2>/dev/null; A shell setprop debug.opengoal.eco.spawn "\"\"" >/dev/null; A shell setprop debug.opengoal.level.warp "\"\"" >/dev/null' EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "warm+warp (<=180s)"; for i in $(seq 1 180); do grep -qa 'LEVEL-WARP-SPAWN name=village2-start' "$LOG" && break; sleep 1; done
grep -qa 'LEVEL-WARP-SPAWN name=village2-start' "$LOG" || { echo NO-WARP|tee "$OUT/PROBE-ABORT.txt"; exit 3; }
sleep 25
win(){ local nm="$1" sec="$2"; sleep 12; echo "W_${nm}_START=$(now)"|tee -a "$MK"; sleep "$sec"; echo "W_${nm}_END=$(now)"|tee -a "$MK"; }

echo "== NAT-OLD =="; setall 1; A shell setprop debug.opengoal.eco.spawn '""' >/dev/null; win NATOLD 40
echo "== NAT-FIX =="; setall 0; win NATFIX 40
echo "== turn ON dense eco-spawn, let it accumulate 25s =="; A shell setprop debug.opengoal.eco.spawn '2 31 0 3 0' >/dev/null; sleep 25
echo "== ECO-OLD =="; setall 1; win ECOOLD 40
echo "== ECO-FIX =="; setall 0; win ECOFIX 40
A shell setprop debug.opengoal.eco.spawn '""' >/dev/null; setall 0
kill $LPID 2>/dev/null; trap - EXIT
echo "DONE"; cat "$MK"
