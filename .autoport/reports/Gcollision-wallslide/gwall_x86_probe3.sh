#!/usr/bin/env bash
# gwall_x86_probe2.sh — x86 crouch-probe (can-exit-duck?) verdict at the exact
# device wall positions. Builds the 2 head-spheres (per can-exit-duck?,
# target-util.gc:619) directly at the device coords and calls
# fill-and-probe-using-spheres. blocked=#f -> CAN stand (no ceiling); a truthy
# result -> blocked -> stays crouched. Single-line forms (no defun).
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
echo '(format 0 "GWBR body-radius=~f~%" (-> *TARGET-bank* body-radius))' >&3
sleep 1

# probe helper as one single-line form; args via a tiny global vector *gwp*
echo '(define *gwp* (new (quote global) (quote vector)))' >&3
# single-line probe: reads *gwp* x/y/z as the player trans, builds 2 head spheres, probes
PROBE='(let ((gp-0 (new (quote stack-no-clear) (quote collide-using-spheres-params))) (s5-0 (new (quote stack-no-clear) (quote inline-array) (quote sphere) 2)) (br (-> *TARGET-bank* body-radius))) (dotimes (s4-0 2) ((method-of-type sphere new) (the-as symbol (-> s5-0 s4-0)) sphere)) (set! (-> s5-0 0 x) (-> *gwp* x)) (set! (-> s5-0 0 y) (+ 5734.4 br (-> *gwp* y))) (set! (-> s5-0 0 z) (-> *gwp* z)) (set! (-> s5-0 0 w) br) (set! (-> s5-0 1 x) (-> *gwp* x)) (set! (-> s5-0 1 y) (+ 2867.2 br (-> *gwp* y))) (set! (-> s5-0 1 z) (-> *gwp* z)) (set! (-> s5-0 1 w) br) (set! (-> gp-0 spheres) s5-0) (set! (-> gp-0 num-spheres) (the-as uint 2)) (set! (-> gp-0 collide-with) (-> *target* control root-prim collide-with)) (set! (-> gp-0 proc) #f) (set! (-> gp-0 ignore-pat) (new (quote static) (quote pat-surface) :noentity #x1)) (set! (-> gp-0 solid-only) #t) (format 0 "GWPROBE p=(~f ~f ~f) blocked=~A~%" (-> *gwp* x) (-> *gwp* y) (-> *gwp* z) (fill-and-probe-using-spheres *collide-cache* gp-0)))'

probe() { echo "(set-vector! *gwp* $1 $2 $3 1.0)" >&3; echo "$PROBE" >&3; sleep 1; }

# Geyser-steps stuck positions (device target-duck-stance, permanently stuck)
probe -5278032.0 15825.9 4412783.5
probe -5278032.0 15900.0 4412783.5
probe -5278032.0 16100.0 4412783.5
probe -5263892.5 21739.7 4383936.5
probe -5263892.5 21850.0 4383936.5
# control: high open air
probe -5278032.0 40000.0 4412783.5

sleep 2
exec 3>&-; sleep 3
{
  echo "==== Gcollision-wallslide x86 crouch-probe verdicts ===="
  grep -a "GWBR" "$GKLOG" || true
  echo "(blocked=#f -> Jak CAN stand; truthy -> stays crouched)"
  grep -a "GWPROBE" "$GKLOG" || echo "(no GWPROBE — probe form failed)"
  echo "---- goalc errors ----"; grep -aiE "Compilation Error|does not exist|looked up as" "$GCLOG" | head -10 || true
} | tee "$OUTLOG"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
