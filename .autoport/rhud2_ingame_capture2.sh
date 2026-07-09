#!/usr/bin/env bash
# rhud2_ingame_capture2.sh — ON-round redo with calibrated timing (eae4df44).
# Run-1 postmortem: the two mouche.buzz scout-fly collects fired ~90s post-launch,
# INSIDE the 90s settle sleep, so the fly-to-HUD icon had auto-hidden before the first
# shot; the blind forward walk also missed the blue eco vent (visible right of spawn).
# Redo: rapid 2.5s screencap cadence across t=55..115s (covers both mouche fires +
# Jak's HUD while the buzzer counter is up), then right-forward bursts toward the vent
# with a shot after each (eco gauge charges while standing in the vent).
# Leaves recharged-hud? ON (this round never touches settings; run1 restored #t).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-hud-jak1; SHOTS="$OUT/shots"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(stat -c%s "$SHOTS/$1.png" 2>/dev/null||echo -)) fg=$(fg)"; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi
echo "== ON redo: warp + mouche window rapid shots =="
V=$(adb shell run-as $PKG cat files/.config/OpenGOAL/jak1/settings/pc-settings.gc 2>/dev/null | grep -a recharged | tr -d '\r'); echo "  flag: $V"
case "$V" in *'#t'*) : ;; *) echo "FLAG NOT ON — abort"; exit 1;; esac
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.f1.warp 1 || true
adb shell setprop debug.opengoal.mouche.buzz 1 || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  launched, settling 55s..."; sleep 55
for i in $(seq -w 1 24); do shot "ON2-t$i"; sleep 2.5; done
echo "== vent seek: right-forward bursts =="
for i in 1 2 3 4 5 6 7 8; do
  inject "lx=255 ly=64"; sleep 1.1; clr; sleep 0.3
  inject "ly=0"; sleep 0.8; clr; sleep 0.4
  shot "ON2-vent$i"
done
echo "== stand still (if in vent the gauge charges + stays) =="
for i in 1 2 3 4; do sleep 2.5; shot "ON2-stand$i"; done
adb logcat -d -v threadtime 2>/dev/null | grep -aE 'F1-WARP|MOUCHE|recharged-hud|Fatal signal|GK-DIAG sig=' > "$OUT/device-ingame-ON2-logcat.txt" || true
grep -a MOUCHE "$OUT/device-ingame-ON2-logcat.txt" || echo "  (no MOUCHE lines)"
adb shell setprop debug.opengoal.f1.warp 0 || true
adb shell setprop debug.opengoal.mouche.buzz 0 || true
echo "[rhud2-ingame2] DONE"
