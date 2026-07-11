#!/usr/bin/env bash
# grass_p18_capture.sh — ROUND#18 proof:
#   (A) the round#17 COLLISION clip is REVERTED -> the 50cm straight bald strips are GONE (pure mesh).
#   (B) NEW object-clip hides grass under the CRATES + the WARP-GATE BUTTON (merc actors). We VERIFY on
#       device that Merc2 actually captured those objects by name (logcat "object-occluder captured"),
#       then capture the spawn view (crates+button, grass NOT poking through) ON vs OFF.
#   (C) a platform-edge close-up (no bald strips; honest overflow check).
# Harvests RIMDIST + the object-occluder census. Refreshes now.png + a moving mp4. Force-stops (hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[p18 FAIL] $*" >&2; exit 1; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject neutral; sleep "${3:-1.0}"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }

set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs18.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs18.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs18.gc
    $ADB push /tmp/pcs18.gc /data/local/tmp/pcs18.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs18.gc "$PCS" 2>/dev/null || true; $ADB shell rm -f /data/local/tmp/pcs18.gc >/dev/null 2>&1
  fi
  echo "  grass now: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"; }

boot_warp(){ local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr18_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 170 ]; do grep -qa 'link finish: logo' "$LOG" && break; grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break; sleep 2; done
  local ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }; grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break; sleep 3; done
  sleep 6; echo "  warp_ok=$ok"; return $((1-ok)); }

record_walk(){ local TAG="$1"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  ( $ADB shell screenrecord --time-limit 22 --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 ) & local REC=$!
  sleep 1
  # slow 360 pan + a little forward walk so the crates + warp button pass through frame
  for turn in "rx=175" "rx=175" "rx=175" "rx=175" "rx=175" "rx=175"; do
    stick "$turn"; sleep 1.1; stick "neutral"; sleep 0.5; stick "ly=0"; sleep 0.8; stick "neutral"; sleep 0.3
  done
  stick "neutral"; wait $REC 2>/dev/null || true; sleep 1
  $ADB pull /sdcard/${TAG}.mp4 "$OUT/${TAG}.mp4" >/dev/null 2>&1 && echo "  pulled ${TAG}.mp4=$(stat -c %s "$OUT/${TAG}.mp4" 2>/dev/null)B"; }

# pan the camera in yaw steps, capturing a still at each, so at least one frames the crates/button
pan_shots(){ local TAG="$1"; local n=0
  stick "ry=232"; sleep 1.0; stick "neutral"; sleep 0.4   # slight look-down at the ground objects
  for a in 0 1 2 3 4 5 6 7; do
    cap "${TAG}_${n}"
    pulse "rx=190" 0.9 0.4
    n=$((n+1))
  done
  echo "  focus=$(focus)"; }

edge_shots(){ local TAG="$1"
  stick "ry=245"; sleep 1.4; stick "neutral"; sleep 0.4; cap "${TAG}_a"
  pulse "rx=200" 1.0 0.5; stick "ry=235"; sleep 0.9; stick "neutral"; sleep 0.4; cap "${TAG}_b"
  stick "ly=0"; sleep 1.3; stick "neutral"; sleep 0.6; stick "ry=242"; sleep 0.8; stick "neutral"; sleep 0.4; cap "${TAG}_c"
  echo "  focus=$(focus)"; }

# ===== 0. sanity: device runs the fresh libgk =====
say "0. deploy_verify (device runs the round#18 libgk)"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -3 || die "deploy_verify FAIL"

# ===== 1. grass ON: boot at spawn, VERIFY object capture, cap spawn + object views, moving mp4 =====
say "1. grass ON @ Geyser Rock spawn — verify object-occluder capture + cap crates/button"
set_grass t
boot_warp "" /tmp/gr18_on.log
echo "  focus=$(focus)"
: > "$OUT/p18_instrument.txt"
echo "=== ROUND#18 object-occluder census (Merc2 name match on device) ===" | tee -a "$OUT/p18_instrument.txt"
grep -aE 'recharged-grass\] ROUND#18 object-occluder captured' /tmp/gr18_on.log | sort -u | tee -a "$OUT/p18_instrument.txt"
echo "=== RIMDIST (pure-mesh placement, collision clip REVERTED) ===" | tee -a "$OUT/p18_instrument.txt"
grep -aE 'recharged-grass\] RIMDIST' /tmp/gr18_on.log | tail -2 | tee -a "$OUT/p18_instrument.txt"
echo "=== any residual ROUND#17 collision log (should be NONE) ===" | tee -a "$OUT/p18_instrument.txt"
grep -acE 'recharged-grass\] ROUND#17 WALKABLE-FLOOR|col_dropped|cantilever' /tmp/gr18_on.log | tee -a "$OUT/p18_instrument.txt"
grep -aoE 'pos="[^"]+"' /tmp/gr18_on.log | sed 's/pos=//;s/"//g' | head -8 > /tmp/gr18_coords.txt
cap now
cap p18_spawn_on
pan_shots p18_objclip_on
record_walk grass_p18_move
command -v ffmpeg >/dev/null 2>&1 && [ -s "$OUT/grass_p18_move.mp4" ] && ffmpeg -y -loglevel error -i "$OUT/grass_p18_move.mp4" -vf fps=2 "$F/grass_p18_move_%03d.png" 2>/dev/null

# ===== 2. grass ON: a raised platform edge (bald strips gone; honest overflow check) =====
say "2. grass ON @ a raised platform edge (bald-strip + overflow check)"
mapfile -t COORDS < /tmp/gr18_coords.txt
P0="${COORDS[0]:-}"; P1="${COORDS[3]:-}"
echo "  P0=[$P0] P1=[$P1]"
if [ -n "$P0" ]; then boot_warp "$P0" /tmp/gr18_edge0.log || echo "  edge0 flaked"; edge_shots p18_edge_0_on; fi
if [ -n "$P1" ]; then boot_warp "$P1" /tmp/gr18_edge1.log || echo "  edge1 flaked"; edge_shots p18_edge_1_on; fi

# ===== 3. grass OFF: same spawn -> OFF==stock A/B (crates/button, no 3D grass) =====
say "3. grass OFF @ spawn (OFF==stock A/B)"
set_grass f
boot_warp "" /tmp/gr18_off.log
cap p18_spawn_off
pan_shots p18_objclip_off
echo "  focus=$(focus)"

# ===== 4. restore ON + force-stop (device hygiene) =====
say "4. restore grass ON + FORCE-STOP"
set_grass t
$ADB shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr18_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[p18] DONE — p18_spawn/objclip/edge frames + p18_instrument.txt in $OUT"
