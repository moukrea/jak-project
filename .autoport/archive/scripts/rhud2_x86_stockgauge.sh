#!/bin/bash
# Discriminator run: SAME eco injection sequence as rhud2_x86_gauge.sh but the
# recharged HUD is NEVER enabled (stock HUD throughout). If the toggle-OFF-beat
# crash reproduces here, it is an eco-injection artifact (crate state recursion),
# NOT a recharged-HUD OFF-path regression. Also captures the stock gauge beats.
set -u
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/rhud2
SHOTDIR="build/game/OpenGOAL/jak1/screenshots"
mkdir -p "$OUT" "$SHOTDIR"

pkill -f 'build/game/gk' 2>/dev/null; sleep 2
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 2

DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$OUT/gk_stock.log" 2>&1 &
GK_PID=$!
deadline=$(( $(date +%s) + 150 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "GK EXITED EARLY"; tail -20 "$OUT/gk_stock.log"; exit 1; }
  grep -qa "machine started" "$OUT/gk_stock.log" && break
  sleep 2
done
grep -qa "machine started" "$OUT/gk_stock.log" || { echo "NEVER BOOTED"; exit 1; }
sleep 15

rm -f "$OUT/fifo3"; mkfifo "$OUT/fifo3"
./build/goalc/goalc --user-auto < "$OUT/fifo3" > "$OUT/goalc_stock.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo3"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }
finish(){ kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap finish EXIT

sleep 4
CONNECTED=0
for i in 1 2 3 4 5 6 7 8; do
  snd '(lt)' 4
  grep -qa "Socket connected established" "$OUT/goalc_stock.log" && { CONNECTED=1; break; }
done
[ "$CONNECTED" = 1 ] || { echo "LISTENER NEVER CONNECTED"; exit 1; }
snd '(build-game)' 45
for i in 1 2 3 4 5 6; do grep -qa "Successfully built all" "$OUT/goalc_stock.log" && break; sleep 10; done
grep -qa "Successfully built all" "$OUT/goalc_stock.log" || { echo "build-game DID NOT FINISH"; exit 1; }

shot(){
  local f="$SHOTDIR/screenshot.png" t=0
  rm -f "$f"
  snd '(pc-screen-shot)' 1
  while [ $t -lt 12 ]; do
    if [ -f "$f" ]; then sleep 0.6; cp "$f" "$OUT/$1.png"; echo "shot $1 ($(stat -c%s "$OUT/$1.png") B)"; return 0; fi
    sleep 1; t=$((t+1))
  done
  echo "shot $1 MISSING"; return 1
}
alive(){ kill -0 "$GK_PID" 2>/dev/null && echo "ALIVE after $1" || echo "GK DEAD after $1"; }

snd "(start 'play (get-continue-by-name *game-info* \"training-start\"))" 35
# recharged-hud? stays at its default (OFF) — NEVER touched in this run
snd '(format 0 "RHSTOCK gate ~A~%" (-> *pc-settings* recharged-hud?))' 1.5

eco_on(){
  snd "(set! (-> *target* fact eco-type) (pickup-type eco-$1))" 0.5
  snd '(set! (-> *target* fact eco-level) 2.0)' 0.5
  snd '(set! (-> *target* fact eco-timeout) (-> *FACT-bank* eco-full-timeout))' 0.5
  snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
}
eco_on blue
shot off_stock_gauge_blue
alive inj1
sleep 9
shot off_stock_gauge_blue_mid
alive inj1-mid
eco_on red
shot off_stock_gauge_red
alive inj2
eco_on yellow
shot off_stock_gauge_yellow
alive inj3
eco_on blue
sleep 3
shot off_stock_gauge_blue_again
alive inj4-crashbeat

grep -ah "RHSTOCK" "$OUT/gk_stock.log" "$OUT/goalc_stock.log" | head -3
echo DONE
ls -la "$OUT"/off_stock_gauge_*.png 2>/dev/null