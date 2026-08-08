#!/usr/bin/env bash
# foliage_wind2_device.sh — Grecharged-foliage-wind2 ROUND 2 device leg.
#
# What this is NOT: a visual-measurement campaign. The owner permanently banned those
# (2026-07-26 / 2026-08-04). No pixel stats, no image deltas, no motion ratios are computed here.
# The clips it records are ILLUSTRATION for the owner's eye only.
#
# What this IS, and the only thing it is gated on:
#   1. COVERAGE   — harvest the renderer's own `[foliage-wind] TIE census` lines (per level, per
#                   tree: wind_draws / wind_instances / static_draws / stiffness spread) from the
#                   REAL shipped .fr3 on the device.
#   2. ACTIVATION — harvest `[foliage-wind] TIE breeze ACTIVE` and `[foliage-wind] shrub sway
#                   ACTIVE` and `[foliage-wind] TIE flutter uniforms`. If those lines are absent the
#                   feature did not run, full stop.
#   3. LIVENESS   — no crash, and fps ON vs OFF.
# Amplitude itself is proven ALGEBRAICALLY in the report (shear is dimensionless: world
# displacement = shear * height-above-instance-origin), not from these clips.
#
# The amplitude knobs are live props read every 64 frames, so the sweep below needs NO rebuild.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'   # external-asset mode; files/.config is DEAD
OUT=.autoport/reports/Grecharged-foliage-wind2; DEV="$OUT/device"; mkdir -p "$DEV"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_foliage(){ # $1 = t|f — flips ONLY recharged-foliage-wind?, everything else stays as the owner left it
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/fw2_pcs.ini 2>/dev/null || true
  grep -q 'recharged-foliage-wind?' /tmp/fw2_pcs.ini || { echo "  FATAL: no recharged-foliage-wind? key in $PCS"; return 1; }
  sed -i "s/^recharged-foliage-wind? = #[tf]/recharged-foliage-wind? = #$1/" /tmp/fw2_pcs.ini
  $ADB push /tmp/fw2_pcs.ini "$PCS" >/dev/null 2>&1
  echo "  toggle now: $($ADB shell cat "$PCS" 2>/dev/null | grep -E 'recharged-(foliage-wind|master)\?' | tr -d '\r' | paste -sd' ')"; }

set_knobs(){ # $1=tie_mult $2=tie_amp $3=frond $4=shrub_amp ; "-" = clear the prop (use compiled default)
  for kv in "tie_mult=$1" "tie_amp=$2" "frond=$3" "shrub_amp=$4"; do
    k=${kv%%=*}; v=${kv#*=}
    if [ "$v" = "-" ]; then $ADB shell "setprop debug.opengoal.foliage.$k ''" >/dev/null 2>&1
    else $ADB shell "setprop debug.opengoal.foliage.$k $v" >/dev/null 2>&1; fi
  done
  echo "  knobs: $($ADB shell 'getprop | grep opengoal.foliage' 2>/dev/null | tr -d '\r' | paste -sd' ')"
  sleep 3; }   # knobs are re-read every 64 frames (~2 s at 30 fps)

# Boot + warp to a fixed pose. Retries because the first launch after a force-stop is flaky.
boot_warp(){ local CONT="$1" POS="$2" LOG="$3" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/fw2_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/fw2_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0; t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 170 ]; do
      grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 8; return 0; }
  done
  return 1; }

# Walk forward toward the palm line, then FREEZE. A static camera is deliberate: with no camera
# motion, anything that moves in the clip is the foliage itself.
approach(){ stick "ly=0"; sleep 4; stick neutral; sleep 3; }

rec(){ local TAG="$1" SECS="${2:-10}"
  $ADB shell rm -f "/sdcard/$TAG.mp4" >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 16000000 "/sdcard/$TAG.mp4" >/dev/null 2>&1
  sleep 1; $ADB pull "/sdcard/$TAG.mp4" "$DEV/$TAG.mp4" >/dev/null 2>&1
  $ADB shell rm -f "/sdcard/$TAG.mp4" >/dev/null 2>&1
  echo "  rec $TAG: $(stat -c %s "$DEV/$TAG.mp4" 2>/dev/null)B $(focus)"; }

