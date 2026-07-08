#!/usr/bin/env bash
# Gjak2-ingame: reproduce+capture the jak2 "Two years later" intro->prison
# scene-transition crash on the CURRENTLY DEPLOYED build. NO install/rebuild.
# Property-inject (debug.opengoal.cpad_inject) drives NEW GAME -> intro cinematic.
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-ingame
RUN="${1:-1}"
LOG="$DIR/twoyears-repro-run${RUN}-routed-logcat.log"
FOCUSLOG="$DIR/twoyears-repro-run${RUN}-focus.txt"
mkdir -p "$DIR"
: > "$FOCUSLOG"

inj()  { $ADB -s $S shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; echo "    inject: '$1'" | tee -a "$FOCUSLOG"; }
clr()  { $ADB -s $S shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1; }

cap() {  # cap <name>
  local name="$1" foc pid f
  foc=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
  pid=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
  if echo "$foc" | grep -q "org.opengoal.gk.jak2"; then f=jak2focus; else f=NOTJAK2; fi
  local out="$DIR/twoyears-run${RUN}-${name}-${f}.png"
  $ADB -s $S exec-out screencap -p > "$out" 2>/dev/null
  echo "  [$name] pid=[$pid] $foc -> ${out##*/} ($(stat -c %s "$out" 2>/dev/null||echo 0)B)" | tee -a "$FOCUSLOG"
}

echo "=== Gjak2-ingame twoyears RUN ${RUN} start $(date) ==="
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB -s $S shell svc power stayon true >/dev/null 2>&1
$ADB -s $S shell am force-stop $PKG
clr
sleep 2
$ADB -s $S logcat -G 16M 2>/dev/null || true
$ADB -s $S logcat -c 2>/dev/null || true
# routed logcat: full detail, keep running the whole time
$ADB -s $S logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V opengoal-gk-d4:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$LOG" 2>&1 &
LOGPID=$!
sleep 1
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1

echo "== stage 1: boot/title warmup (jak2 unpack already done; title flythrough) =="
sleep 55
cap "01-title"

echo "== stage 2: START -> progress menu =="
inj "start"; sleep 1.2; clr; sleep 4
cap "02-menu"

echo "== stage 3: X -> NEW GAME (top entry) =="
inj "x"; sleep 0.6; clr; sleep 3
cap "03-after-newgame-x"

echo "== stage 4: navigate save/continue screen (down x4 -> continue w/o saving) then X =="
for i in 1 2 3 4; do inj "down"; sleep 0.4; clr; sleep 0.8; done
cap "04-continue-sel"
inj "x"; sleep 0.6; clr; sleep 5
cap "05-newgame-start"

# mark the confirm offset
CONFIRM_OFS=$(wc -l < "$LOG" 2>/dev/null || echo 0)
echo "   post-newgame log offset: $CONFIRM_OFS"

echo "== stage 5: intro cinematic window (~6-8 min); watch for crash =="
NG_T0=$(date +%s)
CRASHED=0
for t in $(seq 1 24); do
  sleep 30
  el=$(( $(date +%s) - NG_T0 ))
  cap "06-cine-t${el}s"
  pid=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
  # crash signature
  if grep -aqE 'Fatal signal (11|6|4|7)|signal (11|6|4|7) \(SIG|GK-DIAG sig=(11|6|4|7)|A34-|fp-walk|lr-window' "$LOG" 2>/dev/null; then
    echo "  >>> [t=${el}s] CRASH SIGNATURE detected in log" | tee -a "$FOCUSLOG"
    CRASHED=1
  fi
  if [ -z "$pid" ]; then
    echo "  >>> [t=${el}s] app PID gone (process died)" | tee -a "$FOCUSLOG"
    CRASHED=1
  fi
  echo "  t=${el}s pid=[${pid:-DEAD}] crashed=$CRASHED"
  # once crashed, keep logcat running 90s more past death then stop
  if [ "$CRASHED" = 1 ]; then
    echo "  >>> holding logcat 90s past death for full crash dump" | tee -a "$FOCUSLOG"
    sleep 90
    cap "07-postcrash"
    break
  fi
done

echo "== teardown =="
sleep 3
cap "08-final"
kill $LOGPID >/dev/null 2>&1; wait $LOGPID 2>/dev/null
$ADB -s $S shell svc power stayon true >/dev/null 2>&1
echo "=== RUN ${RUN} done $(date); log lines: $(wc -l < "$LOG") crashed=$CRASHED ==="
echo "LOG: $LOG"
