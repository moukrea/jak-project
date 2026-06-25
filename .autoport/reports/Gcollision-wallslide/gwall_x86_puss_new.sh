#!/usr/bin/env bash
# gwall_x86_puss.sh — x86 per-triangle crouch-probe dump at the device stuck spot.
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"; export OG_PUSS_DUMP=1; cd "$REPO"; mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"; : > "$GKLOG"; : > "$GCLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 90); do kill -0 "$GKPID" 2>/dev/null || { echo "gk died"; exit 1; }; grep -qE "link finish: logo($|-)" "$GKLOG" && break; sleep 1; done
sleep 3
timeout 700 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"; echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && break; done
sleep 4
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
sleep 16
echo '(define *gwp* (new (quote global) (quote vector)))' >&3
PROBE='(let ((gp-0 (new (quote stack-no-clear) (quote collide-using-spheres-params))) (s5-0 (new (quote stack-no-clear) (quote inline-array) (quote sphere) 2)) (br (-> *TARGET-bank* body-radius))) (dotimes (s4-0 2) ((method-of-type sphere new) (the-as symbol (-> s5-0 s4-0)) sphere)) (set! (-> s5-0 0 x) (-> *gwp* x)) (set! (-> s5-0 0 y) (+ 5734.4 br (-> *gwp* y))) (set! (-> s5-0 0 z) (-> *gwp* z)) (set! (-> s5-0 0 w) br) (set! (-> s5-0 1 x) (-> *gwp* x)) (set! (-> s5-0 1 y) (+ 2867.2 br (-> *gwp* y))) (set! (-> s5-0 1 z) (-> *gwp* z)) (set! (-> s5-0 1 w) br) (set! (-> gp-0 spheres) s5-0) (set! (-> gp-0 num-spheres) (the-as uint 2)) (set! (-> gp-0 collide-with) (-> *target* control root-prim collide-with)) (set! (-> gp-0 proc) #f) (set! (-> gp-0 ignore-pat) (new (quote static) (quote pat-surface) :noentity #x1)) (set! (-> gp-0 solid-only) #t) (format 0 "GWPROBE blocked=~A ntris=~D nprims=~D~%" (fill-and-probe-using-spheres *collide-cache* gp-0) (-> *collide-cache* num-tris) (-> *collide-cache* num-prims)))'
echo "(set-vector! *gwp* -5330629.5 30772.4 4403733.5 1.0)" >&3
echo "$PROBE" >&3
sleep 2
exec 3>&-; sleep 3
{
  echo "==== x86 per-triangle crouch-probe dump (stuck spot -5278032 15825.9 4412783.5) ===="
  grep -a "GWPROBE" "$GKLOG" || echo "(no GWPROBE)"
  echo "---- PUSS9 per-triangle (dmr = dist^2 - radius^2; hit=1 if <0) ----"
  grep -a "PUSS9" "$GKLOG" | tail -60 || echo "(no PUSS9 — method 9 not hit; maybe method 10)"
  echo "PUSS9 count: $(grep -ac PUSS9 "$GKLOG"); hits: $(grep -a PUSS9 "$GKLOG" | grep -c 'hit=1')"
} | tee "$OUTLOG"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
