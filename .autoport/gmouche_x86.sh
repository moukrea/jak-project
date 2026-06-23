#!/usr/bin/env bash
# gmouche_x86.sh — Gcrash-mouche x86-first no-crash oracle.
# Proves the Jak1 buzzer (scout-fly) pickup fly-to-HUD effect does NOT crash on
# desktop x86, so the on-device crash is arm64-specific. Boots desktop gk to the
# title attract, connects goalc (lt)+(build-game), warps to NEW-GAME "game-start"
# (level 'training = Geyser Rock), then evals the EXACT buzzer pickup FX form from
# collectables.gc:1272-1274 three times and proves the kernel keeps ticking.
# Non-invasive: no edits to tracked source. Modeled on f1_x86_dump.sh.
#
# Env: REPO (root), GK (rel), GOALC (rel), ISO (rel/abs), OUTLOG (abs)
set -uo pipefail
REPO="${REPO:?}"; GK="${GK:?}"; GOALC="${GOALC:?}"; ISO="${ISO:?}"; OUTLOG="${OUTLOG:?}"
export DISPLAY="${DISPLAY:-:0}"
cd "$REPO"
mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[mouche] repo=$REPO gk=$GK gklog=$GKLOG"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

# 1) boot to link finish: logo
for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[mouche] gk exited during boot"; tail -30 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[mouche] booted ~${i}s"; break; }
  sleep 1
done
sleep 3

# 2) connect goalc, (lt) + (build-game)
timeout 600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[mouche] build-game sent; waiting up to 150s for symbol intern..."
for i in $(seq 1 150); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[mouche] build-game done ~${i}s"; break; }
done
sleep 4

# 3) warp to NEW GAME continue 'game-start' (Geyser Rock / training)
echo "[mouche] warping to NEW GAME continue 'game-start' (Geyser Rock / training)"
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
echo "[mouche] waiting 15s for training to load + *target* to settle..."
sleep 15

# verify *target* alive
echo '(if *target* (format 0 "MOUCHE-TGT ~A tx=~f~%" (-> *target* type) (-> *target* control trans x)) (format 0 "MOUCHE-TGT <target-is-#f>~%"))' >&3
sleep 2

# 4) sanity: buzzer art loaded? (guard against unbound *buzzer-sg*)
echo '(if *buzzer-sg* (format 0 "MOUCHE-SG ~A type=~A~%" (-> *buzzer-sg* art-group-name) (-> *buzzer-sg* type)) (format 0 "MOUCHE-SG <buzzer-sg-not-loaded>~%"))' >&3
sleep 3

# 5) KEY TEST — eval EXACT buzzer pickup FX form (collectables.gc:1272-1274) x3
BUZZFX='(let ((v1-18 (manipy-spawn (-> *target* root trans) #f *buzzer-sg* #f :to *entity-pool*))) (send-event (ppointer->process v1-18) (quote become-hud-object) (ppointer->process (-> *hud-parts* buzzers))))'
for n in 1 2 3; do
  echo "[mouche] buzzer-FX eval #$n"
  echo "$BUZZFX" >&3
  sleep 1
  echo "(format 0 \"MOUCHE-ALIVE frame=~D~%\" (-> *display* base-frame-counter))" >&3
  sleep 3
done

# 6) settle + finalize
exec 3>&-
sleep 5
ALIVE_AT_END=0
kill -0 "$GKPID" 2>/dev/null && ALIVE_AT_END=1
sleep 1

{
  echo "==================== Gcrash-mouche x86 no-crash oracle ===================="
  echo "[cmd] gk:    $GK --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data $ISO -- -boot -debug-mem"
  echo "[cmd] goalc: $GOALC --game jak1 --proj-path . --iso-path $ISO"
  echo "[form] $BUZZFX"
  echo
  echo "---- *target* / buzzer-art probes (from gk log) ----"
  grep -a "MOUCHE-TGT" "$GKLOG" 2>/dev/null || echo "(no MOUCHE-TGT line)"
  grep -a "MOUCHE-SG"  "$GKLOG" 2>/dev/null || echo "(no MOUCHE-SG line)"
  echo
  echo "---- MOUCHE-ALIVE (kernel-tick proof, one per buzzer FX) ----"
  grep -a "MOUCHE-ALIVE" "$GKLOG" 2>/dev/null || echo "(no MOUCHE-ALIVE line)"
  NALIVE=$(grep -ac "MOUCHE-ALIVE" "$GKLOG" 2>/dev/null || echo 0)
  echo "MOUCHE-ALIVE count = $NALIVE"
  echo
  echo "---- goalc compile errors on the buzzer FX form (if any) ----"
  grep -aiE "Compilation Error|does not exist|Unrecognized|cannot|failed to|no such|Could not" "$GCLOG" 2>/dev/null | tail -20 || echo "(none)"
  echo
  echo "---- crash markers in gk log ----"
  grep -aiE "Segmentation|SIGSEGV|terminate|Assertion|crash|abort|signal [0-9]" "$GKLOG" 2>/dev/null | tail -20 || echo "(none)"
  echo
  echo "---- last 60 lines of gk log ----"
  tail -60 "$GKLOG"
  echo
  echo "==================== VERDICT ===================="
  if [ "$ALIVE_AT_END" -eq 1 ]; then
    echo "MOUCHE-X86: NO CRASH (gk alive after $NALIVE buzzer-FX kernel-tick proofs)"
  else
    echo "MOUCHE-X86: CRASHED (gk process dead at end of run; $NALIVE MOUCHE-ALIVE lines captured)"
  fi
  echo "MOUCHE-SG = $(grep -a 'MOUCHE-SG' "$GKLOG" 2>/dev/null | tail -1 || echo '?')"
  echo "MOUCHE-TGT = $(grep -a 'MOUCHE-TGT' "$GKLOG" 2>/dev/null | tail -1 || echo '?')"
} | tee "$OUTLOG"

# preserve full logs alongside the report
cp -f "$GKLOG" "${OUTLOG%.log}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.log}.goalc.log" 2>/dev/null || true
echo "[mouche] full gk log:    ${OUTLOG%.log}.gk.log"
echo "[mouche] full goalc log: ${OUTLOG%.log}.goalc.log"

[ "$ALIVE_AT_END" -eq 1 ]
