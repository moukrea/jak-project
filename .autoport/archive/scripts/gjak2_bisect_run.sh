#!/usr/bin/env bash
# Gjak2-ingame bisect run: set noop_names prop, launch jak2, watch for the
# title-disk-intro link finish + subsequent GK-DIAG SIGSEGV, classify CRASH/BOOTS.
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-ingame
mkdir -p "$DIR"

RUNNAME="$1"      # e.g. run0-cleared
PROP="$2"         # value for debug.opengoal.jak2.noop_names ("" to clear)
WATCH="${3:-150}" # seconds to watch after launch
LOG="$DIR/bisect-${RUNNAME}-routed-logcat.log"

# kill any leftover runner (stale trailing force-stop kills next run)
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB shell svc power stayon true >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1
sleep 2

# set the bisect prop
if [ -z "$PROP" ]; then
  $ADB shell setprop debug.opengoal.jak2.noop_names '""' >/dev/null 2>&1
else
  $ADB shell "setprop debug.opengoal.jak2.noop_names '$PROP'" >/dev/null 2>&1
fi
GOT=$($ADB shell getprop debug.opengoal.jak2.noop_names | tr -d '\r')
echo "=== $RUNNAME  prop_set='$PROP'  getprop='$GOT'  $(date) ==="

$ADB logcat -G 16M >/dev/null 2>&1 || true
$ADB logcat -c >/dev/null 2>&1 || true
$ADB logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V opengoal-gk-d4:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$LOG" 2>&1 &
LOGPID=$!
sleep 1
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1

# watch loop: stop early if we see title-disk-intro then a crash, or after WATCH
SAW_TITLE=0; SAW_CRASH=0; elapsed=0
while [ $elapsed -lt $WATCH ]; do
  sleep 5; elapsed=$((elapsed+5))
  if grep -aq 'link finish: title-disk-intro' "$LOG" 2>/dev/null; then SAW_TITLE=1; fi
  if grep -aqE 'GK-DIAG|Fatal signal|sig=11|sig=6|SIGSEGV|SIGABRT' "$LOG" 2>/dev/null; then SAW_CRASH=1; fi
  pid=$($ADB shell pidof $PKG 2>/dev/null | tr -d '\r')
  if [ $SAW_CRASH -eq 1 ]; then echo "  crash signature seen at ~${elapsed}s"; sleep 3; break; fi
  if [ $SAW_TITLE -eq 1 ] && [ $elapsed -ge 90 ] && [ -n "$pid" ]; then
    echo "  title-disk-intro linked + alive at ${elapsed}s (pid=$pid)"; # keep watching a bit more
  fi
done
sleep 2
kill $LOGPID 2>/dev/null

# verdict
foc=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
pid=$($ADB shell pidof $PKG 2>/dev/null | tr -d '\r')
echo "  final: pid=[$pid]  focus=$foc"
echo "  --- key log lines ---"
grep -aE 'link finish: title-disk-intro|GK-DIAG|Fatal signal|GJ2ING mips2c noop-exclude|A37-MIPS2C-FALLBACK' "$LOG" 2>/dev/null | grep -aoE '(link finish: title-disk-intro|GK-DIAG.*|Fatal signal.*|GJ2ING mips2c noop-exclude:.*|A37-MIPS2C-FALLBACK.*)' | sort -u | head -30
FBCOUNT=$(grep -ac 'A37-MIPS2C-FALLBACK' "$LOG" 2>/dev/null)
echo "  FALLBACK-count=$FBCOUNT"
grep -aq 'parking-spot::find-ground' "$LOG" 2>/dev/null && echo "  parking-spot::find-ground: PRESENT" || echo "  parking-spot::find-ground: absent"
if [ -n "$pid" ] && [ $SAW_CRASH -eq 0 ]; then
  echo "  VERDICT: BOOTS (alive, pid=$pid, no crash sig)"
else
  echo "  VERDICT: CRASH (SAW_CRASH=$SAW_CRASH pid=[$pid])"
fi
echo "  LOG: $LOG"
