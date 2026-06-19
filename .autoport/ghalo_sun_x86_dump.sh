#!/usr/bin/env bash
# ghalo_sun_x86_dump.sh — deterministic SUN-CYCLE state dump over the goalc listener.
# Boots a desktop gk into the title attract, connects goalc (lt)+(build-game) so the
# game symbols are interned, then polls the sun state every 1s for ~POLLS seconds
# while FORCING fast time (ratio 18000) so several sunrises are captured. The reads
# go to the TARGET's stdout via (format 0 ...) -> we capture them from the gk log.
# Non-invasive: no source edits to the target repo (build-game recompiles into the
# already-running target; out/ is gitignored so the repo stays git-clean).
#
# Env: REPO (repo root), GK (rel), GOALC (rel), ISO (rel), OUTLOG (abs), POLLS (def 70)
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
POLLS="${POLLS:-70}"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
cd "$REPO"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[dump] repo=$REPO gk=$GK polls=$POLLS"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 90); do kill -0 "$GKPID" 2>/dev/null || { echo "[dump] gk exited during boot"; tail -10 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[dump] booted ~${i}s"; break; }; sleep 1; done
sleep 3
# NOTE: original v0.3.3 goalc lacks --auto-lt; the explicit (lt) form connects regardless.
timeout $((POLLS+200)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[dump] build-game sent; waiting up to 110s for it to intern symbols..."
for i in $(seq 1 110); do sleep 1; grep -qiE "Successfully built all|Build Successful|\\] OK" "$GCLOG" 2>/dev/null && { echo "[dump] build-game done ~${i}s"; break; }; done
sleep 4
echo "[dump] polling ${POLLS}x @1s (forcing ratio=18000)"
POLLFORM='(when *time-of-day-proc* (begin (set! (-> *time-of-day-proc* 0 time-ratio) 18000.0) (format 0 "GHALO-SUN tod=~f c=~D sf=~f day=~D~%" (-> *time-of-day-proc* 0 time-of-day) (-> *time-of-day-proc* 0 sun-count) (-> *time-of-day-context* sun-fade) (-> *time-of-day-proc* 0 day))))'
for i in $(seq 1 "$POLLS"); do echo "$POLLFORM" >&3; sleep 1; done
exec 3>&-
sleep 3
echo "[dump] === GHALO-SUN samples ==="
grep -a "GHALO-SUN" "$GKLOG" > "$OUTLOG" 2>/dev/null || true
cat "$OUTLOG" || true
N=$(grep -ac 'GHALO-SUN' "$GKLOG" 2>/dev/null || echo 0)
echo "[dump] count=$N  -> $OUTLOG"
echo "[dump] goalc errors:"; grep -aiE "Compilation Error|does not exist|listen to target|Connected to OpenGOAL" "$GCLOG" 2>/dev/null | head -5 || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
[ "$N" -gt 0 ]
