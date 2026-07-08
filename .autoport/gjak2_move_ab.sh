#!/usr/bin/env bash
# Gjak2-movement A/B: force-enable (method 9/10 collide-cache-prim) via prop
# (NO rebuild — bisect run16b/final-culprit proved this config boots clean),
# then drive ANALOG stick movement and an idle window to test:
#   glued?  -> does Jak translate on ly/lx deflection
#   drift?  -> does Jak move during the cleared-input idle window
# Usage: gjak2_move_ab.sh <run-tag> [enable_prop]
#   enable_prop default 'collide-cache-prim' (matches methods 9+10 ONLY;
#   '(method 17 collide-cache)' does NOT contain this substring).
#   Pass '' to run the control leg (shipped default, expect glued+drift).
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
TAG="${1:?run tag}"
ENABLE="${2-collide-cache-prim}"
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-movement
LOG="$DIR/${TAG}-routed-logcat.log"
FOC="$DIR/${TAG}-focus.txt"
mkdir -p "$DIR"; : > "$FOC"

inj(){ $ADB shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; echo "  inject '$1' t=$(date +%H:%M:%S)" | tee -a "$FOC"; }
clr(){ $ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1; }
cleanup(){ clr; $ADB shell setprop debug.opengoal.jak2.enable_names '""' >/dev/null 2>&1; }
trap 'cleanup' EXIT INT TERM  # level-triggered inject MUST be cleared on ANY exit
tap(){ inj "$1"; sleep "${2:-0.5}"; clr; }
cap(){ local n="$1" foc pid f; foc=$($ADB shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG 2>/dev/null|tr -d '\r'); echo "$foc"|grep -q org.opengoal.gk.jak2 && f=jak2focus || f=NOTJAK2; local o="$DIR/${TAG}-${n}-${f}.png"; $ADB exec-out screencap -p > "$o" 2>/dev/null; echo "  [$n] pid=[$pid] $foc -> ${o##*/} ($(stat -c %s "$o" 2>/dev/null||echo 0)B)"|tee -a "$FOC"; }

# preflight: no leftover drivers (device-run overlap kill)
LEFT=$(pgrep -af 'gjak2_|f1d_run|gtf_|capture_device' | grep -v $$ | grep -v grep || true)
[ -n "$LEFT" ] && { echo "LEFTOVER RUNNERS — aborting:"; echo "$LEFT"; exit 3; }

$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB shell svc power stayon true >/dev/null 2>&1
$ADB shell am force-stop $PKG; clr; sleep 2
# A/B prop: force-enable BEFORE launch (static init reads it at first mips2c registration)
$ADB shell setprop debug.opengoal.jak2.noop_names '""'
if [ -n "$ENABLE" ]; then $ADB shell "setprop debug.opengoal.jak2.enable_names '$ENABLE'"; else $ADB shell setprop debug.opengoal.jak2.enable_names '""'; fi
echo "enable_names=[$($ADB shell getprop debug.opengoal.jak2.enable_names|tr -d '\r')] noop_names=[$($ADB shell getprop debug.opengoal.jak2.noop_names|tr -d '\r')]" | tee -a "$FOC"
$ADB logcat -G 16M >/dev/null 2>&1; $ADB logcat -c >/dev/null 2>&1
$ADB logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V opengoal-gk-d4:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$LOG" 2>&1 &
LP=$!; sleep 1
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "== warmup to title ==" | tee -a "$FOC"
sleep 60; cap 01-title
# boot-crash check before proceeding
if ! $ADB shell pidof $PKG >/dev/null 2>&1; then echo "APP DEAD AT TITLE — boot crash. See $LOG" | tee -a "$FOC"; kill $LP 2>/dev/null; exit 4; fi
echo "== NEW GAME: START -> X -> down x4 -> X (taskc-proven nav) ==" | tee -a "$FOC"
tap start 1.2; sleep 3; cap 02-menu
tap x 1.0; sleep 2
tap down 0.4; tap down 0.4; tap down 0.4; tap down 0.4; sleep 1; cap 03-menu-nav
tap x 1.2; sleep 4; cap 04-after-x
echo "== intro begins, SKIP ==" | tee -a "$FOC"
sleep 8; cap 05-intro
tap start 1.0; sleep 2; cap 06-skip1
tap x 0.8; sleep 2
tap start 1.0; sleep 2; cap 07-skip2
tap x 0.8; sleep 3; cap 08-skip3
echo "== wait for level load ==" | tee -a "$FOC"
sleep 20; cap 09-postload
if ! $ADB shell pidof $PKG >/dev/null 2>&1; then echo "APP DEAD POSTLOAD — see $LOG" | tee -a "$FOC"; kill $LP 2>/dev/null; exit 5; fi
echo "== 100s movement recording: analog walk 4 dirs + jumps + 15s idle ==" | tee -a "$FOC"
$ADB shell screenrecord --time-limit 100 /sdcard/gj2move_${TAG}.mp4 >/dev/null 2>&1 &
RP=$!
sleep 2; cap move-00-baseline
inj "ly=0";   sleep 6; clr; sleep 1; cap move-01-fwd      # forward 6s
inj "lx=0";   sleep 5; clr; sleep 1; cap move-02-left     # left 5s
inj "lx=255"; sleep 5; clr; sleep 1; cap move-03-right    # right 5s
inj "ly=255"; sleep 5; clr; sleep 1; cap move-04-back     # back 5s
tap x 0.4; sleep 1.5; tap x 0.4; sleep 1.5; cap move-05-jumps
inj "ly=0";   sleep 6; clr; sleep 1; cap move-06-fwd2     # forward again 6s
echo "== idle drift window: 15s, input PROVABLY cleared ==" | tee -a "$FOC"
clr
echo "cpad_inject=[$($ADB shell getprop debug.opengoal.cpad_inject|tr -d '\r')]" | tee -a "$FOC"
cap idle-00; sleep 5; cap idle-05; sleep 5; cap idle-10; sleep 5; cap idle-15
wait $RP 2>/dev/null
$ADB pull /sdcard/gj2move_${TAG}.mp4 "$DIR/gj2move_${TAG}.mp4" >/dev/null 2>&1 && echo "  video: $DIR/gj2move_${TAG}.mp4 ($(stat -c %s "$DIR/gj2move_${TAG}.mp4" 2>/dev/null||echo 0)B)" | tee -a "$FOC"
$ADB shell rm -f /sdcard/gj2move_${TAG}.mp4 >/dev/null 2>&1
echo "== final state ==" | tee -a "$FOC"
foc=$($ADB shell dumpsys window|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG|tr -d '\r')
echo "final pid=[$pid] focus=$foc" | tee -a "$FOC"
grep -a -c "GK-DIAG sig=" "$LOG" | sed 's/^/GK-DIAG sig count: /' | tee -a "$FOC"
grep -a "GJ2ING mips2c force-enable\|A37-MIPS2C-REAL \[jak2\] (method 9 collide-cache-prim)\|A37-MIPS2C-REAL \[jak2\] (method 10 collide-cache-prim)\|A37-MIPS2C-FALLBACK \[jak2\] (method 17 collide-cache)" "$LOG" | head -12 | tee -a "$FOC"
kill $LP 2>/dev/null
echo "LOG=$LOG"
