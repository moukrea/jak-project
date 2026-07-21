#!/usr/bin/env bash
# glp2_battery.sh — Grecharged-lightprobes playtest#1/#2/#1b OBJECTIVE device battery.
# Runs every capture the reworked gates need, then prints all metrics. ~75 min device time.
# Captures (static = glp_capture.sh, native res; walk = glp2_walk_capture.sh, owner-realistic dyn RS):
#   MULTI-INTERIOR A/B : 4 auto-detected interiors x probe ON/OFF     (gate: interiors non-muted)
#   CONTRAST pair      : deck vantage ON/OFF                          (gate: contrast preserved)
#   REFLECTION no-op   : probes ON, refl ON vs OFF, same vantage      (gate: no grey wash)
#   NIGHT shadow pair  : hour 0 green-sun shadow ON/OFF               (gate: shadow visible)
#   WALK AO flicker    : AO=SSAO probes ON/OFF + AO=off probes ON     (gate: temporally stable)
#   MENU sweep         : screenrecord down-sweep of Recharged page    (gate: rename, no unknown-ID)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
SUM="$OUT/battery_summary.txt"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }

# RESUME=1: keep the summary + skip captures already made SINCE the stamp (mid-run battery aborts
# resume where they stopped; NEVER resume across a redeploy — the stamp is written at fresh-run start).
STAMP="$OUT/.capture_stamp"
if [ "${RESUME:-0}" = 1 ] && [ -f "$STAMP" ]; then
  echo "[glp2-battery] RESUME=1: skipping captures fresher than the last fresh-run stamp"
else
  : > "$SUM"; touch "$STAMP"
fi
say(){ echo "== $*" | tee -a "$SUM"; }
fresh(){ local m="$OUT/glp_$1.mp4"; [ -f "$m" ] || m="$OUT/glp2_$1.mp4"
  [ "${RESUME:-0}" = 1 ] && [ -f "$m" ] && [ "$m" -nt "$STAMP" ] && [ "$(ls "$OUT/frames_$1" 2>/dev/null | wc -l)" -ge 15 ]; }
# SUPERVISOR DEVICE GUARD: stop the run cleanly if the battery dips below 30% (PIN-lock risk).
batt_guard(){ local B; B=$(adb shell dumpsys battery </dev/null 2>/dev/null | grep -m1 -E '^  level' | grep -o '[0-9]*')
  if [ -n "${B:-}" ] && [ "$B" -lt 30 ]; then say "BATTERY ABORT: ${B}% < 30 (device guard) — rerun later with RESUME=1"; exit 3; fi; }
cap(){ local t="$1"; shift; if fresh "$t"; then say "skip $t (fresh)"; else batt_guard; bash .autoport/glp_capture.sh "$t" "$@" 2>&1 | tail -5 | tee -a "$SUM"; fi; }
wcap(){ local t="$1"; shift; if fresh "$t"; then say "skip $t (fresh)"; else batt_guard; bash .autoport/glp2_walk_capture.sh "$t" "$@" 2>&1 | tail -4 | tee -a "$SUM"; fi; }

# Interior warp targets = village1-actors.json NPC anchors (entities that STAND on real interior
# floors — the probe_bake cluster centers put Jak in the void, see attempt-5 forensics; y = actor y+0.8).
# int1 = Samos's/sage's hut (proven vantage, sage-23); int2 = ORACLE chamber (oracle-1);
# int3 = explorer/uncle's hut (explorer-4); int4 = farmhut (farmer-3).
declare -A IPOS=(
  [int1]="-133.0 40.0 207.0"
  [int2]="86.0 18.5 17.4"
  [int3]="-58.9 11.8 33.2"
  [int4]="-4.2 2.4 -66.1"
)
DECK="-112.0 42.0 205.0"

say "A. MULTI-INTERIOR A/B (4 interiors x probe ON/OFF, hour 8, native)"
for k in int1 int2 int3 int4; do
  for p in 1 0; do
    cap "b_${k}_p${p}" "$p" 0 1 village1-hut "${IPOS[$k]}" 8
  done
done

say "B. CONTRAST pair (deck, hour 8, native)"
cap b_ctr_on  1 0 1 village1-hut "$DECK" 8
cap b_ctr_off 0 0 1 village1-hut "$DECK" 8

say "C. REFLECTION no-op pair (probes ON, refl 1 vs 0, deck)"
cap b_refl_on  1 1 1 village1-hut "$DECK" 8
# refl-off reference = b_ctr_on (probe=1 refl=0, same vantage/hour)

say "D. NIGHT green-sun shadow pair (hour 0, deck, native)"
cap b_night_on  1 0 1 village1-hut "$DECK" 0
cap b_night_off 0 0 1 village1-hut "$DECK" 0

