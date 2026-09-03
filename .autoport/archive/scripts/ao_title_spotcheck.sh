#!/usr/bin/env bash
# ao_title_spotcheck.sh — Grecharged-ambient-occlusion FAST STABILITY GATE.
# Owner order (2026-07-16 14:25): the full 15-combo persisted title matrix is DROPPED as a
# per-change gate ("40 minutes de test à chaque modif c'est impossible"). Replacement:
# ONE persisted boot on the historical worst case (GTAO + High + Stronger = defect #6's
# crash combo at the highest strength), 90s alive at title, purple-scan + AOPERF seed
# check. The full matrix ran once and passed on the near-final build (chain-attempt5.log
# 12:25:46 — TITLE-GATE PASS 15/15) — that stands as the one-time certification.
# Produces: title-gate/spotcheck-log.txt + gtao-strong-spot.mp4/frames + spot-combo.log.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
SENTINEL="/storage/emulated/0/OpenGOAL/jak1/ao-boot-guard"
OUT=.autoport/reports/Grecharged-ambient-occlusion/title-gate; mkdir -p "$OUT"
LOGF="$OUT/spotcheck-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }

# Seed the on-disk settings.ini, READ BACK, die if the values did not land.
# (Never local-name anything S in here — the S-shadow bug FAIL(seed)-ed 15 combos once.)
seed_ao(){ local M="$1" Q="$2" STRV="$3"
  $ADB -s $S shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_spot.gc 2>/dev/null
  if ! grep -qa 'ambient-occlusion' /tmp/pcs_ao_spot.gc; then
    say "  SEED FAIL: no ambient-occlusion key on device settings"; return 1; fi
  sed -i "s/^ambient-occlusion = [0-9]*/ambient-occlusion = $M/; s/^ao-quality = [0-9]*/ao-quality = $Q/; s/^ao-strength = [0-9]*/ao-strength = $STRV/" /tmp/pcs_ao_spot.gc
  grep -qa '^ao-strength = ' /tmp/pcs_ao_spot.gc || sed -i "/^ao-quality = [0-9]*/a\\ao-strength = $STRV" /tmp/pcs_ao_spot.gc
  $ADB -s $S push /tmp/pcs_ao_spot.gc "$SETTINGS_DEV" >/dev/null 2>&1
  local BACK; BACK=$($ADB -s $S shell cat "$SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "^(ambient-occlusion|ao-quality|ao-strength) = [0-9]+" | tr '\n' ' ')
  case "$BACK" in *"ambient-occlusion = $M"*) : ;; *) say "  SEED READBACK FAIL: wanted ambient-occlusion = $M, got: $BACK"; return 1 ;; esac
  case "$BACK" in *"ao-quality = $Q"*) : ;; *) say "  SEED READBACK FAIL: wanted ao-quality = $Q, got: $BACK"; return 1 ;; esac
  case "$BACK" in *"ao-strength = $STRV"*) : ;; *) say "  SEED READBACK FAIL: wanted ao-strength = $STRV, got: $BACK"; return 1 ;; esac
  say "  seeded+verified: $BACK"; return 0; }
focus(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
fg_ok(){ $ADB -s $S shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
refront(){ $ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  $ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  sleep 12; fg_ok; }

rec_and_scan(){ # TAG SECS -> returns 0 if purple-clean
  local TAG="$1" SECS="$2"
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
min_frames = max(5, secs // 3)
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
ok = len(files) >= min_frames and worst <= 0.5 and dark <= max(2, len(files) * 3 // 10)
sys.exit(0 if ok else 1)
EOF
}

say "== ao_title_spotcheck: worst-case persisted boot GTAO+High+Stronger (owner fast gate 2026-07-16) =="
readelf -n build-android/lib/arm64-v8a/libgk.so | grep -i 'build id' | sed 's/^/  under test:/' | tee -a "$LOGF"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1; sleep 2
# persisted path only: all ao debug + warp props must be empty
$ADB -s $S shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_strength ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
$ADB -s $S shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
$ADB -s $S shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1

OK=1
if ! seed_ao 3 2 2; then say "[TITLE-SPOTCHECK FAIL] seed"; exit 1; fi
$ADB -s $S shell rm -f "$SENTINEL" >/dev/null 2>&1

CLOG="$OUT/spot-combo.log"
$ADB -s $S logcat -c -b all 2>/dev/null || true
kill "$(cat /tmp/ao_spot_lc.pid 2>/dev/null)" 2>/dev/null || true
( $ADB -s $S logcat -b all -v threadtime > "$CLOG" 2>/dev/null & echo $! > /tmp/ao_spot_lc.pid )

$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 30
say "   focus at start: $(focus)"
t0=$(date +%s); held=0
while [ $(( $(date +%s)-t0 )) -lt 360 ]; do
  if fg_ok; then held=$((held+1)); [ "$held" -ge 4 ] && break
  else held=0; say "   (stabilize) FG-LOST — refront"; refront || true; fi
  sleep 8
done
[ "$held" -ge 4 ] && say "   foreground STABLE (30s continuous)" \
                  || say "   WARNING: foreground never stabilized in 6 min"
PID=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')

seg_ok=0
for attempt in 1 2; do
  if rec_and_scan "gtao-strong-spot" 90 | tee -a "$LOGF"; then
    if fg_ok; then seg_ok=1; break
    else say "   focus lost DURING attempt#$attempt — refront + retry"; refront || break; fi
  else
    if fg_ok; then break; else say "   attempt#$attempt recorded a non-jak1 screen — refront + retry"; refront || break; fi
  fi
done
if [ "$seg_ok" = 1 ]; then say "   gtao-strong-spot: purple-scan CLEAN (jak1 foreground, 90s)"
else say "   gtao-strong-spot: purple-scan FAIL"; OK=0; fi

APCOUNT=$(grep -ac "AOPERF mode=3 quality=2 strength=2" "$CLOG" 2>/dev/null); APCOUNT=${APCOUNT:-0}
say "   AOPERF mode=3 quality=2 strength=2 count: $APCOUNT (need >=3)"
[ "$APCOUNT" -ge 3 ] || OK=0
if grep -aq "SAFE-BOOT" "$CLOG" 2>/dev/null; then say "   SAFE-BOOT present — seed/clear failed"; OK=0; fi
ENDPID=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
if [ -z "$ENDPID" ] || [ "$ENDPID" != "$PID" ] || ! fg_ok; then
  say "   ALIVENESS FAIL: boot PID=$PID end PID=$ENDPID fg=$(fg_ok && echo jak1 || echo other)"
  mkdir -p "$OUT/crash-spot"
  $ADB -s $S logcat -b crash -d > "$OUT/crash-spot/logcat-crash.txt" 2>/dev/null || true
  $ADB -s $S shell dumpsys dropbox --print 2>/dev/null | tail -200 > "$OUT/crash-spot/dropbox.txt" || true
  OK=0
else
  say "   alive at end: PID $PID stable, focus $(focus)"
fi

# restore owner defaults + cleanup
seed_ao 0 1 1 || true
$ADB -s $S shell rm -f "$SENTINEL" >/dev/null 2>&1
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/ao_spot_lc.pid 2>/dev/null)" 2>/dev/null || true

if [ "$OK" = 1 ]; then
  say "[TITLE-SPOTCHECK PASS] worst-case GTAO+High+Stronger persisted boot: textured, 90s alive, AOPERF tracks seed, no SAFE-BOOT"
  exit 0
else
  say "[TITLE-SPOTCHECK FAIL]"
  exit 1
fi
