#!/usr/bin/env bash
# gwall_x86_probe.sh — Gcollision-wallslide x86-first oracle probe.
# Boots desktop gk -> title, connects goalc (lt)+(build-game), warps to NEW-GAME
# continue "game-start" (level 'training = Geyser Rock), then:
#   (1) prints byte OFFSETS of the collide-shape-moving collision fields (for the
#       device C++ capture hook — device has no REPL),
#   (2) prints x86's NaN float-compare + fmax/fmin truth values (the suspected
#       arm64-vs-x86 divergence mechanism: goalc arm64 < -> MI, <= -> LS return #f
#       on NaN where x86 COMISS+jb/jbe return #t),
#   (3) deterministically tests whether the touch-angle PRODUCER math
#       (vector-normalize! of a near-zero/zero into-wall vector, then vector-dot,
#       then fmax) yields NaN/Inf — the slow-slide arg2~0 case,
#   (4) reads the live *target* collision state after warp (baseline standing).
# Non-invasive: no source edits (build-game recompiles into the running target).
#
# Env: REPO GK GOALC ISO OUTLOG
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"
cd "$REPO"
mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gw] repo=$REPO gk=$GK gklog=$GKLOG"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[gw] gk exited during boot"; tail -30 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[gw] booted ~${i}s"; break; }
  sleep 1
done
sleep 3

timeout 700 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gw] build-game sent; waiting up to 160s..."
for i in $(seq 1 160); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[gw] build-game done ~${i}s"; break; }
done
sleep 4

# ---- (1) OFFSETS (null-cast &-> gives the byte offset) ----
echo "[gw] dumping field offsets"
echo '(format 0 "GWOFF target.control=~D~%" (the-as int (&-> (the-as target (the-as pointer 0)) control)))' >&3
echo '(format 0 "GWOFF csm.trans=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) trans)))' >&3
echo '(format 0 "GWOFF csm.transv=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) transv)))' >&3
echo '(format 0 "GWOFF csm.surface-normal=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) surface-normal)))' >&3
echo '(format 0 "GWOFF csm.surface-angle=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) surface-angle)))' >&3
echo '(format 0 "GWOFF csm.poly-angle=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) poly-angle)))' >&3
echo '(format 0 "GWOFF csm.touch-angle=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) touch-angle)))' >&3
echo '(format 0 "GWOFF csm.status=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) status)))' >&3
echo '(format 0 "GWOFF csm.local-normal=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) local-normal)))' >&3
echo '(format 0 "GWOFF csm.poly-normal=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) poly-normal)))' >&3
echo '(format 0 "GWOFF csm.reaction-flag=~D~%" (the-as int (&-> (the-as collide-shape-moving (the-as pointer 0)) reaction-flag)))' >&3
echo '(format 0 "GWOFF proc.next-state=~D~%" (the-as int (&-> (the-as process (the-as pointer 0)) next-state)))' >&3
echo '(format 0 "GWOFF state.name=~D~%" (the-as int (&-> (the-as state (the-as pointer 0)) name)))' >&3
sleep 3

# ---- (2) NaN compare / fmax / fmin truth table (runtime NaN, avoid const-fold) ----
echo "[gw] NaN truth table"
echo '(define *gw-z* (new (quote global) (quote vector)))' >&3
echo '(set-vector! *gw-z* 0.0 0.0 0.0 0.0)' >&3
echo '(define *gw-nanv* (new (quote global) (quote vector)))' >&3
echo '(set-vector! *gw-nanv* 0.0 0.0 0.0 0.0)' >&3
echo '(vector-normalize! *gw-nanv* 1.0)' >&3   # zero vector -> 1/0=Inf -> 0*Inf=NaN
echo '(define *gw-nan* (vector-dot *gw-z* *gw-nanv*))' >&3
echo '(format 0 "GWNAN bits nanv=(~X ~X ~X) nan=~X~%" (-> *gw-nanv* data 0) (-> *gw-nanv* data 1) (-> *gw-nanv* data 2) (the-as int *gw-nan*))' >&3
echo '(format 0 "GWNAN cmp 0.7<nan=~A nan<0.7=~A 0.7<=nan=~A nan<=0.7=~A 0.7>=nan=~A nan>=0.7=~A 0.7>nan=~A nan>0.7=~A~%" (< 0.7 *gw-nan*) (< *gw-nan* 0.7) (<= 0.7 *gw-nan*) (<= *gw-nan* 0.7) (>= 0.7 *gw-nan*) (>= *gw-nan* 0.7) (> 0.7 *gw-nan*) (> *gw-nan* 0.7))' >&3
echo '(format 0 "GWNAN minmax fmax(0.5,nan)=~f fmax(nan,0.5)=~f fmin(0.5,nan)=~f fmin(nan,0.5)=~f~%" (fmax 0.5 *gw-nan*) (fmax *gw-nan* 0.5) (fmin 0.5 *gw-nan*) (fmin *gw-nan* 0.5))' >&3
sleep 3

