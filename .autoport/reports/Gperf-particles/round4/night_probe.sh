#!/usr/bin/env bash
# Validate the night-pin hook + measure NIGHT vs DAY in Rock Village (owner clue:
# slowdown worse at night). Two boots (night hour=23, day hour=12), held pose,
# all fixes ON. Reports fps / render_ms / goal-idle / tie_interp / tie_texsub so
# I can see (a) does the hook pin night (dark frame + TOD-PIN log), (b) is night
# heavier (lower fps, higher render_ms), (c) is the GL thread critical at night.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gperf-particles/round4; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
A(){ "$ADB" -s "$S" "$@"; }
now(){ date +%H:%M:%S; }
A shell svc power stayon true >/dev/null 2>&1||true; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true

probe(){ # probe <hour> <tag>
  local HOUR="$1" TAG="$2"
  local LOG="$OUT/np-$TAG-logcat.txt"
  for s in nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec notodskip; do A shell setprop "debug.opengoal.perf.$s" 0 >/dev/null 2>&1; done
  A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
  A shell setprop debug.opengoal.tod.hour "$HOUR" >/dev/null 2>&1
  A shell setprop debug.opengoal.level.warp village2-start >/dev/null 2>&1
  for boot in 1 2 3 4; do
    A shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 1
    A logcat -G 96M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1; : > "$LOG"
    pkill -f "logcat.*np-$TAG" 2>/dev/null||true
    A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
    local LP=$!; A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
    local WP=0
    for i in $(seq 1 160); do
      grep -qa 'LEVEL-WARP-SPAWN name=village2-start' "$LOG" && { WP=1; break; }
      grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && break
      sleep 1
    done
    [ "$WP" = 1 ] && break
    echo "  [$TAG] boot flake -> retry"; kill $LP 2>/dev/null
  done
  sleep 30
  A exec-out screencap -p > "$OUT/np-$TAG.png" 2>/dev/null||true
  local s=$(now); sleep 40; local e=$(now)
  kill $LP 2>/dev/null
  echo "=== $TAG (hour=$HOUR) ==="
  echo "  TOD-PIN: $(grep -a 'TOD-PIN' "$LOG" | tail -1)"
  python3 -c "
import re,statistics as st
L=open('$LOG',errors='replace').read().splitlines()
def t(l):
 m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)',l);return m.group(1) if m else None
fps=[];rm=[];idle=[];ti=[];tx=[];sc=[]
for ln in L:
 if not ('$s'<=(t(ln) or '')<='$e'): continue
 m=re.search(r'avg-fps=([\d.]+) scale=(\d+)%',ln)
 if m and 'dyn-rs] state' in ln: fps.append(float(m.group(1)));sc.append(int(m.group(2)))
 m=re.search(r'render_ms=([\d.]+)',ln)
 if m and 'A35-RENDER' in ln: rm.append(float(m.group(1)))
 g=re.search(r'goal idle=([\d.]+)',ln)
 if g: idle.append(float(g.group(1)))
 a=re.search(r'tie i=([\d.]+) ts=([\d.]+)',ln)
 if a: ti.append(float(a.group(1)));tx.append(float(a.group(2)))
def md(x): return round(st.median(x),2) if x else None
print(f'  fps median={md(fps)} min={round(min(fps),1) if fps else None} scales={sorted(set(sc))}')
print(f'  render_ms median={md(rm)}  goal_idle median={md(idle)}')
print(f'  tie interp(i) median={md(ti)}  tie texsub(ts) median={md(tx)}  (per 60fr ms)')
"
}
probe 12 DAY
probe 23 NIGHT
# leave clean
A shell setprop debug.opengoal.tod.hour '""' >/dev/null 2>&1
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
echo DONE
