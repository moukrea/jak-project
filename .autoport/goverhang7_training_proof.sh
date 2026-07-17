#!/usr/bin/env bash
# goverhang7_training_proof.sh — round-7 OWNER-RESCOPE deliverable, all in one run:
#   1. training.grassbake sha check (device == build)
#   2. warp boot to the owner's TRAINING vantage (training-start terraces, facing platforms)
#   3. census harvest ([recharged-grass] GOVERHANG expand / STATIC place / PLACE-TIME)
#   4. 10s ON-baseline video + screenshot (settings file overhang? #t as-is)
#   5. LIVE menu toggle proof (goverhang7_menu_toggle.sh): ON->OFF (stateA vid) -> OFF->ON (stateB vid),
#      on-disk settings read after each flip
#   6. props reset + final settings-file diff vs pre-run (must be byte-identical: flip2 restores #t)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-grass-overhang7; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }

echo "== 1: training.grassbake sha (build vs device) =="
sha256sum out/jak1/fr3/training.grassbake | awk '{print "  build  "$1}'
adb shell sha256sum /storage/emulated/0/OpenGOAL/jak1/assets/fr3/training.grassbake | awk '{print "  device "$1}'

adb shell cat "$SETTINGS_DEV" > "$OUT/T-settings-before.gc"
grep -o "^recharged-grass-overhang? = #[tf]" "$OUT/T-settings-before.gc" | sed 's/^/  pre-run: /'

echo "== 2: warp boot to training vantage =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
adb logcat -c 2>/dev/null || true
adb shell setprop debug.opengoal.level.warp training-start
adb shell "setprop debug.opengoal.level.warp.pos '-1310.2 52.8 989.0'"
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
echo "  warp boot, settling 75s..."; sleep 75
fg | tee "$OUT/T-boot.focus"

echo "== 3: census harvest =="
adb logcat -d > "$OUT/T-training-boot-logcat.log" 2>/dev/null
grep -a "recharged-grass" "$OUT/T-training-boot-logcat.log" | grep -a "GOVERHANG expand\|STATIC place\|PLACE-TIME\|PRECOMPUTED" | cut -c1-260 | sed 's/^/  /'
echo "  sigfaults: $(grep -acE 'signal (11|6|4)' "$OUT/T-training-boot-logcat.log" || true)"

echo "== 4: ON baseline (10s) =="
adb exec-out screencap -p > "$OUT/T-training-on.png" 2>/dev/null
echo "  shot T-training-on.png ($(stat -c%s "$OUT/T-training-on.png" 2>/dev/null||echo 0)B)"
fg > "$OUT/T-training-on.focus"
adb shell "screenrecord --time-limit 10 /sdcard/gov7_T_on.mp4" & P=$!
sleep 12; wait $P 2>/dev/null || true
fg >> "$OUT/T-training-on.focus"
adb pull /sdcard/gov7_T_on.mp4 "$OUT/T-training-on.mp4" >/dev/null 2>&1
adb shell rm -f /sdcard/gov7_T_on.mp4 >/dev/null 2>&1 || true
mkdir -p "$OUT/T-training-on_frames"
ffmpeg -y -loglevel error -i "$OUT/T-training-on.mp4" -vf fps=2,scale=600:-1 "$OUT/T-training-on_frames/f_%03d.png"
echo "  rec T-training-on.mp4 ($(stat -c%s "$OUT/T-training-on.mp4" 2>/dev/null||echo 0)B) focus=$(cat "$OUT/T-training-on.focus" | tr '\n' '|')"

echo "== 5: LIVE menu toggle (ON->OFF stateA, OFF->ON stateB) =="
bash .autoport/goverhang7_menu_toggle.sh

echo "== 6: props reset + settings final check =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1 || true
adb shell cat "$SETTINGS_DEV" > "$OUT/T-settings-after.gc"
if cmp -s "$OUT/T-settings-before.gc" "$OUT/T-settings-after.gc"; then
  echo "  settings file RESTORED byte-identical (flip2 returned overhang? to pre-run value)"
else
  echo "  settings file DIFFERS post-run:"; diff "$OUT/T-settings-before.gc" "$OUT/T-settings-after.gc" | head -8
fi
echo "[gov7 training-proof] DONE"
