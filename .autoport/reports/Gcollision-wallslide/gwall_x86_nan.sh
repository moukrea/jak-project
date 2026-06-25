#!/usr/bin/env bash
# gwall_x86_nan.sh — tight x86 NaN-compare + normalize-zero oracle (format <=8 params).
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
timeout 600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"; echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && break; done
sleep 4
# genuine qNaN via bit pattern
echo '(define *gwn* (the-as float (the-as uint #x7fc00000)))' >&3
echo '(format 0 "NANBITS ~X~%" (the-as int *gwn*))' >&3
echo '(format 0 "CMPLT a=~A b=~A~%" (< 0.7 *gwn*) (< *gwn* 0.7))' >&3
echo '(format 0 "CMPLE a=~A b=~A~%" (<= 0.7 *gwn*) (<= *gwn* 0.7))' >&3
echo '(format 0 "CMPGE a=~A b=~A~%" (>= 0.7 *gwn*) (>= *gwn* 0.7))' >&3
echo '(format 0 "CMPGT a=~A b=~A~%" (> 0.7 *gwn*) (> *gwn* 0.7))' >&3
echo '(format 0 "MINMAX fmax=~f fmin=~f~%" (fmax 0.5 *gwn*) (fmin 0.5 *gwn*))' >&3
# normalize of zero and tiny vectors -> NaN or 0 ?
echo '(define *gwv* (new (quote global) (quote vector)))' >&3
echo '(set-vector! *gwv* 0.0 0.0 0.0 1.0)' >&3
echo '(vector-normalize! *gwv* 1.0)' >&3
echo '(format 0 "NORMZERO d0=~X d1=~X d2=~X~%" (-> *gwv* data 0) (-> *gwv* data 1) (-> *gwv* data 2))' >&3
echo '(set-vector! *gwv* 0.0001 0.0 0.0 1.0)' >&3
echo '(vector-normalize! *gwv* 1.0)' >&3
echo '(format 0 "NORMTINY d0=~X d1=~X d2=~X~%" (-> *gwv* data 0) (-> *gwv* data 1) (-> *gwv* data 2))' >&3
# vector-length of zero
echo '(set-vector! *gwv* 0.0 0.0 0.0 1.0)' >&3
echo '(format 0 "VLEN0 ~f bits=~X~%" (vector-length *gwv*) (the-as int (vector-length *gwv*)))' >&3
sleep 3
# warp + live state (chunks of <=8 params)
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
sleep 16
for i in 1 2 3 4; do
  echo '(when *target* (format 0 "LV-A st=~A sa=~f pa=~f ta=~f~%" (-> *target* next-state name) (-> *target* control surface-angle) (-> *target* control poly-angle) (-> *target* control touch-angle)))' >&3
  echo '(when *target* (format 0 "LV-B f60=~f f61=~f status=~X tz=~f~%" (-> *target* control unknown-float60) (-> *target* control unknown-float61) (-> *target* control status) (-> *target* control trans z)))' >&3
  echo '(when *target* (format 0 "LV-C transv-off=~D snorm-off=~D~%" (the-as int (&- (the-as pointer (&-> (-> *target* control) transv)) (the-as uint (-> *target* control)))) (the-as int (&- (the-as pointer (&-> (-> *target* control) surface-normal)) (the-as uint (-> *target* control))))))' >&3
  sleep 1
done
exec 3>&-; sleep 3
{
  echo "==== Gcollision-wallslide x86 NaN/normalize oracle ===="
  grep -aE "NANBITS|CMPLT|CMPLE|CMPGE|CMPGT|MINMAX|NORMZERO|NORMTINY|VLEN0|LV-A|LV-B|LV-C" "$GKLOG" || echo "(no markers)"
  echo "---- goalc errors ----"; grep -aiE "Compilation Error|does not exist" "$GCLOG" | head -8 || true
} | tee "$OUTLOG"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
