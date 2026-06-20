#!/usr/bin/env bash
# gcine_cut_probe.sh — DETERMINISTIC per-frame cutscene camera-POSITION dump over the
# goalc listener. IDENTICAL method on our-x86 and the pristine original (v0.3.3):
#   1. boot gk into the title attract,
#   2. (lt) connect; intern game symbols (ours: (mi); orig: --user-auto already builds),
#   3. trigger the NEW-GAME intro EXACTLY like the menu does:
#        (initialize! *game-info* 'game (the-as game-save #f) "intro-start"),
#   4. spawn a tiny per-FRAME probe process that formats *math-camera* trans (the final
#      render camera world position) + fov each frame to the TARGET's stdout,
#   5. capture the "GCINE-CUT f=.. px=.. py=.. pz=.. fov=.." lines.
#
# This reads only RUNTIME fields over the listener — it makes NO source edits, so the
# original golden repo stays byte-pristine (out/ is gitignored). Both GCINE-CUT (here)
# and the C++ GCINE-CAM dump measure the SAME quantity (math-camera trans), so the
# per-frame velocity (=> CUT vs INTERP) is directly comparable across builds/devices.
#
# Env (required): REPO GK GOALC OUTLOG
# Env (optional): GOALC_ARGS  RECOMPILE(default "(mi)")  FMT_DEST(default 0; orig uses "#t")
#                 WATCH(default 160s)  SETTLE(default 6s)  SPAWN_DELAY(default 6s)
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; OUTLOG="${OUTLOG:?}"
GOALC_ARGS="${GOALC_ARGS:-}"
RECOMPILE="${RECOMPILE:-(mi)}"
FMT_DEST="${FMT_DEST:-0}"
WATCH="${WATCH:-160}"
SETTLE="${SETTLE:-6}"
SPAWN_DELAY="${SPAWN_DELAY:-6}"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
cd "$REPO"

GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[probe] repo=$REPO"; echo "[probe] gk=$GK"; echo "[probe] fmt_dest=$FMT_DEST recompile='$RECOMPILE' watch=${WATCH}s"

# Boot gk (portable desktop). Use -boot -debug so the listener can drive a new game.
"$GK" -v --game jak1 --portable --disable-ansi -- -fakeiso -debug -boot > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null || true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null || true; wait 2>/dev/null || true; rm -f "$FIFO"; }
trap cleanup EXIT
echo "[probe] gk pid=$GKPID; waiting for boot..."
booted=0
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[probe] gk exited during boot"; tail -15 "$GKLOG"; exit 1; }
  if grep -aqE 'link finish: logo($|-)|link finish: default-menu|InitMachineScheme|Initialized GOAL heap' "$GKLOG" 2>/dev/null; then booted=1; echo "[probe] booted ~${i}s"; break; fi
  sleep 1
done
[ "$booted" = 1 ] || { echo "[probe] boot timeout"; tail -15 "$GKLOG"; exit 1; }
echo "[probe] settle ${SETTLE}s (attract loop)"; sleep "$SETTLE"

# The per-frame probe: a process that loops, formats *math-camera* trans+fov, suspends.
PROBE="(define *gcc-probe* (process-spawn-function process (lambda () (loop (format ${FMT_DEST} \"GCINE-CUT f=~D px=~f py=~f pz=~f fov=~f~%\" (current-time) (-> *math-camera* trans x) (-> *math-camera* trans y) (-> *math-camera* trans z) (-> *math-camera* fov)) (suspend)))))"

echo "[probe] open listener (GOALC_ARGS=$GOALC_ARGS)"
timeout $((WATCH+260)) "$GOALC" --game jak1 $GOALC_ARGS < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
if [ -n "$RECOMPILE" ]; then
  echo "[probe] intern symbols via $RECOMPILE"
  echo "$RECOMPILE" >&3
  for i in $(seq 1 140); do sleep 1; grep -qiE "Successfully built all|Build Successful|\] OK|OpenGOAL Runtime" "$GCLOG" 2>/dev/null && { echo "[probe] recompile done ~${i}s"; break; }; done
  sleep 3
fi
echo "[probe] trigger NEW-GAME intro cinematic"
echo "(set! *debug-segment* #f)" >&3
echo "(when *game-info* (set! (-> *game-info* mode) 'play))" >&3
echo "(initialize! *game-info* 'game (the-as game-save #f) \"intro-start\")" >&3
echo "[probe] wait ${SPAWN_DELAY}s for restart, then spawn per-frame probe"
sleep "$SPAWN_DELAY"
echo "$PROBE" >&3
sleep 1
echo "$PROBE" >&3   # re-spawn guard in case the first raced the restart

echo "[probe] watch ${WATCH}s capturing GCINE-CUT frames"
t0=$(date +%s); last=0
while [ $(( $(date +%s) - t0 )) -lt "$WATCH" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "[probe] gk exited at $(( $(date +%s) - t0 ))s"; break; }
  n=$(grep -ac 'GCINE-CUT f=' "$GKLOG" 2>/dev/null || echo 0)
  fm=$(grep -a 'GCINE-CUT f=' "$GKLOG" 2>/dev/null | tail -1 | grep -oE 'f=[0-9]+' | grep -oE '[0-9]+')
  if [ "$n" != "$last" ]; then echo "   [$(( $(date +%s) - t0 ))s] GCINE-CUT lines=$n lastframe=${fm:-?}"; last=$n; fi
  sleep 4
done
exec 3>&-
sleep 2

echo "[probe] === harvest GCINE-CUT -> $OUTLOG ==="
grep -a 'GCINE-CUT f=' "$GKLOG" > "$OUTLOG" 2>/dev/null || true
N=$(grep -ac 'GCINE-CUT f=' "$OUTLOG" 2>/dev/null || echo 0)
echo "[probe] captured $N frames -> $OUTLOG"
echo "[probe] frame range: $(grep -aoE 'f=[0-9]+' "$OUTLOG" | grep -oE '[0-9]+' | sort -n | sed -n '1p;$p' | tr '\n' ' ')"
echo "[probe] goalc errors (if any):"; grep -aiE 'Compilation Error|does not exist|REPL Error|Connected to OpenGOAL|listen to target' "$GCLOG" 2>/dev/null | head -8 || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
[ "$N" -gt 0 ]
