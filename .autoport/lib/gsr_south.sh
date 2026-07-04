#!/usr/bin/env bash
# gsr_south.sh — Gcrash-swamp-real: robust REAL-input southward drive (NO target.drive).
# Warp village2-dock, close task 33, then drive Jak SOUTH toward the swamp with a
# BEARING controller: hold left-stick forward, steer lx by the cross-product of
# actual-movement vs desired-direction (camera-follow safe, no matrix inversion),
# jump to hop/climb pontoons. Persistent: on endlessfall reset Jak returns to the
# dock and re-crosses the (load village2 swamp) boundary — MANY load/unload cycles,
# to trip a load-time race. Observes for crash throughout.
# Usage: gsr_south.sh <tag> [steps] [watch_past_s]
# Env: TGT_X=<raw> TGT_Z=<raw>  STEP_S=<s>  NOREPAIR=1  JUMP=1/0
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-south1}"; STEPS="${2:-90}"; WATCH_PAST="${3:-40}"
TGT_X="${TGT_X:-1842537}"; TGT_Z="${TGT_Z:--7333297}"; STEP_S="${STEP_S:-1.6}"; JUMP="${JUMP:-1}"
OUT=.autoport/reports/Gcrash-swamp-real; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/$TAG-logcat.log"; RES="$OUT/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > /data/data/$PKG/files/cpad_inject'" >/dev/null 2>&1 || true; }
pos(){ grep -a 'F1D target-pos' "$LOG" 2>/dev/null | tail -1 | sed -nE 's/.*=\(([-0-9.]+) ([-0-9.]+) ([-0-9.]+)\).*/\1 \3/p'; }
crash_seen(){ grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|enough stack|too much stack' "$LOG"; }
focus_is_app(){ A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PKG"; }

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true'; then echo "PIN-LOCKED" | tee "$RES"; exit 2; fi

echo "== $TAG: warp village2-dock + task33, bearing-drive SOUTH to ($TGT_X,$TGT_Z), $STEPS steps =="
A shell setprop debug.opengoal.level.warp village2-dock >/dev/null 2>&1
if [ -n "${POSM:-}" ]; then A shell "setprop debug.opengoal.level.warp.pos '$POSM'" >/dev/null 2>&1
else A shell setprop debug.opengoal.level.warp.pos '' >/dev/null 2>&1; fi
A shell "setprop debug.opengoal.task.close '33'" >/dev/null 2>&1
A shell setprop debug.opengoal.target.drive '""' >/dev/null 2>&1
A shell setprop debug.opengoal.diag.norepair '""' >/dev/null 2>&1
for p in f1.warp echo.intro mouche.fx die want.levels want.display want.vis; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done
inj ""
A shell am force-stop "$PKG" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true; : > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
cleanup(){ kill "$LOGPID" 2>/dev/null || true; inj ""
  for p in level.warp level.warp.pos task.close target.drive diag.norepair; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done; }
trap cleanup EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "  waiting title+spawn..."; WARP_OK=0
for i in $(seq 1 170); do grep -qa 'LEVEL-WARP-SPAWN name=village2-dock' "$LOG" && { WARP_OK=1; echo "  spawn ~${i}s"; break; }; crash_seen && break; sleep 1; done
grep -a 'TASK-CLOSE task=' "$LOG" | tail -1
sleep 6
if [ "$WARP_OK" = 1 ] && [ "${NOREPAIR:-0}" = 1 ] && ! crash_seen; then echo "  arming diag.norepair"; A shell setprop debug.opengoal.diag.norepair 1 >/dev/null 2>&1; fi

CROSS_CNT=0; PREV=""; SWAMP_SEEN=0
if [ "$WARP_OK" = 1 ] && ! crash_seen; then
  inj "ly=0"; sleep "$STEP_S"; PREV=$(pos)
  for step in $(seq 1 "$STEPS"); do
    crash_seen && break
    CUR=$(pos); [ -n "$CUR" ] || { sleep 1.2; continue; }
    if [ -z "$PREV" ]; then PREV="$CUR"; fi
    OUTP=$(python3 - "$PREV" "$CUR" "$TGT_X" "$TGT_Z" <<'EOF'
import sys, math
def v(s): p=s.split(); return (float(p[0]), float(p[1]))
prev,cur=v(sys.argv[1]),v(sys.argv[2]); tx,tz=float(sys.argv[3]),float(sys.argv[4])
mv=(cur[0]-prev[0], cur[1]-prev[1]); ds=(tx-cur[0], tz-cur[1])
nm=math.hypot(*mv); nd=math.hypot(*ds) or 1.0
# reached?
if nd < 40000: print("0 127 REACH"); sys.exit()
if nm < 1500:   # stuck: forward + hard steer + will jump
    print("0 190 STUCK"); sys.exit()
# cross product of movement vs desired: sign tells steer direction
cx = mv[0]*ds[1]-mv[1]*ds[0]
dot = (mv[0]*ds[0]+mv[1]*ds[1])/(nm*nd)
# steer magnitude grows as heading error grows
err = math.acos(max(-1,min(1,dot)))   # 0..pi
steer = min(110, int(err/math.pi*140))
lx = 127 + (steer if cx>0 else -steer)   # camera-relative; sign empirical, corrected by feedback
lx = max(0,min(255,lx))
ly = 0 if dot>0.2 else 40   # ease forward when turning hard
print(f"{ly} {lx} GO dot=%.2f"%dot)
EOF
)
    LY=$(echo "$OUTP" | awk '{print $1}'); LX=$(echo "$OUTP" | awk '{print $2}'); ST=$(echo "$OUTP" | awk '{print $3}')
    CZ=$(echo "$CUR" | awk '{print $2}')
    if grep -qa 'Adding level swamp' "$LOG" 2>/dev/null && [ "$SWAMP_SEEN" = 0 ]; then SWAMP_SEEN=1; CROSS_CNT=$((CROSS_CNT+1)); fi
    echo "  step$step pos=($CUR) $ST ly=$LY lx=$LX cross=$CROSS_CNT swamp=$SWAMP_SEEN"
    [ "$ST" = REACH ] && { echo "  REACHED"; inj ""; break; }
    if [ "$ST" = STUCK ]; then
      # unstick: rotate cycle of back-up+jump / camera-spin+forward / hard-steer+jump
      case $((step % 3)) in
        0) inj "ly=255 x";;
        1) inj "rx=255"; sleep 1.2; inj "ly=0 x";;
        2) inj "ly=0 lx=$LX x";;
      esac
    elif [ "$JUMP" = 1 ] && [ $((step % 2)) -eq 0 ]; then inj "ly=$LY lx=$LX x"; else inj "ly=$LY lx=$LX"; fi
    sleep "$STEP_S"
    # detect swamp unload (Jak reset north): recount crossings
    if [ "$SWAMP_SEEN" = 1 ] && ! grep -qa 'Adding level swamp' <(tail -c 4000 "$LOG") 2>/dev/null; then SWAMP_SEEN=0; fi
    PREV="$CUR"
  done
  inj ""
