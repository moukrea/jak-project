#!/usr/bin/env bash
# gsfx_x86_actions.sh — x86 ground truth for the OWNER's action SFX.
# Boots desktop x86 gk, connects goalc (lt)+(build-game), warps to Geyser Rock
# (training, NEW GAME), then evals the EXACT (sound-play "...") forms the
# crate/orb/eco code uses, with the SFX-PROBE enabled, so we capture the correct
# name/idx/vol the device must match. Also breaks a REAL crate via send-event
# 'attack 'explode for an end-to-end crate-break command.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
export OPENGOAL_SFX_PROBE=1
GK=build-x86/game/gk
GOALC=build-x86/goalc/goalc
ISO=out/jak1/iso
OUTDIR=.autoport/reports/Gsfx-actions
mkdir -p "$OUTDIR"
GKLOG="$OUTDIR/x86-actions-gk.log"; GCLOG="$OUTDIR/x86-actions-goalc.log"
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gsfx-x86] gk=$GK iso=$ISO"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[gsfx-x86] gk exited during boot"; tail -30 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[gsfx-x86] booted ~${i}s"; break; }
  sleep 1
done
sleep 3

timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gsfx-x86] build-game sent; waiting up to 200s..."
for i in $(seq 1 200); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[gsfx-x86] build-game done ~${i}s"; break; }
done
sleep 4

echo "[gsfx-x86] warp to NEW GAME continue 'game-start' (Geyser Rock / training)"
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
sleep 20
echo '(if *target* (format 0 "GSFX-TGT ~A~%" (-> *target* type)) (format 0 "GSFX-TGT none~%"))' >&3
sleep 2

# Force-eval each action sound name through the REAL (sound-play ...) macro path.
for nm in wcrate-break icrate-break scrate-break dcrate-break crate-jump \
          buzzer-pickup cell-prize pu-powercell \
          g-eco-pickup b-eco-pickup y-eco-pickup r-eco-pickup pill-pickup; do
  echo "(format 0 \"GSFX-EVAL name=$nm~%\")" >&3
  echo "(sound-play \"$nm\")" >&3
  sleep 1
done
sleep 2

# Also break a REAL crate end-to-end (its :code runs (sound-play "wcrate-break")).
echo '(define *gcrate* (the-as crate #f))' >&3; sleep 1
echo '(set! *gcrate* (the-as crate (search-process-tree *active-pool* (lambda ((p process-tree)) (type-type? (-> p type) crate)))))' >&3; sleep 1
echo '(if *gcrate* (format 0 "GSFX-CRATE-FOUND ~A~%" (-> *gcrate* type)) (format 0 "GSFX-CRATE-FOUND none~%"))' >&3; sleep 1
echo '(when *gcrate* (send-event *gcrate* (quote attack) #f (quote explode) (the-as uint 424242) 0))' >&3
sleep 4

exec 3>&-
sleep 3
echo "==== SFX-PROBE results around GSFX-EVAL markers ===="
echo "[gsfx-x86] gk log: $GKLOG  goalc log: $GCLOG"
grep -aE "GSFX-EVAL|GSFX-CRATE|SFX-PROBE] (play|  lookup|  newplay)|GSFX-TGT" "$GKLOG" | tail -120