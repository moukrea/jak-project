#!/usr/bin/env bash
# f1_x86_dump.sh — deterministic Geyser Rock (training) spawn-state oracle.
# Boots desktop gk into the title attract, connects goalc (lt)+(build-game)
# to intern game symbols, then warps to the canonical NEW-GAME continue
# "game-start" (level 'training = Geyser Rock) and polls Jak's world
# position (-> *target* control trans) once per second while the level
# loads + the body settles. Reads go to the TARGET's stdout via
# (format 0 ...) and are captured from the gk log.  Non-invasive: no
# source edits to the target repo (build-game recompiles into the running
# target; out/ is gitignored).
#
# Env: REPO (root), GK (rel), GOALC (rel), ISO (rel), OUTLOG (abs), POLLS (def 45)
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
POLLS="${POLLS:-45}"
export DISPLAY="${DISPLAY:-:0}"
cd "$REPO"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[dump] repo=$REPO gk=$GK polls=$POLLS log=$GKLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 90); do kill -0 "$GKPID" 2>/dev/null || { echo "[dump] gk exited during boot"; tail -20 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[dump] booted ~${i}s"; break; }; sleep 1; done
sleep 3
timeout $((POLLS+220)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[dump] build-game sent; waiting up to 130s for symbol intern..."
for i in $(seq 1 130); do sleep 1; grep -qiE "Successfully built all|Build Successful|\\] OK" "$GCLOG" 2>/dev/null && { echo "[dump] build-game done ~${i}s"; break; }; done
sleep 4
echo "[dump] warping to NEW GAME continue 'game-start' (Geyser Rock / training)"
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
POLLFORM='(when *target* (format 0 "F1-STATE tx=~f ty=~f tz=~f cont=~A~%" (-> *target* control trans x) (-> *target* control trans y) (-> *target* control trans z) (-> *game-info* current-continue name)))'
echo "[dump] polling ${POLLS}x @1s for (-> *target* control trans)"
for i in $(seq 1 "$POLLS"); do echo "$POLLFORM" >&3; sleep 1; done
exec 3>&-
sleep 3
echo "[dump] === F1-STATE samples ==="
grep -a "F1-STATE" "$GKLOG" > "$OUTLOG" 2>/dev/null || true
cat "$OUTLOG" || true
N=$(grep -ac 'F1-STATE' "$GKLOG" 2>/dev/null || echo 0)
echo "[dump] count=$N  -> $OUTLOG"
echo "[dump] level/gameplay markers in gk log:"
grep -aE "GAMEPLAY: enter|link finish: (training|medres-training|village1)|\\bcomplete-cb\\b" "$GKLOG" 2>/dev/null | tail -15 || true
echo "[dump] goalc errors:"; grep -aiE "Compilation Error|does not exist|listen to target|Connected to OpenGOAL" "$GCLOG" 2>/dev/null | head -8 || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
[ "$N" -gt 0 ]
