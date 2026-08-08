#!/usr/bin/env bash
# Grecharged-hud-jak1 ROUND 5 — x86 ground truth (owner methodology 2026-07-09: judge LOOKS on
# x86 at 100% render scale, keep the device for arm64 structural behaviour).
# Boots warped into Geyser Rock, drives the recharged HUD through every state via the goalc
# listener, and dumps CODE-LEVEL facts (per-launch-control user-hvdf matrix index, hud state,
# health/eco) next to named screenshots. The frames are for the owner's eye; the matrix/state
# dumps are the objective proof.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk
OUT=.autoport/reports/Grecharged-hud-jak1/round5/x86
mkdir -p "$OUT"
LOG=/tmp/rhud5x86; rm -rf "$LOG"; mkdir -p "$LOG"
SHOTDIR=build/game/OpenGOAL/jak1/screenshots
XAUTH="$(ls /run/user/1000/.mutter-Xwaylandauth* 2>/dev/null | head -1)"

[ -x "$GK" ] || { echo "no $GK"; exit 1; }
pkill -f "[b]uild/game/gk" 2>/dev/null; sleep 2
pkill -f "[g]oalc --game jak1" 2>/dev/null; sleep 1
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/*.png

DISPLAY="${DISPLAY:-:0}" XAUTHORITY="$XAUTH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
OG_LEVEL_WARP=training-start \
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -- -boot -debug-mem > "$LOG/gk.log" 2>&1 &
GKPID=$!
cleanup(){ kill $GKPID 2>/dev/null; pkill -f "[g]oalc --game jak1" 2>/dev/null; }
trap cleanup EXIT

t=0
until grep -qa "LEVEL-WARP-SPAWN" "$LOG/gk.log"; do
  sleep 3; t=$((t+3))
  kill -0 $GKPID 2>/dev/null || { echo "gk died during boot"; tail -25 "$LOG/gk.log"; exit 1; }
  [ $t -ge 300 ] && { echo "no warp after ${t}s"; tail -20 "$LOG/gk.log"; exit 1; }
done
echo "warped after ${t}s; settling"
sleep 20

rm -f "$LOG/fifo"; mkfifo "$LOG/fifo"
( build/goalc/goalc --game jak1 --proj-path . --disable-ansi < "$LOG/fifo" > "$LOG/goalc.log" 2>&1 ) &
exec 9>"$LOG/fifo"
snd(){ printf '%s\n' "$1" >&9; sleep "${2:-1.5}"; }
snd '(lt)' 8
grep -qa "Got version" "$LOG/goalc.log" || { snd '(lt)' 8; }
grep -qa "Got version" "$LOG/goalc.log" || { echo "LISTENER NOT CONNECTED"; tail -20 "$LOG/goalc.log"; exit 1; }
echo "listener connected"

# (mi) is MANDATORY before any probe: a freshly started goalc has an EMPTY compiler
# environment, so every form referencing a game symbol (*target*, *pc-settings*,
# *hud-parts-pc*, (pickup-type eco-blue) ...) fails with "looked up as a global variable,
# but it does not exist" — silently, since the REPL error never reaches the game. That is
# how the first pass of this script produced 19 screenshots of the SAME idle frame.
echo "recompiling the project into the running game ((mi)) — a few minutes"
snd '(mi)' 5
mi_t=0
until grep -qa "RHUD5-READY" "$LOG/goalc.log" "$LOG/gk.log" 2>/dev/null; do
  sleep 15; mi_t=$((mi_t+15))
  printf '%s\n' '(format 0 "RHUD5-READY~%")' >&9
  [ $mi_t -ge 480 ] && { echo "(mi) never made the env usable after ${mi_t}s"; tail -25 "$LOG/goalc.log"; exit 1; }
done
echo "compiler env usable after ${mi_t}s"

shot(){
  snd '(pc-screen-shot)' 3
  local f; f=$(ls -t "$SHOTDIR"/*.png 2>/dev/null | head -1)
  if [ -n "$f" ]; then mv "$f" "$OUT/x86-$1.png"; echo "  shot x86-$1.png"; else echo "  shot $1 MISSING"; fi
}
# ONE LINE — the fifo feeds the repl line by line, a multi-line form never closes its parens.
probe(){
  # GOAL functions cap at 8 params -> two format calls, each <= 8 args.
  snd "(let ((h (-> *hud-parts-pc* recharged-health 0))) (format 0 \"RHUD5a $1 hmtx ~D hnb ~D hhid ~A hp ~F~%\" (-> h particles 0 part matrix) (-> h nb-of-particles) (hidden? h) (-> *target* fact health)))" 1.2
  snd "(let ((p (-> *hud-parts-pc* recharged-power 0))) (format 0 \"RHUD5b $1 pmtx ~D ~D ~D phid ~A lastidx ~D~%\" (-> p particles 0 part matrix) (-> p particles 1 part matrix) (-> p particles 2 part matrix) (hidden? p) (-> (the-as hud-recharged-power p) last-eco-idx)))" 1.2
}

# native render scale — fidelity must never be judged off a dynamically-downscaled frame
snd '(set! (-> *pc-settings* dynamic-render-scale?) #f)' 0.7
snd '(set! (-> *pc-settings* render-scale) 100.0)' 0.7

echo "== OFF baseline (stock hud) =="
snd '(set! (-> *pc-settings* recharged-hud?) #f)' 2
snd '(set! (-> *target* fact health) 3.0)' 1
snd '(set! (-> *target* fact eco-type) (pickup-type eco-blue))' 0.5
snd '(set! (-> *target* fact eco-timeout) (-> *FACT-bank* eco-full-timeout))' 0.5
snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
probe OFF-blue
shot off_stock_blue_full
snd '(set! (-> *target* fact health) 1.0)' 2
probe OFF-hp1
shot off_stock_hp1

echo "== ON =="
snd '(set! (-> *pc-settings* recharged-hud?) #t)' 3
probe ON-initial

echo "-- heart buckets --"
for hp in 3.0 2.0 1.0 0.0; do
  snd "(set! (-> *target* fact health) $hp)" 2.5
  probe "ON-hp$hp"
  shot "on_heart_hp${hp%%.*}"
done
sleep 0.5; shot on_heart_hp0_b
snd '(set! (-> *target* fact health) 1.0)' 2
shot on_heart_hp1_fade_a
sleep 0.5
shot on_heart_hp1_fade_b
snd '(set! (-> *target* fact health) 3.0)' 2

echo "-- eco gauge per type + fill fractions --"
for t in eco-blue eco-red eco-yellow; do
  snd "(set! (-> *target* fact eco-type) (pickup-type $t))" 0.5
  snd '(set! (-> *target* fact eco-timeout) (-> *FACT-bank* eco-full-timeout))' 0.5
  snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2.5
  probe "ON-$t-full"
  shot "on_gauge_${t}_full"
  sleep 8
  probe "ON-$t-mid"
  shot "on_gauge_${t}_mid"
done

echo "-- green eco pickup: heart must POP with the counter --"
snd '(set! (-> *target* fact health) 2.0)' 1
snd "(send-event *target* 'get-pickup (pickup-type eco-green) 1.0)" 2
probe ON-greenpickup
shot on_green_pickup_heart_pop
sleep 1
shot on_green_pickup_heart_pop_b

echo "-- GREEN ECO SPRITE A/B: eco pills make the stock pickups element (counter + its own"
echo "   green sprite at the SAME 110/55 slot) visible, so ON vs OFF at that slot is a direct"
echo "   comparison of our group 720 against ND's group 75. --"
snd '(set! (-> *target* fact eco-pill) 5.0)' 2.5
probe ON-ecopill
shot on_greeneco_slot_a
sleep 1.2
shot on_greeneco_slot_b
snd '(set! (-> *pc-settings* recharged-hud?) #f)' 3
snd '(set! (-> *target* fact eco-pill) 6.0)' 2.5
shot off_greeneco_slot_a
sleep 1.2
shot off_greeneco_slot_b
snd '(set! (-> *pc-settings* recharged-hud?) #t)' 3
snd '(set! (-> *target* fact eco-pill) 7.0)' 2.5
shot on_greeneco_slot_c

echo "-- fuel cell / buzzer icons --"
snd "(send-event *target* 'get-pickup (pickup-type fuel-cell) 1.0)" 3
probe ON-cell
shot on_fuel_cell_icon
snd "(send-event *target* 'get-pickup (pickup-type buzzer) 1.0)" 3
shot on_buzzer_icon

echo "-- OFF again: stock must come back --"
snd '(set! (-> *pc-settings* recharged-hud?) #f)' 3
probe OFF-restored
shot off_restored_stock

exec 9>&-
sleep 2
cleanup

grep -aE "RHUD5[ab] " "$LOG/gk.log" "$LOG/goalc.log" 2>/dev/null | sed 's/^[^ ]*RHUD5/RHUD5/' | sort -u > "$OUT/x86-probes.txt"
grep -aiE "recharged-hud:|Fatal|signal|Compilation Error|REPL Error" "$LOG/goalc.log" "$LOG/gk.log" 2>/dev/null | head -40 > "$OUT/x86-gk-notes.txt"
echo "== probes =="; cat "$OUT/x86-probes.txt"
echo "== notes =="; head -20 "$OUT/x86-gk-notes.txt"
ls -la "$OUT"/*.png 2>/dev/null | head -40
