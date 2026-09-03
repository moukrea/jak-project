#!/usr/bin/env bash
# Gjak2-movement: movement+idle capture segment. PRECONDITION: jak2 already
# in-game under PLAYER CONTROL (caller verified via screencaps).
# Records ~100s: analog walks in 4 directions + jumps + 15s cleared-input idle.
# Usage: gjak2_move_seg.sh <tag>
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
TAG="${1:?tag}"
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-movement
FOC="$DIR/${TAG}-seg-focus.txt"
mkdir -p "$DIR"; : > "$FOC"
inj(){ $ADB shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; echo "  inject '$1' t=$(date +%H:%M:%S)" | tee -a "$FOC"; }
clr(){ $ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1; }
trap 'clr' EXIT INT TERM
tap(){ inj "$1"; sleep "${2:-0.5}"; clr; }
cap(){ local n="$1" foc pid f; foc=$($ADB shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG 2>/dev/null|tr -d '\r'); echo "$foc"|grep -q org.opengoal.gk.jak2 && f=jak2focus || f=NOTJAK2; local o="$DIR/${TAG}-${n}-${f}.png"; $ADB exec-out screencap -p > "$o" 2>/dev/null; echo "  [$n] pid=[$pid] $foc -> ${o##*/} ($(stat -c %s "$o" 2>/dev/null||echo 0)B)"|tee -a "$FOC"; }

$ADB shell screenrecord --time-limit 100 /sdcard/gj2seg_${TAG}.mp4 >/dev/null 2>&1 &
RP=$!
sleep 2; cap move-00-baseline
inj "ly=0";   sleep 6; clr; sleep 1; cap move-01-fwd
inj "lx=0";   sleep 5; clr; sleep 1; cap move-02-left
inj "lx=255"; sleep 5; clr; sleep 1; cap move-03-right
inj "ly=255"; sleep 5; clr; sleep 1; cap move-04-back
tap x 0.4; sleep 1.5; tap x 0.4; sleep 1.5; cap move-05-jumps
inj "ly=0";   sleep 6; clr; sleep 1; cap move-06-fwd2
echo "== idle drift window: 15s, input PROVABLY cleared ==" | tee -a "$FOC"
clr
echo "cpad_inject=[$($ADB shell getprop debug.opengoal.cpad_inject|tr -d '\r')]" | tee -a "$FOC"
cap idle-00; sleep 5; cap idle-05; sleep 5; cap idle-10; sleep 5; cap idle-15
wait $RP 2>/dev/null
$ADB pull /sdcard/gj2seg_${TAG}.mp4 "$DIR/gj2move_${TAG}.mp4" >/dev/null 2>&1 && echo "  video: $DIR/gj2move_${TAG}.mp4 ($(stat -c %s "$DIR/gj2move_${TAG}.mp4" 2>/dev/null||echo 0)B)" | tee -a "$FOC"
$ADB shell rm -f /sdcard/gj2seg_${TAG}.mp4 >/dev/null 2>&1
foc=$($ADB shell dumpsys window|grep -iE mCurrentFocus|head -1|tr -d '\r'); pid=$($ADB shell pidof $PKG|tr -d '\r')
echo "final pid=[$pid] focus=$foc" | tee -a "$FOC"
