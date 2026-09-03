#!/usr/bin/env bash
# gmc_boot_audit.sh — Grecharged-mesh-consolidation device audit harvest.
# libgk was built + deployed by .autoport/gpbrf_redeploy_freshbuild.sh (deploy_verify PASS).
# This stage: clear the audit file, seed TOD noon, boot, capture >=150s of logcat, prove
# jak1 foreground at the END, pull files/mesh_audit.txt.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-mesh-consolidation/device; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo; echo "######## $* ########"; }

say "A. stop app, clear the stale audit file (PROVE this boot wrote it)"
adb shell am force-stop $PKG >/dev/null 2>&1 || true
sleep 3
adb shell "run-as $PKG rm -f files/mesh_audit.txt" >/dev/null 2>&1 || true
echo "  after rm, ls files/mesh_audit.txt:"
adb shell "run-as $PKG ls -la files/mesh_audit.txt" 2>&1 | tr -d '\r' | sed 's/^/    /'

say "B. settings readback (the gate: pbr-materials? and realtime-lighting? must be #t)"
adb shell "cat /storage/emulated/0/OpenGOAL/jak1/settings.ini" 2>/dev/null \
  | grep -aE '^(recharged-master\?|pbr-materials\?|realtime-lighting\?|pbr-isolate|pbr-displacement|pbr-texture-relief)' \
  | tr -d '\r' | tee "$OUT/settings_readback.txt"

say "C. seed props"
adb shell setprop debug.opengoal.tod.hour 12
adb shell setprop debug.opengoal.recharged 1
adb shell setprop debug.opengoal.rt.light 1
adb shell setprop debug.opengoal.pbr.kill 0
adb shell setprop debug.opengoal.cpad_inject neutral
adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell getprop debug.opengoal.tod.hour | tr -d '\r' | sed 's/^/  tod.hour=/'

say "D. launch + capture 190s of logcat"
adb logcat -c >/dev/null 2>&1 || true
LOG="$OUT/boot-logcat.log"; : > "$LOG"
( timeout 200 "$ADB" -s $S logcat -v threadtime GK_STDOUT:V GK_STDERR:V opengoal-gk:V DEBUG:V libc:V '*:I' >> "$LOG" ) 2>/dev/null &
LCP=$!
sleep 2
T_LAUNCH=$(date +%s)
adb shell am start -W -n "$PKG/$ACT" 2>&1 | tr -d '\r' | sed 's/^/  /'
echo "  launched at $(date -d @$T_LAUNCH '+%T'); capturing..."
wait $LCP 2>/dev/null || true
T_END=$(date +%s)
echo "  capture window = $((T_END - T_LAUNCH))s past launch; logcat lines=$(wc -l < "$LOG")"

say "E. foreground proof at END of capture"
adb shell dumpsys window 2>/dev/null | grep -aE 'mCurrentFocus|mFocusedApp' | tr -d '\r' > "$OUT/focus.txt"
cat "$OUT/focus.txt"
adb shell "pidof $PKG" | tr -d '\r' | sed 's/^/  pid=/'

say "F. pull mesh_audit.txt"
adb shell "run-as $PKG ls -la files/mesh_audit.txt" 2>&1 | tr -d '\r' | sed 's/^/  /'
adb exec-out run-as $PKG cat files/mesh_audit.txt > "$OUT/mesh_audit_device.txt" 2>"$OUT/mesh_audit_pull_err.txt" || true
echo "  pulled bytes=$(stat -c %s "$OUT/mesh_audit_device.txt" 2>/dev/null || echo 0)"
[ -s "$OUT/mesh_audit_pull_err.txt" ] && { echo "  pull stderr:"; sed 's/^/    /' "$OUT/mesh_audit_pull_err.txt"; }
echo "[gmc] stage done"
