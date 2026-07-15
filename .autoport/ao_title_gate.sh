#!/usr/bin/env bash
# ao_title_gate.sh — Grecharged-ambient-occlusion DEFECT #4 + #6 MANDATORY GATE.
# With the AO build deployed, the title flythrough must render fully TEXTURED (no
# purple/magenta untextured meshes) AND survive >=2 min alive at title in EVERY
# PERSISTED mode/quality combo. Defect #6 (native GTAO title crash on a persisted-high
# boot) means props are NOT sufficient: the crash only reproduces on the persisted
# settings path (renderscale-resize storm at boot), so this gate seeds the on-disk
# pc-settings.gc and BOOTS each of 12 combos fresh, instead of live-flipping props on one
# boot. Matrix (mode,quality): off/ssao/hbao/gtao x low/med/high = 12 boots.
# Per combo we assert: textured (purple-scan CLEAN on both recorded segments), >=120s
# alive at title, AOPERF mode/quality tracks the seeded values, and NO "SAFE-BOOT" line
# (the sentinel is cleared before each boot, so a SAFE-BOOT means seeding/clear failed).
# Produces: .autoport/reports/Grecharged-ambient-occlusion/title-gate/{TAG}-{a,b}.mp4 +
# frames + purple-scan verdicts + combo-{TAG}.log (full logcat) + crash-{TAG}/ evidence +
# libgk-under-test.so (A34 forensics archive) + per-combo PASS/FAIL + GATE summary.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"
SENTINEL="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/ao-boot-guard"
OUT=.autoport/reports/Grecharged-ambient-occlusion/title-gate; mkdir -p "$OUT"
LOGF="$OUT/gate-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }

# Seed the on-disk pc-settings.gc with a persisted AO mode+quality, then READ BACK and die
# if the values did not land (a failed push was the attempt-4 false-negative root cause).
# Returns 0 on verified seed, 1 otherwise. Args: MODE QUALITY.
seed_ao(){ local M="$1" Q="$2"
  $ADB -s $S shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_gate.gc 2>/dev/null
  if ! grep -qa 'ambient-occlusion' /tmp/pcs_ao_gate.gc; then
    say "  SEED FAIL: no ambient-occlusion key on device settings"; return 1; fi
  sed -i "s/(ambient-occlusion [0-9]*)/(ambient-occlusion $M)/; s/(ao-quality [0-9]*)/(ao-quality $Q)/" /tmp/pcs_ao_gate.gc
  $ADB -s $S push /tmp/pcs_ao_gate.gc "$SETTINGS_DEV" >/dev/null 2>&1
  local BACK; BACK=$($ADB -s $S shell cat "$SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "\((ambient-occlusion|ao-quality) [0-9]+\)" | tr '\n' ' ')
  case "$BACK" in
    *"(ambient-occlusion $M)"*) : ;;
    *) say "  SEED READBACK FAIL: wanted (ambient-occlusion $M), got: $BACK"; return 1 ;;
  esac
  case "$BACK" in
    *"(ao-quality $Q)"*) : ;;
    *) say "  SEED READBACK FAIL: wanted (ao-quality $Q), got: $BACK"; return 1 ;;
  esac
  say "  seeded+verified: $BACK"; return 0; }
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

say "== ao_title_gate: PERSISTED-MODE MATRIX (12 boots) — defect #6 =="
# Archive the EXACT binary under test for A34 forensics (build-id ties any crash-TAG
# dropbox tombstone back to this .so).
$ADB -s $S shell am force-stop $PKG; sleep 2
cp build-android/lib/arm64-v8a/libgk.so "$OUT/libgk-under-test.so"
readelf -n "$OUT/libgk-under-test.so" | grep -i 'build id' | tee -a "$LOGF"
# The matrix tests the PERSISTED path: ALL ao debug + warp props MUST be empty (a forced
# prop would mask the persisted-boot crash we are hunting).
$ADB -s $S shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
$ADB -s $S shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
$ADB -s $S shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1

