#!/usr/bin/env bash
# gres_device_verify.sh — Gres-picker device verification helper (eae4df44).
# Provides reusable functions to boot the consolidated HEAD build to the title
# attract, drive the in-game menu via the cpad_inject channel, screencap, and
# harvest the resolution apply/persistence markers from GK_STDOUT logcat.
#
# Usage:
#   bash .autoport/gres_device_verify.sh boot          # deploy_verify + launch + wait attract
#   bash .autoport/gres_device_verify.sh press <tok>   # hold token ~0.35s then release
#   bash .autoport/gres_device_verify.sh shot <name>   # screencap -> $OUT/<name>.png
#   bash .autoport/gres_device_verify.sh logmark       # grep resolution markers from $LOG
#   bash .autoport/gres_device_verify.sh relaunch      # force-stop + start (persistence test)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Gres-picker; mkdir -p "$OUT"
LOG="$OUT/device-logcat.log"
INJ=debug.opengoal.cpad_inject

press(){ "$ADB" shell setprop $INJ "$1" >/dev/null 2>&1 || true; sleep 0.35; "$ADB" shell setprop $INJ '""' >/dev/null 2>&1 || true; sleep 0.35; echo "  press: $1"; }
hold(){ "$ADB" shell setprop $INJ "$1" >/dev/null 2>&1 || true; echo "  hold: $1"; }
release(){ "$ADB" shell setprop $INJ '""' >/dev/null 2>&1 || true; echo "  release"; }
shot(){ "$ADB" exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || true; echo "  shot -> $OUT/$1.png ($(stat -c%s "$OUT/$1.png" 2>/dev/null) bytes)"; }
focus(){ "$ADB" shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
logmark(){
  echo "== resolution apply / persistence markers =="
  grep -aE "Setting borderless/fullscreen size to|Setting window size to|\[PC Settings\]: (Valid|Invalid) game-size" "$LOG" 2>/dev/null | tail -25
  echo "== crash sigs =="
  grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null
}

startlog(){
  "$ADB" shell setprop $INJ '""' >/dev/null 2>&1 || true
  "$ADB" logcat -G 64M >/dev/null 2>&1 || true
  "$ADB" logcat -c >/dev/null 2>&1 || true
  : > "$LOG"
  ( "$ADB" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE 'Setting (borderless|window)|PC Settings|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) &
  echo $! > "$OUT/.logcat.pid"
}
stoplog(){ kill "$(cat "$OUT/.logcat.pid" 2>/dev/null)" 2>/dev/null || true; pkill -f "logcat -v threadtime GK_STDOUT" 2>/dev/null || true; }

case "${1:-}" in
  boot)
    "$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    if "$ADB" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED — needs owner unlock"; exit 2; fi
    echo "== deploy_verify =="; bash .autoport/lib/deploy_verify.sh eae4df44 2>&1 | tail -3
    "$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
    startlog
    echo "== launch =="; "$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
    for ((i=1;i<=50;i++)); do
      sleep 3; FM=$(maxframe); FM=${FM:-0}
      (( i % 4 == 0 )) && echo "  [${i}] frame=$FM focus=$(focus)"
      [ "$FM" -ge 1500 ] && { echo "  >>> attract rendering (frame $FM)"; break; }
    done ;;
  press)   press "${2:-}";;
  hold)    hold "${2:-}";;
  release) release;;
  shot)    shot "${2:-shot}";;
  logmark) logmark;;
  relaunch)
    stoplog; "$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true; sleep 1; startlog
    "$ADB" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
    for ((i=1;i<=50;i++)); do sleep 3; FM=$(maxframe); FM=${FM:-0}; [ "$FM" -ge 1200 ] && { echo "  relaunched, frame $FM"; break; }; done
    logmark ;;
  stoplog) stoplog;;
  *) echo "usage: $0 {boot|press <tok>|hold <tok>|release|shot <name>|logmark|relaunch|stoplog}";;
esac
