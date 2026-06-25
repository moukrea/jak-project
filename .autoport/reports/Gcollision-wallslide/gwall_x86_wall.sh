#!/usr/bin/env bash
# gwall_x86_wall.sh — x86 oracle at the DEVICE wall-wedge positions.
# Teleports Jak to the exact device-captured stuck spots, observes whether x86
# also gets wedged (frozen) or recovers, and replicates the can-exit-duck? head
# probe (fill-and-probe-using-spheres) to compare the CROUCH verdict. The shared
# GWALL hook (OG_GWALL_LOG=1) also logs x86's per-frame collision state.
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"; export OG_GWALL_LOG=1; cd "$REPO"; mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"; : > "$GKLOG"; : > "$GCLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 90); do kill -0 "$GKPID" 2>/dev/null || { echo "gk died"; tail -20 "$GKLOG"; exit 1; }; grep -qE "link finish: logo($|-)" "$GKLOG" && break; sleep 1; done
sleep 3
timeout 700 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"; echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && break; done
sleep 4

# define a probe helper that replicates can-exit-duck? at an arbitrary position
cat >&3 <<'LISP'
(defun gw-probe ((px float) (py float) (pz float))
  (set! (-> *target* control trans x) px)
  (set! (-> *target* control trans y) py)
  (set! (-> *target* control trans z) pz)
  (let ((gp-0 (new 'stack-no-clear 'collide-using-spheres-params))
        (s5-0 (new 'stack-no-clear 'inline-array 'sphere 2)))
    (dotimes (s4-0 2) ((method-of-type sphere new) (the-as symbol (-> s5-0 s4-0)) sphere))
    (set! (-> s5-0 0 quad) (-> *target* control trans quad))
    (set! (-> s5-0 0 y) (+ 5734.4 (-> *TARGET-bank* body-radius) (-> s5-0 0 y)))
    (set! (-> s5-0 0 w) (-> *TARGET-bank* body-radius))
    (set! (-> s5-0 1 quad) (-> *target* control trans quad))
    (set! (-> s5-0 1 y) (+ 2867.2 (-> *TARGET-bank* body-radius) (-> s5-0 1 y)))
    (set! (-> s5-0 1 w) (-> *TARGET-bank* body-radius))
    (set! (-> gp-0 spheres) s5-0)
    (set! (-> gp-0 num-spheres) (the-as uint 2))
    (set! (-> gp-0 collide-with) (-> *target* control root-prim collide-with))
    (set! (-> gp-0 proc) #f)
    (set! (-> gp-0 ignore-pat) (new 'static 'pat-surface :noentity #x1))
    (set! (-> gp-0 solid-only) #t)
    (let ((r (fill-and-probe-using-spheres *collide-cache* gp-0)))
      (format 0 "GWPROBE pos=(~f ~f ~f) blocked=~A~%" px py pz r))))
LISP
sleep 2

echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
sleep 16
# confirm state-name resolves + offsets
echo '(when (-> *target* next-state) (format 0 "GWLNAME st=~A nameoff=~D~%" (-> *target* next-state name) (- (the-as int (&-> (-> *target* next-state) name)) (the-as int (-> *target* next-state)))))' >&3
sleep 1

# === Test A: frozen-wedge position (device f=4504-7656) ===
echo '(set! (-> *target* control transv quad) (the-as uint128 0))' >&3
echo '(gw-probe -5353232.0 23424.0 4087960.0)' >&3
sleep 1
# observe whether x86 stays wedged after teleport (poll state + trans 6x@0.7s)
for i in 1 2 3 4 5 6; do
  echo '(when *target* (format 0 "GWWEDGE st=~A sa=~f ta=~f tx=~f ty=~f tz=~f~%" (-> *target* next-state name) (-> *target* control surface-angle) (-> *target* control touch-angle) (-> *target* control trans x) (-> *target* control trans y) (-> *target* control trans z)))' >&3
  sleep 1
done

# === Test B: moving-slide wall position (device f=4520) ===
echo '(gw-probe -5353231.5 23423.9 4087960.5)' >&3
sleep 1

# === Test C: settled wall-base position (device settle) ===
echo '(gw-probe -5386376.0 24615.8 4064680.8)' >&3
sleep 2

exec 3>&-; sleep 3
{
  echo "==== Gcollision-wallslide x86 wall oracle ===="
  echo "---- state-name resolution ----"; grep -a "GWLNAME" "$GKLOG" || echo "(none)"
  echo "---- can-exit-duck probe verdicts (blocked=#f -> CAN stand) ----"; grep -a "GWPROBE" "$GKLOG" || echo "(none)"
  echo "---- x86 behavior after teleport to frozen-wedge ----"; grep -a "GWWEDGE" "$GKLOG" || echo "(none)"
  echo "---- x86 GWALL stream sample (last 30) ----"; grep -a "GWALL" "$GKLOG" | tail -30 || echo "(none)"
  echo "---- goalc errors ----"; grep -aiE "Compilation Error|does not exist" "$GCLOG" | head -10 || true
} | tee "$OUTLOG"
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
