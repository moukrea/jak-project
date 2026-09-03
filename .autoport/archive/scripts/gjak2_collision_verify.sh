#!/usr/bin/env bash
# Gjak2-ingame collision verify: NEW GAME -> SKIP intro cinematic (do NOT let the
# "Two years later" card play) -> land in-game (Fortress/prison) -> record 60s+ of
# movement (walk/jump/turn) and prove Jak STANDS on the floor (no fall-through loop).
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-ingame
LOG="$DIR/collision-verify-run1-routed-logcat.log"
FOCUSLOG="$DIR/collision-verify-run1-focus.txt"
mkdir -p "$DIR"
: > "$FOCUSLOG"

inj() { $ADB -s $S shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; echo "    inject: '$1'" | tee -a "$FOCUSLOG"; }
clr() { $ADB -s $S shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1; }
trap 'clr' EXIT INT TERM  # Gjak2-ingame: level-triggered inject MUST be cleared on ANY exit — leftover state = permanently held input for the owner
tap() { local t="$1" d="${2:-0.5}"; inj "$t"; sleep "$d"; clr; }

cap() {  # cap <name>
  local name="$1" foc pid f
  foc=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
  pid=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
  if echo "$foc" | grep -q "org.opengoal.gk.jak2"; then f=jak2focus; else f=NOTJAK2; fi
  local out="$DIR/cv-run1-${name}-${f}.png"
  $ADB -s $S exec-out screencap -p > "$out" 2>/dev/null
  echo "  [$name] pid=[$pid] $foc -> ${out##*/} ($(stat -c %s "$out" 2>/dev/null||echo 0)B)" | tee -a "$FOCUSLOG"
}

echo "=== Gjak2 collision verify RUN1 start $(date) ==="
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB -s $S shell svc power stayon true >/dev/null 2>&1
$ADB -s $S shell am force-stop $PKG
clr
sleep 2
$ADB -s $S logcat -G 16M 2>/dev/null || true
$ADB -s $S logcat -c 2>/dev/null || true
$ADB -s $S logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V opengoal-gk-d4:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$LOG" 2>&1 &
LOGPID=$!
sleep 1
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1

echo "== stage 1: title warmup =="
sleep 55
cap "01-title"

echo "== stage 2: START -> progress menu =="
tap "start" 1.2; sleep 4
cap "02-menu"

echo "== stage 3: X -> NEW GAME =="
tap "x" 0.6; sleep 3
cap "03-newgame-x"

echo "== stage 4: down x4 -> continue-without-save, then X =="
for i in 1 2 3 4; do tap "down" 0.4; sleep 0.6; done
cap "04-continue-sel"
tap "x" 0.6; sleep 5
cap "05-newgame-start"

echo "== stage 5: SKIP the intro cinematic (START pulses + X confirm) — do NOT let 'Two years later' play =="
# Skip loop: hit START to open scene-skip, then X to confirm. Repeat until in-game
# or a bounded number of attempts. Keep each attempt short.
for a in $(seq 1 12); do
  pid=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
  [ -z "$pid" ] && { echo "  >>> app died during skip attempt $a" | tee -a "$FOCUSLOG"; break; }
  tap "start" 0.8; sleep 1.5
  tap "x" 0.6; sleep 1.2
  # also try triangle as an alt confirm on some skip dialogs
  tap "triangle" 0.5; sleep 1.0
  cap "06-skip-a${a}"
  sleep 2
done

echo "== stage 6: post-skip settle =="
sleep 6
cap "07-postskip"
pid=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
echo "  post-skip pid=[${pid:-DEAD}]" | tee -a "$FOCUSLOG"

echo "== stage 7: MOVEMENT CAPTURE — screenrecord + walk/jump/turn (collision test) =="
# device-side screenrecord in segments (max 180s each; we do ~75s total in one seg)
$ADB -s $S shell rm -f /sdcard/cv-run1-seg1.mp4 >/dev/null 2>&1
$ADB -s $S shell screenrecord --time-limit 90 --bit-rate 6000000 /sdcard/cv-run1-seg1.mp4 &
SRPID=$!
sleep 1
cap "08-move-start"

echo "  walk forward (ly=0) 8s"
inj "ly=0"; 
for i in 1 2 3 4; do sleep 2; cap "09-walk-t$((i*2))s"; done
clr; sleep 1
cap "10-stopped"

echo "  jump x4 (x)"
for i in 1 2 3 4; do tap "x" 0.3; sleep 1.2; cap "11-jump$i"; done

echo "  turn (rx=255) 3s then walk forward again"
inj "rx=255"; sleep 3; clr; sleep 1
cap "12-turned"
echo "  walk forward again (ly=0) 8s"
inj "ly=0"
for i in 1 2 3 4; do sleep 2; cap "13-walk2-t$((i*2))s"; done
clr; sleep 1
cap "14-walk2-stop"

echo "  strafe left (lx=0) 3s, jump, walk"
inj "lx=0"; sleep 3; clr; sleep 1; cap "15-strafe"
tap "x" 0.3; sleep 1.2; cap "16-jump-after-strafe"
inj "ly=0"; sleep 4; clr; sleep 1; cap "17-final-walk"

# wait for screenrecord to finish
wait $SRPID 2>/dev/null
sleep 2
echo "== stage 8: pull screenrecord =="
$ADB -s $S pull /sdcard/cv-run1-seg1.mp4 "$DIR/collision-verify-run1-seg1.mp4" 2>&1 | tail -1
cap "18-final"

echo "== teardown =="
sleep 2
pid=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
echo "  final pid=[${pid:-DEAD}]" | tee -a "$FOCUSLOG"
kill $LOGPID >/dev/null 2>&1; wait $LOGPID 2>/dev/null
$ADB -s $S shell svc power stayon true >/dev/null 2>&1
echo "=== RUN1 done $(date); log lines: $(wc -l < "$LOG") ==="
echo "LOG: $LOG"
echo "MP4: $DIR/collision-verify-run1-seg1.mp4"
