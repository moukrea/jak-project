#!/bin/bash
# Grecharged-hud-jak1 ROUND-2 x86 visual verification of hud-classes-pc.gc edits.
# Modeled on rhud2_x86_gauge.sh + rhud2_x86_stockgauge.sh working idioms.
# Do NOT edit source. Build via listener, boot gk, drive HUD beats, screenshot,
# measure gauge parity. Manager reviews images.
set -u
cd "$(git rev-parse --show-toplevel)"
OUT=/tmp/rhud2_r2
DEST=".autoport/reports/Grecharged-hud-jak1/round2/x86"
SHOTDIR="build/game/OpenGOAL/jak1/screenshots"
mkdir -p "$OUT" "$SHOTDIR" "$DEST"

pkill -f 'build/game/gk' 2>/dev/null; sleep 2
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 2

# ---- Phase 0: goalc listener FIRST, relink CGOs via (mi) = (make-group "iso") ----
# NOTE: (build-game) only writes out/jak1/obj/*.o and does NOT relink the CGOs in
# out/jak1/iso; gk -iso-data serves those CGOs, so we MUST run (mi) to get fresh code.
SRC="goal_src/jak1/pc/hud-classes-pc.gc"
GAMECGO="out/jak1/iso/GAME.CGO"
rm -f "$OUT/fifo"; mkfifo "$OUT/fifo"
./build/goalc/goalc --user-auto < "$OUT/fifo" > "$OUT/goalc.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }
GK_PID=""
finish(){ [ -n "$GK_PID" ] && { kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" 2>/dev/null; }; kill "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap finish EXIT

sleep 4
snd '(mi)' 5
# Poll up to 15 min: fail on Compilation Error; success when GAME.CGO is newer than SRC.
BUILT=0
for i in $(seq 1 90); do
  if grep -qa "Compilation Error" "$OUT/goalc.log"; then
    echo "=== COMPILATION ERROR during (mi) ==="
    if grep -qaiE "hud-classes-pc\.gc" "$OUT/goalc.log"; then
      echo "=== POSSIBLE COMPILE ERROR mentioning hud-classes-pc.gc ==="
      grep -aiE -A3 -B3 "hud-classes-pc\.gc" "$OUT/goalc.log"
    fi
    echo "=== tail goalc.log ==="; tail -40 "$OUT/goalc.log"; exit 2
  fi
  if [ "$GAMECGO" -nt "$SRC" ]; then BUILT=1; break; fi
  sleep 10
done
if [ "$BUILT" != 1 ]; then
  echo "(mi) DID NOT PRODUCE FRESH GAME.CGO in time — tail:"; tail -40 "$OUT/goalc.log"; exit 1
fi
echo "BUILD OK: (mi) finished, GAME.CGO relinked"

# ---- HARD freshness gate: GAME.CGO must be NEWER than the source file ----
echo "=== FRESHNESS GATE ==="
ls -la "$GAMECGO"
ls -la "$SRC"
[ "$GAMECGO" -nt "$SRC" ] || { echo "FRESHNESS GATE FAILED: GAME.CGO not newer than $SRC"; exit 3; }
echo "FRESHNESS GATE PASS: GAME.CGO is newer than $SRC"

# ---- Phase 1: boot gk (stockgauge launch line verbatim) ----
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$OUT/gk.log" 2>&1 &
GK_PID=$!
deadline=$(( $(date +%s) + 150 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "GK EXITED EARLY"; tail -20 "$OUT/gk.log"; exit 1; }
  grep -qa "machine started" "$OUT/gk.log" && break
  sleep 2
done
grep -qa "machine started" "$OUT/gk.log" || { echo "NEVER BOOTED"; exit 1; }
sleep 15

# connect listener to running gk
CONNECTED=0
for i in 1 2 3 4 5 6 7 8; do
  snd '(lt)' 4
  grep -qa "Socket connected established" "$OUT/goalc.log" && { CONNECTED=1; break; }
done
[ "$CONNECTED" = 1 ] || { echo "LISTENER NEVER CONNECTED to gk"; exit 1; }

shot(){
  local f="$SHOTDIR/screenshot.png" t=0
  rm -f "$f"
  snd '(pc-screen-shot)' 1
  while [ $t -lt 12 ]; do
    if [ -f "$f" ]; then sleep 0.6; cp "$f" "$DEST/$1.png"; echo "shot $1 ($(stat -c%s "$DEST/$1.png") B) -> $DEST/$1.png"; return 0; fi
    sleep 1; t=$((t+1))
  done
  echo "shot $1 MISSING"; return 1
}
alive(){ kill -0 "$GK_PID" 2>/dev/null && echo "GK ALIVE after $1" || echo "GK DEAD after $1"; }

eco_on(){ # eco_on <color>  (rhud2_x86_gauge.sh verbatim)
  snd "(set! (-> *target* fact eco-type) (pickup-type eco-$1))" 0.5
  snd '(set! (-> *target* fact eco-level) 2.0)' 0.5
  snd '(set! (-> *target* fact eco-timeout) (-> *FACT-bank* eco-full-timeout))' 0.5
  snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
}

snd "(start 'play (get-continue-by-name *game-info* \"training-start\"))" 35

# =================== ON ROUND ===================
snd '(set! (-> *pc-settings* recharged-hud?) #t)' 3

# a. gauge blue full + natural drain to mid
eco_on blue
shot on_gauge_blue_full
sleep 0.8
shot on_gauge_blue_orb_b
sleep 8
shot on_gauge_blue_mid
# b. red / yellow full
eco_on red
shot on_gauge_red_full
eco_on yellow
shot on_gauge_yellow_full
# ON gauge-hidden frame: let eco fully drain (standing pose)
sleep 25
shot on_gauge_hidden

# c. green orb by heart (pickups counter + NEW green eco particle composite)
snd '(+! (-> *target* fact eco-pill) 1.0)' 1.5
shot on_greenorb_pickups
# c2. greenorb fade waver (green eco particle system should change between frames)
sleep 0.8
shot on_greenorb_b
sleep 0.8
shot on_greenorb_c
sleep 0.8
shot on_greenorb_d
# c3. heart-pop check (heart popped by green-eco pickup, visible alongside pickups counter)
shot on_heartpop
# d. heart states
snd '(set! (-> *target* fact health) 2.0)' 1.5
shot on_heart_66
snd '(set! (-> *target* fact health) 1.0)' 1
shot on_heart_33_a
sleep 0.7
shot on_heart_33_b
sleep 0.4
shot on_heart_33_c
sleep 0.4
shot on_heart_33_d
snd '(set! (-> *target* fact health) 3.0)' 1.5
shot on_heart_healed
# e. cell icon spin
snd '(+! (-> *target* game fuel) 1.0)' 2
shot on_cell
sleep 1
shot on_cell_b
# e2. cell ANIM-RATE series (spin/animation over time after fuel increment)
snd '(+! (-> *target* game fuel) 1.0)' 0
shot on_cell_t0
sleep 0.5
shot on_cell_t05
sleep 0.5
shot on_cell_t10
sleep 1
shot on_cell_t20
# f. buzzer icon
snd "(send-event (ppointer->process (-> *hud-parts* buzzers)) 'show)" 1.5
shot on_buzzer
# g. REGRESSION beat: eco active + toggle OFF (old SIGSEGV)
eco_on blue
snd '(set! (-> *pc-settings* recharged-hud?) #f)' 2
alive "OFF-toggle-with-eco (regression beat g)"
snd '(set! (-> *pc-settings* recharged-hud?) #t)' 1.5

# e3. cell GLOW/TINT beat (force fuel-cell hud show) — right before OFF round
snd "(send-event (ppointer->process (-> *hud-parts* fuel-cell)) 'show)" 1.5
shot on_cell_glow

# =================== OFF ROUND ===================
snd '(set! (-> *pc-settings* recharged-hud?) #f)' 3
eco_on blue
shot off_stock_gauge_blue_full
snd '(+! (-> *target* fact eco-pill) 1.0)' 1.5
shot off_stock_pickups
snd '(+! (-> *target* game fuel) 1.0)' 1.5
shot off_stock_cell
snd '(set! (-> *target* fact health) 2.0)' 1.5
shot off_stock_heart
# OFF gauge-hidden frame (let eco drain, standing pose)
sleep 25
shot off_gauge_hidden

alive "end of beats"

# =================== MEASURE (skipped per coordinator; measured from shots directly) ===================
echo "=== FRESHNESS GATE PROOF (GAME.CGO mtime) ==="
ls -la out/jak1/iso/GAME.CGO

echo "=== gk log exceptions ==="
grep -aiE 'exception|segfault|SIGSEGV|SIGILL|SIGABRT|panic|terminate|std::|abort' "$OUT/gk.log" | grep -aviE 'link and exec|link finish' | head -30
echo "=== goalc build tail ==="
tail -20 "$OUT/goalc.log"
echo DONE
