#!/usr/bin/env bash
# rhud2_ingame_capture3.sh — event-driven ON-round HUD capture (eae4df44).
# Run-1/2 postmortem: warp-to-control latency varies 10s..90s across boots (cold asset
# check vs warm start), so sleep-based shot timing keeps missing the ~8s fly-to-HUD
# window after the mouche.buzz collects (which fire within ~±4s of the F1-WARP line).
# This round TAILS LOGCAT and starts a rapid screencap burst the moment the warp line
# appears, then makes one short calibrated nudge toward the blue eco vent (run2's
# 8 long bursts overshot to the sea cliff).
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
shot(){ adb exec-out screencap -p > "$SHOTS/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(date +%H:%M:%S)) fg=$(fg)"; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi
V=$(adb shell run-as $PKG cat files/.config/OpenGOAL/jak1/settings/pc-settings.gc 2>/dev/null | grep -a recharged | tr -d '\r'); echo "  flag: $V"
case "$V" in *'#t'*) : ;; *) echo "FLAG NOT ON — abort"; exit 1;; esac
adb shell am force-stop $PKG >/dev/null 2>&1 || true
sleep 2
adb logcat -c >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.f1.warp 1 || true
adb shell setprop debug.opengoal.mouche.buzz 1 || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  launched $(date +%H:%M:%S); waiting for the F1-WARP line (max 180s)..."
WARPED=0; t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
  if adb logcat -d -v brief 2>/dev/null | grep -aq "F1-WARP\] (start 'play game-start)"; then WARPED=1; break; fi
  sleep 1
done
[ "$WARPED" = 1 ] || { echo "WARP LINE NEVER APPEARED"; exit 1; }
echo "  WARP at $(date +%H:%M:%S) — rapid burst"
for i in $(seq -w 1 20); do shot "ON3-w$i"; sleep 0.9; done
echo "  vent nudge: one short right-forward"
inject "lx=255 ly=64"; sleep 0.7; clr; sleep 0.5
for i in 1 2 3; do shot "ON3-vent-a$i"; sleep 2; done
inject "lx=255 ly=64"; sleep 0.6; clr; sleep 0.5
for i in 1 2 3; do shot "ON3-vent-b$i"; sleep 2; done
inject "ly=0"; sleep 0.6; clr; sleep 0.5
for i in 1 2 3; do shot "ON3-vent-c$i"; sleep 2; done
adb logcat -d -v threadtime 2>/dev/null | grep -aE 'F1-WARP|MOUCHE|recharged-hud|Fatal signal|GK-DIAG sig=' > "$OUT/device-ingame-ON3-logcat.txt" || true
grep -a 'MOUCHE-BUZZ' "$OUT/device-ingame-ON3-logcat.txt" || echo "  (no MOUCHE lines)"
adb shell setprop debug.opengoal.f1.warp 0 || true
adb shell setprop debug.opengoal.mouche.buzz 0 || true
echo "[rhud2-ingame3] DONE"
