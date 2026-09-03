#!/bin/bash
# Grecharged-hud-jak1: focused x86 GAUGE beats (run 4's fact-field eco injection
# no-opped on a seconds/uint typecheck; use the canonical 'get-pickup event).
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
  -iso-data out/jak1/iso -- -boot -debug-mem > "$OUT/gk_gauge.log" 2>&1 &
GK_PID=$!
deadline=$(( $(date +%s) + 150 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "GK EXITED EARLY"; tail -20 "$OUT/gk_gauge.log"; exit 1; }
  grep -qa "machine started" "$OUT/gk_gauge.log" && break
  sleep 2
done
grep -qa "machine started" "$OUT/gk_gauge.log" || { echo "NEVER BOOTED"; exit 1; }
sleep 15

rm -f "$OUT/fifo2"; mkfifo "$OUT/fifo2"
./build/goalc/goalc --user-auto < "$OUT/fifo2" > "$OUT/goalc_gauge.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo2"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }
finish(){ kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap finish EXIT

sleep 4
CONNECTED=0
for i in 1 2 3 4 5 6 7 8; do
  snd '(lt)' 4
  grep -qa "Socket connected established" "$OUT/goalc_gauge.log" && { CONNECTED=1; break; }
done
[ "$CONNECTED" = 1 ] || { echo "LISTENER NEVER CONNECTED"; exit 1; }
snd '(build-game)' 45
for i in 1 2 3 4 5 6; do grep -qa "Successfully built all" "$OUT/goalc_gauge.log" && break; sleep 10; done
grep -qa "Successfully built all" "$OUT/goalc_gauge.log" || { echo "build-game DID NOT FINISH"; exit 1; }

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
dumpe(){ snd '(format 0 "RHECO type ~D timeout ~D level ~F~%" (-> *target* fact eco-type) (-> *target* fact eco-timeout) (-> *target* fact eco-level))' 1.5; }

snd "(start 'play (get-continue-by-name *game-info* \"training-start\"))" 35
snd '(set! (-> *pc-settings* recharged-hud?) #t)' 3

# eco drive: direct fact fields with CORRECT types (run 4's (the-as uint ...) on the
# seconds-typed eco-timeout no-opped on typecheck; both sides are seconds — no cast)
eco_on(){ # eco_on <color>
  snd "(set! (-> *target* fact eco-type) (pickup-type eco-$1))" 0.5
  snd '(set! (-> *target* fact eco-level) 2.0)' 0.5
  snd '(set! (-> *target* fact eco-timeout) (-> *FACT-bank* eco-full-timeout))' 0.5
  snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
}
eco_on blue
dumpe
shot on_gauge_blue_full
sleep 9
shot on_gauge_blue_mid
eco_on red
dumpe
shot on_gauge_red_full
eco_on yellow
shot on_gauge_yellow_full

# OFF: stock gauge A/B
snd '(set! (-> *pc-settings* recharged-hud?) #f)' 3
eco_on blue
dumpe
shot off_stock_gauge_blue
kill -0 "$GK_PID" 2>/dev/null && echo "GK ALIVE after OFF-toggle-with-eco (recursion fix holds)" || echo "GK DEAD after OFF beat (fix FAILED)"
sleep 9
shot off_stock_gauge_blue_mid
kill -0 "$GK_PID" 2>/dev/null && echo "GK ALIVE at end" || echo "GK DEAD at end"

grep -ah "RHECO" "$OUT/gk_gauge.log" "$OUT/goalc_gauge.log" > "$OUT/eco_dumps.txt"
echo DONE
ls -la "$OUT"/on_gauge_*.png "$OUT"/off_stock_gauge_*.png 2>/dev/null
cat "$OUT/eco_dumps.txt"
