#!/usr/bin/env bash
# Gcine-cut: capture OUR-x86 new-game intro cinematic per-frame camera via GCINE-CAM.
# Fix vs attempt 1: run (build-game) over the listener BEFORE the trigger form so
# *game-info* is interned (bare (lt) leaves goalc without game symbols).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"

GK="build-x86/game/gk"
GOALC="build-x86/goalc/goalc"
ISO="out/jak1/iso"
OUT=".autoport/reports/Gcine-cut"
LOG="$OUT/ourx86-cam.log"
GCLOG="$OUT/ourx86-goalc.log"
mkdir -p "$OUT"
WALLCAP=420
[ -x "$GK" ] || { echo "FAIL: $GK missing"; exit 1; }

cur_frame(){ grep -a 'GCINE-CAM f=' "$LOG" 2>/dev/null | tail -1 | grep -oE 'f=[0-9]+' | head -1 | grep -oE '[0-9]+'; }
seen_lvl(){ grep -aoE 'lvl=[a-zA-Z0-9_-]+' "$LOG" 2>/dev/null | sort -u | tr '\n' ' '; }

echo "== launch our-x86 gk (OG_GCINE_CAM=1) =="
: > "$LOG"
env OG_GCINE_CAM=1 "$GK" --game jak1 --portable -fakeiso --verbose \
  --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GK_PID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GK_PID" "${GC_PID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
echo "  gk pid=$GK_PID"

echo "== wait for title (link finish: default-menu) =="
for i in $(seq 1 120); do
  kill -0 $GK_PID 2>/dev/null || { echo "FAIL: gk exited during boot"; tail -20 "$LOG"; exit 1; }
  grep -qE "link finish: default-menu($|-pc)" "$LOG" && { echo "  title up at ~${i}s"; break; }
  sleep 1
done
sleep 3

echo "== goalc (lt)+(build-game) to intern *game-info*, then trigger cinematic =="
: > "$GCLOG"
timeout 600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GC_PID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "  build-game sent; waiting up to 180s for symbol intern..."
for i in $(seq 1 180); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game done ~${i}s"; break; }
done
sleep 4
echo "== send NEW-GAME intro trigger =="
TRIG='(begin (set! (-> *game-info* mode) (quote play)) (initialize! *game-info* (quote game) (the-as game-save #f) "intro-start") (set-master-mode (quote game)))'
echo "$TRIG" >&3

echo "== watch cinematic up to ${WALLCAP}s =="
t0=$(date +%s)
while :; do
  now=$(date +%s); el=$((now-t0))
  kill -0 $GK_PID 2>/dev/null || { echo "  gk exited at ${el}s"; break; }
  [ "$el" -ge "$WALLCAP" ] && { echo "  wall cap"; break; }
  FM=$(cur_frame); FM=${FM:-0}
  echo "   [${el}s] frame=$FM levels: $(seen_lvl)"
  if seen_lvl | grep -q "lvl=misty" && [ "$FM" -ge 11000 ]; then echo "  cinematic complete (misty seen, frame=$FM)"; break; fi
  sleep 5
done

exec 3>&- 2>/dev/null || true
kill $GK_PID 2>/dev/null || true; wait $GK_PID 2>/dev/null || true; trap - EXIT; rm -f "$FIFO"
echo "== scoreboard =="
echo "  GCINE-CAM lines : $(grep -ac 'GCINE-CAM f=' "$LOG" 2>/dev/null || echo 0)"
echo "  max frame       : $(grep -a 'GCINE-CAM f=' "$LOG" | grep -oE 'f=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)"
echo "  distinct levels : $(seen_lvl)"
echo "  goalc errors    : $(grep -aiE 'Compilation Error|does not exist' "$GCLOG" | head -3)"
echo "  log: $LOG"
