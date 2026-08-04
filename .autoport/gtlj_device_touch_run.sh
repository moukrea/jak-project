#!/usr/bin/env bash
# =====================================================================================
# Gtouch-longjump-regression — LIVE multi-touch gesture repro on device.
#
# Prereq: the current APK (with TouchReplayPlayer) is deployed + verified (deploy
# recipe: hd4_deploy_fresh.sh style). This script:
#   1. arms debug.opengoal.pad_replay=record + pad_replay_realtime=1 (records the
#      EXACT cpad stream the GOAL kernel consumes, under REAL pacing — the forced
#      1/60 timestep would mask a pacing-dependent bug) + f1.warp=1 geyser anchor
#   2. launches, waits for the pad_replay ANCHOR (warp spawn), settles
#   3. pushes the touch gesture script -> TouchReplayPlayer dispatches the owner's
#      3-finger long jump (stick fwd + l1r1 + X) x REPS through TouchOverlayView
#   4. harvests [JAK-HD-TGT] state trace + overlay/JNI/pad markers
#   5. pulls the cpad record and decodes it around every L1/R1 press edge
#
# Verdict logic: each rep should show target-wheel -> target-wheel-flip.
# duck-walk instead == owner's regression reproduced under synthetic touch.
# The decoded record then says whether the FAILING gate saw a bad stick (input
# chain) or a good stick (game-side gate) — the central discriminator.
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gtouch-longjump-regression; mkdir -p "$OUT"
RUN="${RUN:-r1}"; VARIANT="${VARIANT:-owner}"; REPS="${REPS:-5}"
LOG="$OUT/touchrun_${RUN}.txt"; : > "$LOG"
LC="$OUT/touchrun_${RUN}.logcat.log"; : > "$LC"
GESTURE=/tmp/gtlj_touch_${RUN}.txt
DEV_GESTURE=/storage/emulated/0/OpenGOAL/touch_replay.txt
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[gtlj FAIL] $*"; exit 1; }

say "===== gtlj touch run RUN=$RUN VARIANT=$VARIANT REPS=$REPS — $(date -Is) ====="
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not on adb"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
  die "device PIN-LOCKED — wait for owner"
fi

python3 .autoport/gtlj_gen_touch_gesture.py "$GESTURE" "$REPS" "$VARIANT" | tee -a "$LOG"

cleanup(){
  $ADB -s "$S" shell setprop debug.opengoal.dump.pos 0 >/dev/null 2>&1 || true
  kill "${POSP:-0}" 2>/dev/null || true
  $ADB -s "$S" shell setprop debug.opengoal.pad_replay '""' >/dev/null 2>&1 || true
  $ADB -s "$S" shell setprop debug.opengoal.pad_replay_realtime '""' >/dev/null 2>&1 || true
  $ADB -s "$S" shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1 || true
  $ADB -s "$S" shell rm -f "$DEV_GESTURE" "$DEV_GESTURE.done" >/dev/null 2>&1 || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
  kill "${LCP:-0}" 2>/dev/null || true
  say "cleanup: props cleared, gesture removed, app stopped"
}
trap cleanup EXIT

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
$ADB -s "$S" shell rm -f "$DEV_GESTURE" "$DEV_GESTURE.done" >/dev/null 2>&1 || true
$ADB -s "$S" shell run-as $PKG rm -f files/pad_demo.inputs >/dev/null 2>&1 || true
$ADB -s "$S" shell setprop debug.opengoal.pad_replay record
$ADB -s "$S" shell setprop debug.opengoal.pad_replay_realtime 1
$ADB -s "$S" shell setprop debug.opengoal.f1.warp 1
$ADB -s "$S" shell setprop debug.opengoal.dump.pos 1

$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
$ADB -s "$S" shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true

say "waiting for pad_replay ANCHOR (warp spawn)..."
T0=$(date +%s); OK=0
while [ $(( $(date +%s)-T0 )) -lt 300 ]; do
  if grep -aq "pad_replay: ANCHOR reached" "$LC"; then OK=1; break; fi
  sleep 3
done
[ "$OK" = 1 ] || die "ANCHOR never reached (see $LC)"
say "anchor reached at t+$(( $(date +%s)-T0 ))s; settling 8s"
sleep 8

grep -aq "touch-replay: watcher armed" "$LC" || say "WARN: watcher-armed marker not seen yet (MainActivity may lag; pushing anyway)"
$ADB -s "$S" push "$GESTURE" "$DEV_GESTURE" >/dev/null 2>&1 || die "gesture push failed"
say "gesture pushed; waiting for touch-replay DONE..."
# trajectory sampler: Jak's world pos (meters) ~every 2s -> pos_${RUN}.log
( while true; do
    P=$($ADB -s "$S" exec-out run-as $PKG head -1 files/pos_dump.txt 2>/dev/null | tr -d '\r')
    [ -n "$P" ] && echo "$(date +%s.%N) $P"
    sleep 2
  done >> "$OUT/pos_${RUN}.log" ) &
POSP=$!
T0=$(date +%s); OK=0
SPAN_S=$(( REPS * 10 + 30 ))
while [ $(( $(date +%s)-T0 )) -lt $SPAN_S ]; do
  if grep -aq "touch-replay: DONE" "$LC"; then OK=1; break; fi
  sleep 3
done
[ "$OK" = 1 ] || die "touch-replay never finished (started: $(grep -ac 'touch-replay: START' "$LC" || true) starts; see $LC)"
say "gesture done at t+$(( $(date +%s)-T0 ))s; settling 4s"
sleep 4
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 1

# ---- harvest --------------------------------------------------------------
grep -a "JAK-HD-TGT" "$LC" | sed 's/.*st=/st=/' | tr -d '\r' > "$OUT/states_${RUN}.txt"
grep -aE "touch-replay|overlay-actuate|kernel: pad:|pad_replay|onPadAxis|onPadButton" "$LC" > "$OUT/events_${RUN}.txt"
NW=$(grep -ac "st=target-wheel$" "$OUT/states_${RUN}.txt" || true)
NF=$(grep -ac "st=target-wheel-flip" "$OUT/states_${RUN}.txt" || true)
ND=$(grep -ac "st=target-duck-walk" "$OUT/states_${RUN}.txt" || true)
NJ=$(grep -ac "st=target-jump" "$OUT/states_${RUN}.txt" || true)
say "states: wheel=$NW wheel-flip=$NF duck-walk=$ND plain-jump=$NJ (expected: flip=$REPS duck=0)"

$ADB -s "$S" exec-out run-as $PKG cat files/pad_demo.inputs > "$OUT/record_${RUN}.inputs" 2>/dev/null || true
SZ=$(stat -c%s "$OUT/record_${RUN}.inputs" 2>/dev/null || echo 0)
[ "$SZ" -gt 64 ] || die "cpad record pull failed/empty ($SZ bytes)"
say "cpad record: $SZ bytes -> $OUT/record_${RUN}.inputs"
python3 .autoport/gtlj_decode_record.py "$OUT/record_${RUN}.inputs" | tee "$OUT/record_${RUN}.decoded.txt" | tail -n 60 | tee -a "$LOG"

if [ "$NF" -eq "$REPS" ] && [ "$ND" -eq 0 ]; then
  say "[gtlj RESULT] NO REPRO: $NF/$REPS wheel-flips, 0 duck-walk — gesture variant '$VARIANT' passes on this build"
else
  say "[gtlj RESULT] REPRO/PARTIAL: flips=$NF/$REPS duck-walk=$ND — inspect $OUT/record_${RUN}.decoded.txt vs states_${RUN}.txt"
fi
