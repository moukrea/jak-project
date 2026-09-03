#!/usr/bin/env bash
# Gtouch-menus TAP calibration (robust): boot, then retry (press START -> tap
# OPTIONS via REAL adb input tap) until Gtm-tap fires. RELEASE uses a non-token
# word ("neutral") because `setprop key ""` drops the empty arg (no-op) and would
# leave START stuck-held. Captures per-row calibration logs (Gtm-row idx/oy/cy).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gtouch-menus/shots; mkdir -p "$OUT"
LOG=.autoport/reports/Gtouch-menus/tap-cal.log
adb(){ "$ADB" -s "$S" "$@"; }
inj(){ adb shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
rel(){ inj neutral; }
press(){ inj "$1"; sleep 0.4; rel; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
tap(){ adb shell input tap "$1" "$2"; }

echo "== boot ==" | tee "$LOG"
rel
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
sleep 46
rel
for a in 1 2 3 4 5 6; do
  echo "== attempt $a: START then TAP OPTIONS (1152,443) ==" | tee -a "$LOG"
  press start 2.6
  shot "cal-a${a}-menu"
  adb logcat -c 2>/dev/null || true
  tap 1152 443
  sleep 1.8
  HITS=$(adb logcat -d 2>/dev/null | grep -acE 'Gtm-tap')
  echo "  Gtm-tap hits this attempt: $HITS  fg=$(adb shell dumpsys window 2>/dev/null|grep -m1 mCurrentFocus|tr -d '\r')" | tee -a "$LOG"
  if [ "$HITS" -gt 0 ]; then
    shot "cal-a${a}-after"
    echo "== CALIBRATION DATA (attempt $a) ==" | tee -a "$LOG"
    adb logcat -d 2>/dev/null | grep -aE 'Gtouch-menus onMenuTap|Gtm-tap|Gtm-row' | tee -a "$LOG"
    break
  fi
done
rel
echo "== DONE ==" | tee -a "$LOG"
