#!/usr/bin/env bash
# rhud4_offon.sh — CLEAN controlled OFF vs ON A/B (no menu nav, pure flag-file toggle).
# Verifies OFF == stock (no recharged heart) is honored on device. Each side: force-stop,
# set the pc-settings flag, VERIFY the file, boot+warp, collect green, screencap.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
OUT=.autoport/reports/Grecharged-hud-jak1/round4/final; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
setp(){ adb shell "setprop $1 '$2'"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
setflag(){ adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r' > /tmp/of.gc
  sed -i "s/^recharged-hud? = #[tf]/recharged-hud? = $1/" /tmp/of.gc
  adb push /tmp/of.gc /data/local/tmp/of.gc >/dev/null 2>&1; adb shell run-as $PKG cp /data/local/tmp/of.gc "$SETF" >/dev/null 2>&1
  echo "  FILE FLAG: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"; }
run(){ # $1 label  $2 flag
  echo "###### $1 (flag $2) ######"
  adb shell am force-stop $PKG >/dev/null 2>&1 || true
  setflag "$2"
  setp debug.opengoal.f1.warp 1; setp debug.opengoal.eco.spawn "4 45 0.3 0.3 0.3"
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true; echo "  settle 85s"; sleep 85
  echo "  fg=$(fg)"
  # collect green: gentle wiggle for 10s, then screencap while heart is up
  for i in 1 2 3 4; do inject "ly=0.35"; sleep 1.2; clr; sleep 0.3; inject "lx=0.35"; sleep 1.0; clr; sleep 0.3; done
  adb exec-out screencap -p > "$OUT/device-offon-$1.png" 2>/dev/null
  echo "  shot device-offon-$1.png ($(stat -c%s "$OUT/device-offon-$1.png" 2>/dev/null||echo 0) B)"
  # a few more shots to catch the heart-up window
  for k in 2 3 4; do inject "ly=0.35"; sleep 1.0; clr; adb exec-out screencap -p > "$OUT/device-offon-$1-$k.png" 2>/dev/null; done
}
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true; adb shell svc power stayon true >/dev/null 2>&1 || true
run OFF '#f'
run ON  '#t'
setp debug.opengoal.eco.spawn ""; setflag '#t'
echo "[rhud4-offon] DONE fg=$(fg)"; ls -la "$OUT"/device-offon-*.png 2>/dev/null