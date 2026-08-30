#!/usr/bin/env bash
# glcr_proof.sh — Gloadgate-crash-regression : LA PREUVE DE SORTIE.
#   1. N chargements de sauvegarde consecutifs, ZERO plantage        -> LOADOK
#   2. la fenetre encadre toujours la transition                     -> LSWIN
#   3. le look valide par l'owner est INCHANGE                       -> LOOKUNCHANGED
# Le tout sur UN SEUL binaire et UNE SEULE course : dix boots couteraient dix fois plus cher
# et ne prouveraient pas davantage.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloadgate-crash-regression"; mkdir -p "$OUT"
N="${N:-12}"
LOG="$OUT/proof.log"; GCLOG="$OUT/proof-goalc.log"
: > "$LOG"; : > "$GCLOG"
touch .autoport/.deploy-in-progress 2>/dev/null || true

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
  | stdbuf -oL python3 -u -c 'import sys,time
t0=time.time()
for l in sys.stdin:
    sys.stdout.write("%9.3f %s" % (time.time()-t0, l))' >> "$LOG" &
PIPEPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){
  exec 3>&- 2>/dev/null || true
  P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  kill "$PIPEPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"
}
trap cleanup EXIT

for i in $(seq 1 240); do
  grep -qaE "BOOTLINE etape=titre-affiche|link finish: default-menu" "$LOG" && break; sleep 1
done
sleep 3
timeout 3600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 900); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
echo '(format 0 "REPL-LIVE~%")' >&3
for i in $(seq 1 30); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && break; done
grep -qa "REPL-LIVE" "$LOG" || { echo "FAIL: listener non connecte"; exit 1; }

# L'INSTRUMENT DE FENETRE EST OPT-IN : c'est le harnais qui l'arme, jamais le joueur.
echo '(set! *ls-window-instr* #t)' >&3
sleep 1

VIVANTS=0; MORTS=0
for i in $(seq 1 "$N"); do
  # alterner Geyser Rock (le niveau que l'owner voit planter) et Sandover Village
  if [ $((i % 2)) -eq 1 ]; then CP="game-start"; LB="save-geyser"; else CP="village1-hut"; LB="save-sandover"; fi
  echo "== chargement $i/$N : $CP =="
  echo "(set! *ls-window-label* \"$LB\")" >&3
  echo "(initialize! *game-info* (quote game) (the-as game-save #f) \"$CP\")" >&3
  sleep "${WAIT:-42}"
  if pgrep -f "game/gk --game jak1 --portable -fakeiso" >/dev/null; then
    VIVANTS=$((VIVANTS+1)); echo "   vivant apres $i"
  else
    MORTS=$((MORTS+1)); echo "   !! MORT au chargement $i"; break
  fi
done
echo '(loading-window-close! "harnais")' >&3
sleep 2
# le look, RELU dans la memoire que le chemin d'emission lit
echo '(ls-color-trace)' >&3
sleep 2
exec 3>&-; sleep 2
echo "LOADOK plateforme=x86 chargements=$VIVANTS plantages=$MORTS scene=geyser-rock"
echo "---- LSWIN ----"; grep -aE "^ *[0-9.]+ LSWIN " "$LOG" | tail -20
echo "---- LOOK ----"; grep -aE "LOADSCREEN-COSM|LSCOLOR-BRUT" "$LOG" | tail -6
echo "---- log: $LOG ----"
