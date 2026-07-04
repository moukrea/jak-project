#!/usr/bin/env bash
# Gperf-particles round-4 FIRE-POSE in-session A/B. Robust to (1) the ~1/6 boot
# flake (retries boot) and (2) warp-settle camera variance (re-boots until the
# camera frames the Rock Village FIRE — objective gate: window-probe 2d-iter >=
# FIRE_MIN, i.e. braziers/bonfire in view, the heavy particle regime the phase
# targets). Then runs 4 pose-held windows in that boot:
#   A = ALL 7 switches 1 (fully OLD)   C = prior fixes ON, round-4 OFF (no2dvec=1)
#   B = ALL 7 switches 0 (ALL fixes)   A2 = revert ALL OLD
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gperf-particles/round4; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/fire-logcat.txt"; MK="$OUT/fire-markers.txt"
FIRE_MIN=330000
A(){ "$ADB" -s "$S" "$@"; }
SW=(nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec)
setall(){ for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$1" >/dev/null 2>&1; done; }
setlist(){ local d="$1"; shift; for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$d" >/dev/null 2>&1; done
  for kv in "$@"; do A shell setprop "debug.opengoal.perf.${kv%=*}" "${kv#*=}" >/dev/null 2>&1; done; }
now(){ date +%H:%M:%S; }
focus_ok(){ A shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|grep -q "$PKG"; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG"|grep -oE '[0-9]+$'|sort -n|tail -1; }
med2dit(){ python3 -c "
import re,statistics as st,sys
s,e=sys.argv[1],sys.argv[2]
L=open('$LOG',errors='replace').read().splitlines()
def t(l):
 m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)',l);return m.group(1) if m else None
it=[int(x) for ln in L if (t(ln) or '')>=s and (t(ln) or '')<=e for x in re.findall(r'2d=[\d.]+ms/\d+c/(\d+)it',ln)]
print(int(st.median(it)) if it else 0)
" "$1" "$2"; }
: > "$MK"
A shell svc power stayon true >/dev/null 2>&1||true; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
A shell dumpsys window 2>/dev/null|grep -q 'mDreamingLockscreen=true' && { echo PIN-LOCKED|tee "$OUT/FIRE-ABORT.txt"; exit 2; }

FIRE_OK=0
for boot in 1 2 3 4 5 6 7 8; do
  echo "=== boot attempt $boot ==="
  setall 0; A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
  A shell setprop debug.opengoal.level.warp village2-start >/dev/null 2>&1
  A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1
  A shell setprop debug.opengoal.spart.dump '""' >/dev/null 2>&1
  A shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 1
  A logcat -G 128M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1; : > "$LOG"
  pkill -f "logcat.*fire-logcat" 2>/dev/null||true
  A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
  LPID=$!
  A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
  CR=0; WP=0
  for i in $(seq 1 180); do
    grep -qa 'LEVEL-WARP-SPAWN name=village2-start' "$LOG" && { WP=1; break; }
    grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && { CR=1; break; }
    sleep 1
  done
  if [ "$CR" = 1 ] || [ "$WP" = 0 ]; then echo "  boot flake/crash (cr=$CR wp=$WP) -> retry"; kill $LPID 2>/dev/null; continue; fi
  echo "  warp fired; settle 30s"; sleep 30
  # pose probe 14s
  ps=$(now); sleep 14; pe=$(now)
  IT=$(med2dit "$ps" "$pe")
  A exec-out screencap -p > "$OUT/fire-pose-probe.png" 2>/dev/null||true
  echo "  pose-probe 2d_it median=$IT (fire needs >=$FIRE_MIN)"
  if [ "${IT:-0}" -ge "$FIRE_MIN" ]; then echo "  FIRE POSE confirmed"; FIRE_OK=1; break; fi
  echo "  light/rocky pose -> re-boot"; kill $LPID 2>/dev/null
done
if [ "$FIRE_OK" != 1 ]; then echo "could not reach fire pose in 8 boots"|tee "$OUT/FIRE-ABORT.txt"; kill ${LPID:-0} 2>/dev/null; exit 4; fi

trap 'kill $LPID 2>/dev/null; A shell setprop debug.opengoal.level.warp "\"\"" >/dev/null 2>&1' EXIT
A exec-out screencap -p > "$OUT/fire-A-pose.png" 2>/dev/null||true
run_win(){ local nm="$1" sec="$2"; echo "  [$nm] settle 16s"; sleep 16
  local s=$(now); echo "WINDOW_${nm}_START=$s"|tee -a "$MK"; echo "WINDOW_${nm}_SF=$(maxframe)">>"$MK"
  sleep "$sec"; local e=$(now); echo "WINDOW_${nm}_END=$e"|tee -a "$MK"; echo "WINDOW_${nm}_EF=$(maxframe)">>"$MK"
  focus_ok && echo "  [$nm] focus OK"||echo "  [$nm] !! focus NOT app"
  A exec-out screencap -p > "$OUT/fire-${nm}-end.png" 2>/dev/null||true; }
echo "== A: ALL OLD =="; setall 1; run_win A 90
echo "== C: prior fixes, round-4 OFF =="; setlist 0 no2dvec=1; run_win C 90
echo "== B: ALL FIX =="; A exec-out screencap -p > "$OUT/fire-B-pose.png" 2>/dev/null; setall 0; run_win B 90
echo "== A2: revert OLD =="; setall 1; run_win A2 55
setall 0; A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
kill $LPID 2>/dev/null; trap - EXIT
echo "DONE fire A/B"; cat "$MK"
