#!/usr/bin/env bash
# goverhang8_capture.sh — Grecharged-grass-overhang7 ROUND 8 evidence.
# Round-8 fix: zone-3 fall drape inherits WALKABLE lawn colour+light (no darkening),
# 3 layers + belly/width = volume, lip cell-noise jitter = ragged (no "eyeliner").
# Phases:
#   C  deploy round-8 build (APK install + deploy_verify; bakes unchanged — GBK7 layout carries
#      the rim-segment lawn colours already, NO rebake)
#   T  training warp to the owner vantage, boot census + still + 10s video
#   W  <x> <y> <z> [yaw-walk spec] — framing iteration: warp to explicit pos, still only
# Usage: goverhang8_capture.sh C|T|W ...
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-grass-overhang7; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1.png ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B) fg=$(fg)"; }
rec(){ local N="$1" SEC="${2:-10}"
  fg > "$OUT/$N.focus"
  adb shell "screenrecord --time-limit $SEC /sdcard/gov8_$N.mp4" &
  local RPID=$!; sleep $((SEC+2)); wait $RPID 2>/dev/null || true
  fg >> "$OUT/$N.focus"
  adb pull "/sdcard/gov8_$N.mp4" "$OUT/$N.mp4" >/dev/null 2>&1
  adb shell rm -f "/sdcard/gov8_$N.mp4" >/dev/null 2>&1 || true
  mkdir -p "$OUT/${N}_frames"
  ffmpeg -y -loglevel error -i "$OUT/$N.mp4" -vf fps=2,scale=600:-1 "$OUT/${N}_frames/f_%03d.png"
  echo "  rec $N.mp4 ($(stat -c%s "$OUT/$N.mp4" 2>/dev/null||echo 0)B) frames=$(ls "$OUT/${N}_frames" | wc -l) focus=$(cat "$OUT/$N.focus" | tr '\n' '|')"
}
stop_app(){ adb shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2; }
harvest(){ adb logcat -d > "$OUT/$1-logcat.log" 2>/dev/null
  echo "  --- $1 grass lines ---"
  grep -a "PLACE-TIME\|GOVERHANG6 zones\|GOVERHANG expand\|STATIC place\|mode=precomputed" "$OUT/$1-logcat.log" | cut -c1-240 | sed 's/^/  /' | head -8
  echo "  sigfaults: $(grep -acE 'signal (11|6|4)' "$OUT/$1-logcat.log" || true)"
}
guard_free(){ if [ "${FORCE:-0}" != 1 ] && fg | grep -q "$PKG"; then
    echo "[gov8] app is FOREGROUND (owner session?) — refusing. FORCE=1 to override."; exit 2; fi }
warp_boot(){ # $1 = "x y z" pos (empty = level spawn), settle $2
  adb logcat -c 2>/dev/null || true
  adb shell setprop debug.opengoal.level.warp training-start
  if [ -n "${1:-}" ]; then adb shell "setprop debug.opengoal.level.warp.pos '$1'"; else adb shell setprop debug.opengoal.level.warp.pos '""'; fi
  adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
  echo "  warp boot pos='${1:-spawn}', settling ${2:-75}s..."; sleep "${2:-75}"
}
clear_props(){ adb shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
  adb shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true; }

PH="${1:?phase C|T|W}"
adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }

case "$PH" in
C)
  echo "== C: deploy round-8 build =="
  APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
  [ -f "$APK" ] || { echo "APK missing"; exit 1; }
  stop_app
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && { echo "DEVICE_LOCKED"; exit 1; }
  adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  adb shell pm trim-caches 999G 2>/dev/null || true
  adb install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4
  ;;
T)
  guard_free
  echo "== T: round-8 training capture at the owner vantage =="
  stop_app
  warp_boot "-1310.2 52.8 989.0" 75
  shot R8-training
  rec R8-training-on 10
  harvest R8-training
  stop_app; clear_props
  ;;
W)
  guard_free
  POS="${2:?x y z}"
  TAG="${3:-Wframe}"
  stop_app
  warp_boot "$POS" 70
  shot "$TAG"
  harvest "$TAG"
  stop_app; clear_props
  ;;
*) echo "unknown phase $PH"; exit 1;;
esac
echo "[gov8 $PH] DONE"
