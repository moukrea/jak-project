#!/usr/bin/env bash
# x86 oracle probe at the run3 device GWALL-HIT trans, dumping blocked + ntris +
# each cached triangle's 3 verts, to compare with the device's hitting triangle.
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"; cd "$REPO"; mkdir -p "$(dirname "$OUTLOG")"
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
PROBE='(let ((gp-0 (new (quote stack-no-clear) (quote collide-using-spheres-params))) (s5-0 (new (quote stack-no-clear) (quote inline-array) (quote sphere) 2)) (br (-> *TARGET-bank* body-radius))) (dotimes (s4-0 2) ((method-of-type sphere new) (the-as symbol (-> s5-0 s4-0)) sphere)) (set! (-> s5-0 0 x) (-> *gwp* x)) (set! (-> s5-0 0 y) (+ 5734.4 br (-> *gwp* y))) (set! (-> s5-0 0 z) (-> *gwp* z)) (set! (-> s5-0 0 w) br) (set! (-> s5-0 1 x) (-> *gwp* x)) (set! (-> s5-0 1 y) (+ 2867.2 br (-> *gwp* y))) (set! (-> s5-0 1 z) (-> *gwp* z)) (set! (-> s5-0 1 w) br) (set! (-> gp-0 spheres) s5-0) (set! (-> gp-0 num-spheres) (the-as uint 2)) (set! (-> gp-0 collide-with) (-> *target* control root-prim collide-with)) (set! (-> gp-0 proc) #f) (set! (-> gp-0 ignore-pat) (new (quote static) (quote pat-surface) :noentity #x1)) (set! (-> gp-0 solid-only) #t) (format 0 "GWPROBE p=(~f ~f ~f) blocked=~A ntris=~D~%" (-> *gwp* x) (-> *gwp* y) (-> *gwp* z) (fill-and-probe-using-spheres *collide-cache* gp-0) (-> *collide-cache* num-tris)) (dotimes (ti (-> *collide-cache* num-tris)) (let ((tt (-> *collide-cache* tris ti))) (format 0 "GWTRI ~D v0=(~f ~f ~f)~%" ti (-> tt vertex 0 x) (-> tt vertex 0 y) (-> tt vertex 0 z)))))'
probe() { echo "(format 0 \"=== SPOT $4 ===~%\")" >&3; echo "(set-vector! *gwp* $1 $2 $3 1.0)" >&3; echo "$PROBE" >&3; sleep 1.5; }
# run3 device GWALL-HIT trans (sphere0.y - 8601.6):
probe -5103029.0 21946.5 4195777.5 H1
probe -5107173.5 21618.5 4189157.5 H3
probe -5152194.5 47644.8 4160631.0 H4
sleep 2
exec 3>&-; sleep 3
{
  echo "==== x86 probe at device GWALL-HIT trans (blocked + cache tris) ===="
  grep -aE "=== SPOT|GWPROBE|GWTRI" "$GKLOG" | sed -n '1,120p'
} | tee "$OUTLOG"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
