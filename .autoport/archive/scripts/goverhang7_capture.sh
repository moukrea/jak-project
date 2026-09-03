#!/usr/bin/env bash
# goverhang7_capture.sh — Grecharged-grass-overhang7 device evidence, in owner-truth order:
#   A  pre-fix: HIS boot (plain am start, HIS settings untouched, continue to his beach save)
#      -> prove the v6 build places NO grass at beach (no PLACE-TIME) = verdict (a)
#   B  pre-fix: training warp -> prove v6 zones DO render there (the harness fantasy vs his reality)
#   C  deploy round-7 build (libgk + beach.grassbake) + deploy_verify
#   D  post-fix owner flow: plain boot + continue -> beach census + drape; MENU live toggle
#      OFF->ON with on-disk settings reads; matched ON/OFF 10s videos at the same vantage
# Usage: goverhang7_capture.sh A|B|C|D
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-grass-overhang7; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
tapb(){ inject "$1"; sleep 0.4; clr; sleep "${2:-0.7}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1.png ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B) fg=$(fg)"; }
rec(){ # $1 name  $2 seconds — screenrecord + focus bracket + frame extraction
  local N="$1" SEC="${2:-10}"
  fg > "$OUT/$N.focus"
  adb shell "screenrecord --time-limit $SEC /sdcard/gov7_$N.mp4" &
  local RPID=$!
  sleep $((SEC+2)); wait $RPID 2>/dev/null || true
  fg >> "$OUT/$N.focus"
  adb pull "/sdcard/gov7_$N.mp4" "$OUT/$N.mp4" >/dev/null 2>&1
  adb shell rm -f "/sdcard/gov7_$N.mp4" >/dev/null 2>&1 || true
  mkdir -p "$OUT/${N}_frames"
  ffmpeg -y -loglevel error -i "$OUT/$N.mp4" -vf fps=2,scale=600:-1 "$OUT/${N}_frames/f_%03d.png"
  echo "  rec $N.mp4 ($(stat -c%s "$OUT/$N.mp4" 2>/dev/null||echo 0)B) frames=$(ls "$OUT/${N}_frames" | wc -l) focus=$(cat "$OUT/$N.focus" | tr '\n' '|')"
}
stop_app(){ adb shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2; }
plain_boot(){ # HIS path: no props, LoaderActivity
  adb shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
  adb shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
  adb logcat -c 2>/dev/null || true
  adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
  echo "  plain boot, settling ${1:-45}s..."; sleep "${1:-45}"
}
continue_to_save(){ # title -> START -> X on Continue (top row)
  tapb "start" 2.5
  tapb "x" 2.0
  echo "  continue pressed; level load settle ${1:-30}s..."; sleep "${1:-30}"
}
harvest(){ # $1 tag — logcat since boot
  adb logcat -d > "$OUT/$1-logcat.log" 2>/dev/null
  echo "  --- $1 grass lines ---"
  grep -a "PLACE-TIME\|GOVERHANG6 zones\|STATIC place\|PRECOMPUTED unavailable\|foliage-wind] toggle" "$OUT/$1-logcat.log" | cut -c1-220 | sed 's/^/  /' | head -8
  echo "  (empty above = NO grass placement lines)"
  echo "  sigfaults: $(grep -acE 'signal (11|6|4)' "$OUT/$1-logcat.log" || true)"
}
guard_free(){ # refuse to run while the owner is in the game (unless FORCE=1)
  if [ "${FORCE:-0}" != 1 ] && fg | grep -q "$PKG"; then
    echo "[gov7] app is FOREGROUND (owner session?) — refusing. FORCE=1 to override."; exit 2
  fi
}

PH="${1:?phase A|B|C|D}"
adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }

case "$PH" in
A)
  guard_free
  echo "== A: pre-fix HIS boot (settings untouched, plain launch, continue to his save) =="
  adb shell cat "$SETTINGS_DEV" > "$OUT/A-settings-before.gc"
  grep -oE "^recharged[^ ]* = .*" "$OUT/A-settings-before.gc" | sed 's/^/  /'
  stop_app
  plain_boot 45
  continue_to_save 35
  shot A-spawn
  rec A-beach-asis 10
  harvest A-prefix-beach
  stop_app
  adb shell cat "$SETTINGS_DEV" > "$OUT/A-settings-after.gc"
  cmp -s "$OUT/A-settings-before.gc" "$OUT/A-settings-after.gc" && echo "  settings UNTOUCHED by run" || echo "  settings CHANGED (diff):" && diff "$OUT/A-settings-before.gc" "$OUT/A-settings-after.gc" | head -5 || true
  ;;
B)
  guard_free
  echo "== B: pre-fix training warp (v6 zones render there?) =="
  stop_app
  adb logcat -c 2>/dev/null || true
  adb shell setprop debug.opengoal.level.warp training-start
  adb shell "setprop debug.opengoal.level.warp.pos '-1310.2 52.8 989.0'"
  adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
  echo "  warp boot, settling 75s..."; sleep 75
  shot B-training
  rec B-training-v6 10
  harvest B-prefix-training
  stop_app
  adb shell setprop debug.opengoal.level.warp '""'
  adb shell setprop debug.opengoal.level.warp.pos '""'
  ;;
C)
  echo "== C: deploy round-7 build =="
  APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
  [ -f "$APK" ] || { echo "APK missing"; exit 1; }
  stop_app
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && { echo "DEVICE_LOCKED"; exit 1; }
  adb shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  adb shell pm trim-caches 999G 2>/dev/null || true
  adb install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2
  adb push out/jak1/fr3/beach.grassbake /storage/emulated/0/OpenGOAL/jak1/assets/fr3/beach.grassbake
  echo "  bake shas (build vs device vs archive):"
  sha256sum out/jak1/fr3/beach.grassbake | awk '{print "  build  "$1}'
  adb shell sha256sum /storage/emulated/0/OpenGOAL/jak1/assets/fr3/beach.grassbake | awk '{print "  device "$1}'
  unzip -p out/artifacts/jak1_assets.zip fr3/beach.grassbake 2>/dev/null | sha256sum | awk '{print "  archive "$1}'
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4
  ;;
D)
  echo "== D: post-fix owner flow =="
  stop_app
  plain_boot 45
  continue_to_save 35
  shot D-spawn
  rec D-beach-on 10
  harvest D-postfix-on
  echo "== D2: MENU live toggle (pause -> graphics -> recharged -> grass -> overhang) =="
  echo "  (row walk is interactive — see goverhang7 menu helper or drive manually)"
  ;;
*) echo "unknown phase $PH"; exit 1;;
esac
echo "[gov7 $PH] DONE"
