#!/usr/bin/env bash
# goptions_recapture.sh — clean visual persistence shot (settings currently have
# dynamic-render-scale? #f from the prior test -> expect Dynamic OFF + MTF hidden)
# and a scroll-down shot to reveal V-Sync / MSAA / ADVANCED SETTINGS / Back.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
SHOTS=.autoport/reports/Goptions-reorder/shots; mkdir -p "$SHOTS"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/$1.png" 2>/dev/null; echo "    shot $1.png ($(stat -c%s "$SHOTS/$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
nav_to_graphics(){
  inject "start"; sleep 0.5; clr; sleep 2.2
  inject "down";  sleep 0.4; clr; sleep 0.7
  inject "down";  sleep 0.4; clr; sleep 0.7
  inject "x";     sleep 0.4; clr; sleep 2.0
  inject "down";  sleep 0.4; clr; sleep 0.7
  inject "x";     sleep 0.4; clr; sleep 2.0
}
echo "== relaunch (NO wipe: settings hold dynamic #f from the persistence test) =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
sleep 55
echo "  fg after boot: $(fg)"
echo "  boot crash check:"; adb logcat -d 2>/dev/null | grep -aE "Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=" | tail -3 || echo "   (none)"
echo "== persistence visual: open graphics menu (expect Dynamic OFF + MTF hidden) =="
nav_to_graphics
shot 05-graphics-persist-clean
echo "== scroll DOWN to reveal V-Sync / MSAA / ADVANCED SETTINGS / Back =="
for k in 1 2 3 4 5 6 7; do inject "down"; sleep 0.35; clr; sleep 0.35; done
sleep 0.8
shot 06-graphics-bottom-advanced
echo "== restore fresh defaults (Dynamic ON) for the owner's next boot =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell run-as $PKG rm -f "files/.config/OpenGOAL/jak1/settings/pc-settings.gc" 2>/dev/null || true
echo "[recap] DONE"
