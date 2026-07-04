#!/usr/bin/env bash
# Gperf-particles round-4 NIGHT headline A/B (owner clue: slowdown worse at night,
# TOD passes are the suspect). Pins the clock to night (hour=23, frozen), Rock
# Village fire zone, held pose. Headline = NIGHT-OLD -> NIGHT-ALL-FIX. Also isolates
# the TOD memoize (window C) and takes a DAY-OLD reference (night-vs-day evidence).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gperf-particles/round4; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
A(){ "$ADB" -s "$S" "$@"; }
SW=(nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec notodskip)
setall(){ for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$1" >/dev/null 2>&1; done; }
setlist(){ local d="$1"; shift; for s in "${SW[@]}"; do A shell setprop "debug.opengoal.perf.$s" "$d" >/dev/null 2>&1; done
  for kv in "$@"; do A shell setprop "debug.opengoal.perf.${kv%=*}" "${kv#*=}" >/dev/null 2>&1; done; }
now(){ date +%H:%M:%S; }
focus_ok(){ A shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|grep -q "$PKG"; }
A shell svc power stayon true >/dev/null 2>&1||true; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true

# boot with a pinned hour; returns 0 on warp; sets LOG/LP globals
boot_scene(){ # boot_scene <hour> <logfile>
  local HOUR="$1" LOG="$2"
  setall 0; A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
  A shell setprop debug.opengoal.tod.hour "$HOUR" >/dev/null 2>&1
  A shell setprop debug.opengoal.level.warp village2-start >/dev/null 2>&1
  for b in 1 2 3 4 5 6; do
    A shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 1
    A logcat -G 128M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1; : > "$LOG"
    pkill -f "logcat.*$(basename "$LOG" .txt)" 2>/dev/null||true
    A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
    LP=$!; A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
    local WP=0
    for i in $(seq 1 170); do
      grep -qa 'LEVEL-WARP-SPAWN name=village2-start' "$LOG" && { WP=1; break; }
      grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && break
      sleep 1
    done
    [ "$WP" = 1 ] && return 0
    echo "  boot $b flake -> retry"; kill $LP 2>/dev/null
  done
  return 1
}
mfps(){ python3 -c "
import re,statistics as st,sys
s,e=sys.argv[2],sys.argv[3]
L=open(sys.argv[1],errors='replace').read().splitlines()
def t(l):
 m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)',l);return m.group(1) if m else None
fps=[];rm=[];idle=[];tx=[];sc=[]
for ln in L:
 if not (s<=(t(ln) or '')<=e): continue
 m=re.search(r'avg-fps=([\d.]+) scale=(\d+)%',ln)
 if m and 'dyn-rs] state' in ln: fps.append(float(m.group(1)));sc.append(int(m.group(2)))
 m=re.search(r'render_ms=([\d.]+)',ln)
 if m and 'A35-RENDER' in ln: rm.append(float(m.group(1)))
 g=re.search(r'goal idle=([\d.]+)',ln); idle.append(float(g.group(1))) if g else None
 x=re.search(r' ts=([\d.]+)',ln); tx.append(float(x.group(1))) if x else None
def md(x): return round(st.median(x),2) if x else None
print(f'fps={md(fps)} (min {round(min(fps),1) if fps else 0}) scale={sorted(set(sc))} render_ms={md(rm)} goal_idle={md(idle)} tie_ts={md(tx)}')
" "$1" "$2" "$3"; }

# ---------- NIGHT boot + 4-window A/B ----------
NLOG="$OUT/night-logcat.txt"; NMK="$OUT/night-markers.txt"; : > "$NMK"
if ! boot_scene 23 "$NLOG"; then echo "NIGHT no-boot"|tee "$OUT/NIGHT-ABORT.txt"; exit 4; fi
echo "night warp ok; pin: $(grep -a 'TOD-PIN hour=23' "$NLOG" | tail -1)"
sleep 30
A exec-out screencap -p > "$OUT/night-pose.png" 2>/dev/null||true
run(){ local nm="$1" sec="$2"; sleep 16; local s=$(now); sleep "$sec"; local e=$(now)
  echo "WINDOW_${nm} $s $e -> $(mfps "$NLOG" "$s" "$e")" | tee -a "$NMK"
  focus_ok && echo "  [$nm] focus OK"||echo "  [$nm] focus NOT app"
  A exec-out screencap -p > "$OUT/night-${nm}.png" 2>/dev/null||true; }
echo "== NIGHT A: all OLD =="; setall 1; run A 80
echo "== NIGHT C: TOD-memoize only (notodskip=0) =="; setlist 1 notodskip=0; run C 80
echo "== NIGHT B: all FIX =="; setall 0; run B 80
echo "== NIGHT A2: revert =="; setall 1; run A2 50
kill $LP 2>/dev/null

# ---------- DAY reference (all OLD) for night-vs-day ----------
DLOG="$OUT/day-logcat.txt"
if boot_scene 12 "$DLOG"; then
  echo "day warp ok; pin: $(grep -a 'TOD-PIN hour=12' "$DLOG" | tail -1)"
  sleep 30; A exec-out screencap -p > "$OUT/day-pose.png" 2>/dev/null||true
  setall 1; sleep 16; ds=$(now); sleep 70; de=$(now)
  echo "WINDOW_DAY_OLD $ds $de -> $(mfps "$DLOG" "$ds" "$de")" | tee -a "$NMK"
  kill $LP 2>/dev/null
else echo "DAY no-boot" | tee -a "$NMK"; fi

setall 0; A shell setprop debug.opengoal.tod.hour '""' >/dev/null 2>&1
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
echo "DONE"; echo "=== markers ==="; cat "$NMK"
