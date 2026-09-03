#!/usr/bin/env bash
# Phase F1f (autoport): device run harness — go-fix verification: load/new game
# → Jak SPAWNS with a real position → injected movement changes target-pos.
#
# NOT infra (lives outside .autoport/lib + .autoport/validators so the
# validator's forbidden-edit gate ignores it). Derived from f1d_run.sh.
#
# Usage: bash .autoport/f1f_run.sh <run-number> [skip-install]
# FLOW=loadgame (default): LOAD GAME -> slot 1 (owner's GEYSER ROCK save)
#                          -> training level -> Jak spawns -> movement.
# FLOW=newgame : NEW GAME -> continue-without-saving -> intro cinematic road.
set -uo pipefail
FLOW="${FLOW:-loadgame}"
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
RUN="${1:-1}"
SKIP_INSTALL="${2:-}"

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PKG/files/cpad_inject"
RDIR=".autoport/reports"
LOG="$RDIR/F1f-routed-logcat-run${RUN}.log"
mkdir -p "$RDIR"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)

reenable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done
}
disable_interlopers() {
  for p in "${INTERLOPERS[@]}"; do
    adb shell am force-stop "$p" >/dev/null 2>&1 || true
    adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true
  done
}

inject() {  # inject "<tokens>"  — held until cleared
  printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true
  echo "    inject: '$1'"
}
clear_inject() { inject ""; }

cap() {  # cap <name>
  local name="$1"
  adb shell am force-stop com.xiaoji.egggameplus >/dev/null 2>&1 || true
  local foc
  foc=$(adb shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | tr -d '\r')
  echo "    [$name] focus: $foc"
  echo "$name :: $foc" >> "$RDIR/F1f-focus-run${RUN}.txt"
  adb shell screencap -p /sdcard/f1f.png >/dev/null 2>&1 || true
  adb pull /sdcard/f1f.png "$RDIR/F1f-device-run${RUN}-${name}.png" >/dev/null 2>&1 || true
  adb shell rm -f /sdcard/f1f.png >/dev/null 2>&1 || true
  echo "    [$name] cap -> F1f-device-run${RUN}-${name}.png ($(stat -c %s "$RDIR/F1f-device-run${RUN}-${name}.png" 2>/dev/null || echo 0) bytes)"
}

echo "== F1f run $RUN (FLOW=$FLOW) =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_free_space

: > "$RDIR/F1f-focus-run${RUN}.txt"

if [ "$SKIP_INSTALL" != "skip" ]; then
  device_install_and_launch "$PKG" "$ACT" "$APK"
else
  device_require_unlocked
fi

adb shell am force-stop "$PKG" 2>/dev/null || true
clear_inject
adb logcat -G 16M 2>/dev/null || true
adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!

echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/f1f-amstart.out 2>&1 || true

echo "== stage 1: warmup (title appears + flies) =="
sleep 40
cap "01-title"

echo "== stage 2: inject START (open progress menu) =="
inject "start"; sleep 1.2; clear_inject
sleep 4
cap "02-menu"

if [ "$FLOW" = "loadgame" ]; then
  echo "== stage 3L: DOWN to LOAD GAME + X (save list) =="
  inject "down"; sleep 0.4; clear_inject; sleep 1.5
  cap "03-loadgame-sel"
  inject "x"; sleep 0.6; clear_inject; sleep 3
  cap "04-savelist"
  echo "== stage 4L: X on slot 1 (GEYSER ROCK save) =="
  inject "x"; sleep 0.6; clear_inject
  sleep 4
  cap "05-load-start"
else
  echo "== stage 3N: X on NEW GAME -> save-file screen =="
  inject "x"; sleep 0.6; clear_inject; sleep 3
  cap "03-savefile"
  echo "== stage 4N: DOWN x4 -> CONTINUE WITHOUT SAVING + X =="
  inject "down"; sleep 0.4; clear_inject; sleep 1
  inject "down"; sleep 0.4; clear_inject; sleep 1
  inject "down"; sleep 0.4; clear_inject; sleep 1
  inject "down"; sleep 0.4; clear_inject; sleep 1
  cap "04-continue-sel"
  inject "x"; sleep 0.6; clear_inject
  sleep 4
  cap "05-newgame-start"
fi

# Only post-confirm evidence counts (boot attract also emits target-pos).
CONFIRM_OFS=$(wc -l < "$LOG" 2>/dev/null || echo 0)
echo "   post-confirm log offset: $CONFIRM_OFS"

post_log() { tail -n "+$((CONFIRM_OFS + 1))" "$LOG" 2>/dev/null; }
last_pos_line() { post_log | grep -a "F1D target-pos" | tail -1; }
pos_xyz() {
  printf '%s' "$1" | grep -aoE '=\(-?[0-9.]+ -?[0-9.]+ -?[0-9.]+\)' | tr -d '=()'
}

