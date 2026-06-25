#!/usr/bin/env bash
# x86 crouch-probe (+per-triangle dump) at the 4 device stuck spots.
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
PROBE='(let ((gp-0 (new (quote stack-no-clear) (quote collide-using-spheres-params))) (s5-0 (new (quote stack-no-clear) (quote inline-array) (quote sphere) 2)) (br (-> *TARGET-bank* body-radius))) (dotimes (s4-0 2) ((method-of-type sphere new) (the-as symbol (-> s5-0 s4-0)) sphere)) (set! (-> s5-0 0 x) (-> *gwp* x)) (set! (-> s5-0 0 y) (+ 5734.4 br (-> *gwp* y))) (set! (-> s5-0 0 z) (-> *gwp* z)) (set! (-> s5-0 0 w) br) (set! (-> s5-0 1 x) (-> *gwp* x)) (set! (-> s5-0 1 y) (+ 2867.2 br (-> *gwp* y))) (set! (-> s5-0 1 z) (-> *gwp* z)) (set! (-> s5-0 1 w) br) (set! (-> gp-0 spheres) s5-0) (set! (-> gp-0 num-spheres) (the-as uint 2)) (set! (-> gp-0 collide-with) (-> *target* control root-prim collide-with)) (set! (-> gp-0 proc) #f) (set! (-> gp-0 ignore-pat) (new (quote static) (quote pat-surface) :noentity #x1)) (set! (-> gp-0 solid-only) #t) (format 0 "GWPROBE p=(~f ~f ~f) blocked=~A ntris=~D~%" (-> *gwp* x) (-> *gwp* y) (-> *gwp* z) (fill-and-probe-using-spheres *collide-cache* gp-0) (-> *collide-cache* num-tris)))'
probe() { echo "(format 0 \"=== SPOT $4 ===~%\")" >&3; echo "(set-vector! *gwp* $1 $2 $3 1.0)" >&3; echo "$PROBE" >&3; sleep 1.5; }
probe -5289353.5 32616.6 4079193.8 S1
probe -5342971.0 23828.3 4094617.8 S2
probe -5237659.0 9111.6  4512007.0 S3
probe -5117947.0 28954.0 4171906.0 S4
sleep 2
exec 3>&-; sleep 3
{
  echo "==== x86 crouch-probe at 4 device stuck spots (blocked=#f -> x86 CAN stand) ===="
  grep -aE "=== SPOT|GWPROBE|PUSS9" "$GKLOG" | sed -n '1,200p'
} | tee "$OUTLOG"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
