#!/usr/bin/env bash
# gjungle_x86.sh — Forbidden Jungle (level 'jungle / JUN.DGO) load oracle on the
# PRISTINE golden x86 (jak-original-v033). Boots gk to title, connects goalc
# (lt)+(build-game), warps to the "jungle-start" continue point — the exact
# (start 'play ...) form the device JUNGLE-WARP replays — and polls Jak's world
# position while JUN.DGO loads + the body settles. Proves the jungle loads fine
# on x86 (confirming any device crash is an arm64-side divergence).
#
# Usage: gjungle_x86.sh [OUTLOG]
set -uo pipefail
REPO="${REPO:-/home/emeric/code/jak-original-v033}"
GK="${GK:-$REPO/build/game/gk}"
GOALC="${GOALC:-$REPO/build/Release/bin/goalc/goalc}"
ISO="${ISO:-$REPO/iso_data/jak1}"
OUTLOG="${1:-/home/emeric/code/jak-project/.autoport/reports/Gcrash-jungle/x86-oracle.txt}"
POLLS="${POLLS:-40}"
mkdir -p "$(dirname "$OUTLOG")"
export DISPLAY="${DISPLAY:-:0}"
cd "$REPO"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[jungle-x86] repo=$REPO gk=$GK polls=$POLLS log=$GKLOG"
"$GK" --game jak1 --proj-path . --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 120); do kill -0 "$GKPID" 2>/dev/null || { echo "[jungle-x86] gk exited during boot"; tail -20 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[jungle-x86] booted ~${i}s"; break; }; sleep 1; done
sleep 3
timeout $((POLLS+260)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[jungle-x86] build-game sent; waiting up to 160s for symbol intern..."
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful|\\] OK" "$GCLOG" 2>/dev/null && { echo "[jungle-x86] build-game done ~${i}s"; break; }; done
sleep 4
echo "[jungle-x86] warping to 'jungle-start' (Forbidden Jungle / JUN.DGO)"
echo "(start 'play (get-continue-by-name *game-info* \"jungle-start\"))" >&3
POLLFORM='(when *target* (format 0 "JUNGLE-STATE tx=~f ty=~f tz=~f cont=~A~%" (-> *target* control trans x) (-> *target* control trans y) (-> *target* control trans z) (-> *game-info* current-continue name)))'
echo "[jungle-x86] polling ${POLLS}x @1s for (-> *target* control trans)"
for i in $(seq 1 "$POLLS"); do echo "$POLLFORM" >&3; sleep 1; done
exec 3>&-
sleep 3
echo "[jungle-x86] === JUNGLE-STATE samples ==="
grep -a "JUNGLE-STATE" "$GKLOG" > "$OUTLOG" 2>/dev/null || true
cat "$OUTLOG" || true
N=$(grep -ac 'JUNGLE-STATE' "$GKLOG" 2>/dev/null || echo 0)
echo "[jungle-x86] count=$N -> $OUTLOG"
echo "[jungle-x86] level/load markers in gk log:"
grep -aE "Adding level jungle|link finish: (jun|jungle)|complete-cb|EE play|crash|Segmentation|signal" "$GKLOG" 2>/dev/null | tail -20 || true
echo "[jungle-x86] did gk exit early?"; kill -0 "$GKPID" 2>/dev/null && echo "  gk still ALIVE (good)" || echo "  gk DIED"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
[ "$N" -gt 0 ]
