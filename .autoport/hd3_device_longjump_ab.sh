#!/usr/bin/env bash
# =====================================================================================
# Grecharged-hd-models3 defect-7 (long jump "cancelled" with HD ON) — DEVICE A/B.
#
# Same synthesized pad_replay v2 demo as the x86 A/B (hd3_gen_longjump_inputs.py:
# 3 roll+X long-jump combos in 3 stick directions + 1 duck high jump), replayed ON
# DEVICE via the Android channel (gk_android_main.cpp:9324: prop
# debug.opengoal.pad_replay=replay reads <files>/pad_demo.inputs), anchored at the
# geyser warp (prop debug.opengoal.f1.warp=1; kmachine.cpp:2804 defers the pad_replay
# anchor until the warp spawns Jak — same anchor as the x86 legs, same runway).
# Deterministic mode (1 logic tick per drawn frame, rng forced) — the device gameplay
# sim is the same instrument as x86, now with the real device renderer/loader load.
#
# Per-leg objective trace: [JAK-HD-TGT] st=<state> transition log (jak-hd.gc
# maybe-spawn-jak-hd!, runs EVERY frame on BOTH legs regardless of the toggle).
# Long jump = target-wheel -> target-wheel-flip. PASS = both legs reach wheel-flip
# the same number of times (3 expected from the demo).
# Cleanup ALWAYS: props cleared, demo file removed, owner's toggle restored, force-stop.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-AREE026206000788}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-hd-models3
LOG="$OUT/longjump_device_ab.txt"; : > "$LOG"
PCS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
INPUTS=/tmp/hd3_longjump.inputs
HEAD_T="${HEAD_T:-1200}"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[devAB FAIL] $*"; exit 1; }
pidof_app(){ $ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r'; }

set_enhanced(){ # $1 = enhanced '#t'|'#f', $2 = master '#t'|'#f' — BOTH matter:
  # Loader gates the enhanced fr3 on Gfx::recharged_active(enhanced) which folds in the
  # GLOBAL recharged-master? (Redmi bench had master #f -> 08:09 run silently STOCK with
  # enhanced-toggle=true). Both legs run master #t so the ONLY A/B variable is enhanced.
  local want="$1" master="$2" tmp; tmp=$(mktemp)
  $ADB -s "$S" pull "$PCS_DEV" "$tmp" >/dev/null 2>&1 || die "cannot pull $PCS_DEV"
  sed -i "s/recharged-enhanced-models? = #[tf]/recharged-enhanced-models? = $want/" "$tmp"
  sed -i "s/recharged-master? = #[tf]/recharged-master? = $master/" "$tmp"
  $ADB -s "$S" push "$tmp" "$PCS_DEV" >/dev/null 2>&1 || die "cannot push settings"; rm -f "$tmp"
  local now; now=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -aE 'recharged-(enhanced-models|master)\?' | tr -d '\r' | tr '\n' ' ')
  [[ "$now" == *"recharged-enhanced-models? = $want"* && "$now" == *"recharged-master? = $master"* ]] || die "toggle write did not stick ('$now')"
  say "device toggles: $now"
}

say "===== defect-7 DEVICE A/B (pad_replay, geyser anchor) — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED"; fi
bash .autoport/lib/deploy_verify.sh "$S" jak1 > "$OUT/devab.deploy_verify.log" 2>&1 \
  || { tail -4 "$OUT/devab.deploy_verify.log" | tee -a "$LOG"; die "deploy_verify FAILED"; }
say "deploy_verify: $(tail -1 "$OUT/devab.deploy_verify.log")"

python3 .autoport/hd3_gen_longjump_inputs.py "$INPUTS" "$HEAD_T" | tee -a "$LOG"
# run-as cannot read /sdcard on MIUI — stage via /data/local/tmp (dir is o+x, file made o+r)
$ADB -s "$S" push "$INPUTS" /data/local/tmp/hd3_pad_demo.inputs >/dev/null 2>&1 || die "push demo failed"
$ADB -s "$S" shell chmod 644 /data/local/tmp/hd3_pad_demo.inputs
$ADB -s "$S" shell run-as $PKG cp /data/local/tmp/hd3_pad_demo.inputs files/pad_demo.inputs || die "run-as cp demo failed"
SZ=$($ADB -s "$S" shell run-as $PKG stat -c %s files/pad_demo.inputs | tr -d '\r')
[ "$SZ" = "$(stat -c%s "$INPUTS")" ] || die "device demo size $SZ != local $(stat -c%s "$INPUTS")"
say "demo staged on device ($SZ bytes)"

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
ORIG_ENH=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-enhanced-models?' | grep -q '#t' && echo '#t' || echo '#f')
ORIG_MASTER=$($ADB -s "$S" shell cat "$PCS_DEV" 2>/dev/null | grep -a 'recharged-master?' | grep -q '#t' && echo '#t' || echo '#f')
say "pre-run values: enhanced=$ORIG_ENH master=$ORIG_MASTER (both restored at exit)"

cleanup(){
  $ADB -s "$S" shell setprop debug.opengoal.pad_replay '""' >/dev/null 2>&1 || true
  $ADB -s "$S" shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1 || true
  $ADB -s "$S" shell setprop debug.opengoal.cpad_inject release >/dev/null 2>&1 || true
  $ADB -s "$S" shell run-as $PKG rm -f files/pad_demo.inputs >/dev/null 2>&1 || true
  $ADB -s "$S" shell rm -f /data/local/tmp/hd3_pad_demo.inputs >/dev/null 2>&1 || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  set_enhanced "$ORIG_ENH" "$ORIG_MASTER" && say "cleanup: props cleared, demo removed, toggles restored (enh=$ORIG_ENH master=$ORIG_MASTER), force-stopped" \
    || say "cleanup WARNING: could not restore owner's toggles"
  kill "${LCP:-0}" 2>/dev/null || true
}
trap cleanup EXIT

