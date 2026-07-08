#!/usr/bin/env bash
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-ingame
PROP='17 collide-cache,sphere-hash,spatial-hash'
LOG="$DIR/taskc-routed-logcat.log"
FOC="$DIR/taskc-focus.txt"
: > "$FOC"; mkdir -p "$DIR"

inj(){ $ADB shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; echo "  inject '$1'" | tee -a "$FOC"; }
clr(){ $ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1; }
tap(){ inj "$1"; sleep "${2:-0.5}"; clr; }
cap(){ local n="$1" foc pid f; foc=$($ADB shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG 2>/dev/null|tr -d '\r'); echo "$foc"|grep -q org.opengoal.gk.jak2 && f=jak2focus || f=NOTJAK2; local o="$DIR/taskc-${n}-${f}.png"; $ADB exec-out screencap -p > "$o" 2>/dev/null; echo "  [$n] pid=[$pid] $foc -> ${o##*/} ($(stat -c %s "$o" 2>/dev/null||echo 0)B)"|tee -a "$FOC"; }

$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB shell svc power stayon true >/dev/null 2>&1
$ADB shell am force-stop $PKG; clr; sleep 2
$ADB shell "setprop debug.opengoal.jak2.noop_names '$PROP'"
echo "prop=[$($ADB shell getprop debug.opengoal.jak2.noop_names|tr -d '\r')]" | tee -a "$FOC"
$ADB logcat -G 16M >/dev/null 2>&1; $ADB logcat -c >/dev/null 2>&1
$ADB logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V opengoal-gk-d4:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$LOG" 2>&1 &
LP=$!; sleep 1
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "== warmup to title ==" | tee -a "$FOC"
sleep 60; cap 01-title
echo "== NEW GAME: START -> X -> down x4 -> X ==" | tee -a "$FOC"
tap start 1.2; sleep 3; cap 02-menu
tap x 1.0; sleep 2
tap down 0.4; tap down 0.4; tap down 0.4; tap down 0.4; sleep 1; cap 03-menu-nav
tap x 1.2; sleep 4; cap 04-after-x
echo "== let intro begin, then SKIP: START during cinematic ==" | tee -a "$FOC"
sleep 8; cap 05-intro
tap start 1.0; sleep 2; cap 06-skip1
tap x 0.8; sleep 2       # confirm skip dialog if any
tap start 1.0; sleep 2; cap 07-skip2
tap x 0.8; sleep 3; cap 08-skip3
echo "== wait for level load ==" | tee -a "$FOC"
sleep 20; cap 09-postload
echo "== start 40s gameplay recording (move+jump) ==" | tee -a "$FOC"
$ADB shell screenrecord --time-limit 40 /sdcard/taskc_gameplay.mp4 >/dev/null 2>&1 &
RP=$!
for i in 1 2 3 4; do
  inj up; sleep 2; clr
  inj x; sleep 0.6; clr        # jump
  inj left; sleep 1.5; clr
  inj right; sleep 1.5; clr
  cap "rec-$i"
done
wait $RP 2>/dev/null
cap 10-after-rec
$ADB pull /sdcard/taskc_gameplay.mp4 "$DIR/taskc_gameplay.mp4" >/dev/null 2>&1 && echo "  video: $DIR/taskc_gameplay.mp4 ($(stat -c %s "$DIR/taskc_gameplay.mp4" 2>/dev/null||echo 0)B)" | tee -a "$FOC"
sleep 2
echo "== final state ==" | tee -a "$FOC"
foc=$($ADB shell dumpsys window|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG|tr -d '\r')
echo "final pid=[$pid] focus=$foc" | tee -a "$FOC"
kill $LP 2>/dev/null
echo "LOG=$LOG"
