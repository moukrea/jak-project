#!/usr/bin/env bash
# hd_x86_proof.sh — DESKTOP runtime proof of the HD anim-retarget companion (Grecharged-hd-models3 M1).
# Boots the freshly built HD-flagged gk + CGOs, warps to NEW GAME (spawns *target*), enables the
# recharged-enhanced-models? setting (so (update *pc-settings*)->maybe-spawn-jak-hd! spawns the jak-hd
# companion), then dumps OBJECTIVE numbers over the goalc listener:
#   - did the companion spawn (*jak-hd-process*) and load its art (skeleton bone count > 0)
#   - for sample mapped joints k: the HD bone WORLD position vs the eichar bone it is retargeted from
#     (must be FINITE + CO-LOCATED on the same body — exploded/NaN/km-away => wrong matrix order)
# Adapted from .autoport/bsf_x86_menu_dump.sh (proven boot+listener recipe). No screenshots; numbers only.
set -uo pipefail
REPO="$(git rev-parse --show-toplevel)"; cd "$REPO"
GK="${GK:-$REPO/build/game/gk}"; GOALC="${GOALC:-$REPO/build/goalc/goalc}"
ISO="${ISO:-$REPO/out/jak1/iso}"
OUT=.autoport/reports/hd-models3; mkdir -p "$OUT"
DUMPLOG="$OUT/hd-x86-proof.txt"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
echo "[hd-x86] gk=$GK iso=$ISO" | tee "$DUMPLOG"
echo "[hd-x86] HD asset present: $(ls -la "$ISO/jak-hd-ag.go" 2>/dev/null || echo MISSING)" | tee -a "$DUMPLOG"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 200); do kill -0 "$GKPID" 2>/dev/null || { echo "[hd-x86] gk exited during boot"; tail -20 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo-loop" "$GKLOG" && { echo "[hd-x86] title attract ~${i}s"; break; }; sleep 1; done
grep -qE "link finish: logo-loop" "$GKLOG" || { echo "[hd-x86] never reached logo-loop"; tail -25 "$GKLOG"; exit 1; }
sleep 6

timeout 500 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[hd-x86] build-game sent; waiting up to 180s..."
for i in $(seq 1 180); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "[hd-x86] build-game done ~${i}s"; break; }; done
sleep 4

echo "[hd-x86] warping to NEW GAME continue 'game-start' (spawns *target*)"
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
# wait for *target* to exist
for i in $(seq 1 60); do
  echo '(when *target* (format 0 "HD-TGT-READY tx=~f~%" (-> *target* control trans x)))' >&3
  sleep 2
  grep -qa "HD-TGT-READY" "$GKLOG" "$GCLOG" 2>/dev/null && { echo "[hd-x86] *target* ready ~$((i*2))s"; break; }
done

echo "[hd-x86] enabling recharged-enhanced-models? (triggers maybe-spawn-jak-hd!)"
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
sleep 6   # let several (update *pc-settings*) frames run so the companion spawns + loads art + fills bones

# OBJECTIVE dump: spawn state, art load, sample mapped-joint HD world pos vs the eichar joint it tracks.
DUMP='(let ((pp *jak-hd-process*))
  (format 0 "HD-SPAWN handle-nonzero=~A~%" (and pp (nonzero? (the-as int (-> pp 0)))))
  (when (and pp (nonzero? (the-as int (-> pp 0))))
    (let ((hp (the-as process-drawable (-> pp 0))))
      (format 0 "HD-PROC type=~A bones=~D jgeo-joints=~D tgt=~A~%"
              (-> hp type)
              (if (nonzero? (-> hp draw skeleton)) (-> hp draw skeleton length) -1)
              (if (nonzero? (-> hp draw jgeo)) (-> hp draw jgeo length) -1)
              (and *target* #t))
      (when (and *target* (nonzero? (-> hp draw skeleton)))
        (let ((ks (new (quote static) (quote array) int32 6 3 10 20 30 45 60)))
          (dotimes (ii 6)
            (let* ((k (-> ks ii)) (e (-> *jak-hd->eichar-joint* k)))
              (let ((hpos (-> hp draw skeleton bones (+ k 1) transform vector 3))
                    (epos (-> *target* draw skeleton bones (+ e 1) transform vector 3)))
                (format 0 "HD-BONE k=~D e=~D hd=(~f ~f ~f) ei=(~f ~f ~f)~%"
                        k e (-> hpos x) (-> hpos y) (-> hpos z) (-> epos x) (-> epos y) (-> epos z))))))))))'
for try in 1 2 3; do
  echo "$DUMP" >&3
  sleep 5
  { grep -ha "HD-SPAWN\|HD-PROC\|HD-BONE" "$GKLOG" "$GCLOG" 2>/dev/null || true; } > "$OUT/.hd_lines.tmp"
  [ -s "$OUT/.hd_lines.tmp" ] && break
  sleep 3
done
echo "=== HD PROOF DUMP ===" | tee -a "$DUMPLOG"
grep -ha "HD-SPAWN\|HD-PROC\|HD-BONE\|HD-TGT-READY" "$GKLOG" "$GCLOG" 2>/dev/null | sort -u | tee -a "$DUMPLOG"
echo "=== any art-error / crash in gk log ===" | tee -a "$DUMPLOG"
grep -aiE "art-error|art-group|jak-highres|crash|segfault|signal|MISSING|not found|do-joint" "$GKLOG" 2>/dev/null | tail -15 | tee -a "$DUMPLOG"
grep -qa "HD-SPAWN" "$DUMPLOG" || { echo "[hd-x86] DUMP FAILED (no HD-SPAWN line)"; tail -30 "$GCLOG"; exit 2; }
echo "[hd-x86] proof dump complete -> $DUMPLOG"
