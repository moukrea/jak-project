#!/usr/bin/env bash
# grv_run.sh — Gcrash-rockvillage repro driver.
# Replicates the owner route state: village2 resident (warp continue village2-dock =
# village2+rolling want-set) with Jak placed on the swamp-side shore just NORTH of the
# buzzer crate (crate-3131 @ raw 1778057,9285,-7187726), then DRIVES Jak south across
# the (load village2 swamp) boundary (z ~ -7196k at that x) so SWA.DGO streams in while
# walking — the exact transition the owner hit. Steering is closed-loop off the F1D
# target-pos logcat telemetry (printed every 15 frames): two calibration holds give the
# stick->world 2x2 map, then waypoint steering.
# Usage: grv_run.sh <tag> [watch_past_s] [pos_override_m]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-repro1}"
WATCH_PAST="${2:-45}"
POSM="${3-434.1 3.5 -1750}"   # pass explicit "" as $3 for no pos override
CONT="${CONT:-village2-dock}"
# WAYPOINTS: semicolon list "x,z;x,z;..." — steer to each in order (advance when within 25k).
WAYPOINTS="${WAYPOINTS:-1778057,-7187726;1842537,-7333297}"
# STOP_MARKER: grep -aE pattern; when it appears in logcat, release stick and go observe.
STOP_MARKER="${STOP_MARKER:-}"
# REACH_Z: consider route complete when z below this.
REACH_Z="${REACH_Z:--7310000}"
MAX_STEPS="${MAX_STEPS:-30}"
OUT=.autoport/reports/Gcrash-rockvillage
mkdir -p "$OUT"
PACKAGE=org.opengoal.gk.jak1
ACTIVITY=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/$TAG-logcat.log"
RES="$OUT/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > /data/data/$PACKAGE/files/cpad_inject'" >/dev/null 2>&1 || true; }
pos(){ grep -a 'F1D target-pos' "$LOG" 2>/dev/null | tail -1 | sed -nE 's/.*=\(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\).*/\1 \3/p'; }
crash_seen(){ grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|enough stack|too much stack' "$LOG"; }
focus_is_app(){ A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true'; then
  echo "PIN-LOCKED: needs owner unlock" | tee "$RES"; exit 2
fi

echo "== $TAG: warp $CONT pos=($POSM)m, drive south across (load village2 swamp) =="
A shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
if [ -n "$POSM" ]; then
  A shell "setprop debug.opengoal.level.warp.pos '$POSM'" >/dev/null 2>&1
else
  A shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
fi
for p in f1.warp echo.intro mouche.fx mouche.buzz die eco.trace; do
  A shell setprop debug.opengoal.$p 0 >/dev/null 2>&1 || true; done
# TASK_CLOSE env: "<task>[:<status>][,...]" e.g. 33 = village2-warrior-money (pontoons)
A shell "setprop debug.opengoal.task.close '${TASK_CLOSE:-}'" >/dev/null 2>&1 || true

A shell am force-stop "$PACKAGE" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
cleanup(){ kill "$LOGPID" 2>/dev/null || true
  A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.task.close '""' >/dev/null 2>&1 || true; }
trap cleanup EXIT
A shell am start -W -n "$PACKAGE/$ACTIVITY" >/dev/null 2>&1

echo "  waiting title..."
for i in $(seq 1 150); do grep -qa 'link finish: logo' "$LOG" && break; crash_seen && break; sleep 1; done
echo "  waiting LEVEL-WARP-SPAWN..."
WARP_OK=0
for i in $(seq 1 90); do
  grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { WARP_OK=1; echo "  warp fired ~${i}s"; break; }
  grep -qa "LEVEL-WARP-FAIL name=$CONT" "$LOG" && { echo "  warp FAILED"; break; }
  crash_seen && { echo "  crash before warp"; break; }
  sleep 1
done
grep -a 'LEVEL-WARP-POS' "$LOG" | tail -1
if [ -n "${TASK_CLOSE:-}" ]; then
  for i in $(seq 1 30); do grep -qa 'TASK-CLOSE task=' "$LOG" && break; sleep 1; done
  grep -a 'TASK-CLOSE' "$LOG" | tail -3
fi
sleep 8

DROVE=0; REACHED=0
if [ "$WARP_OK" = 1 ] && ! crash_seen; then
  # --- calibrate: hold forward 2.5s, then right 2.5s, measure world deltas ---
  P0=$(pos); inj "ly=0"; sleep 2.5; P1=$(pos)
  inj "lx=255"; sleep 2.5; P2=$(pos); inj ""
  echo "  calib p0=($P0) p1=($P1) p2=($P2)"
  # --- waypoint drive ---
  WPIDX=0
  for step in $(seq 1 "$MAX_STEPS"); do
    crash_seen && break
    if [ -n "$STOP_MARKER" ] && grep -qaE "$STOP_MARKER" "$LOG"; then
      REACHED=1; echo "  STOP-MARKER '$STOP_MARKER' seen — releasing stick"; break
    fi
    CUR=$(pos); [ -n "$CUR" ] || { sleep 2; continue; }
    CZ=$(echo "$CUR" | awk '{print $2}')
    if awk "BEGIN{exit !($CZ < $REACH_Z)}"; then REACHED=1; echo "  REACHED z=$CZ (< $REACH_Z)"; break; fi
    OUTP=$(python3 - "$P0" "$P1" "$P2" "$CUR" "$WAYPOINTS" "$WPIDX" <<'EOF'
import sys, math
def v(s): p=s.split(); return (float(p[0]), float(p[1]))
p0,p1,p2,cur=(v(x) for x in sys.argv[1:5])
wps=[tuple(map(float,w.split(','))) for w in sys.argv[5].split(';') if w]
idx=int(sys.argv[6])
while idx < len(wps)-1 and math.hypot(wps[idx][0]-cur[0], wps[idx][1]-cur[1]) < 25000:
    idx += 1
tgt=wps[min(idx,len(wps)-1)]
m1=(p1[0]-p0[0], p1[1]-p0[1])       # response to stick (0,-1) fwd
m2=(p2[0]-p1[0], p2[1]-p1[1])       # response to stick (1,0) right
d=(tgt[0]-cur[0], tgt[1]-cur[1])
n=math.hypot(*d) or 1.0; d=(d[0]/n, d[1]/n)
det=m1[0]*m2[1]-m1[1]*m2[0]
if abs(det)<1e-3:
    print(f"0 127 {idx}"); sys.exit()   # calib degenerate: hold fwd
a=(d[0]*m2[1]-d[1]*m2[0])/det          # fwd amount
b=(m1[0]*d[1]-m1[1]*d[0])/det          # right amount
n=math.hypot(a,b) or 1.0; a,b=a/n,b/n
ly=max(0,min(255,int(round(127-a*127)))); lx=max(0,min(255,int(round(127+b*127))))
print(f"{ly} {lx} {idx}")
EOF
)
    LY=$(echo "$OUTP" | awk '{print $1}'); LX=$(echo "$OUTP" | awk '{print $2}'); WPIDX=$(echo "$OUTP" | awk '{print $3}')
    echo "  step$step pos=($CUR) wp=$WPIDX stick ly=$LY lx=$LX"
    inj "lx=$LX ly=$LY"
    sleep 3
    DROVE=1
    if [ $((step % 5)) -eq 0 ]; then   # recalibrate: camera frame drifts as Jak turns
      P0=$(pos); inj "ly=0"; sleep 2; P1=$(pos); inj "lx=255"; sleep 2; P2=$(pos)
      echo "  recalib p0=($P0) p1=($P1) p2=($P2)"
    fi
  done
  inj ""
fi

echo "  observing ${WATCH_PAST}s past drive..."
for i in $(seq 1 "$WATCH_PAST"); do crash_seen && { echo "  >>> CRASH ~${i}s into observe"; break; }; sleep 1; done
sleep 1
A exec-out screencap -p > "$OUT/$TAG-end.png" 2>/dev/null || true

FOC="no"; focus_is_app && FOC="yes"
SIG=$(grep -aoE 'Fatal signal [0-9]+ \(SIG[A-Z]+\)[^,]*|GK-DIAG sig=[0-9]+ fault=0x[0-9a-f]+|enough stack|too much stack' "$LOG" | tail -2 | tr '\n' ';')
GKD=$(grep -aE 'GK-DIAG sig=' "$LOG" | tail -3 | tr '\n' ';')
A34=$(grep -aE 'A34-DIAG (fp-walk|pp\+|lr-)' "$LOG" | tail -10 | tr '\n' ';')
ADDLEV=$(grep -aoE 'Adding level [a-z0-9-]+' "$LOG" | tail -6 | tr '\n' ';')
LINKS=$(grep -aoE 'link finish: [a-z0-9-]+' "$LOG" | tail -8 | tr '\n' ' ')
LASTPOS=$(pos)
CR=0; crash_seen && CR=1
STATUS=UNKNOWN
if [ "$CR" = 1 ]; then STATUS="CRASH"; elif [ "$REACHED" = 1 ]; then STATUS="ROUTE-COMPLETE-NO-CRASH"
elif [ "$DROVE" = 1 ]; then STATUS="DROVE-INCOMPLETE"; else STATUS="NO-DRIVE"; fi
{
  echo "=== grv_run $TAG (cont=$CONT posm=$POSM) $(date -Is) ==="
  echo "RESULT tag=$TAG status=$STATUS reached_past=$REACHED crashed=$CR focus_app=$FOC"
  echo "  last-pos(x z)=$LASTPOS"
  echo "  sig=${SIG:-none}"
  echo "  gk-diag: ${GKD:-none}"
  echo "  fp-walk: ${A34:-none}"
  echo "  adding-level: ${ADDLEV:-none}"
  echo "  links: ${LINKS:-none}"
} | tee "$RES"
kill "$LOGPID" 2>/dev/null || true
trap - EXIT
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
A shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
echo "== $TAG done: $STATUS =="
