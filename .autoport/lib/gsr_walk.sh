#!/usr/bin/env bash
# gsr_walk.sh — Gcrash-swamp-real FAITHFUL real-input walk (NO target.drive).
# Warp continue village2-dock (owner level set), close task 33 (raise pontoons),
# optional one-time spawn placement on a pontoon (level.warp.pos, NOT per-frame forcing),
# then RIDE/swim SOUTH-EAST across the (load village2 swamp) + display + vis boundaries
# using REAL cpad analog input (left stick + periodic X jump), closed-loop off the F1D
# target-pos telemetry, until the swamp loads/displays and it crashes.
# Usage: gsr_walk.sh <tag> [watch_past_s] ["posm x y z"|empty]
# Env: WAYPOINTS="x,z;..."  REACH_Z=<raw>  MAX_STEPS=<n>  JUMP=1(default)/0
#      NOREPAIR=1 (arm debug.opengoal.diag.norepair AFTER spawn so the TRUE first
#      swamp crash reaches the fatal forensic dump)  STEP_S=<seconds per hold>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-walk1}"; WATCH_PAST="${2:-45}"; POSM="${3-}"
CONT=village2-dock
# Pontoon chain (cluster B) -> swamp shore -> swamp-start. Raw x,z.
WAYPOINTS="${WAYPOINTS:-1664683,-7070614;1774171,-7067836;1780935,-7132758;1842537,-7333297;1850000,-7360000}"
REACH_Z="${REACH_Z:--7300000}"
MAX_STEPS="${MAX_STEPS:-50}"
JUMP="${JUMP:-1}"
STEP_S="${STEP_S:-2.0}"
OUT=.autoport/reports/Gcrash-swamp-real; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/$TAG-logcat.log"; RES="$OUT/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > /data/data/$PKG/files/cpad_inject'" >/dev/null 2>&1 || true; }
pos(){ grep -a 'F1D target-pos' "$LOG" 2>/dev/null | tail -1 | sed -nE 's/.*=\(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\).*/\1 \3/p'; }
posy(){ grep -a 'F1D target-pos' "$LOG" 2>/dev/null | tail -1 | sed -nE 's/.*=\(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\).*/\2/p'; }
crash_seen(){ grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|enough stack|too much stack' "$LOG"; }
focus_is_app(){ A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PKG"; }
stable_wait(){ local A B AX AZ BX BZ i
  for i in $(seq 1 12); do A=$(pos); sleep 1.2; B=$(pos)
    { [ -n "$A" ] && [ -n "$B" ]; } || continue
    read -r AX AZ <<<"$A"; read -r BX BZ <<<"$B"
    awk "BEGIN{dx=($AX)-($BX); dz=($AZ)-($BZ); exit !(dx*dx+dz*dz < 9000000)}" && { echo "$B"; return 0; }
  done; pos; }
calibrate(){ local c CV
  for c in 1 2 3; do
    P0=$(stable_wait); inj "ly=0"; sleep 2.2; P1=$(pos); inj "lx=255"; sleep 2.2; P2=$(pos); inj ""
    CV=$(python3 - "$P0" "$P1" "$P2" <<'PYEOF'
import sys,math
def v(s): p=s.split(); return (float(p[0]),float(p[1]))
p0,p1,p2=(v(x) for x in sys.argv[1:4])
m1=(p1[0]-p0[0],p1[1]-p0[1]); m2=(p2[0]-p1[0],p2[1]-p1[1])
n1,n2=math.hypot(*m1),math.hypot(*m2)
ok = 1200<n1<50000 and 1200<n2<50000 and abs(m1[0]*m2[1]-m1[1]*m2[0])/(n1*n2) > 0.30
print("ok" if ok else "bad")
PYEOF
)
    echo "  calib#$c p0=($P0) p1=($P1) p2=($P2) -> $CV"
    [ "$CV" = ok ] && return 0; sleep 1.5
  done; return 1; }

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true'; then
  echo "PIN-LOCKED: needs owner unlock" | tee "$RES"; exit 2; fi

echo "== $TAG: warp $CONT posm='$POSM' task33, REAL-input ride SE across swamp boundaries =="
A shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
if [ -n "$POSM" ]; then A shell "setprop debug.opengoal.level.warp.pos '$POSM'" >/dev/null 2>&1
else A shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1; fi
A shell "setprop debug.opengoal.task.close '33'" >/dev/null 2>&1
A shell setprop debug.opengoal.target.drive '""' >/dev/null 2>&1
A shell setprop debug.opengoal.diag.norepair '""' >/dev/null 2>&1
for p in f1.warp echo.intro mouche.fx die eco.trace want.levels want.display want.vis; do
  A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done
inj ""

A shell am force-stop "$PKG" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true; : > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
cleanup(){ kill "$LOGPID" 2>/dev/null || true; inj ""
  for p in level.warp level.warp.pos task.close target.drive diag.norepair; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done; }
trap cleanup EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1

echo "  waiting title..."; for i in $(seq 1 160); do grep -qa 'link finish: logo' "$LOG" && break; crash_seen && break; sleep 1; done
echo "  waiting spawn..."; WARP_OK=0
for i in $(seq 1 90); do
  grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { WARP_OK=1; echo "  spawn ~${i}s"; break; }
  grep -qa "LEVEL-WARP-FAIL" "$LOG" && { echo "  warp FAILED"; break; }
  crash_seen && { echo "  crash before spawn"; break; }
  sleep 1
done
grep -a 'LEVEL-WARP-POS\|TASK-CLOSE task=' "$LOG" | tail -2
sleep 6
if [ "$WARP_OK" = 1 ] && [ "${NOREPAIR:-0}" = 1 ] && ! crash_seen; then
  echo "  arming diag.norepair (first-fault forensics)"; A shell setprop debug.opengoal.diag.norepair 1 >/dev/null 2>&1; fi

DROVE=0; REACHED=0
if [ "$WARP_OK" = 1 ] && ! crash_seen; then
  calibrate || echo "  calib not validated — driving with last probe"
  SPAWNP="$P0"; PLY=0; PLX=127; WPIDX=0
  for step in $(seq 1 "$MAX_STEPS"); do
    crash_seen && break
    CUR=$(pos); [ -n "$CUR" ] || { sleep 1.5; continue; }
    CZ=$(echo "$CUR" | awk '{print $2}'); CY=$(posy)
    if awk "BEGIN{exit !($CZ < $REACH_Z)}"; then REACHED=1; echo "  REACHED z=$CZ"; break; fi
    OUTP=$(python3 - "$P0" "$P1" "$P2" "$CUR" "$WAYPOINTS" "$PLY" "$PLX" "$WPIDX" "$SPAWNP" <<'EOF'
import sys, math
def v(s): p=s.split(); return (float(p[0]), float(p[1]))
p0,p1,p2,cur=(v(x) for x in sys.argv[1:5])
wps=[tuple(map(float,w.split(','))) for w in sys.argv[5].split(';') if w]
ply,plx=int(sys.argv[6]),int(sys.argv[7]); idx=int(sys.argv[8]); spawn=v(sys.argv[9])
while idx < len(wps):
    wp=wps[idx]; anchor = wps[idx-1] if idx>0 else spawn
    ax,az=cur[0]-wp[0], cur[1]-wp[1]; bx,bz=wp[0]-anchor[0], wp[1]-anchor[1]
    if math.hypot(ax,az) < 32000 or ax*bx+az*bz > 0: idx += 1
    else: break
tgt=wps[min(idx,len(wps)-1)]
m1=(p1[0]-p0[0], p1[1]-p0[1]); m2=(p2[0]-p1[0], p2[1]-p1[1])
n1,n2=math.hypot(*m1),math.hypot(*m2); det=m1[0]*m2[1]-m1[1]*m2[0]
if n1<1200 or n1>50000 or n2<1200 or n2>50000 or abs(det)/(max(n1,1)*max(n2,1))<0.30:
    print(f"{ply} {plx} {idx} D"); sys.exit()
d=(tgt[0]-cur[0], tgt[1]-cur[1]); n=math.hypot(*d) or 1.0; d=(d[0]/n, d[1]/n)
a=(d[0]*m2[1]-d[1]*m2[0])/det; b=(m1[0]*d[1]-m1[1]*d[0])/det
n=math.hypot(a,b) or 1.0; a,b=a/n,b/n
ly=max(0,min(255,int(round(127-a*127)))); lx=max(0,min(255,int(round(127+b*127))))
print(f"{ly} {lx} {idx} K")
EOF
)
    LY=$(echo "$OUTP" | awk '{print $1}'); LX=$(echo "$OUTP" | awk '{print $2}'); WPIDX=$(echo "$OUTP" | awk '{print $3}'); FLAG=$(echo "$OUTP" | awk '{print $4}')
    echo "  step$step pos=($CUR) y=$CY wp=$WPIDX stick ly=$LY lx=$LX $FLAG"
    if [ "$FLAG" = "D" ] && [ "${CALIB_ONCE:-0}" != 1 ]; then inj ""; calibrate || true; DROVE=1; continue; fi
    # jump every 2nd step to hop pontoon gaps / clamber the shore
    if [ "$JUMP" = 1 ] && [ $((step % 2)) -eq 0 ]; then inj "lx=$LX ly=$LY x"; else inj "lx=$LX ly=$LY"; fi
    sleep "$STEP_S"; DROVE=1; PLY=$LY; PLX=$LX
    if [ "${CALIB_ONCE:-0}" != 1 ] && [ $((step % 7)) -eq 0 ]; then inj ""; calibrate || true; fi
  done
  inj ""
fi

echo "  observing ${WATCH_PAST}s..."; for i in $(seq 1 "$WATCH_PAST"); do crash_seen && { echo "  >>> CRASH ~${i}s"; break; }; sleep 1; done
sleep 1
A exec-out screencap -p > "$OUT/$TAG-end.png" 2>/dev/null || true
FOC="no"; focus_is_app && FOC="yes"; CR=0; crash_seen && CR=1
STATUS=UNKNOWN
if [ "$CR" = 1 ]; then STATUS=CRASH; elif [ "$REACHED" = 1 ]; then STATUS=REACHED-NO-CRASH
elif [ "$DROVE" = 1 ]; then STATUS=DROVE-INCOMPLETE; else STATUS=NO-DRIVE; fi
{
  echo "=== gsr_walk $TAG (posm='$POSM') $(date -Is) ==="
  echo "RESULT tag=$TAG status=$STATUS reached=$REACHED crashed=$CR focus_app=$FOC last=($(pos))"
  echo "--- sig ---"; grep -aoE 'Fatal signal [0-9]+ \(SIG[A-Z]+\)[^,]*|GK-DIAG sig=[0-9]+ fault=0x[0-9a-f]+ pc=0x[0-9a-f]+ lr=0x[0-9a-f]+' "$LOG" | tail -4
  echo "--- fp-walk / nearest fn ---"; grep -aE 'A34-DIAG (fp-walk|pp\+|lr-)|nearest|goal-fn|BARERET-FORENSIC' "$LOG" | tail -18
  echo "--- adding-level ---"; grep -aoE 'Adding level [a-z0-9-]+' "$LOG" | sort -u | tr '\n' ' '; echo
  echo "--- swamp links ---"; grep -aoE 'link finish: swamp[a-z0-9-]*|link finish: (kermit|sharkey|swamp-vis)' "$LOG" | tail -6 | tr '\n' ' '; echo
  echo "--- display/vis ---"; grep -aoE 'display swamp|vis swa|swamp-vis' "$LOG" | sort -u | tr '\n' ' '; echo
} | tee "$RES"
kill "$LOGPID" 2>/dev/null || true; trap - EXIT
for p in level.warp level.warp.pos task.close target.drive diag.norepair; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
echo "== $TAG done: $STATUS =="
