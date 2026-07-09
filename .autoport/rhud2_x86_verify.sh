#!/bin/bash
# Grecharged-hud-jak1 round-2: x86 verify driver.
# Boots gk, drives HUD states via the goalc listener, dumps the recharged-heart
# state machine, captures named screenshots (ON per state + OFF stock A/B).
set -u
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-hud-jak1
OUT=/tmp/rhud2
mkdir -p "$R" "$OUT"

pkill -f 'build/game/gk' 2>/dev/null; sleep 2
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 1

./build/game/gk -boot -fakeiso -debug > "$OUT/gk.log" 2>&1 &
GK_PID=$!
echo "gk pid $GK_PID"
sleep 30

rm -f "$OUT/fifo"; mkfifo "$OUT/fifo"
./build/goalc/goalc --user-auto < "$OUT/fifo" > "$OUT/goalc.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }
shot(){ # shot <name> — request a screenshot and copy the newest png
  snd '(pc-screen-shot)' 3
  local f
  f=$(find . -name '*.png' -newermt '-8 seconds' -not -path './recharged_assets/*' -not -path './.autoport/*' -not -path './custom_assets/*' 2>/dev/null | head -1)
  if [ -n "$f" ]; then cp "$f" "$OUT/$1.png"; echo "shot $1 <- $f"; else echo "shot $1 MISSING"; fi
}
dumph(){ # dump recharged-health state machine
  snd '(let ((h (-> *hud-parts-pc* recharged-health 0))) (format 0 "RHSTATE ~A off ~D val ~D val2 ~D pin ~A hp ~F~%" (-> h next-state name) (-> h offset) (-> h value) (-> h value2) (-> h force-on-screen) (-> *target* fact health)))' 1
}

snd '(lt)' 6
# into gameplay
snd "(start 'play (get-continue-by-name *game-info* \"training-start\"))" 35

# ---- toggle ON ----
snd '(set! (-> *pc-settings* recharged-hud?) #t)' 3

# ---- probe: at rest, full health — heart must be HIDDEN (stock rules) ----
for i in 1 2 3 4 5; do dumph; done
shot on_rest_full_health

# ---- damage 3->2: shows ~2s then auto-hides ----
snd '(set! (-> *target* fact health) 2.0)' 1
dumph
shot on_heart_66_shown
sleep 4
dumph
shot on_heart_hidden_after_timeout

# ---- last notch: pinned + blink ----
snd '(set! (-> *target* fact health) 1.0)' 6
dumph
shot on_heart_33_pinned_a
sleep 0.25
shot on_heart_33_pinned_b
sleep 4
dumph
shot on_heart_33_still_pinned

# ---- heal to full: unpin, auto-hide ----
snd '(set! (-> *target* fact health) 3.0)' 1
shot on_heart_100_shown
sleep 4
dumph
shot on_heart_hidden_after_heal

# ---- gauge: blue full then drain ----
snd '(set! (-> *target* fact eco-type) (pickup-type eco-blue))' 0.5
snd '(set! (-> *target* fact eco-timeout) (the-as uint (-> *FACT-bank* eco-full-timeout)))' 0.5
snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
shot on_gauge_blue_full
sleep 8
shot on_gauge_blue_mid
# red
snd '(set! (-> *target* fact eco-type) (pickup-type eco-red))' 0.5
snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
shot on_gauge_red_full
# yellow
snd '(set! (-> *target* fact eco-type) (pickup-type eco-yellow))' 0.5
snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
shot on_gauge_yellow_full

# ---- fuel-cell + money: no flat sprite / no glow when ON ----
snd "(send-event (ppointer->process (-> *hud-parts* fuel-cell)) 'show)" 1.5
snd "(send-event (ppointer->process (-> *hud-parts* money)) 'show)" 1.5
shot on_cell_and_orb
snd '(format 0 "RHSKIP fc ~D money ~D~%" (-> *hud-parts* fuel-cell 0 skip-particle) (-> *hud-parts* money 0 skip-particle))' 1

# ---- OFF: stock restore A/B ----
snd '(set! (-> *pc-settings* recharged-hud?) #f)' 3
snd '(format 0 "RHSKIP-OFF fc ~D money ~D~%" (-> *hud-parts* fuel-cell 0 skip-particle) (-> *hud-parts* money 0 skip-particle))' 1
# stock heart shown by a change
snd '(set! (-> *target* fact health) 2.0)' 1
shot off_stock_heart_shown
sleep 4
shot off_stock_heart_hidden
snd '(set! (-> *target* fact health) 3.0)' 1
# stock gauge with blue eco
snd '(set! (-> *target* fact eco-type) (pickup-type eco-blue))' 0.5
snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
shot off_stock_gauge_blue
# stock cell + orb (flat sprite + glow must be BACK)
snd "(send-event (ppointer->process (-> *hud-parts* fuel-cell)) 'show)" 1.5
snd "(send-event (ppointer->process (-> *hud-parts* money)) 'show)" 1.5
shot off_stock_cell_and_orb

# ---- evidence: loader lines ----
grep -a "recharged-hud" "$OUT/gk.log" | head -15 > "$OUT/loader_lines.txt"
grep -a "RHSTATE\|RHSKIP" "$OUT/gk.log" > "$OUT/state_dumps.txt"

kill $GK_PID $GOALC_PID 2>/dev/null
exec 3>&-
echo DONE; ls -la "$OUT"/*.png 2>/dev/null | head -30; echo; cat "$OUT/loader_lines.txt"; echo; cat "$OUT/state_dumps.txt"