# ---- (3) Producer NaN test: normalize zero/tiny into-wall vector then dot ----
echo "[gw] touch-angle producer NaN test"
echo '(define *gw-norm* (new (quote global) (quote vector)))' >&3
echo '(set-vector! *gw-norm* 1.0 0.0 0.0 0.0)' >&3   # a wall normal (unit +x)
# zero arg2 (Jak fully stopped against wall — slow-slide terminal)
echo '(let ((a2 (new (quote stack) (quote vector)))) (set-vector! a2 0.0 0.0 0.0 0.0) (let ((ta (fmax 0.0 (vector-dot *gw-norm* (vector-normalize! (vector-negate! (new-stack-vector0) a2) 1.0))))) (format 0 "GWPROD arg2=ZERO touch-angle=~f bits=~X (>=0.7? ~A)~%" ta (the-as int ta) (>= 0.7 ta))))' >&3
# tiny arg2 (barely moving into wall)
echo '(let ((a2 (new (quote stack) (quote vector)))) (set-vector! a2 0.0001 0.0 0.0 0.0) (let ((ta (fmax 0.0 (vector-dot *gw-norm* (vector-normalize! (vector-negate! (new-stack-vector0) a2) 1.0))))) (format 0 "GWPROD arg2=TINY touch-angle=~f bits=~X (>=0.7? ~A)~%" ta (the-as int ta) (>= 0.7 ta))))' >&3
# normal arg2 (moving solidly into wall)
echo '(let ((a2 (new (quote stack) (quote vector)))) (set-vector! a2 4096.0 0.0 0.0 0.0) (let ((ta (fmax 0.0 (vector-dot *gw-norm* (vector-normalize! (vector-negate! (new-stack-vector0) a2) 1.0))))) (format 0 "GWPROD arg2=NORM touch-angle=~f bits=~X (>=0.7? ~A)~%" ta (the-as int ta) (>= 0.7 ta))))' >&3
sleep 3

# ---- (4) warp + read live target collision state ----
echo "[gw] warping to game-start (training/Geyser Rock)"
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
echo "[gw] settling 16s..."
sleep 16
for i in 1 2 3 4 5 6; do
  echo '(when *target* (format 0 "GWLIVE st=~A sa=~f pa=~f ta=~f f60=~f f61=~f status=~X tx=~f ty=~f tz=~f~%" (-> *target* next-state name) (-> *target* control surface-angle) (-> *target* control poly-angle) (-> *target* control touch-angle) (-> *target* control unknown-float60) (-> *target* control unknown-float61) (-> *target* control status) (-> *target* control trans x) (-> *target* control trans y) (-> *target* control trans z)))' >&3
  sleep 1
done
sleep 1

exec 3>&-
sleep 3

{
  echo "==================== Gcollision-wallslide x86 probe ===================="
  echo "---- (1) field offsets ----"; grep -a "GWOFF" "$GKLOG" || echo "(none)"
  echo "---- (2) NaN truth table ----"; grep -a "GWNAN" "$GKLOG" || echo "(none)"
  echo "---- (3) touch-angle producer ----"; grep -a "GWPROD" "$GKLOG" || echo "(none)"
  echo "---- (4) live target state ----"; grep -a "GWLIVE" "$GKLOG" || echo "(none)"
  echo "---- goalc errors (first 12) ----"
  grep -aiE "Compilation Error|does not exist|not connected|Connected to OpenGOAL|listen to target" "$GCLOG" | head -12 || true
} | tee "$OUTLOG"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
echo "[gw] done -> $OUTLOG"
