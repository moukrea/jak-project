#!/usr/bin/env bash
# glcr_repro.sh — Gloadgate-crash-regression : REPRODUIRE LE PLANTAGE, sous gdb, sur x86.
#
# Ordre impose par l'owner (complement du 2026-08-30) : le chemin pause -> OPTIONS d'abord,
# parce qu'il ne charge RIEN et se joue en quelques secondes ; il discrimine immediatement
# entre « la barriere de chargement » et « quelque chose que notre lot laisse derriere lui ».
#
# gk tourne SOUS gdb : sur signal fatal, on obtient le signal, le fil fautif et la pile de
# TOUS les fils. Un resume ne suffit pas (mandat).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloadgate-crash-regression"; mkdir -p "$OUT"
SCN="${1:-options}"          # options | geyser | mixte
TAG="${2:-$SCN}"
LOG="$OUT/repro-$TAG.log"; GCLOG="$OUT/repro-$TAG-goalc.log"
: > "$LOG"; : > "$GCLOG"

# rafraichir le verrou de livraison pour que l'auto-constructeur ne reecrive pas out/jak1/iso
touch .autoport/.deploy-in-progress 2>/dev/null || true

export OG_FIXED_TICK="${OG_FIXED_TICK:-1}"
gdb -batch -q -nx \
    -ex 'set pagination off' -ex 'set confirm off' \
    -ex 'handle SIGPIPE nostop noprint pass' \
    -ex 'run' \
    -ex 'printf "\n=== CRASHTRACE-BEGIN ===\n"' \
    -ex 'info program' \
    -ex 'info threads' \
    -ex 'thread apply all bt' \
    -ex 'printf "=== CRASHTRACE-END ===\n"' \
    --args "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
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
  G=$(pgrep -n -f "gdb -batch -q -nx" || true); [ -n "$G" ] && kill "$G" 2>/dev/null
  kill "$PIPEPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"
}
trap cleanup EXIT

echo "== scenario=$SCN =="
echo "== attente de l'ecran titre =="
for i in $(seq 1 240); do
  grep -qaE "BOOTLINE etape=titre-affiche|link finish: default-menu" "$LOG" && { echo "  titre a ~${i}s"; break; }
  sleep 1
done
sleep 3
timeout 2400 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 900); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }; done
sleep 3
# VIVACITE : sans listener connecte, goalc compile avec `allow_emit=#f` et jette tout EN SILENCE.
echo '(format 0 "REPL-LIVE~%")' >&3
for i in $(seq 1 30); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && break; done
grep -qa "REPL-LIVE" "$LOG" || { echo "FAIL: listener goalc non connecte"; exit 1; }
echo "  REPL vivant"

# ---- le corps du scenario est fourni par un fichier de commandes ----
CMDS="${CMDS:-}"
if [ -n "$CMDS" ] && [ -f "$CMDS" ]; then
  while IFS= read -r line; do
    case "$line" in
      "#SLEEP "*) s="${line#\#SLEEP }"; echo "  ... sleep $s"; sleep "$s" ;;
      "#ECHO "*)  echo "  == ${line#\#ECHO } ==" ;;
      "#DEAD")    if ! pgrep -f "game/gk --game jak1 --portable -fakeiso" >/dev/null; then
                    echo "  !! gk MORT — plantage reproduit"; break; fi ;;
      ""|"#"*)    : ;;
      *)          echo "$line" >&3 ;;
    esac
  done < "$CMDS"
fi

exec 3>&-
sleep 3
echo "---- gk vivant ? ----"
if pgrep -f "game/gk --game jak1 --portable -fakeiso" >/dev/null; then echo "GK-VIVANT=1"; else echo "GK-VIVANT=0 (mort)"; fi
echo "---- log: $LOG ----"
