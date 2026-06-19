#!/usr/bin/env bash
# Gcine-audit x86 ORACLE capture. Plays the jak1 NEW-GAME intro cinematic on the
# desktop build via the goalc listener (running the SAME initialize! path the
# progress menu's NEW GAME option runs) and records the per-frame GCINE-CAM
# camera/scene log (armed by OG_GCINE_CAM=1).
#
# goalc needs game symbols (*game-info* etc.) to compile the trigger form, so we
# (mi) (recompile the active project, x86) right after (lt). That hot-loads into
# the already-running gk; then the trigger form starts the cinematic.
#
# Stills (pass 2): gk's built-in AUTOPORT_SHOT framebuffer hook dumps PNGs named
# autoport_f<frame>.png (same frame_idx as GCINE-CAM) into
# build-x86/game/OpenGOAL/jak1/screenshots — no X screencap needed, at 2400x1080
# to match the device aspect.
#
# Usage:
#   bash gcine_audit_x86.sh log                 # pass 1: camera log only
#   bash gcine_audit_x86.sh shots START STOP    # pass 2: + stills in [START,STOP]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"

GK="build-x86/game/gk"
GOALC="build-x86/goalc/goalc"
ISO="out/jak1/iso"
OUT=".autoport/reports/Gcine-audit"
MODE="${1:-log}"
mkdir -p "$OUT"

if [ "$MODE" = "shots" ]; then
  LOG="$OUT/x86-cam-shots.log"
  SHOT_START="${2:-0}"; SHOT_STOP="${3:-99999999}"
  SHOTENV=(AUTOPORT_SHOT_EVERY=20 AUTOPORT_SHOT_START="$SHOT_START" AUTOPORT_SHOT_STOP="$SHOT_STOP"
           AUTOPORT_SHOT_W=2400 AUTOPORT_SHOT_H=1080 AUTOPORT_SHOT_MSAA=2)
  SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
  mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/autoport_f*.png 2>/dev/null || true
else
  LOG="$OUT/x86-cam.log"
  SHOTENV=()
fi

WALLCAP=360
[ -x "$GK" ] || { echo "FAIL: $GK missing"; exit 1; }
cur_frame() { grep -a 'GCINE-CAM f=' "$LOG" 2>/dev/null | tail -1 | grep -oE 'f=[0-9]+' | head -1 | grep -oE '[0-9]+'; }
seen_lvl()  { grep -aoE 'lvl=[a-zA-Z0-9_-]+' "$LOG" 2>/dev/null | sort -u | tr '\n' ' '; }

echo "== launch gk (OG_GCINE_CAM=1, DISPLAY=$DISPLAY) mode=$MODE =="
: > "$LOG"
env OG_GCINE_CAM=1 "${SHOTENV[@]}" "$GK" --game jak1 --portable -fakeiso --verbose \
  --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GK_PID=$!
trap 'kill $GK_PID 2>/dev/null; wait $GK_PID 2>/dev/null' EXIT
echo "  gk pid=$GK_PID"

echo "== wait for title (link finish: default-menu) =="
for i in $(seq 1 90); do
  kill -0 $GK_PID 2>/dev/null || { echo "FAIL: gk exited during boot"; tail -20 "$LOG"; exit 1; }
  grep -qE "link finish: default-menu($|-pc)" "$LOG" && { echo "  title up at ~${i}s"; break; }
  sleep 1
done
sleep 3

echo "== (lt) + (build-game) [code-only, interns *game-info*] + trigger cinematic =="
FORM='(begin (set! (-> *game-info* mode) (quote play)) (initialize! *game-info* (quote game) (the-as game-save #f) "intro-start") (set-master-mode (quote game)))'
printf '(lt)\n%s\n' "$FORM" | timeout 120 "$GOALC" --game jak1 --proj-path . \
  --iso-path "$ISO" --auto-lt > "$OUT/x86-goalc-$MODE.log" 2>&1 || true
echo "  goalc returned. tail:"; tail -4 "$OUT/x86-goalc-$MODE.log" | sed 's/\x1b\[[0-9;]*m//g'

echo "== watch cinematic up to ${WALLCAP}s (stop when misty+intro seen & gameplay resumes or cap) =="
t0=$(date +%s)
while :; do
  now=$(date +%s); el=$((now-t0))
  kill -0 $GK_PID 2>/dev/null || { echo "  gk exited at ${el}s"; break; }
  [ "$el" -ge "$WALLCAP" ] && { echo "  wall cap"; break; }
  FM=$(cur_frame); FM=${FM:-0}
  echo "   [${el}s] frame=$FM levels: $(seen_lvl)"
  # cinematic done heuristic: we've seen intro level AND frame is high
  if seen_lvl | grep -q "lvl=intro" && [ "$FM" -ge 11500 ]; then echo "  cinematic complete (intro seen, frame=$FM)"; break; fi
  sleep 5
done

echo "== teardown =="
kill $GK_PID 2>/dev/null || true; wait $GK_PID 2>/dev/null || true; trap - EXIT
if [ "$MODE" = "shots" ]; then
  DEST="$OUT/x86-shots"; mkdir -p "$DEST"; cp -f build-x86/game/OpenGOAL/jak1/screenshots/autoport_f*.png "$DEST/" 2>/dev/null || true
  echo "  stills copied: $(ls "$DEST"/*.png 2>/dev/null | wc -l) -> $DEST"
fi
echo "== scoreboard =="
echo "  GCINE-CAM lines : $(grep -ac 'GCINE-CAM f=' "$LOG" 2>/dev/null || echo 0)"
echo "  max frame       : $(grep -a 'GCINE-CAM f=' "$LOG" | grep -oE 'f=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)"
echo "  distinct levels : $(seen_lvl)"
echo "  log: $LOG"