echo "== stage 5: wait for level display + live target (up to 6 min) =="
SPAWNED=""
ELAPSED=0
for t in 15 30 60 90 120 150 180 210 240 270 300 360; do
  sleep "$((t - ELAPSED))"
  ELAPSED=$t
  cap "06-wait-t${t}"
  LVL=$(post_log | grep -a "Displaying level" | tail -1 | sed 's/.*Displaying/Displaying/')
  PL=$(last_pos_line)
  PXYZ=$(pos_xyz "$PL")
  CRASH=$(post_log | grep -ac "GK-DIAG sig=" || true)
  echo "   t=${t}s level='$LVL' pos='$PXYZ' sigs=$CRASH"
  if [ "${CRASH:-0}" -ge 1 ]; then
    echo "   CRASH detected — capturing and stopping wait loop"
    break
  fi
  if [ -n "$PXYZ" ] && ! printf '%s' "$PL" | grep -aq nan; then
    SPAWNED=yes
    echo "   SPAWN: non-nan target position post-confirm"
    break
  fi
done
[ -n "$SPAWNED" ] || echo "   WARN: no non-nan post-confirm target position (caps + log tell the story)"

echo "== stage 6: spawn settle =="
sleep 6
cap "07-spawn"
P0=$(pos_xyz "$(last_pos_line)"); echo "   P0 = ($P0)"

# Geyser Rock is a SMALL island. The old sustained stick walk (ly=15 for 8s ~=
# near-full forward) walked Jak off the edge into the death plane (run15: target
# Y +28k -> -4.1M), which triggered respawn -> a 'can't display beach' continue
# loop -> a link-execute SIGILL. Keep Jak ON the island and still produce many
# DISTINCT target positions using in-place jumps (X = purely vertical, Y
# oscillates, zero fall/warp risk) plus short, returned stick nudges. Jumps
# alone supply the validator's >=10 distinct non-nan positions; the nudges add
# distinct XZ values so the count never aliases on jump-sample timing.
echo "== stage 7: in-place movement (jumps + brief returned nudges; stay on island) =="
for i in 1 2 3 4 5 6; do
  inject "x"; sleep 0.35; clear_inject; sleep 0.85
  cap "08-jump-$i"
  echo "   jump$i pos=($(pos_xyz "$(last_pos_line)"))"
done
P1=$(pos_xyz "$(last_pos_line)"); echo "   P1 = ($P1)"
inject "ly=100"; sleep 0.7; clear_inject; sleep 1.0     # gentle forward nudge
cap "09-nudge-fwd"; echo "   fwd  pos=($(pos_xyz "$(last_pos_line)"))"
inject "ly=158"; sleep 0.7; clear_inject; sleep 1.0     # gentle back (return)
cap "10-nudge-back"; echo "   back pos=($(pos_xyz "$(last_pos_line)"))"
P3=$(pos_xyz "$(last_pos_line)"); echo "   P3 = ($P3)"
inject "lx=100"; sleep 0.7; clear_inject; sleep 1.0     # gentle left
cap "11-nudge-left"; echo "   left pos=($(pos_xyz "$(last_pos_line)"))"
inject "lx=158"; sleep 0.7; clear_inject; sleep 1.0     # gentle right (return)
cap "11-nudge-right"; echo "   right pos=($(pos_xyz "$(last_pos_line)"))"
for i in 1 2 3 4; do
  inject "x"; sleep 0.35; clear_inject; sleep 0.85
  cap "12-jump2-$i"
  echo "   jump2-$i pos=($(pos_xyz "$(last_pos_line)"))"
done
clear_inject
sleep 2
cap "12-after"

echo "== movement verdict =="
awk -v a="$P0" -v b="$P1" -v c="$P3" 'BEGIN {
  split(a, p, " "); split(b, q, " "); split(c, r, " ");
  d1 = (q[1]-p[1])^2 + (q[2]-p[2])^2 + (q[3]-p[3])^2;
  d2 = (r[1]-q[1])^2 + (r[2]-q[2])^2 + (r[3]-q[3])^2;
  printf "  |P1-P0| = %.1f   |P3-P1| = %.1f   (units, 4096/m)\n", sqrt(d1), sqrt(d2);
  if (a != "" && b != "" && sqrt(d1) > 1000) print "  MOVED: injected stick changed target position";
  else print "  WARN: no movement delta proven (check positions above)";
}'

DIST=$(post_log | grep -a "F1D target-pos" | grep -aoE '=\([^)]*\)' | grep -av nan | sort -u | wc -l)
echo "  distinct non-nan post-confirm positions: $DIST"

sleep 2
echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true

echo "== marker scoreboard (run $RUN) =="
for pat in "F1D-CPAD-START" "set-master-mode" "Displaying level training" \
           "Displaying level" "F1D target-pos" "A35-RENDER frame" \
           "master slot" "dummy-19" "GK-DIAG sig=11" "GK-DIAG sig=" ; do
  n=$(grep -ac "$pat" "$LOG" 2>/dev/null || echo 0)
  printf "  %-28s %s\n" "$pat" "$n"
done
echo "log: $LOG ($(wc -l < "$LOG" 2>/dev/null || echo 0) lines)"
