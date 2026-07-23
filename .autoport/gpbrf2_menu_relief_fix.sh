#!/usr/bin/env bash
# Targeted TEXTURE RELIEF menu-edit proof: 17x down lands on SPECULAR INTENSITY (proven),
# so 1x UP = TEXTURE RELIEF. Edit X, right (+0.25), X -> disk must show 1.75.
set -uo pipefail
cd /home/emeric/code/jak-project
ADB=~/Android/platform-tools/adb; SER=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/menu-proof
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$SER" "$@"; }
say(){ echo "$*" | tee -a "$OUT/proof-log.txt"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.8; inject ""; sleep "${2:-2.0}"; }
fg_ok(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
shot(){ local FB
  FB=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null
  printf '%s\n' "$FB" > "$OUT/$1.focus.txt"; }
disk_relief(){ adb shell cat "$PCS" 2>/dev/null | tr -d '\r' | grep -aE '^pbr-(texture-relief|specular-intensity) = ' | tr '\n' ' '; echo; }

say "== RELIEF-FIX run: boot, nav, 17x down (=SPEC INT row), 1x UP (=TEXTURE RELIEF), edit +0.25 =="
adb shell am force-stop $PKG; sleep 2
say "disk pre: $(disk_relief)"
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 80
held=0; for i in $(seq 1 40); do
  if fg_ok; then held=$((held+1)); [ $held -ge 4 ] && break; else held=0; adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 8; fi
  sleep 6
done
say "  fg held=$held"
tapb "start" 3.0; tapb "down"; tapb "down"; tapb "x" 3.0; tapb "down"; tapb "x" 3.0
for i in $(seq 1 8); do tapb "down" 1.6; done
tapb "x" 2.5
for i in $(seq 1 17); do tapb "down" 1.6; done
tapb "up" 1.6; shot "11-relief-row-fix"
tapb "x" 1.5; tapb "right" 1.5; tapb "x" 2.0; shot "12-relief-committed-fix"
sleep 2
D=$(disk_relief); say "disk post-relief-edit: $D"
case "$D" in *"pbr-texture-relief = 1.75"*) say "RELIEF-EDIT-OK (menu row live-edits + persists)";;
  *) say "RELIEF-EDIT-MISSING (disk: $D)";; esac
adb shell am force-stop $PKG; sleep 2
say "[relief-fix] DONE"
