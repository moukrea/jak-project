#!/usr/bin/env bash
# Gperf-particles round-4 PARTICLE-HEAVY A/B via mandate-sanctioned eco-spawn.
# Rock Village (fire zone). Accumulate a dense eco particle load, STOP spawning,
# verify the load is STATIONARY (pickups persist), then run a pose-held in-session
# A/B at that fixed heavy load. Boot-retry for the ~1/6 flake.
#   A = ALL 7 switches 1 (OLD)   B = ALL 7 switches 0 (ALL fixes)   A2 = revert OLD
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gperf-particles/round4; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/eco-logcat.txt"; MK="$OUT/eco-markers.txt"
A(){ "$ADB" -s "$S" "$@"; }
SW=(nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec)
setall(){ for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$1" >/dev/null 2>&1; done; }
now(){ date +%H:%M:%S; }
focus_ok(){ A shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|grep -q "$PKG"; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG"|grep -oE '[0-9]+$'|sort -n|tail -1; }
m2d(){ python3 -c "
import re,statistics as st,sys
s,e=sys.argv[1],sys.argv[2]
L=open('$LOG',errors='replace').read().splitlines()
def t(l):
 m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)',l);return m.group(1) if m else None
it=[int(x) for ln in L if s<=(t(ln) or '')<=e for x in re.findall(r'2d=[\d.]+ms/\d+c/(\d+)it',ln)]
print(int(st.median(it)) if it else 0)
" "$1" "$2"; }
: > "$MK"
A shell svc power stayon true >/dev/null 2>&1||true; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
A shell dumpsys window 2>/dev/null|grep -q 'mDreamingLockscreen=true' && { echo PIN-LOCKED|tee "$OUT/ECO-ABORT.txt"; exit 2; }

# ---- boot (retry flake) ----
BOK=0
for boot in 1 2 3 4 5 6; do
  echo "=== boot $boot ==="
  setall 0; A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
  A shell setprop debug.opengoal.level.warp village2-start >/dev/null 2>&1
  A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1
  A shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 1
  A logcat -G 160M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1; : > "$LOG"
  pkill -f "logcat.*eco-logcat" 2>/dev/null||true
  A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
  LPID=$!; A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
  CR=0; WP=0
  for i in $(seq 1 180); do
    grep -qa 'LEVEL-WARP-SPAWN name=village2-start' "$LOG" && { WP=1; break; }
    grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && { CR=1; break; }
    sleep 1
  done
  [ "$WP" = 1 ] && { BOK=1; break; }
  echo "  flake (cr=$CR) -> retry"; kill $LPID 2>/dev/null
done
[ "$BOK" = 1 ] || { echo "no boot in 6"|tee "$OUT/ECO-ABORT.txt"; exit 4; }
trap 'kill $LPID 2>/dev/null; A shell setprop debug.opengoal.eco.spawn "\"\"" >/dev/null 2>&1; A shell setprop debug.opengoal.level.warp "\"\"" >/dev/null 2>&1' EXIT
echo "warp ok; settle 20s"; sleep 20

# ---- accumulate dense eco, then STOP ----
echo "eco-spawn dense 55s (accumulate)"; A shell setprop debug.opengoal.eco.spawn '2 31 0 3 0' >/dev/null 2>&1; sleep 55
echo "STOP eco-spawn; hold"; A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1; sleep 6
A exec-out screencap -p > "$OUT/eco-pose.png" 2>/dev/null||true

# ---- stationarity check (4 x 10s samples after stop) ----
echo "stationarity check"
declare -a ST
for k in 1 2 3 4; do s=$(now); sleep 10; e=$(now); v=$(m2d "$s" "$e"); ST[$k]=$v; echo "  sample$k 2d_it=$v" | tee -a "$MK"; done
MINV=${ST[1]}; MAXV=${ST[1]}
for k in 2 3 4; do (( ST[$k] < MINV )) && MINV=${ST[$k]}; (( ST[$k] > MAXV )) && MAXV=${ST[$k]}; done
echo "STATIONARITY min=$MINV max=$MAXV" | tee -a "$MK"
# require load heavy (>=340k) and stable (max-min <= 12% of max)
if [ "${MAXV:-0}" -lt 340000 ]; then echo "load too light ($MAXV)"|tee "$OUT/ECO-ABORT.txt"; exit 5; fi
SPREAD=$(( (MAXV-MINV)*100 / (MAXV>0?MAXV:1) ))
echo "spread=${SPREAD}%" | tee -a "$MK"
if [ "$SPREAD" -gt 15 ]; then echo "NON-STATIONARY spread ${SPREAD}%"|tee "$OUT/ECO-ABORT.txt"; exit 6; fi

# ---- A/B at fixed heavy load ----
run_win(){ local nm="$1" sec="$2"; sleep 14
  local s=$(now); echo "WINDOW_${nm}_START=$s"|tee -a "$MK"; echo "WINDOW_${nm}_SF=$(maxframe)">>"$MK"
  sleep "$sec"; local e=$(now); echo "WINDOW_${nm}_END=$e"|tee -a "$MK"; echo "WINDOW_${nm}_EF=$(maxframe)">>"$MK"
  echo "WINDOW_${nm}_2DIT=$(m2d "$s" "$e")">>"$MK"
  focus_ok && echo "  [$nm] focus OK"||echo "  [$nm] !! focus NOT app"
  A exec-out screencap -p > "$OUT/eco-${nm}-end.png" 2>/dev/null||true; }
echo "== A OLD =="; setall 1; run_win A 75
echo "== B FIX =="; A exec-out screencap -p > "$OUT/eco-B-pose.png" 2>/dev/null; setall 0; run_win B 75
echo "== A2 revert =="; setall 1; run_win A2 55
setall 0; A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1; A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
kill $LPID 2>/dev/null; trap - EXIT
echo "DONE eco-heavy A/B"; cat "$MK"
