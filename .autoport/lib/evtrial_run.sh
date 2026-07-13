#!/usr/bin/env bash
# evtrial_run.sh — Phase Gjak1-intermittent-events single-trial driver.
# Warps to a continue point with the EVTRIAL actor-state telemetry probe armed
# and (per <arm>) either the arm64 bug-class-#14 icache flush ON (fixed) or the
# no-op-flush pre-fix behavior restored (stale). Both arms run the SAME binary
# (no mixed builds — the grass A/B lesson): the difference is a runtime prop.
# After a warp + watch window it runs evtrial_analyze.py and emits a single
# machine-parseable EVTRIAL-RESULT line.
# Usage: evtrial_run.sh <tag> <arm:flush|noflush> <cont> [posm] [watch_s]
# Env:   EVFILTER (default empty)  CRITERIA (default empty)
#        OUT_DIR (default .autoport/reports/Gjak1-intermittent-events)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-ev1}"
ARM="${2:-flush}"
CONT="${3:-village1}"
POSM="${4-}"                 # pass "" for no pos override
WATCH_S="${5:-50}"
EVFILTER="${EVFILTER:-}"
CRITERIA="${CRITERIA:-}"
OUT_DIR="${OUT_DIR:-.autoport/reports/Gjak1-intermittent-events}"
mkdir -p "$OUT_DIR"
PACKAGE=org.opengoal.gk.jak1
ACTIVITY=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT_DIR/$TAG-logcat.log"
RES="$OUT_DIR/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
crash_seen(){ grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|enough stack|too much stack' "$LOG"; }
focus_is_app(){ A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }

case "$ARM" in flush|noflush) ;; *) echo "bad arm '$ARM' (flush|noflush)"; exit 3;; esac

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if A shell dumpsys window 2>/dev/null | grep -q 'mDreamingLockscreen=true'; then
  echo "PIN-LOCKED: needs owner unlock" | tee "$RES"; exit 2
fi

echo "== $TAG: arm=$ARM warp=$CONT pos=($POSM) filter='$EVFILTER' =="
A shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
if [ -n "$POSM" ]; then
  A shell "setprop debug.opengoal.level.warp.pos '$POSM'" >/dev/null 2>&1
else
  A shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
fi
# arm the EVTRIAL probe + filter
A shell setprop debug.opengoal.evtrial 1 >/dev/null 2>&1
A shell "setprop debug.opengoal.evtrial.filter '$EVFILTER'" >/dev/null 2>&1
# A/B arm: noflush = restore pre-fix stale-icache behavior; flush = fixed.
if [ "$ARM" = noflush ]; then
  A shell setprop debug.opengoal.icache.noflush 1 >/dev/null 2>&1
else
  A shell setprop debug.opengoal.icache.noflush 0 >/dev/null 2>&1
fi
# zero the other grv props so a prior driver's state can't bleed in.
for p in f1.warp echo.intro mouche.fx die eco.trace mouche.buzz task.close \
         want.levels want.display want.vis eco.spawn; do
  A shell setprop debug.opengoal.$p 0 >/dev/null 2>&1 || true; done

A shell am force-stop "$PACKAGE" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
stop_logger(){
  # LOGPID is the backgrounded subshell running the A() function; killing it
  # orphans the adb child which keeps appending to this trial's log across
  # later trials (round-A contamination). Kill the adb logcat child too.
  pkill -P "$LOGPID" 2>/dev/null || true
  kill "$LOGPID" 2>/dev/null || true
  pkill -f "adb -s $SERIAL logcat" 2>/dev/null || true
}
cleanup(){ stop_logger
  A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.evtrial 0 >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.evtrial.filter '""' >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.icache.noflush 0 >/dev/null 2>&1 || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
A shell am start -W -n "$PACKAGE/$ACTIVITY" >/dev/null 2>&1

echo "  waiting title..."
for i in $(seq 1 150); do grep -qa 'link finish: logo' "$LOG" && break; crash_seen && break; sleep 1; done
echo "  waiting LEVEL-WARP-SPAWN..."
WARP_OK=0; WARP_FAIL=0
for i in $(seq 1 90); do
  grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { WARP_OK=1; echo "  warp fired ~${i}s"; break; }
  grep -qa "LEVEL-WARP-FAIL name=$CONT" "$LOG" && { WARP_FAIL=1; echo "  warp FAILED"; break; }
  crash_seen && { echo "  crash before warp"; break; }
  sleep 1
done

# --- status classification ---
STATUS=UNKNOWN
if crash_seen && [ "$WARP_OK" = 0 ]; then
  STATUS=BOOT-CRASH
elif [ "$WARP_FAIL" = 1 ]; then
  STATUS=WARP-FAIL
else
  echo "  observing ${WATCH_S}s post-spawn..."
  POST_CRASH=0
  for i in $(seq 1 "$WATCH_S"); do
    crash_seen && { POST_CRASH=1; echo "  >>> CRASH ~${i}s into observe"; break; }
    sleep 1
  done
  if [ "$POST_CRASH" = 1 ]; then STATUS=POST-SPAWN-CRASH; else STATUS=OK; fi
fi

# --- ARM INTEGRITY CHECK (mandatory: prove the arm actually took effect) ---
ARMCHECK=OK
if [ "$ARM" = noflush ]; then
  grep -qa 'ICACHE-NOFLUSH armed' "$LOG" || ARMCHECK=BAD
else
  grep -qa 'ICACHE-NOFLUSH armed' "$LOG" && ARMCHECK=BAD
fi

sleep 1
A exec-out screencap -p > "$OUT_DIR/$TAG-end.png" 2>/dev/null || true
FOC="no"; focus_is_app && FOC="yes"

echo "  --- evtrial_analyze ---"
python3 .autoport/lib/evtrial_analyze.py "$LOG" ${CRITERIA:+--criteria "$CRITERIA"} \
  | tee "$OUT_DIR/$TAG-analysis.txt"

if [ -n "$CRITERIA" ]; then
  FIRED=$(grep -aoE 'VERDICT fired=[0-9]+/[0-9]+' "$OUT_DIR/$TAG-analysis.txt" | tail -1 | sed -E 's/VERDICT fired=//')
  [ -n "$FIRED" ] || FIRED=na
else
  FIRED=na
fi

RESLINE="EVTRIAL-RESULT tag=$TAG arm=$ARM cont=$CONT status=$STATUS armcheck=$ARMCHECK focus=$FOC fired=$FIRED"
echo "$RESLINE" | tee "$RES"

trap - EXIT
cleanup
echo "== $TAG done: $STATUS (arm=$ARMCHECK) =="