GATE_OK=1; FAILN=0; PASSN=0
# TAG:MODE:QUALITY — off/ssao/hbao/gtao x low(0)/med(1)/high(2)
for combo in \
  "off-low:0:0"  "off-med:0:1"  "off-high:0:2" \
  "ssao-low:1:0" "ssao-med:1:1" "ssao-high:1:2" \
  "hbao-low:2:0" "hbao-med:2:1" "hbao-high:2:2" \
  "gtao-low:3:0" "gtao-med:3:1" "gtao-high:3:2" ; do
  IFS=: read -r TAG M Q <<<"$combo"
  say "-- combo $TAG (mode=$M quality=$Q, persisted boot) --"
  CLOG="$OUT/combo-$TAG.log"

  # 1. force-stop, seed disk + verify, clear the safe-boot sentinel (else this boot, which
  #    follows the previous combo's within-60s force-stop, would run AO forced-off).
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  if ! seed_ao "$M" "$Q"; then
    say "combo $TAG: FAIL(seed)"; GATE_OK=0; FAILN=$((FAILN+1)); continue
  fi
  $ADB -s $S shell rm -f "$SENTINEL" >/dev/null 2>&1

  # 2. fresh full logcat into the per-combo log (kill any prior logcat first).
  $ADB -s $S logcat -c -b all 2>/dev/null || true
  kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( $ADB -s $S logcat -b all -v threadtime > "$CLOG" 2>/dev/null & echo $! > /tmp/ao_lc.pid )

  # 3. boot + stabilize (foreground held 30s continuous, refront on loss, max 6 min).
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

  # 4. record the PID for the aliveness check.
  PID=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')

  # 5. two recorded segments (>=120s total alive at title past stabilization); purple/dark
  #    scan must pass on BOTH (retry-once-on-focus-loss, like the old loop).
  seg_all_ok=1
  for SUB in a b; do
    STAG="$TAG-$SUB"
    if ! fg_ok; then
      say "   FG-LOST before $STAG — re-fronting"
      refront || { say "   $STAG: FOCUS FAIL (cannot re-front jak1)"; seg_all_ok=0; break; }
    fi
    seg_ok=0
    for attempt in 1 2; do
      if rec_and_scan "$STAG" 55 | tee -a "$LOGF"; then
        if fg_ok; then seg_ok=1; break
        else say "   $STAG: focus lost DURING attempt#$attempt — refront + retry"; refront || break; fi
      else
        if fg_ok; then break   # genuine purple/black with app fronted: real FAIL
        else say "   $STAG: attempt#$attempt recorded a non-jak1 screen — refront + retry"; refront || break; fi
      fi
    done
    if [ "$seg_ok" = 1 ]; then say "   $STAG: purple-scan CLEAN (jak1 foreground)"
    else say "   $STAG: purple-scan FAIL (untextured/black or focus unrecoverable)"; seg_all_ok=0; fi
  done

  # 6. AOPERF assertion (mode+quality must track the seeded values): >=3 lines. And NO
  #    SAFE-BOOT (sentinel was cleared, so its presence means the seed/clear failed).
  APCOUNT=$(grep -ac "AOPERF mode=$M quality=$Q" "$CLOG" 2>/dev/null); APCOUNT=${APCOUNT:-0}
  say "   AOPERF mode=$M quality=$Q count: $APCOUNT (need >=3)"
  SB=0
  if grep -aq "SAFE-BOOT" "$CLOG" 2>/dev/null; then
    SB=1; say "   SAFE-BOOT present in combo log — seed/clear failed, AO ran forced-off"
  fi

  # 7. aliveness at end: pidof non-empty AND == the boot PID, and foreground jak1.
  ENDPID=$($ADB -s $S shell pidof $PKG 2>/dev/null | tr -d '\r')
  ALIVE=1
  if [ -z "$ENDPID" ] || [ "$ENDPID" != "$PID" ] || ! fg_ok; then
    ALIVE=0
    say "   ALIVENESS FAIL: boot PID=$PID end PID=$ENDPID fg=$(fg_ok && echo jak1 || echo other)"
    mkdir -p "$OUT/crash-$TAG"
    $ADB -s $S logcat -b crash -d > "$OUT/crash-$TAG/logcat-crash.txt" 2>/dev/null || true
    $ADB -s $S shell dumpsys dropbox --print 2>/dev/null | tail -200 > "$OUT/crash-$TAG/dropbox.txt" || true
    tail -400 "$CLOG" > "$OUT/crash-$TAG/combo-tail.txt" 2>/dev/null || true
  fi

  # combo verdict
  if [ "$seg_all_ok" = 1 ] && [ "$APCOUNT" -ge 3 ] && [ "$SB" = 0 ] && [ "$ALIVE" = 1 ]; then
    say "combo $TAG: PASS"; PASSN=$((PASSN+1))
  else
    REASON=""
    [ "$seg_all_ok" != 1 ] && REASON="$REASON purple/focus"
    [ "$APCOUNT" -lt 3 ] && REASON="$REASON aoperf<3"
    [ "$SB" != 0 ] && REASON="$REASON safe-boot"
    [ "$ALIVE" != 1 ] && REASON="$REASON died"
    say "combo $TAG: FAIL(${REASON# })"; GATE_OK=0; FAILN=$((FAILN+1))
  fi

  # 8. force-stop + kill the logcat before the next combo.
  $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
  kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
done

# restore the owner's default persisted state, clear the sentinel, force-stop.
say "== restore settings to AO Off / quality Medium =="
seed_ao 0 1 || true
$ADB -s $S shell rm -f "$SENTINEL" >/dev/null 2>&1
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
say "focus at end: $(focus)"

if [ "$GATE_OK" = 1 ]; then
  say "[TITLE-GATE PASS] all 12 persisted combos: textured title, 2min alive, AOPERF tracks seeding"
  exit 0
else
  say "[TITLE-GATE FAIL] $FAILN combos failed"
  exit 1
fi
