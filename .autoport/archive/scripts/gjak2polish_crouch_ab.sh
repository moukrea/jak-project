#!/usr/bin/env bash
# gjak2polish_crouch_ab.sh — Gjak2-polish item 1 (crouch-lock) device A/B.
# Reuses the Gjak2-movement NEW-GAME/intro-skip/level nav, then reproduces the
# owner's exact repro (two jumps) and probes whether Jak can STAND + move.
#  leg A (arg2 empty)  = shipped default, method 17 collide-cache ON -> Jak stands
#                        after landing, no crouch-lock.
#  leg B (arg2 = noop) = setprop debug.opengoal.jak2.noop_names re-noops method 17
#                        -> can-exit-duck? #f forever -> Jak stuck ducked (repro).
# Usage: gjak2polish_crouch_ab.sh <legA|legB> <'' | noop>
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak2; ACT=org.opengoal.gk.LoaderActivity
TAG="${1:?leg tag}"; MODE="${2-}"
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-polish/evidence
LOG="$DIR/crouch-${TAG}-routed-logcat.log"; FOC="$DIR/crouch-${TAG}-focus.txt"
mkdir -p "$DIR"; : > "$FOC"
inj(){ $ADB shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
clr(){ $ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1; }
cleanup(){ clr; $ADB shell setprop debug.opengoal.jak2.noop_names '""' >/dev/null 2>&1; }
trap 'cleanup' EXIT INT TERM
tap(){ inj "$1"; sleep "${2:-0.5}"; clr; }
cap(){ local n="$1" foc pid f; foc=$($ADB shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG 2>/dev/null|tr -d '\r'); echo "$foc"|grep -q org.opengoal.gk.jak2 && f=jak2focus || f=NOTJAK2; local o="$DIR/crouch-${TAG}-${n}-${f}.png"; $ADB exec-out screencap -p > "$o" 2>/dev/null; echo "  [$n] pid=[$pid] $foc -> ${o##*/} ($(stat -c %s "$o" 2>/dev/null||echo 0)B)"|tee -a "$FOC"; }

LEFT=$(pgrep -af 'gjak2|f1d_run|gtf_|capture_device|gjak2polish' | grep -v $$ | grep -v grep || true)
[ -n "$LEFT" ] && { echo "LEFTOVER RUNNERS — aborting:"; echo "$LEFT"; exit 3; }

$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB shell svc power stayon true >/dev/null 2>&1
$ADB shell am force-stop $PKG; clr; sleep 2
$ADB shell setprop debug.opengoal.jak2.enable_names '""'
if [ "$MODE" = noop ]; then $ADB shell "setprop debug.opengoal.jak2.noop_names '(method 17 collide-cache)'"; else $ADB shell setprop debug.opengoal.jak2.noop_names '""'; fi
echo "leg=$TAG noop_names=[$($ADB shell getprop debug.opengoal.jak2.noop_names|tr -d '\r')]" | tee -a "$FOC"
$ADB logcat -G 16M >/dev/null 2>&1; $ADB logcat -c >/dev/null 2>&1
$ADB logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$LOG" 2>&1 &
LP=$!; sleep 1
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "== warmup to title (60s) ==" | tee -a "$FOC"; sleep 60; cap 01-title
$ADB shell pidof $PKG >/dev/null 2>&1 || { echo "APP DEAD AT TITLE — boot crash (method 17?)" | tee -a "$FOC"; grep -a '0x1fc2864\|GK-DIAG sig=' "$LOG"|tail -5|tee -a "$FOC"; kill $LP 2>/dev/null; exit 4; }
echo "== NEW GAME: start -> x -> down x4 -> x ==" | tee -a "$FOC"
tap start 1.2; sleep 3; cap 02-menu
tap x 1.0; sleep 2; tap down 0.4; tap down 0.4; tap down 0.4; tap down 0.4; sleep 1
tap x 1.2; sleep 4; cap 03-afterx
echo "== skip intro ==" | tee -a "$FOC"
sleep 8; tap start 1.0; sleep 2; tap x 0.8; sleep 2; tap start 1.0; sleep 2; tap x 0.8; sleep 3; cap 04-skip
echo "== wait level load (20s) ==" | tee -a "$FOC"; sleep 20; cap 05-postload
$ADB shell pidof $PKG >/dev/null 2>&1 || { echo "APP DEAD POSTLOAD" | tee -a "$FOC"; grep -a '0x1fc2864\|GK-DIAG sig=' "$LOG"|tail -5|tee -a "$FOC"; kill $LP 2>/dev/null; exit 5; }
echo "== CROUCH REPRO: record 70s: baseline -> 2 jumps -> stance -> move -> more jumps -> stance ==" | tee -a "$FOC"
$ADB shell screenrecord --time-limit 70 /sdcard/crouch_${TAG}.mp4 >/dev/null 2>&1 & RP=$!
sleep 2; cap 06-baseline-stance
echo "  -- owner repro: two jumps --" | tee -a "$FOC"
tap x 0.3; sleep 1.6; tap x 0.3; sleep 1.8; cap 07-after-2jumps      # KEY: standing (A) vs ducked (B)
echo "  -- try to move forward 5s --" | tee -a "$FOC"
inj "ly=0"; sleep 5; clr; sleep 1; cap 08-after-move                 # moves upright (A) vs stuck/crawl-crouched (B)
echo "  -- two more jumps + turn --" | tee -a "$FOC"
tap x 0.3; sleep 1.6; tap x 0.3; sleep 1.8; cap 09-after-2more-jumps
inj "lx=255"; sleep 3; clr; sleep 1; cap 10-after-turn
inj "ly=0"; sleep 4; clr; sleep 1; cap 11-final-stance
wait $RP 2>/dev/null
$ADB pull /sdcard/crouch_${TAG}.mp4 "$DIR/crouch_${TAG}.mp4" >/dev/null 2>&1 && echo "  video: crouch_${TAG}.mp4 ($(stat -c %s "$DIR/crouch_${TAG}.mp4" 2>/dev/null||echo 0)B)" | tee -a "$FOC"
$ADB shell rm -f /sdcard/crouch_${TAG}.mp4 >/dev/null 2>&1
foc=$($ADB shell dumpsys window|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG|tr -d '\r')
echo "final pid=[$pid] focus=$foc" | tee -a "$FOC"
echo "GK-DIAG sig count: $(grep -a -c 'GK-DIAG sig=' "$LOG" 2>/dev/null)" | tee -a "$FOC"
grep -a 'A37-MIPS2C-REAL \[jak2\] (method 17 collide-cache)\|A37-MIPS2C-FALLBACK \[jak2\] (method 17 collide-cache)' "$LOG" | head -3 | tee -a "$FOC"
kill $LP 2>/dev/null; echo "LOG=$LOG"
