#!/usr/bin/env bash
# glp4_fbo_proof.sh — standalone render-scale-honors-settings FBO proof (streaming logcat: the
# single Dynamic-OFF FBO-setup line rotates out of the ring buffer, so `logcat -d` misses it).
# Pushes the menu-persisted settings variant (dynamic-render-scale? #f, render-scale 100, legacy
# game-size 640x480 KEPT to prove the update-to-os migration), clears every render-scale debug
# prop, boots to the heavy deck vantage, and captures the A35-RENDER FBO setup lines live.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-lightprobes/device
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
LOG="$OUT/glp4_fbo_proof.log"; : > "$LOG"
[ -f "$OUT/settings.ini.owner-backup" ] || { echo "[fbo-proof FAIL] no owner settings backup"; exit 1; }
[ -f /tmp/glp4_settings_C.ini ] || {
  sed -e 's/^pbr-materials? = .*/pbr-materials? = #f/' \
      -e 's/^load-custom-assets? = .*/load-custom-assets? = #f/' \
      -e 's/^dynamic-render-scale? = .*/dynamic-render-scale? = #f/' \
      -e 's/^render-scale = .*/render-scale = 100.0000/' \
      "$OUT/settings.ini.owner-backup" > /tmp/glp4_settings_C.ini
}
restore(){ $ADB -s $S push "$OUT/settings.ini.owner-backup" "$SET" >/dev/null 2>&1
           $ADB -s $S shell am force-stop $PKG </dev/null 2>/dev/null; }
trap restore EXIT
$ADB -s $S push /tmp/glp4_settings_C.ini "$SET" >/dev/null
$ADB -s $S shell "setprop debug.opengoal.renderscale.native ''; setprop debug.opengoal.render.scale ''; setprop debug.opengoal.tod.hour 8; setprop debug.opengoal.level.warp village1-hut; setprop debug.opengoal.level.warp.pos '-112.0 42.0 205.0'; am force-stop $PKG" </dev/null
sleep 2
$ADB -s $S logcat -c </dev/null 2>/dev/null
( $ADB -s $S logcat -v threadtime GK_STDOUT:I opengoal-gk:I '*:S' \
    | grep --line-buffered -aE 'A35-RENDER FBO setup|LEVEL-WARP-SPAWN' >> "$LOG" ) 2>/dev/null &
LCP=$!
$ADB -s $S shell am start -W -n $PKG/.LoaderActivity </dev/null >/dev/null 2>&1
ok=0
for i in $(seq 1 24); do
  sleep 5
  grep -aq 'LEVEL-WARP-SPAWN' "$LOG" && { ok=1; break; }
done
sleep 30   # well past load: any late FBO recreate (there must be none with Dynamic OFF) would show
kill "$LCP" 2>/dev/null || true
restore
echo "== FBO-PROOF (menu-persisted Dynamic-OFF/scale-100, zero debug props, legacy game-size kept) =="
cat "$LOG"
[ "$ok" = 1 ] || { echo "[fbo-proof FAIL] warp never spawned"; exit 1; }
grep -aq 'A35-RENDER FBO setup' "$LOG" || { echo "[fbo-proof FAIL] no FBO setup line captured"; exit 1; }
