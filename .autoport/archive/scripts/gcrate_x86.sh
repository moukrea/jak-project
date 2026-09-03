#!/usr/bin/env bash
# gcrate_x86.sh — Gcollectible-state x86 crate-deactivate confirmation.
# Boots desktop x86 gk to Geyser Rock (training, NEW GAME), connects goalc
# (lt)+(build-game), warps, then finds ONE crate process via iterate-process-tree
# + type-type?, sends it an 'attack ('explode mode -> breaks wood/iron/steel),
# waits past the die :code's (suspend-for (seconds 5)), and harvests GDBG- lines.
# Correct x86 behavior: GDBG-PES type=crate fires ONCE (or a few times), then
# GDBG-DEACT type=crate eq=#t fires ONCE -> process deactivates and STOPS.
# (arm64 device loops GDBG-PES ~108x at ~4s and NEVER fires GDBG-DEACT.)
# Non-invasive: no edits to tracked source. Modeled on gcollect_x86.sh.
#
# Env: REPO GK GOALC ISO OUTLOG
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"
cd "$REPO"
mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gcrate] repo=$REPO gk=$GK gklog=$GKLOG"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

# 1) boot to link finish: logo
for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[gcrate] gk exited during boot"; tail -30 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[gcrate] booted ~${i}s"; break; }
  sleep 1
done
sleep 3

# 2) connect goalc, (lt) + (build-game)
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gcrate] build-game sent; waiting up to 200s for symbol intern..."
for i in $(seq 1 200); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[gcrate] build-game done ~${i}s"; break; }
done
sleep 4

# 3) warp to NEW GAME continue 'game-start' (Geyser Rock / training)
echo "[gcrate] warping to NEW GAME continue 'game-start' (Geyser Rock / training)"
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
echo "[gcrate] waiting 20s for training to load + *target* to settle..."
sleep 20

# verify *target* alive
echo '(if *target* (format 0 "GCRATE-TGT ~A tx=~f~%" (-> *target* type) (-> *target* control trans x)) (format 0 "GCRATE-TGT <target-is-#f>~%"))' >&3
sleep 2

# 4) PROVEN REPL-safe find+break:
#    (a) process-count *active-pool*  -> verify the live tree is populated
#    (b) search-process-tree (no mutable capture) -> first crate into global *gcrate*
#    (c) report it; (d) send 'attack 'explode (breaks wood/iron/steel).
echo '(define *gcrate* (the-as crate #f))' >&3
sleep 1
echo '(format 0 "GCRATE-COUNT total=~D~%" (process-count *active-pool*))' >&3
sleep 1
echo '(set! *gcrate* (the-as crate (search-process-tree *active-pool* (lambda ((p process-tree)) (type-type? (-> p type) crate)))))' >&3
sleep 1
echo '(if *gcrate* (format 0 "GFOUND ~A self=#x~X defense=~A look=~A state=~A~%" (-> *gcrate* type) (the-as int *gcrate*) (-> *gcrate* defense) (-> *gcrate* look) (-> (-> *gcrate* next-state) name)) (format 0 "GFOUND none~%"))' >&3
sleep 1
echo '(when *gcrate* (send-event *gcrate* (quote attack) #f (quote explode) (the-as uint 424242) 0) (format 0 "GBREAK-SENT-TO self=#x~X~%" (the-as int *gcrate*)))' >&3
sleep 2
echo '(format 0 "GCRATE-SENT frame=~D~%" (-> *display* base-frame-counter))' >&3

# 5) wait PAST the die :code (suspend-for (seconds 5)) so it deactivates.
echo "[gcrate] waiting 14s (>5s suspend-for) for die to complete + deactivate..."
sleep 14
echo '(format 0 "GALIVE frame=~D~%" (-> *display* base-frame-counter))' >&3
sleep 2
# extra window to catch any ~4s re-loop (arm64 symptom) if it were present
echo "[gcrate] extra 10s window to catch any re-loop..."
sleep 10
echo '(format 0 "GALIVE2 frame=~D~%" (-> *display* base-frame-counter))' >&3
sleep 2

