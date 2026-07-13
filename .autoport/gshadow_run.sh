#!/usr/bin/env bash
# gshadow_run.sh — Gjak1-shadow-cast device evidence run.
# Boots the installed build, warps village1-hut, records Jak STANDING (shadow
# beneath him) and JUMPING (shadow stays on the ground), harvests A35-RENDER
# render_ms for fps, checks focus + crash signals, then repeats the same beat
# with the kill-switch prop (debug.opengoal.jak1.noshadow=1) for the
# shadow-OFF fps/no-shadow A/B (pre-fix behavior on the same build).
# Usage: gshadow_run.sh <tag> [noshadow(0|1)] [soak_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-shadow1}"; NOSHADOW="${2:-0}"; SOAK="${3:-60}"
OUT=.autoport/reports/Gjak1-shadow-cast; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SERIAL="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/$TAG-logcat.log"; RES="$OUT/$TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > /data/data/$PKG/files/cpad_inject'" >/dev/null 2>&1 || true; }
crash_seen(){ grep -qaE 'Fatal signal|GK-DIAG sig=(4|6|11)|enough stack|too much stack' "$LOG"; }
rec(){ # rec <name> <seconds> — screenrecord + pull + frame extraction
  local name="$1" secs="$2"
  A shell screenrecord --time-limit "$secs" /sdcard/"$name".mp4
  A pull /sdcard/"$name".mp4 "$OUT/$name.mp4" >/dev/null
  A shell rm -f /sdcard/"$name".mp4 || true
  ffmpeg -y -loglevel error -i "$OUT/$name.mp4" -vf fps=2 "$OUT/$name-%02d.png"
}

A shell svc power stayon true >/dev/null 2>&1 || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
A shell setprop debug.opengoal.level.warp village1-hut >/dev/null 2>&1
A shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
A shell setprop debug.opengoal.jak1.noshadow "$NOSHADOW" >/dev/null 2>&1
inj ""

A shell am force-stop "$PKG" >/dev/null 2>&1
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true; : > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGPID=$!
cleanup(){ kill "$LOGPID" 2>/dev/null || true
  for p in level.warp level.warp.pos jak1.noshadow; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done; }
trap cleanup EXIT
A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "  waiting warp village1-hut (noshadow=$NOSHADOW)..."
WARPED=0
for i in $(seq 1 180); do
  grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { WARPED=1; echo "  warp ~${i}s"; break; }
  crash_seen && break; sleep 1
done
sleep 12  # settle: camera behind Jak
FOCUS=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus: $FOCUS"
echo "  recording STAND (10s)..."
rec "$TAG-stand" 10
echo "  recording JUMP (8s, X presses mid-record)..."
( sleep 2; inj "x"; sleep 0.7; inj ""; sleep 1.5; inj "x"; sleep 0.7; inj ""; sleep 1.5; inj "x"; sleep 0.7; inj "" ) &
JPID=$!
rec "$TAG-jump" 8
wait "$JPID" 2>/dev/null || true
inj ""
echo "  soaking ${SOAK}s for crash check..."
for i in $(seq 1 "$SOAK"); do crash_seen && { echo "  >>> CRASH ~${i}s"; break; }; sleep 1; done
FOCUS_END=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
{
  echo "=== gshadow_run $TAG noshadow=$NOSHADOW $(date -Is) ==="
  echo "warped=$WARPED"
  echo "focus_mid: $FOCUS"
  echo "focus_end: $FOCUS_END"
  echo "--- render_ms samples (A35-RENDER, in-game beat) ---"
  grep -a 'A35-RENDER frame=' "$LOG" | tail -20
  echo "--- shadow bucket ---"
  grep -a 'A35-RENDER jak1 bucket table ready' "$LOG" | tail -1
  echo "--- kill-switch ---"
  grep -a 'GJAK1SHADOW' "$LOG" | tail -2
  echo "--- crash signals ---"
  grep -aE 'Fatal signal|GK-DIAG sig=(4|6|11)' "$LOG" | tail -5 || true
} | tee "$RES"
kill "$LOGPID" 2>/dev/null || true; trap - EXIT
for p in level.warp level.warp.pos jak1.noshadow; do A shell setprop debug.opengoal.$p '""' >/dev/null 2>&1 || true; done
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
echo "== $TAG done =="