fps(){ local tag="$1" f0 f1 dt=10
  f0=$($ADB logcat -d -v brief 2>/dev/null | grep -aoE 'A35-RENDER frame=[0-9]+' | tail -1 | grep -oE '[0-9]+$'); f0=${f0:-0}
  sleep $dt
  f1=$($ADB logcat -d -v brief 2>/dev/null | grep -aoE 'A35-RENDER frame=[0-9]+' | tail -1 | grep -oE '[0-9]+$'); f1=${f1:-$f0}
  echo "  PERF[$tag]: frames=$(( f1 - f0 )) over ${dt}s => ~$(awk "BEGIN{printf \"%.2f\", ($f1-$f0)/$dt}") fps"; }

harvest(){ local LOG="$1" tag="$2"
  echo "  --- [foliage-wind] lines ($tag) ---"
  grep -a "\[foliage-wind\]" "$LOG" | sed 's/^.*\[foliage-wind\]/[foliage-wind]/' | sort -u
  echo "  --- crash markers ($tag) ---"
  grep -acE 'signal (4|6|11) \(SIG|Fatal signal|FORTIFY' "$LOG" | sed 's/^/  crashlines=/'; }

BEACH_POS="-123.3 2.3 -54.6"
V1_POS="-156.0 34.0 188.0"

say "LEG 1/4 — beach, toggle OFF (stock reference)"
set_foliage f || exit 1
set_knobs - - - -
boot_warp beach-start "$BEACH_POS" "$DEV/beach-OFF.log" || { echo "[fw2 FAIL] beach OFF boot"; exit 1; }
approach
fps "beach-OFF"
rec "fw2-beach-OFF" 10
harvest "$DEV/beach-OFF.log" "beach-OFF"

say "LEG 2/4 — beach, toggle ON, COMPILED DEFAULTS (tie_mult=3.0 tie_amp=0.055 frond=0.10 shrub=0.16)"
set_foliage t || exit 1
set_knobs - - - -
boot_warp beach-start "$BEACH_POS" "$DEV/beach-ON.log" || { echo "[fw2 FAIL] beach ON boot"; exit 1; }
approach
fps "beach-ON-default"
sleep 12                      # let a full 300-frame shear-audit window close on the DEFAULTS
rec "fw2-beach-ON-default" 10

say "LEG 3/4 — beach, toggle ON, STRONGER SETTING via live props (NO rebuild)"
# One alternative point, not a shotgun sweep. Two purposes:
#   * it PROVES the live knobs reach the renderer — the shear-audit line must come back with a
#     larger applied_peak than the default leg did (round 1 could not show this: its only ACTIVE
#     log line was one-shot, so a prop change left no trace anywhere);
#   * it gives the owner a second, deliberately stronger reference clip so his verdict can be
#     "between these two" instead of just yes/no.
# The hold is 22 s because the audit window is 300 frames (~17 s at the ~18 fps measured here) —
# a shorter hold would report a window straddling the prop change and mixing both settings.
set_knobs 3.0 0.12 0.22 0.26
sleep 22
rec "fw2-beach-ON-strong-amp0.12-frond0.22" 10
fps "beach-ON-strong"
set_knobs - - - -
sleep 22
# harvested only NOW, after both settings have run: the round-1 script harvested before its sweep,
# which is structurally why no evidence of the swept values could ever exist in its output.
harvest "$DEV/beach-ON.log" "beach-ON (defaults + strong)"

say "LEG 4/4 — village1, toggle ON (coverage census for the second level)"
boot_warp village1-hut "$V1_POS" "$DEV/village1-ON.log" || echo "[fw2 WARN] village1 boot failed (census unavailable)"
sleep 4
harvest "$DEV/village1-ON.log" "village1-ON"
rec "fw2-village1-ON-default" 8

say "CLEANUP"
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/fw2_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "artifacts under $DEV/"
ls -la "$DEV/" | tail -20
