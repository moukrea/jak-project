#!/usr/bin/env bash
# Gcine-cut: capture OUR-x86 new-game intro cinematic via the lean every-16-frame
# GOAL dumps (GCINE-OC othercam world pos, GCINE-SP spool af/strpos, GCINE-JC joint
# cmds, GCINE-GUARD spike-clamp). NO per-frame GCINE-CAM flood. Verifies the
# loader.gc spike-guard is x86-SAFE (GCINE-GUARD must be 0 on x86) and that x86
# still CUTS (joint cmds fire spread out, camera pos jumps at switches).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"

GK="build-x86/game/gk"
GOALC="build-x86/goalc/goalc"
ISO="out/jak1/iso"
OUT=".autoport/reports/Gcine-cut"
LOG="$OUT/ourx86-fix.log"
GCLOG="$OUT/ourx86-fix-goalc.log"
mkdir -p "$OUT"
WALLCAP="${WALLCAP:-360}"
[ -x "$GK" ] || { echo "FAIL: $GK missing"; exit 1; }

cur_af(){ grep -a 'GCINE-SP ' "$LOG" 2>/dev/null | tail -1 | grep -oE 'af=[0-9.]+' | head -1 | grep -oE '[0-9.]+'; }
cur_part(){ grep -a 'GCINE-SP ' "$LOG" 2>/dev/null | tail -1 | grep -oE 'part=[0-9]+' | grep -oE '[0-9]+'; }

echo "== launch our-x86 gk (lean dumps; no GCINE-CAM flood) =="
: > "$LOG"
"$GK" --game jak1 --portable -fakeiso --verbose \
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
timeout 700 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GC_PID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "  build-game sent; waiting up to 200s for symbol intern..."
for i in $(seq 1 200); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game done ~${i}s"; break; }
done
sleep 4
echo "== send NEW-GAME intro trigger =="
TRIG='(begin (set! (-> *game-info* mode) (quote play)) (initialize! *game-info* (quote game) (the-as game-save #f) "intro-start") (set-master-mode (quote game)))'
echo "$TRIG" >&3

echo "== watch cinematic up to ${WALLCAP}s (target af>=2560 = past last joint cmd 2490) =="
t0=$(date +%s)
while :; do
  now=$(date +%s); el=$((now-t0))
  kill -0 $GK_PID 2>/dev/null || { echo "  gk exited at ${el}s"; break; }
  [ "$el" -ge "$WALLCAP" ] && { echo "  wall cap"; break; }
  AF=$(cur_af); AF=${AF:-0}; PART=$(cur_part)
  JC=$(grep -ac 'GCINE-JC ' "$LOG" 2>/dev/null); GUARD=$(grep -ac 'GCINE-GUARD ' "$LOG" 2>/dev/null)
  echo "   [${el}s] af=$AF part=${PART:-?} JC=$JC GUARD=$GUARD SP=$(grep -ac 'GCINE-SP ' "$LOG") OC=$(grep -ac 'GCINE-OC ' "$LOG")"
  # stop once we are clearly past the last joint command (af 2490)
  awk "BEGIN{exit !($AF>=2560)}" && { echo "  past last joint cmd (af=$AF)"; sleep 3; break; }
  sleep 5
done

exec 3>&- 2>/dev/null || true
kill $GK_PID 2>/dev/null || true; wait $GK_PID 2>/dev/null || true; trap - EXIT; rm -f "$FIFO"
echo "== scoreboard =="
echo "  GCINE-SP    : $(grep -ac 'GCINE-SP ' "$LOG")"
echo "  GCINE-OC    : $(grep -ac 'GCINE-OC ' "$LOG")"
echo "  GCINE-JC    : $(grep -ac 'GCINE-JC ' "$LOG")"
echo "  GCINE-GUARD : $(grep -ac 'GCINE-GUARD ' "$LOG")   (MUST be 0 on x86)"
echo "  max af      : $(grep -aoE 'af=[0-9.]+' "$LOG" | grep -oE '[0-9.]+' | sort -n | tail -1)"
echo "  af>5000     : $(grep -a 'GCINE-SP ' "$LOG" | grep -oE 'af=[0-9.]+' | grep -oE '[0-9.]+' | awk '$1>5000{c++}END{print c+0}')  (af-spike count; MUST be 0 on x86)"
echo "  log: $LOG"
