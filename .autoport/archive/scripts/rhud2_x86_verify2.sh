#!/bin/bash
# Grecharged-hud-jak1 round-2: x86 verify driver, v2.
# v1 postmortem: (a) gk must run on XWayland (DISPLAY=:0 + XAUTHORITY) or
# pc-screen-shot never lands a file; (b) gk stdout is block-buffered to a file,
# so (format 0 ...) dumps vanish on kill — stdbuf -oL; (c) screenshots land in
# ~/.config/OpenGOAL/jak1/screenshots for the non-portable build; (d) (lt) races
# goalc startup — retry until connected.
set -u
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Grecharged-hud-jak1
OUT=/tmp/rhud2
# --portable => screenshots/settings under build/game/OpenGOAL (gmenu precedent)
SHOTDIR="build/game/OpenGOAL/jak1/screenshots"
mkdir -p "$R" "$OUT" "$SHOTDIR"

pkill -f 'build/game/gk' 2>/dev/null; sleep 2
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 2
rm -f "$SHOTDIR"/*.png

# CRITICAL: -debug-mem, NOT -debug. With -debug (DebugSegment=1) on (mi)-built
# CGOs the kernel never registers DECI2 protos -> 8112 never binds (probed
# 200s twice). -boot -debug-mem = MasterDebug 1 / DebugSegment 0 is the proven
# combo (visuals-x86 session + gmenu_x86_capture.sh).
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$OUT/gk.log" 2>&1 &
GK_PID=$!
echo "gk pid $GK_PID"

# wait for boot. NOTE: with -debug the GOAL kernel prints (incl. "link finish:")
# route to the DECI2 listener, NOT stdout — gate on the C++-side "machine started"
# marker instead, then give the game time to reach the title attract.
deadline=$(( $(date +%s) + 150 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "GK EXITED EARLY"; tail -20 "$OUT/gk.log"; exit 1; }
  grep -qa "machine started" "$OUT/gk.log" && break
  sleep 2
done
grep -qa "machine started" "$OUT/gk.log" || { echo "NEVER BOOTED"; tail -20 "$OUT/gk.log"; exit 1; }
echo "machine started; settling 20s toward title"
sleep 20

rm -f "$OUT/fifo"; mkfifo "$OUT/fifo"
./build/goalc/goalc --user-auto < "$OUT/fifo" > "$OUT/goalc.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }

finish(){ kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap finish EXIT

# ---- connect (socket-level detect), THEN intern symbols, THEN format probe.
# (format/(anything) can't even COMPILE before (build-game) interns the world —
# the RHMARK probe must come AFTER build-game, not before.)
sleep 4
CONNECTED=0
for i in 1 2 3 4 5 6 7 8; do
  snd '(lt)' 4
  grep -qa "Socket connected established" "$OUT/goalc.log" && { CONNECTED=1; break; }
done
[ "$CONNECTED" = 1 ] || { echo "LISTENER NEVER CONNECTED"; tail -15 "$OUT/goalc.log"; exit 1; }
echo "socket connected; interning via (build-game)..."
snd '(build-game)' 45
for i in 1 2 3 4 5 6; do
  grep -qa "Successfully built all" "$OUT/goalc.log" && break
  sleep 10
done
grep -qa "Successfully built all" "$OUT/goalc.log" || { echo "build-game DID NOT FINISH"; tail -10 "$OUT/goalc.log"; exit 1; }

# now the format probe tells us where GOAL prints route
MARK_LOG="$OUT/gk.log"
snd '(format 0 "RHMARK-ALIVE~%")' 2
if grep -qa "RHMARK-ALIVE" "$OUT/gk.log"; then MARK_LOG="$OUT/gk.log";
elif grep -qa "RHMARK-ALIVE" "$OUT/goalc.log"; then MARK_LOG="$OUT/goalc.log";
else echo "FORMAT ROUTING DEAD (connected+interned but no marker)"; tail -10 "$OUT/goalc.log"; exit 1; fi
echo "listener alive; format routes to $MARK_LOG"

shot(){ # shot <name> — pc-screen-shot OVERWRITES a fixed screenshot.png; delete
        # it first and wait for it to reappear (newest-filename compare never fires)
  local f="$SHOTDIR/screenshot.png" t=0
  rm -f "$f"
  snd '(pc-screen-shot)' 1
  while [ $t -lt 12 ]; do
    if [ -f "$f" ]; then sleep 0.6; cp "$f" "$OUT/$1.png"; echo "shot $1 ($(stat -c%s "$OUT/$1.png") B)"; return 0; fi
    sleep 1; t=$((t+1))
  done
  echo "shot $1 MISSING"; return 1
}
dumph(){
  snd '(let ((h (the hud (-> *hud-parts-pc* recharged-health 0)))) (format 0 "RHSTATE ~A off ~D val ~D pin ~A hp ~F~%" (-> h next-state name) (-> h offset) (-> h value) (-> h force-on-screen) (-> *target* fact health)))' 1.5
}

# ---- probe the screenshot path EARLY, at title ----
shot probe_title || { echo "SCREENSHOT PATH DEAD at title — aborting"; exit 1; }

# into gameplay
snd "(start 'play (get-continue-by-name *game-info* \"training-start\"))" 35

# ---- toggle ON ----
snd '(set! (-> *pc-settings* recharged-hud?) #t)' 3

# ---- at rest, full health: heart must be HIDDEN (stock rules) ----
dumph
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
snd '(set! (-> *target* fact eco-type) (pickup-type eco-red))' 0.5
snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
shot on_gauge_red_full
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
snd '(set! (-> *target* fact health) 2.0)' 1
shot off_stock_heart_shown
sleep 4
shot off_stock_heart_hidden
snd '(set! (-> *target* fact health) 3.0)' 1
snd '(set! (-> *target* fact eco-type) (pickup-type eco-blue))' 0.5
snd '(set! (-> *target* fact eco-pickup-time) (-> *display* game-frame-counter))' 2
shot off_stock_gauge_blue
snd "(send-event (ppointer->process (-> *hud-parts* fuel-cell)) 'show)" 1.5
snd "(send-event (ppointer->process (-> *hud-parts* money)) 'show)" 1.5
shot off_stock_cell_and_orb

# ---- evidence ----
grep -a "recharged-hud" "$OUT/gk.log" | head -15 > "$OUT/loader_lines.txt"
grep -ah "RHSTATE\|RHSKIP\|RHMARK" "$OUT/gk.log" "$OUT/goalc.log" > "$OUT/state_dumps.txt"

echo DONE
ls -la "$OUT"/*.png 2>/dev/null
echo; cat "$OUT/loader_lines.txt"; echo; cat "$OUT/state_dumps.txt"
