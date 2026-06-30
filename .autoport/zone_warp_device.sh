#!/usr/bin/env bash
# zone_warp_device.sh — REAL on-device per-zone load+run confirmation for jak1 arm64.
# Arms the generic LEVEL-WARP hook (debug.opengoal.level.warp=<continue-name>), which
# replays  (start 'play (get-continue-by-name *game-info* "<name>"))  on the GOAL
# kernel thread — warping the device DIRECTLY into a level. Then observes for WATCH_S
# seconds PAST the warp and emits an honest per-zone verdict:
#   LOADS+RENDERS  — app foreground at end, render frames advanced, no sig 11/6/4,
#                    no "enough stack" abort
#   CRASH<detail>  — captured signal + forensics
#
# Assumes the libgk + full asset set are ALREADY deployed+verified (run once up front).
# This script does NOT rebuild/reinstall — it only force-stops, re-arms the prop, boots,
# observes. That keeps each zone fast and avoids re-pushing 1.2GB per zone.
#
# Usage: zone_warp_device.sh <zone_tag> <continue-name> [watch_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

ZONE_TAG="${1:?zone tag e.g. JUN}"
CONT="${2:?continue-point name e.g. jungle-start}"
WATCH_S="${3:-25}"
OUT_DIR="${OUT_DIR:-.autoport/reports/Gzone-device}"
mkdir -p "$OUT_DIR"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT_DIR/$ZONE_TAG-logcat.log"
RESULT="$OUT_DIR/$ZONE_TAG-result.txt"
SHOT="$OUT_DIR/$ZONE_TAG-frame.png"
A() { "$ADB" -s "$SERIAL" "$@"; }

# keep awake
A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

# device must be unlocked
LOCK=$(A shell dumpsys window 2>/dev/null | grep -m1 mDreamingLockscreen | tr -d '\r')
if echo "$LOCK" | grep -q 'mDreamingLockscreen=true'; then
  echo "PIN-LOCKED: device needs owner unlock — cannot test $ZONE_TAG" | tee "$RESULT"
  exit 2
fi

echo "== $ZONE_TAG: arm LEVEL-WARP continue='$CONT' =="
A shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp     0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.echo.intro  0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.mouche.fx   0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.mouche.buzz 0 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.die         0 >/dev/null 2>&1 || true
# (warp settle uses the hook default ~600 dispatch ticks after engine-ready; the
#  delay is env-only OG_LEVEL_WARP_DELAY, not settable via setprop, so we use default)

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
pkill -f "logcat.*$ZONE_TAG" 2>/dev/null || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c    >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/zw-am.out 2>&1 || true

crash_seen() { grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|enough stack|too much stack' "$LOG"; }
focus_is_app() { A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

echo "  warming to title (link finish: logo, up to 150s)..."
for i in $(seq 1 150); do
  grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }
  crash_seen && { echo "  CRASH before title ~${i}s"; break; }
  sleep 1
done

echo "  waiting for LEVEL-WARP to fire (up to 90s)..."
WARP_OK=0; WARP_FAIL=0
for i in $(seq 1 90); do
  grep -qaE "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { echo "  warp fired ~${i}s"; WARP_OK=1; break; }
  grep -qaE "LEVEL-WARP-FAIL name=$CONT"  "$LOG" && { echo "  warp FAILED (continue not found) ~${i}s"; WARP_FAIL=1; break; }
  crash_seen && { echo "  CRASH before warp ~${i}s"; break; }
  sleep 1
done

FRAME_AT_WARP=$(max_frame); FRAME_AT_WARP=${FRAME_AT_WARP:-0}
echo "  observing $ZONE_TAG for ${WATCH_S}s past warp (frame@warp=$FRAME_AT_WARP)..."
CRASHED=0
for ((i=1;i<=WATCH_S;i++)); do
  if crash_seen; then echo "   >>> CRASH during $ZONE_TAG run ~${i}s"; CRASHED=1; break; fi
  (( i % 5 == 0 )) && echo "   [watch ${i}/${WATCH_S}s] frame=$(max_frame)"
  sleep 1
done
sleep 1

# screencap a frame at end (foreground evidence)
A exec-out screencap -p > "$SHOT" 2>/dev/null || true
SHOT_BYTES=$(stat -c%s "$SHOT" 2>/dev/null || echo 0)

FRAME_END=$(max_frame); FRAME_END=${FRAME_END:-0}
FOC="no"; focus_is_app && FOC="yes"
ADVANCED=$(( FRAME_END - FRAME_AT_WARP ))
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+|signal (11|6|4) \(SIG[A-Z]+|enough stack|too much stack' "$LOG" | tail -1)
GKDIAG=$(grep -aE 'GK-DIAG sig=[0-9]+ fault=' "$LOG" | tail -1)
LASTLINK=$(grep -aoE 'link finish: [a-z0-9-]+' "$LOG" | tail -6 | tr '\n' ' ')
ADDLEV=$(grep -aoE 'Adding level [a-z0-9-]+' "$LOG" | tail -4 | tr '\n' ';')
A34=$(grep -aE 'A34-DIAG (fp-walk|pp\+|lr-)' "$LOG" | tail -6 | tr '\n' ';')
BTLR=$(grep -aoE 'pc=0x[0-9a-f]+ lr=0x[0-9a-f]+' "$LOG" | tail -1)

STATUS="UNKNOWN"
if [ "$CRASHED" = 1 ]; then
  STATUS="CRASH(${SIG:-?})"
elif [ "$WARP_FAIL" = 1 ]; then
  STATUS="WARP-CONTINUE-NOT-FOUND"
elif [ "$WARP_OK" = 1 ] && [ "$FOC" = "yes" ] && [ "$ADVANCED" -gt 30 ]; then
  STATUS="LOADS+RENDERS(frame+$ADVANCED,foreground)"
elif [ "$WARP_OK" = 1 ] && [ "$FOC" = "yes" ]; then
  STATUS="WARP-OK-LOWFRAME(frame+$ADVANCED,foreground)"
elif [ "$WARP_OK" = 1 ]; then
  STATUS="WARP-OK-NOT-FOREGROUND(frame+$ADVANCED,focus=$FOC)"
else
  STATUS="NO-WARP(frame=$FRAME_END,focus=$FOC)"
fi

{
  echo "=== zone_warp_device $ZONE_TAG (continue=$CONT) $(date -Is) ==="
  echo "RESULT zone=$ZONE_TAG continue=$CONT status=$STATUS"
  echo "  warp_fired=$WARP_OK warp_fail=$WARP_FAIL crashed=$CRASHED"
  echo "  frame@warp=$FRAME_AT_WARP frame@end=$FRAME_END advanced=$ADVANCED focus_app=$FOC screencap_bytes=$SHOT_BYTES"
  echo "  sig=${SIG:-none}"
  echo "  gk-diag: ${GKDIAG:-none}"
  echo "  pc/lr: ${BTLR:-none}"
  echo "  adding-level: ${ADDLEV:-none}"
  echo "  last link-finish: ${LASTLINK:-none}"
  echo "  a34-fp-walk: ${A34:-none}"
} | tee "$RESULT"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
echo "== $ZONE_TAG done: $STATUS =="