fi
echo "  observing ${WATCH_PAST}s..."; for i in $(seq 1 "$WATCH_PAST"); do crash_seen && { echo "  >>> CRASH ~${i}s"; break; }; sleep 1; done
sleep 1; A exec-out screencap -p > "$OUT/$TAG-end.png" 2>/dev/null || true
FOC="no"; focus_is_app && FOC="yes"; CR=0; crash_seen && CR=1
{
  echo "=== gsr_south $TAG $(date -Is) ==="
  echo "RESULT tag=$TAG crashed=$CR focus_app=$FOC load_crossings~$CROSS_CNT last=($(pos))"
  echo "--- sig ---"; grep -aoE 'Fatal signal [0-9]+ \(SIG[A-Z]+\)[^,]*|GK-DIAG sig=[0-9]+ fault=0x[0-9a-f]+ pc=0x[0-9a-f]+ lr=0x[0-9a-f]+' "$LOG" | tail -4
  echo "--- fp-walk/fn ---"; grep -aE 'A34-DIAG (fp-walk|pp\+|lr-)|BARERET-FORENSIC|nearest|goal-fn' "$LOG" | tail -16
  echo "--- adding-level counts ---"; grep -aoE 'Adding level swamp' "$LOG" | wc -l | sed 's/^/  swamp-adds=/'
  echo "--- display/vis ---"; grep -aoE 'display swamp|vis swa|swamp-vis' "$LOG" | sort | uniq -c
} | tee "$RES"
kill "$LOGPID" 2>/dev/null || true; trap - EXIT
for p in level.warp level.warp.pos task.close target.drive diag.norepair; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
echo "== $TAG done crashed=$CR crossings~$CROSS_CNT =="
