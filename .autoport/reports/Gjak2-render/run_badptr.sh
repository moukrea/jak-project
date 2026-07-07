#!/usr/bin/env bash
# Gjak2-render JAK2-BADPTR run harness (diagnostic only). Runs the jak2 boot N
# times, capturing GK_STDERR/STDOUT + crash channels to per-run logs.
set -u
source /home/emeric/code/jak-project/.autoport/lib/android-env.sh 2>/dev/null
DEV=eae4df44
PKG=org.opengoal.gk.jak2
ACT="$PKG/org.opengoal.gk.LoaderActivity"
OUTDIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-render
WAIT=120

run_once() {
  local n=$1
  local log="$OUTDIR/jak2-badptr-run${n}.log"
  echo "===== RUN $n -> $log ====="
  adb -s $DEV shell am force-stop "$PKG" 2>/dev/null
  adb -s $DEV shell input keyevent KEYCODE_WAKEUP 2>/dev/null
  sleep 2
  adb -s $DEV logcat -c 2>/dev/null
  # background logcat capture
  adb -s $DEV logcat GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V \
      AndroidRuntime:E libc:F DEBUG:F '*:S' > "$log" 2>&1 &
  local lcpid=$!
  sleep 1
  adb -s $DEV shell am start -n "$ACT" 2>&1 | tr -d '\r'
  # wait the boot window
  local waited=0
  while [ $waited -lt $WAIT ]; do
    sleep 5
    waited=$((waited+5))
  done
  # capture focus at end
  echo "----FOCUS-AT-END----" >> "$log"
  adb -s $DEV shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus|mFocusedApp" | tr -d '\r' >> "$log"
  kill $lcpid 2>/dev/null
  wait $lcpid 2>/dev/null
  adb -s $DEV shell am force-stop "$PKG" 2>/dev/null
  echo "----- run $n done ($(wc -l < "$log") log lines) -----"
}

for i in 1 2 3 4 5 6; do
  run_once $i
done
echo "ALL RUNS COMPLETE"