say "E. WALK AO-flicker (SSAO, probes ON/OFF; + AO-off probes ON; dyn RS = owner-realistic)"
wcap b_walk_p1_ao1 1 1 village1-hut "$DECK" 8 0
wcap b_walk_p0_ao1 0 1 village1-hut "$DECK" 8 0
wcap b_walk_p1_ao0 1 0 village1-hut "$DECK" 8 0

say "G. PROBE-FED MODEL TIERS (OWNER #3: Hemisphere/SH/IBL = eval fidelity of the PROBE data; probes ON, deck)"
cap b_model0 1 0 1 village1-hut "$DECK" 8 0
cap b_model1 1 0 1 village1-hut "$DECK" 8 1
cap b_model2 1 0 1 village1-hut "$DECK" 8 2
# analytic-fallback reference at the same vantage/model = b_ctr_off (probe=0, model default SH)

batt_guard
say "F. MENU sweep (screenrecord a full DOWN-sweep of the Recharged Settings page)"
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
tapb(){ stick "$1"; sleep 0.8; stick ""; sleep "${2:-1.8}"; }
adb shell am force-stop $PKG </dev/null; sleep 2
stick neutral
adb shell "setprop debug.opengoal.rt.probe ''" </dev/null
adb shell "setprop debug.opengoal.renderscale.native ''" </dev/null
adb shell "setprop debug.opengoal.ao.force_mode ''" </dev/null
adb shell "setprop debug.opengoal.tod.hour ''" </dev/null
adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
adb shell "setprop debug.opengoal.level.warp.pos '$DECK'" </dev/null
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null || true
sleep 60   # boot + ND logo + level load, then in-game
FOCUS_MENU=$(adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r')
say "menu-run focus: $FOCUS_MENU"
adb shell rm -f /sdcard/glp2_menu.mp4 </dev/null
( adb shell screenrecord --time-limit 120 --bit-rate 8000000 /sdcard/glp2_menu.mp4 </dev/null ) &
RECP=$!
sleep 2
tapb "start" 3.0                                 # pause menu
tapb "down"; tapb "down"; tapb "x" 3.0           # OPTIONS
tapb "down"; tapb "x" 3.0                        # GRAPHIC OPTIONS
for i in $(seq 1 8); do tapb "down" 1.4; done    # -> RECHARGED SETTINGS row
tapb "x" 2.5                                     # enter recharged page
for i in $(seq 1 22); do tapb "down" 1.6; done   # full sweep past every row (wraps at end)
wait $RECP 2>/dev/null || true
sleep 1
adb pull /sdcard/glp2_menu.mp4 "$OUT/glp2_menu.mp4" >/dev/null 2>&1
adb shell rm -f /sdcard/glp2_menu.mp4 </dev/null
mkdir -p "$OUT/frames_b_menu"; rm -f "$OUT/frames_b_menu"/*.png
ffmpeg -y -loglevel error -i "$OUT/glp2_menu.mp4" -vf fps=1 "$OUT/frames_b_menu/m_%03d.png" 2>/dev/null
stick neutral
adb shell am force-stop $PKG </dev/null
say "menu frames: $(ls "$OUT/frames_b_menu" | wc -l)"

say "==================== METRICS ===================="
say "-- interiors: luma + RGB (ON vs OFF per interior)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_int?_p? 2>&1 | tee -a "$SUM"
say "-- interiors: contrast (detail preservation inside)"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_int?_p? 2>&1 | tee -a "$SUM"
say "-- contrast pair (deck): luma + contrast"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
say "-- reflections no-op (b_refl_on vs b_ctr_on must be ~identical)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_refl_on "$OUT"/frames_b_ctr_on 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_refl_on "$OUT"/frames_b_ctr_on 2>&1 | tee -a "$SUM"
say "-- ground grid-pattern FFT (ON vs OFF: no probe-added periodicity)"
python3 .autoport/glp2_measure.py gridfft "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
say "-- night green-sun shadow contrast (ON vs OFF: shadow stays visible)"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_b_night_on "$OUT"/frames_b_night_off 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_night_on "$OUT"/frames_b_night_off 2>&1 | tee -a "$SUM"
say "-- AO temporal stability on movement (probe ON vs OFF vs AO-off)"
python3 .autoport/glp2_measure.py flicker "$OUT"/frames_b_walk_p1_ao1 "$OUT"/frames_b_walk_p0_ao1 "$OUT"/frames_b_walk_p1_ao0 2>&1 | tee -a "$SUM"
say "-- probe-fed model tiers (H vs SH vs IBL must DIFFER with probes ON; each vs analytic b_ctr_off)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_model0 "$OUT"/frames_b_model1 "$OUT"/frames_b_model2 "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py pairdiff "$OUT"/frames_b_model0 "$OUT"/frames_b_model1 "$OUT"/frames_b_model2 "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
say "battery DONE"
