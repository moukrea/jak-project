#!/usr/bin/env bash
# rhud4_observe2.sh — ROUND 4 decisive device observation (eae4df44, fresh HEAD).
# Fixes the setprop quoting bug (multi-token value must be ONE device-shell arg) and
# spawns eco/cell VERY CLOSE (0.3m) with a short period so pickups auto-collect and the
# recharged HUD elements actually SHOW. Three rounds, one video each:
#   green (type 4): heart pop + green particle by heart + WORLD-SPACE LEAK check
#   blue  (type 3): eco gauge fill + gauge-center particle
#   cell  (type 6): fuel-cell HUD icon — does the BODY render or only the glow?
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
OUT=.autoport/reports/Grecharged-hud-jak1/round4; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
setp(){ adb shell "setprop $1 '$2'"; }   # wrap remote cmd so multi-token value = 1 arg
getp(){ adb shell "getprop $1" | tr -d '\r'; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(stat -c%s "$OUT/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
boot(){ adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true; echo "  launched, settling ${1:-85}s..."; sleep "${1:-85}"; }
# gentle collection nudges: small alternating forward/back taps so pills next to Jak get touched
nudge(){ local n="${1:-6}"; for i in $(seq 1 "$n"); do inject "ly=0.35"; sleep 1.2; clr; sleep 0.3; inject "ly=-0.35"; sleep 1.2; clr; sleep 0.3; done; }
record(){ # $1 name  $2 seconds  $3 nudge-count
  adb shell "screenrecord --time-limit $2 --bit-rate 8000000 /sdcard/r4-$1.mp4" &
  local rp=$!; sleep 1; nudge "$3"; wait $rp 2>/dev/null || sleep "$2"
  adb pull "/sdcard/r4-$1.mp4" "$OUT/r4-$1.mp4" >/dev/null 2>&1 && echo "  pulled r4-$1.mp4 ($(stat -c%s "$OUT/r4-$1.mp4" 2>/dev/null||echo 0) B)"
}

adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && { echo "DEVICE_LOCKED"; exit 1; }

echo "== confirm recharged-hud? ON =="
CUR=$(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r'); echo "  flag: $CUR"
echo "$CUR" | grep -q '^recharged-hud? = #t' || { echo "  FLAG NOT ON — aborting (menu-set needed)"; }

echo "== warp ON to Geyser Rock, GREEN eco close-spawn =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
setp debug.opengoal.f1.warp 1
setp debug.opengoal.eco.spawn "4 45 0.3 0.3 0.3"
echo "  eco.spawn now: $(getp debug.opengoal.eco.spawn)"
boot 85
echo "  focus: $(fg)"
adb logcat -d -v brief 2>/dev/null | grep -aE 'F1-WARP|ECO-SPAWN|eco.spawn|birth-pickup' | tail -6
echo "== A. GREEN round (24s) =="
record green 24 6
shot A-green-still

echo "== B. BLUE round (20s) =="
setp debug.opengoal.eco.spawn "3 45 0.3 0.3 0.3"; echo "  eco.spawn now: $(getp debug.opengoal.eco.spawn)"; sleep 3
record blue 20 5
shot B-blue-still

echo "== C. FUEL-CELL round (20s) =="
setp debug.opengoal.eco.spawn "6 90 0.4 0.4 0.4"; echo "  eco.spawn now: $(getp debug.opengoal.eco.spawn)"; sleep 3
record cell 20 5
shot C-cell-still

echo "== logcat harvest =="
adb logcat -d -v threadtime 2>/dev/null | grep -aE 'F1-WARP|ECO|eco|SPART|recharged|Fatal signal|GK-DIAG sig=|signal 11|signal 6' > "$OUT/device-ON2-logcat.txt" || true
echo "  logcat lines: $(wc -l < "$OUT/device-ON2-logcat.txt" 2>/dev/null || echo 0)"
echo "  crash sigs: $(grep -acE 'Fatal signal|sig=11|sig=6|signal 11|signal 6' "$OUT/device-ON2-logcat.txt" || echo 0)"
setp debug.opengoal.eco.spawn ""
echo "[rhud4-observe2] DONE. focus=$(fg)"
ls -la "$OUT"/r4-*.mp4 "$OUT"/device-[ABC]-*.png 2>/dev/null
