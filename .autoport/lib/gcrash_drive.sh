#!/usr/bin/env bash
# Gcrash-geyser interactive drive: inject a held cpad STATE for <dur>s, release,
# optionally screencap, and report any crash/hang seen in the hold logcat.
# Usage: gcrash_drive.sh "<cpad tokens>" <dur-seconds> [snapname]
#   tokens: lx=/ly=/rx=/ry= (0-255, 127 neutral; ly<127 forward) + button names
#           (square=spin-attack, x=jump, circle, triangle, l1/r1/l2/r2)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
PACKAGE=org.opengoal.gk.jak1
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PACKAGE/files/cpad_inject"
OUT=.autoport/reports/Gcrash-geyser
LOG="$OUT/hold-logcat.log"
TOK="${1:-}"; DUR="${2:-1}"; SNAP="${3:-}"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
inj "$TOK"
sleep "$DUR"
inj ""   # release
if [ -n "$SNAP" ]; then
  A shell screencap -p /sdcard/gd.png >/dev/null 2>&1 || true
  A pull /sdcard/gd.png "$OUT/drive-$SNAP.png" >/dev/null 2>&1 || true
fi
# status: crash / hang / pos
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+' "$LOG" 2>/dev/null | tail -1)
HANG=$(grep -acE 'A37-HANG watchdog: frame stuck' "$LOG" 2>/dev/null || echo 0)
POS=$(grep -aE 'F1-STATE tx=' "$LOG" 2>/dev/null | tail -1 | grep -aoE 'tx=[-0-9.]+ ty=[-0-9.]+ tz=[-0-9.]+')
COLLECT=$(grep -aciE 'buzzer-pickup|got.*buzzer|become-hud' "$LOG" 2>/dev/null || echo 0)
FOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -c "$PACKAGE")
echo "drive '$TOK' ${DUR}s -> sig=${SIG:-none} hangs=$HANG collect_markers=$COLLECT focus_app=$FOC | $POS"
