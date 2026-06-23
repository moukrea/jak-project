#!/usr/bin/env bash
# Gcrash-geyser interactive: launch + warp to Geyser Rock, leave the app RUNNING
# (no force-stop) with logcat capturing to a file, so the scene can be driven
# interactively via gcrash_drive.sh (inject cpad + screencap). Assumes the fresh
# HEAD libgk is already deployed (run a gcrash_run.sh first, or pass DEPLOY=1).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
PACKAGE=org.opengoal.gk.jak1; ACTIVITY=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"; export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
OUT=.autoport/reports/Gcrash-geyser; mkdir -p "$OUT"
LOG="$OUT/hold-logcat.log"
INJECT="/data/data/$PACKAGE/files/cpad_inject"
A(){ "$ADB" -s "$SERIAL" "$@"; }

pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true
device_require_attached; device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked
A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp   1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.fly.collect 0 >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
printf '' | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
nohup "$ADB" -s "$SERIAL" logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
echo $! > /tmp/gcrash-hold-logcat.pid
A shell am start -W -n "$PACKAGE/$ACTIVITY" >/dev/null 2>&1 || true
echo "  warming to title..."; for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && break; sleep 1; done
echo "  warp + training load..."; OK=0
for i in $(seq 1 110); do grep -qaE "Adding level training|link finish: training-vis" "$LOG" && { OK=1; echo "  training loaded ~$((i*3))s"; break; }; sleep 3; done
[ "$OK" = 1 ] || { echo "FAIL: training never loaded"; exit 1; }
echo "  settle 20s..."; sleep 20
echo "HELD: app running + warped. logcat -> $LOG  (drive via gcrash_drive.sh)"
