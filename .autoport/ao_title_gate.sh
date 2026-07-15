#!/usr/bin/env bash
# ao_title_gate.sh — Grecharged-ambient-occlusion DEFECT #4 MANDATORY GATE.
# With the AO build deployed, the title flythrough must render fully TEXTURED (no
# purple/magenta untextured meshes) in ALL modes: OFF (settings, no props) and each of
# SSAO/HBAO/GTAO forced live via debug props. A purple world = automatic FAIL — do not
# proceed to any further device testing.
# Produces: .autoport/reports/Grecharged-ambient-occlusion/title-gate/{TAG}.mp4 + frames +
# purple-scan verdicts + AOPERF lines per segment + GATE PASS/FAIL summary.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-ambient-occlusion/title-gate; mkdir -p "$OUT"
LOGF="$OUT/gate-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }
focus(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
ao_force(){ $ADB -s $S shell "setprop debug.opengoal.ao.force_mode '$1'" >/dev/null 2>&1
            $ADB -s $S shell "setprop debug.opengoal.ao.force_quality '$2'" >/dev/null 2>&1; }
ao_clear(){ $ADB -s $S shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
            $ADB -s $S shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1; }

fg_ok(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
refront(){ # bring the game back to the foreground (shared-device focus steals: MIUI home / parallel project)
  $ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  sleep 12
  fg_ok; }

rec_and_scan(){ # TAG SECS -> returns 0 if purple-clean
  local TAG="$1" SECS="$2"
  # attempt-4 hole: a leftover screenrecord (killed battery) starves the encoder -> 3.7KB
  # header-only mp4s, and the scan PASSed on frames=0. Kill strays, log screenrecord's own
  # output, and hard-require a real frame count.
  $ADB -s $S shell pkill screenrecord >/dev/null 2>&1; sleep 1
  $ADB -s $S shell rm -f /sdcard/aogate.mp4 >/dev/null 2>&1
  $ADB -s $S shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/aogate.mp4 2>&1 \
    | tail -3 | sed 's/^/   [screenrecord] /' | tee -a "$LOGF"
  sleep 1
  $ADB -s $S pull /sdcard/aogate.mp4 "$OUT/${TAG}.mp4" >/dev/null 2>&1
  $ADB -s $S shell rm -f /sdcard/aogate.mp4 >/dev/null 2>&1
  mkdir -p "$OUT/${TAG}_frames"; rm -f "$OUT/${TAG}_frames"/*.png
  ffmpeg -y -loglevel error -i "$OUT/${TAG}.mp4" -vf fps=1 "$OUT/${TAG}_frames/f_%03d.png" 2>/dev/null
  python3 - "$OUT/${TAG}_frames" "$SECS" <<'EOF'
import sys, os
import numpy as np
from PIL import Image
d = sys.argv[1]
secs = int(sys.argv[2])
min_frames = max(5, secs // 3)  # a SECS-long 1fps extraction must yield a real frame set
worst = 0.0; worst_f = ''; dark = 0
files = sorted(os.listdir(d))
for f in files:
    a = np.asarray(Image.open(os.path.join(d, f)).convert('RGB'), dtype=np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    purple = (r > 100) & (b > 100) & (g < 0.6 * np.minimum(r, b))
    frac = float(purple.mean()) * 100.0
    if frac > worst:
        worst, worst_f = frac, f
    if a.mean() < 15:
        dark += 1
print(f"frames={len(files)} (min {min_frames}) worst_purple={worst:.3f}% at {worst_f} dark_frames={dark}")
# gate: too few frames (dead recording), any frame >0.5% purple, or >30% near-black -> FAIL
ok = len(files) >= min_frames and worst <= 0.5 and dark <= max(2, len(files) * 3 // 10)
sys.exit(0 if ok else 1)
EOF
}

say "== fr3 integrity preamble: device files/out/jak1/fr3 must == out/jak1/fr3 (stock) =="
# A bundle-version change makes LoaderActivity WIPE files/out/jak1/fr3 before re-extract
# (and the cgo pack ships no fr3s) — verify + repair BEFORE judging purple, so the gate
# tests the AO pass, not a stale/missing texture set.
FR3_BAD=0
for f in out/jak1/fr3/*.fr3; do
  bn=$(basename "$f"); want=$(sha256sum "$f" | awk '{print $1}')
  got=$($ADB -s $S shell run-as $PKG sha256sum "files/out/jak1/fr3/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
  if [ "$got" != "$want" ]; then
    say "  fr3 STALE/MISSING on device: $bn — repairing"
    $ADB -s $S push "$f" "/data/local/tmp/$bn" >/dev/null 2>&1
    $ADB -s $S shell run-as $PKG mkdir -p files/out/jak1/fr3 >/dev/null 2>&1
    $ADB -s $S shell run-as $PKG cp "/data/local/tmp/$bn" "files/out/jak1/fr3/$bn"
    $ADB -s $S shell rm -f "/data/local/tmp/$bn" >/dev/null 2>&1
    got2=$($ADB -s $S shell run-as $PKG sha256sum "files/out/jak1/fr3/$bn" 2>/dev/null | awk '{print $1}' | tr -d '\r')
    [ "$got2" = "$want" ] || { say "  fr3 REPAIR FAILED: $bn"; FR3_BAD=1; }
  fi
done
[ "$FR3_BAD" = 0 ] && say "  fr3 set OK (all device fr3 == stock out/jak1/fr3)" \
                   || { say "[TITLE-GATE FAIL] fr3 repair failed"; exit 1; }

say "== ao_title_gate: boot to title with AO build, settings-OFF (props cleared) =="
$ADB -s $S shell am force-stop $PKG; sleep 2
ao_clear
$ADB -s $S shell setprop debug.opengoal.level.warp '""'
$ADB -s $S shell setprop debug.opengoal.level.warp.pos '""'
$ADB -s $S logcat -c 2>/dev/null || true
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 30
say "focus at start: $(focus)"
# Early-boot focus steals (MIUI popups over a fresh boot) hit the first segment: wait
# until jak1 holds the foreground CONTINUOUSLY for 30s (refront as needed, max 6 min).
t0=$(date +%s); held=0
while [ $(( $(date +%s)-t0 )) -lt 360 ]; do
  if fg_ok; then
    held=$((held+1)); [ "$held" -ge 4 ] && break
  else
    held=0; say "  (stabilize) FG-LOST — refront"; refront || true
  fi
  sleep 8
done
[ "$held" -ge 4 ] && say "foreground STABLE (30s continuous)" || say "WARNING: foreground never stabilized in 6 min"

GATE_OK=1
for combo in "off:100:: " "ssao:60:1:2" "hbao:60:2:2" "gtao:60:3:2"; do
  IFS=: read -r TAG SECS M Q <<<"$combo"
  if [ -n "${M// /}" ]; then ao_force "$M" "$Q"; sleep 6; else ao_clear; fi
  say "-- segment $TAG (${SECS}s) --"
  # focus-gated: a recording of the MIUI launcher is not evidence either way.
  if ! fg_ok; then
    say "   FG-LOST before $TAG — re-fronting"
    refront || { say "   $TAG: FOCUS FAIL (cannot re-front jak1)"; GATE_OK=0; continue; }
  fi
  seg_ok=0
  for attempt in 1 2; do
    if rec_and_scan "$TAG" "$SECS" | tee -a "$LOGF"; then
      if fg_ok; then seg_ok=1; break
      else say "   $TAG: focus lost DURING attempt#$attempt — refront + retry"; refront || break; fi
    else
      if fg_ok; then break   # genuine purple/black with app fronted: real FAIL
      else say "   $TAG: attempt#$attempt recorded a non-jak1 screen — refront + retry"; refront || break; fi
    fi
  done
  if [ "$seg_ok" = 1 ]; then
    say "   $TAG: purple-scan CLEAN (jak1 foreground)"
  else
    say "   $TAG: purple-scan FAIL (untextured/black frames or focus unrecoverable)"; GATE_OK=0
  fi
done
ao_clear
say "focus at end: $(focus)"
say "AOPERF lines per segment (mode must track the forced prop):"
$ADB -s $S logcat -d 2>/dev/null | grep -a "AOPERF" | tail -25 | tee -a "$LOGF"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
if [ "$GATE_OK" = 1 ]; then
  say "[TITLE-GATE PASS] world textured in OFF + SSAO + HBAO + GTAO"
  exit 0
else
  say "[TITLE-GATE FAIL] purple/untextured frames detected — DO NOT PROCEED"
  exit 1
fi
