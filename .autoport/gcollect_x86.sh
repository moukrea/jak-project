#!/usr/bin/env bash
# gcollect_x86.sh — Gcollectible-state x86-first ground truth.
# Boots desktop x86 gk to Geyser Rock (training, NEW GAME), connects goalc
# (lt)+(build-game), then deterministically exercises the GREEN-ECO respawn gate
# from collectables.gc:567:
#     (< 0.0 (the-as float (send-event *target* 'query 'pickup (pickup-type eco-green))))
# with the player's green-eco `health` set to FULL (3.0) and ZERO (0.0).
# Correct x86 behavior: gate=#t at full (pickup STAYS gone), gate=#f at zero
# (pickup RESPAWNS).  This is the state-anchored reference for the arm64 diff.
# Also dumps the eco-pill (small green) query for completeness.
# Non-invasive: no edits to tracked source. Modeled on gmouche_x86.sh / f1_x86_dump.sh.
#
# Env: REPO (root), GK (rel/abs), GOALC (rel/abs), ISO (rel/abs), OUTLOG (abs)
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"
cd "$REPO"
mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gcollect] repo=$REPO gk=$GK gklog=$GKLOG"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

# 1) boot to link finish: logo
for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[gcollect] gk exited during boot"; tail -30 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[gcollect] booted ~${i}s"; break; }
  sleep 1
done
sleep 3

# 2) connect goalc, (lt) + (build-game)
timeout 600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gcollect] build-game sent; waiting up to 150s for symbol intern..."
for i in $(seq 1 150); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[gcollect] build-game done ~${i}s"; break; }
done
sleep 4

# 3) warp to NEW GAME continue 'game-start' (Geyser Rock / training)
echo "[gcollect] warping to NEW GAME continue 'game-start' (Geyser Rock / training)"
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
echo "[gcollect] waiting 18s for training to load + *target* to settle..."
sleep 18

# verify *target* alive
echo '(if *target* (format 0 "GECO-TGT ~A tx=~f~%" (-> *target* type) (-> *target* control trans x)) (format 0 "GECO-TGT <target-is-#f>~%"))' >&3
sleep 2

# 4) baseline fact fields
echo '(format 0 "GECO-BASE health=~f hmax=~f pill=~f pillmax=~f~%" (-> *target* fact health) (-> *target* fact health-max) (-> *target* fact eco-pill) (-> *target* fact eco-pill-max))' >&3
sleep 2

# 5) KEY TEST — respawn gate at FULL green-eco health (3.0)
echo '(set! (-> *target* fact health) 3.0)' >&3
sleep 1
echo '(format 0 "GECO-Q-FULL h=~f q=~f gate=~A~%" (-> *target* fact health) (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-green))) (< 0.0 (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-green)))))' >&3
sleep 2

# 6) respawn gate at ZERO green-eco health (0.0)
echo '(set! (-> *target* fact health) 0.0)' >&3
sleep 1
echo '(format 0 "GECO-Q-ZERO h=~f q=~f gate=~A~%" (-> *target* fact health) (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-green))) (< 0.0 (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-green)))))' >&3
sleep 2

# 7) eco-pill (small green) query at FULL pill and ZERO pill
echo '(set! (-> *target* fact eco-pill) 25.0)' >&3
sleep 1
echo '(format 0 "GECO-PILL-FULL p=~f q=~f gate=~A~%" (-> *target* fact eco-pill) (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-pill))) (< 0.0 (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-pill)))))' >&3
sleep 1
echo '(set! (-> *target* fact eco-pill) 0.0)' >&3
sleep 1
echo '(format 0 "GECO-PILL-ZERO p=~f q=~f gate=~A~%" (-> *target* fact eco-pill) (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-pill))) (< 0.0 (the-as float (send-event *target* (quote query) (quote pickup) (pickup-type eco-pill)))))' >&3
sleep 2

# 8) raw return-register inspection: the same send-event as an INT (object) to see the bit pattern
echo '(set! (-> *target* fact health) 3.0)' >&3
sleep 1
echo '(format 0 "GECO-RAW health=3.0 obj=~D hex=#x~X~%" (the-as int (send-event *target* (quote query) (quote pickup) (pickup-type eco-green))) (the-as int (send-event *target* (quote query) (quote pickup) (pickup-type eco-green))))' >&3
sleep 2

# 9) alive proof
echo '(format 0 "GECO-ALIVE frame=~D~%" (-> *display* base-frame-counter))' >&3
sleep 3

exec 3>&-
sleep 3
ALIVE_AT_END=0
kill -0 "$GKPID" 2>/dev/null && ALIVE_AT_END=1

{
  echo "==================== Gcollectible-state x86 ground truth ===================="
  echo "[cmd] gk:    $GK ... -iso-data $ISO -- -boot -debug-mem"
  echo "[cmd] goalc: $GOALC --game jak1 --proj-path . --iso-path $ISO"
  echo
  echo "---- *target* probe ----"
  grep -a "GECO-TGT"  "$GKLOG" 2>/dev/null || echo "(no GECO-TGT)"
  echo
  echo "---- green-eco respawn-gate ground truth (collectables.gc:567) ----"
  grep -a "GECO-BASE"      "$GKLOG" 2>/dev/null || echo "(no GECO-BASE)"
  grep -a "GECO-Q-FULL"    "$GKLOG" 2>/dev/null || echo "(no GECO-Q-FULL)"
  grep -a "GECO-Q-ZERO"    "$GKLOG" 2>/dev/null || echo "(no GECO-Q-ZERO)"
  grep -a "GECO-PILL-FULL" "$GKLOG" 2>/dev/null || echo "(no GECO-PILL-FULL)"
  grep -a "GECO-PILL-ZERO" "$GKLOG" 2>/dev/null || echo "(no GECO-PILL-ZERO)"
  grep -a "GECO-RAW"       "$GKLOG" 2>/dev/null || echo "(no GECO-RAW)"
  grep -a "GECO-ALIVE"     "$GKLOG" 2>/dev/null || echo "(no GECO-ALIVE)"
  echo
  echo "EXPECTED x86 (correct): GECO-Q-FULL gate=#t (stays gone while holding eco);"
  echo "                        GECO-Q-ZERO gate=#f (respawns once consumed to 0)."
  echo
  echo "---- goalc compile errors (if any) ----"
  grep -aiE "Compilation Error|does not exist|Unrecognized|cannot|failed to|no such|Could not" "$GCLOG" 2>/dev/null | tail -20 || echo "(none)"
  echo
  echo "---- crash markers ----"
  grep -aiE "Segmentation|SIGSEGV|terminate|Assertion|signal [0-9]" "$GKLOG" 2>/dev/null | tail -10 || echo "(none)"
  echo
  echo "==================== VERDICT ===================="
  echo "ALIVE_AT_END=$ALIVE_AT_END"
} | tee "$OUTLOG"

cp -f "$GKLOG" "${OUTLOG%.log}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.log}.goalc.log" 2>/dev/null || true
echo "[gcollect] full gk log:    ${OUTLOG%.log}.gk.log"
echo "[gcollect] full goalc log: ${OUTLOG%.log}.goalc.log"
[ "$ALIVE_AT_END" -eq 1 ]
