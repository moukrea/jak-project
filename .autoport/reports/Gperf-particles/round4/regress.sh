#!/usr/bin/env bash
# Gperf-particles round-4 regression: eco bursts (blue/red/yellow) + orb/HUD +
# flicker, with the CURRENT build (block_18 + quant + TOD memoize all ON), in
# Rock Village. Confirms the round-4 particle/TOD changes did NOT regress the
# same-family eco bursts, the orb HUD, or introduce flicker.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gperf-particles/round4/regress; mkdir -p "$OUT"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
S="${ANDROID_SERIAL:-eae4df44}"; ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT/regress-logcat.txt"
A(){ "$ADB" -s "$S" "$@"; }
A shell svc power stayon true >/dev/null 2>&1||true; A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1||true
# all fixes ON
for s in nospritelean nostatecache noinstance nooverlap notodpp noshrubidx no2dvec notodskip; do A shell setprop "debug.opengoal.perf.$s" 0 >/dev/null 2>&1; done
A shell setprop debug.opengoal.perf.buckets 1 >/dev/null 2>&1
A shell setprop debug.opengoal.level.warp village2-start >/dev/null 2>&1
A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1
for b in 1 2 3 4 5 6; do
  A shell am force-stop "$PKG" >/dev/null 2>&1||true; sleep 1
  A logcat -G 96M >/dev/null 2>&1; A logcat -c >/dev/null 2>&1; : > "$LOG"
  A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
  LP=$!; A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1||true
  WP=0
  for i in $(seq 1 170); do
    grep -qa 'LEVEL-WARP-SPAWN name=village2-start' "$LOG" && { WP=1; break; }
    grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" && break
    sleep 1
  done
  [ "$WP" = 1 ] && break
  echo "boot $b flake -> retry"; kill $LP 2>/dev/null
done
[ "$WP" = 1 ] || { echo "no boot"|tee "$OUT/ABORT.txt"; exit 4; }
trap 'kill $LP 2>/dev/null; A shell setprop debug.opengoal.eco.spawn "\"\"" >/dev/null 2>&1; A shell setprop debug.opengoal.level.warp "\"\"" >/dev/null 2>&1' EXIT
sleep 28
# ORB/HUD gameplay frame (money/orb count HUD is on-screen in gameplay)
A exec-out screencap -p > "$OUT/hud-gameplay.png" 2>/dev/null||true
# FLICKER: 12s screenrecord of the held fire scene
A shell screenrecord --time-limit 12 --size 1280x720 /sdcard/gpp_flicker.mp4 2>/dev/null &
RP=$!; wait $RP 2>/dev/null||true; sleep 1
A pull /sdcard/gpp_flicker.mp4 "$OUT/flicker.mp4" >/dev/null 2>&1||true
A shell rm /sdcard/gpp_flicker.mp4 >/dev/null 2>&1||true
# ECO bursts: blue(3) red(2) yellow(1); spawn continuously, capture several frames each
eco(){ local type="$1" name="$2"; A shell setprop debug.opengoal.eco.spawn "$type 31 0 3 0" >/dev/null 2>&1; sleep 6
  for k in 1 2 3; do A exec-out screencap -p > "$OUT/eco-$name-$k.png" 2>/dev/null||true; sleep 2; done
  A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1; sleep 4; }
eco 3 blue
eco 2 red
eco 1 yellow
A shell setprop debug.opengoal.eco.spawn '""' >/dev/null 2>&1
FOC=no; A shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|grep -q "$PKG" && FOC=yes
echo "focus=$FOC"
# crash + NaN scan
echo "crash_lines=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)|SIGSEGV|SIGILL' "$LOG")"
echo "spart_nan=$(grep -ac 'SPART-ORBPRE NaN\|nan\|NaN' "$LOG")"
kill $LP 2>/dev/null; trap - EXIT
A shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
echo "DONE regress; artifacts in $OUT"
ls -la "$OUT"