exec 3>&-
sleep 3
ALIVE_AT_END=0
kill -0 "$GKPID" 2>/dev/null && ALIVE_AT_END=1

{
  echo "==================== Gcollectible-state x86 crate-deactivate confirmation ===================="
  echo "[cmd] gk:    $GK ... -iso-data $ISO -- -boot -debug-mem"
  echo "[cmd] goalc: $GOALC --game jak1 --proj-path . --iso-path $ISO"
  echo "[break] send-event crate 'attack #f 'explode 424242 0"
  echo
  echo "---- *target* probe ----"
  grep -a "GCRATE-TGT" "$GKLOG" 2>/dev/null || echo "(no GCRATE-TGT)"
  echo
  echo "---- GFOUND (crate located?) ----"
  grep -a "GCRATE-COUNT" "$GKLOG" 2>/dev/null || echo "(no GCRATE-COUNT)"
  grep -a "GFOUND" "$GKLOG" 2>/dev/null || echo "(no GFOUND)"
  grep -a "GBREAK-SENT-TO" "$GKLOG" 2>/dev/null || echo "(no GBREAK-SENT-TO)"
  grep -a "GPROC" "$GKLOG" 2>/dev/null | head -10 || echo "(no GPROC)"
  grep -a "GCRATE-SENT\|GALIVE" "$GKLOG" 2>/dev/null || echo "(no GCRATE-SENT/GALIVE)"
  echo
  echo "---- ALL GDBG-PES type=crate lines ----"
  grep -a "GDBG-PES type=crate" "$GKLOG" 2>/dev/null || echo "(none)"
  echo "  GDBG-PES type=crate COUNT = $(grep -ac 'GDBG-PES type=crate' "$GKLOG" 2>/dev/null || echo 0)"
  echo
  echo "---- ALL GDBG-PES-SET type=crate lines ----"
  grep -a "GDBG-PES-SET type=crate" "$GKLOG" 2>/dev/null || echo "(none)"
  echo
  echo "---- ALL GDBG-DEACT type=crate lines (the deactivation proof) ----"
  grep -a "GDBG-DEACT type=crate" "$GKLOG" 2>/dev/null || echo "(none)"
  echo "  GDBG-DEACT type=crate COUNT = $(grep -ac 'GDBG-DEACT type=crate' "$GKLOG" 2>/dev/null || echo 0)"
  echo "  GDBG-DEACT type=crate eq=#t COUNT = $(grep -ac 'GDBG-DEACT type=crate.*eq=#t' "$GKLOG" 2>/dev/null || echo 0)"
  echo
  echo "---- ALL GDBG-BIRTH lines containing crate ----"
  grep -a "GDBG-BIRTH" "$GKLOG" 2>/dev/null | grep -ai crate || echo "(no crate births)"
  echo
  echo "---- crash markers ----"
  grep -aiE "Segmentation|SIGSEGV|terminate|Assertion|signal [0-9]" "$GKLOG" 2>/dev/null | tail -10 || echo "(none)"
  echo
  echo "==================== VERDICT ===================="
  echo "ALIVE_AT_END=$ALIVE_AT_END"
} | tee "$OUTLOG"

# also dump every GDBG- line + GFOUND verbatim for the report
grep -aE "GDBG-|GFOUND|GCRATE-|GALIVE" "$GKLOG" > "$(dirname "$OUTLOG")/gdbg-x86.log" 2>/dev/null || true
cp -f "$GKLOG" "${OUTLOG%.log}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.log}.goalc.log" 2>/dev/null || true
echo "[gcrate] gdbg-x86.log: $(dirname "$OUTLOG")/gdbg-x86.log"
echo "[gcrate] full gk log:    ${OUTLOG%.log}.gk.log"
echo "[gcrate] full goalc log: ${OUTLOG%.log}.goalc.log"
[ "$ALIVE_AT_END" -eq 1 ]
