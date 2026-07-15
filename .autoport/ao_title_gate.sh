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

rec_and_scan(){ # TAG SECS -> returns 0 if purple-clean
  local TAG="$1" SECS="$2"
  $ADB -s $S shell rm -f /sdcard/aogate.mp4 >/dev/null 2>&1
  $ADB -s $S shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/aogate.mp4 >/dev/null 2>&1
  sleep 1
  $ADB -s $S pull /sdcard/aogate.mp4 "$OUT/${TAG}.mp4" >/dev/null 2>&1
  $ADB -s $S shell rm -f /sdcard/aogate.mp4 >/dev/null 2>&1
  mkdir -p "$OUT/${TAG}_frames"; rm -f "$OUT/${TAG}_frames"/*.png
  ffmpeg -y -loglevel error -i "$OUT/${TAG}.mp4" -vf fps=1 "$OUT/${TAG}_frames/f_%03d.png" 2>/dev/null
  python3 - "$OUT/${TAG}_frames" <<'EOF'
import sys, os
import numpy as np
from PIL import Image
d = sys.argv[1]
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
print(f"frames={len(files)} worst_purple={worst:.3f}% at {worst_f} dark_frames={dark}")
# gate: any frame >0.5% purple, or >30% of frames near-black -> FAIL
ok = worst <= 0.5 and (len(files) == 0 or dark <= max(2, len(files) * 3 // 10))
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

GATE_OK=1
for combo in "off:100:: " "ssao:60:1:2" "hbao:60:2:2" "gtao:60:3:2"; do
  IFS=: read -r TAG SECS M Q <<<"$combo"
  if [ -n "${M// /}" ]; then ao_force "$M" "$Q"; sleep 6; else ao_clear; fi
  say "-- segment $TAG (${SECS}s) --"
  if rec_and_scan "$TAG" "$SECS" | tee -a "$LOGF"; then
    say "   $TAG: purple-scan CLEAN"
  else
    say "   $TAG: purple-scan FAIL (untextured/black frames)"; GATE_OK=0
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