run_leg(){ # off|on
  local LEG="$1" TOGGLE LC
  [ "$LEG" = on ] && TOGGLE='#t' || TOGGLE='#f'
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  set_enhanced "$TOGGLE" '#t'
  $ADB -s "$S" shell setprop debug.opengoal.pad_replay replay
  $ADB -s "$S" shell setprop debug.opengoal.f1.warp 1
  $ADB -s "$S" logcat -c >/dev/null 2>&1 || true
  LC="$OUT/devab_${LEG}.logcat.log"; : > "$LC"
  ( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' >> "$LC" ) 2>/dev/null &
  LCP=$!
  say "[$LEG] launching (pad_replay=replay, f1.warp=1)"
  $ADB -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local T0=$(date +%s) ANCH=0
  while [ $(( $(date +%s)-T0 )) -lt 300 ]; do
    grep -aq 'pad_replay: ANCHOR reached' "$LC" && { ANCH=1; break; }
    sleep 5
  done
  [ "$ANCH" = 1 ] || { say "[$LEG] FAIL: pad_replay anchor never reached (replay/warp props not honored?)"; grep -a 'pad_replay\|F1-SPAWN' "$LC" | head -4 | tee -a "$LOG"; return 1; }
  # toggle assertion from the loader's own decision line (the 06:36 x86 lesson)
  local FRSEL; FRSEL=$(grep -a 'HD-MODELS fr3-select GAME' "$LC" | head -1 | tr -d '\r')
  if [ "$LEG" = on ]; then [[ "$FRSEL" == *ENHANCED* ]] || { say "[$LEG] FAIL: toggle did not take ($FRSEL)"; return 1; }
  else [[ "$FRSEL" == *enhanced-toggle=false* ]] || { say "[$LEG] FAIL: not stock ($FRSEL)"; return 1; }; fi
  say "[$LEG] anchored + toggle verified: $FRSEL"
  # demo = 2656 ticks; device draws 30-60fps deterministic -> <=90s; watch by state trace growth
  local T1=$(date +%s) NDONE=0
  if [ "$LEG" = on ]; then
    ( $ADB -s "$S" shell screenrecord --time-limit 60 /sdcard/hd3_lj_on.mp4 >/dev/null 2>&1 ) &
    sleep 1; say "[on] screenrecord rolling (60s)"
  fi
  while [ $(( $(date +%s)-T1 )) -lt 240 ]; do
    kill -0 "$LCP" 2>/dev/null || die "logcat died"
    local P; P=$(pidof_app)
    [ -n "$P" ] || { say "[$LEG] app DIED mid-replay (itself a finding)"; break; }
    # the demo tail is 300 neutral ticks; once we see the last combo's landing states + quiet, stop
    NDONE=$(grep -ac 'JAK-HD-TGT' "$LC" | head -1); NDONE=${NDONE:-0}
    [ "$NDONE" -ge 8 ] && grep -aq 'st=target-stance' <(grep -a 'JAK-HD-TGT' "$LC" | tail -2) && [ $(( $(date +%s)-T1 )) -gt 120 ] && break
    sleep 10
  done
  [ "$LEG" = on ] && { $ADB -s "$S" pull /sdcard/hd3_lj_on.mp4 "$OUT/devab_on.mp4" >/dev/null 2>&1; $ADB -s "$S" shell rm -f /sdcard/hd3_lj_on.mp4 >/dev/null 2>&1; }
  grep -a 'JAK-HD-TGT' "$LC" | sed 's/.*st=/st=/' | tr -d '\r' > "$OUT/devab_${LEG}_states.txt"
  say "[$LEG] state transitions: $(wc -l < "$OUT/devab_${LEG}_states.txt")"
  $ADB -s "$S" shell setprop debug.opengoal.pad_replay '""' >/dev/null 2>&1 || true
  kill "$LCP" 2>/dev/null || true
  return 0
}

run_leg off || exit 1
run_leg on  || exit 1

{
  echo "=== defect-7 DEVICE A/B result (same demo, deterministic replay, geyser anchor) ==="
  for LEG in off on; do
    NW=$(grep -c '^st=target-wheel$' "$OUT/devab_${LEG}_states.txt" || true)
    NF=$(grep -c '^st=target-wheel-flip$' "$OUT/devab_${LEG}_states.txt" || true)
    NH=$(grep -cE '^st=target-(duck-)?high-jump' "$OUT/devab_${LEG}_states.txt" || true)
    echo "LEG $LEG: wheel-entries=$NW wheel-flip-entries=$NF high-jump-entries=$NH"
    echo "  sequence: $(tr '\n' ' ' < "$OUT/devab_${LEG}_states.txt" | sed 's/st=//g')"
  done
  OFF_F=$(grep -c '^st=target-wheel-flip$' "$OUT/devab_off_states.txt" || true)
  ON_F=$(grep -c '^st=target-wheel-flip$' "$OUT/devab_on_states.txt" || true)
  if [ "${OFF_F:-0}" -eq 0 ]; then echo "VERDICT: HARNESS-INCONCLUSIVE — OFF leg never long-jumped on device (demo/terrain issue)";
  elif [ "${ON_F:-0}" -lt "${OFF_F:-0}" ]; then echo "VERDICT: REPRODUCED ON DEVICE — HD ON loses long jumps ($ON_F vs $OFF_F)";
  else echo "VERDICT: DEVICE-CLEAN — long jump executes identically with HD ON ($ON_F) vs OFF ($OFF_F) on the same input"; fi
} | tee -a "$LOG"
