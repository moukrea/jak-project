#!/usr/bin/env bash
# gpbrf11_editmode_capture.sh — capture (1) the PBR ISOLATE row in EDIT MODE showing the option
# value as a REAL STRING (that is where the owner saw "Unknown ID 5924-5927"), and (2) a fresh
# default-render mp4/png of the fused-PBR attract flythrough for the report device evidence.
set -uo pipefail
cd /home/emeric/code/jak-project
ADB=~/Android/platform-tools/adb; SER=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/menu-proof11
mkdir -p "$OUT"
adb(){ "$ADB" -s "$SER" "$@"; }
say(){ echo "$*"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.8; inject ""; sleep "${2:-2.0}"; }
fg_ok(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }

adb shell am force-stop $PKG; sleep 2
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 80
held=0; for i in $(seq 1 40); do
  if fg_ok; then held=$((held+1)); [ $held -ge 4 ] && break; else held=0; adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 8; fi
  sleep 6
done
say "fg held=$held"

# --- fresh default-render evidence (fused PBR active: rt ON + pbr ON) ---
say "capture default render (attract flythrough, fused PBR)"
adb shell screenrecord --time-limit 8 /sdcard/gpbrf11_default.mp4 >/dev/null 2>&1 &
SRP=$!; sleep 9; kill $SRP 2>/dev/null || true; sleep 2
adb pull /sdcard/gpbrf11_default.mp4 "$OUT/../gpbrf11_default.mp4" >/dev/null 2>&1 || true
# still frame from the mp4 (screencap is black on the GL surface)
which ffmpeg >/dev/null 2>&1 && ffmpeg -y -i "$OUT/../gpbrf11_default.mp4" -vf "select=eq(n\,120)" -vframes 1 "$OUT/../gpbrf11_default.png" >/dev/null 2>&1 || true

# --- edit-mode capture of the PBR ISOLATE option value string ---
say "nav to PBR ISOLATE + enter EDIT mode to show the option value string"
tapb "start" 3.0; tapb "down"; tapb "down"; tapb "x" 3.0; tapb "down"; tapb "x" 3.0
for i in $(seq 1 8); do tapb "down" 1.6; done
tapb "x" 2.5
for i in $(seq 1 17); do tapb "down" 1.6; done
for i in $(seq 1 3); do tapb "down" 1.6; done         # PBR ISOLATE row
shot "07-isolate-row-selected"
tapb "x" 2.0; shot "08-isolate-EDITMODE-value"         # edit mode: option value carousel visible
tapb "right" 1.8; shot "09-isolate-EDITMODE-next"      # advance one option
tapb "right" 1.8; shot "10-isolate-EDITMODE-next2"
tapb "x" 1.5                                            # confirm (leaves at some option)
adb shell am force-stop $PKG; sleep 1
say "DONE — 07..10 edit-mode shots + fresh default mp4/png"
ls -la "$OUT"/07*.png "$OUT"/08*.png "$OUT"/09*.png "$OUT"/10*.png "$OUT/../gpbrf11_default.mp4" "$OUT/../gpbrf11_default.png" 2>&1
