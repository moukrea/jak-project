#!/usr/bin/env bash
# grass_p19b_beats.sh — post-gap-fix proof beats: terrace EDGE close-up, CRATE trample, RELIEF tilt A/B.
# Each beat: warp-boot, verify jak1 foreground, capture stills. Force-stop at the end (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
capck(){ local fo; fo=$(focus); $ADB exec-out screencap -p > "$1" 2>/dev/null
  echo "  cap $(basename "$1") = $(stat -c %s "$1" 2>/dev/null)B $(echo "$fo"|grep -q $PKG && echo FG-OK || echo FG-BAD)"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }

boot_warp(){ local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr19b_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s) ok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
    sleep 3
  done
  sleep 6; echo "  warp_ok=$ok pos=[$POS] $(focus)"; return $((1-ok)); }

EDGE_POS="${EDGE_POS:-}"   # caller passes a RIMCAND pos (plateau rim, y 14-20m preferred)
CRATE_POS="${CRATE_POS:--1362.5 16.2 1094.2}"
RELIEF_POS="${RELIEF_POS:--1407.0 8.5 1126.5}"

if [ -n "$EDGE_POS" ]; then
  say "EDGE beat @ [$EDGE_POS] — grass must STOP at the upper rim (gap cull), lower terrace grassed"
  boot_warp "$EDGE_POS" /tmp/gr19b_edge.log || echo "  (edge warp flaked)"
  grep -a 'ROUND#19b FLOORGAP' /tmp/gr19b_edge.log | tail -1
  capck "$F/p19b_edge_terrace_a.png"
  pulse "rx=185" 1.0 0.6; capck "$F/p19b_edge_terrace_b.png"   # pan
  pulse "ry=240" 0.9 0.6; capck "$F/p19b_edge_terrace_c.png"   # pitch down at the rim
  pulse "rx=175" 1.0 0.6; capck "$F/p19b_edge_terrace_d.png"
fi

say "CRATE beat @ [$CRATE_POS] — crate pressing a flat grass disc"
boot_warp "$CRATE_POS" /tmp/gr19b_crate.log || echo "  (crate warp flaked)"
capck "$F/p19b_crate_closeup_a.png"
pulse "rx=185" 0.9 0.6; capck "$F/p19b_crate_closeup_b.png"
pulse "rx=185" 0.9 0.6; capck "$F/p19b_crate_closeup_c.png"
pulse "rx=185" 0.9 0.6; capck "$F/p19b_crate_closeup_d.png"

say "RELIEF beat @ [$RELIEF_POS] — same-pose tilt A/B (0 vs 0.30)"
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
boot_warp "$RELIEF_POS" /tmp/gr19b_relief.log || echo "  (relief warp flaked)"
pulse "ry=240" 0.8 0.6   # pitch down at the slope, then DON'T move
sleep 2; capck "$F/p19b_relief_tiltA.png"
$ADB shell setprop debug.opengoal.grass_tilt 0.30 >/dev/null 2>&1
sleep 6                   # throttled prop read (~64 frames)
capck "$F/p19b_relief_tiltB.png"
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1

say "teardown"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr19b_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[p19b beats] DONE"
