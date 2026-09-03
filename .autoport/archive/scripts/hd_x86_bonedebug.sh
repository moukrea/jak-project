#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
OUT=.autoport/reports/hd-models3; mkdir -p "$OUT"; DUMP="$OUT/bone-debug.txt"; : > "$DUMP"
GKLOG="$OUT/.bd_gk.log"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
"$GK" --game jak1 --portable -fakeiso --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 200); do kill -0 "$GKPID" 2>/dev/null || { echo "gk died"|tee -a "$DUMP"; tail -20 "$GKLOG">>"$DUMP"; exit 1; }; grep -qE "link finish: logo-loop" "$GKLOG" && break; sleep 1; done
sleep 6
timeout 400 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!; exec 3>"$FIFO"
echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
for i in $(seq 1 40); do echo '(when *target* (format 0 "TGT-READY~%"))' >&3; sleep 2; grep -qa TGT-READY "$GKLOG" "$GCLOG" 2>/dev/null && break; done
sleep 8   # let the companion spawn + run many frames (its [JAK-HD] f60/f150 dump fires from its OWN :post read)
# LISTENER probe: companion alive? + companion's filled bone (via listener) + target bone (via listener)
P='(begin
  (if (and *jak-hd-process* (nonzero? (-> *jak-hd-process* 0)))
    (let ((h (-> *jak-hd-process* 0)))
      (format 0 "PROBE hd-alive skel=~D~%" (if (nonzero? (-> h draw skeleton)) (-> h draw skeleton length) -1))
      (format 0 "PROBE hd-bone4(listener)=(~f ~f ~f)~%" (-> h draw skeleton bones 4 transform vector 3 x) (-> h draw skeleton bones 4 transform vector 3 y) (-> h draw skeleton bones 4 transform vector 3 z)))
    (format 0 "PROBE hd-NONE~%")))'
for t in 1 2 3; do echo "$P" >&3; sleep 4; grep -qa "PROBE hd-" "$GKLOG" "$GCLOG" && break; done
sleep 2
echo "=== companion's OWN :post read ([JAK-HD] bone3 = what fill saw) ===" | tee -a "$DUMP"
grep -ha "\[JAK-HD\]" "$GKLOG" 2>/dev/null | tail -6 | tee -a "$DUMP"
echo "=== listener probes ===" | tee -a "$DUMP"
grep -ha "PROBE" "$GKLOG" "$GCLOG" 2>/dev/null | grep -v "format 0" | sort -u | tee -a "$DUMP"
