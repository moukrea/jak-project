#!/usr/bin/env bash
# capture_oracle_cine.sh — solve the capture_oracle_beats.sh TODO: capture the
# v0.3.3 ORIGINAL's newgame-cinematic + ingame-firstframe oracle frames.
#
# The original could not reach these via menu input (its saved input-settings
# remaps START off ENTER and EWMH uinput keys don't route reliably to the gk
# window). The robust route is the goalc LISTENER: the menu's NEW GAME action is
# literally (initialize! *game-info* 'game (the-as game-save #f) "intro-start"),
# so once goalc (lt)-connects to the running gk we can trigger the new-game intro
# DIRECTLY — no menu navigation needed.
#
# It dumps a DENSE burst of frames across the new-game timeline (the engine's
# AUTOPORT_SHOT hook) into .autoport/gold/oracle-beats/cine-burst/ for the
# supervisor to SELECT the cutscene + first-in-game frames from. It does NOT
# auto-pick (the human/owner picks the canonical beat). Honest: if (lt) cannot
# bind, it reports that and writes nothing.
#
# Single-user desktop resource (DISPLAY=:0). NEVER pgrep bare 'gk' (matches the
# claude -p process); only the launched PID is killed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
FORK_ROOT="$(pwd)"

ORIG="/home/emeric/code/jak-original-v033"
GK="$ORIG/build/Release/bin/game/gk"
GOALC="$ORIG/build/Release/bin/goalc/goalc"
SHOTDIR="$ORIG/build/Release/bin/game/OpenGOAL/jak1/screenshots"
OUTDIR="$FORK_ROOT/.autoport/gold/oracle-beats"
BURST="$OUTDIR/cine-burst"
LOG="/tmp/oracle-cine.log"
GLOG="/tmp/oracle-cine-goalc.log"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
SHOT_W="${SHOT_W:-2400}"; SHOT_H="${SHOT_H:-1080}"; SHOT_MSAA="${SHOT_MSAA:-2}"

die() { echo "capture_oracle_cine: FATAL: $*" >&2; exit 1; }
[ -x "$GK" ] || die "original gk not found at $GK"
[ -x "$GOALC" ] || die "original goalc not found at $GOALC"
mkdir -p "$BURST" "$SHOTDIR"
rm -f "$SHOTDIR"/autoport_f*.png 2>/dev/null || true
: > "$LOG"

cur_frame() { local v; v=$(ls "$SHOTDIR"/autoport_f*.png 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1); [ -n "$v" ] && echo $((10#$v)) || echo 0; }

echo "== launch ORIGINAL gk (v0.3.3) with AUTOPORT_SHOT hook =="
( cd "$ORIG" && env \
    AUTOPORT_SHOT_EVERY=10 AUTOPORT_SHOT_START=300 \
    AUTOPORT_SHOT_W="$SHOT_W" AUTOPORT_SHOT_H="$SHOT_H" AUTOPORT_SHOT_MSAA="$SHOT_MSAA" \
    "$GK" -v --game jak1 --portable --disable-ansi -- -fakeiso -debug -boot ) > "$LOG" 2>&1 &
GK_PID=$!
trap 'kill -INT $GK_PID 2>/dev/null; sleep 2; kill -KILL $GK_PID 2>/dev/null; wait $GK_PID 2>/dev/null' EXIT
echo "  gk pid=$GK_PID"

echo "== wait for boot =="
dl=$(( $(date +%s) + 150 ))
booted=0
while [ "$(date +%s)" -lt "$dl" ]; do
  kill -0 "$GK_PID" 2>/dev/null || die "gk exited during boot; tail: $(tail -5 "$LOG")"
  if grep -aqE 'InitIOP OK|Initialized GOAL heap|dkernel: boot mode|Compiled Version' "$LOG" 2>/dev/null; then booted=1; break; fi
  sleep 2
done
[ "$booted" = 1 ] || die "gk did not boot in time"
echo "  booted; let attract settle (frames dumping from f300)"
sleep 20

echo "== goalc (lt): connect to running gk + trigger NEW GAME (intro-start) =="
F_TRIG=$(cur_frame)
echo "  frame at trigger ~ $F_TRIG"
# Pipe forms to goalc: (lt) connects to target; then start the new-game intro.
# A short sleep between forms lets the listener attach before we inject.
{
  printf '(lt)\n'
  sleep 6
  printf '(set! *debug-segment* #f)\n'
  printf "(initialize! *game-info* 'game (the-as game-save #f) \"intro-start\")\n"
  sleep 90
  printf '(:exit)\n'
} | ( cd "$ORIG" && "$GOALC" --game jak1 --user-auto ) > "$GLOG" 2>&1 &
GOALC_PID=$!

echo "== capture dense burst across the new-game timeline (~100s) =="
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 105 ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "  gk EXITED at $(( $(date +%s) - t0 ))s (crash during cinematic?)"; break; }
  sleep 3
done
kill $GOALC_PID 2>/dev/null || true

echo "== goalc connection log (did (lt) bind?) =="
grep -aiE 'connect|listen|target|reset|run-time|fail|error' "$GLOG" 2>/dev/null | head -20 || true

# Copy post-trigger frames into the burst dir for human selection.
echo "== harvest post-trigger frames -> $BURST =="
n=0
for f in "$SHOTDIR"/autoport_f*.png; do
  [ -e "$f" ] || continue
  fi=$(basename "$f" | grep -oE '[0-9]+'); fi=$((10#$fi))
  if [ "$fi" -ge "$F_TRIG" ]; then
    cp -f "$f" "$BURST/$(basename "$f")"; n=$((n+1))
  fi
done
echo "  harvested $n post-trigger frames (trigger frame=$F_TRIG, last frame=$(cur_frame))"
echo "  CONNECTED=$(grep -aciE 'connect to target|listen.*succe|reset target' "$GLOG" 2>/dev/null || echo 0)"
ls -la "$BURST" 2>/dev/null | tail -8

kill -INT $GK_PID 2>/dev/null || true; sleep 2; kill -KILL $GK_PID 2>/dev/null || true; wait $GK_PID 2>/dev/null || true
trap - EXIT
echo "== done. burst in $BURST; select newgame-cinematic + ingame-firstframe from it. =="
