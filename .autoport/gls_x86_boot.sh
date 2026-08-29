#!/usr/bin/env bash
# gls_x86_boot.sh — Gloading-screen : CHRONOLOGIE DU DEMARRAGE JUSQU'A L'ECRAN TITRE
# et RECENSEMENT DES FRAMES NOIRES, sur x86.
#
# Pourquoi un horodatage EXTERNE : le jeu n'imprime pas d'heure, et `(current-time)` est une
# horloge de frames, pas une horloge murale. Le temps que l'owner ressent est du temps MUR.
# `stdbuf -oL` des deux cotes : un stdout redirige est bufferise par BLOCS, et une capture
# tronquee ressemble exactement a un evenement qui ne s'est pas produit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; mkdir -p "$OUT"
TAG="${1:-avant}"
MAXWAIT="${2:-120}"
LOG="$OUT/boot-$TAG.log"
[ -x "$GK" ] || { echo "FAIL: $GK manquant"; exit 1; }
: > "$LOG"
echo "== demarrage x86, tag=$TAG =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
  | python3 -u -c 'import sys,time
t0=time.time()
for l in sys.stdin:
    sys.stdout.write("%9.3f %s" % (time.time()-t0, l))' \
  >> "$LOG" &
PIPEPID=$!
GKPID=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true)
for i in $(seq 1 "$MAXWAIT"); do
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre affiche apres ~${i}s"; break; }
  sleep 1
done
sleep 2
# tuer par PID exact, jamais par motif large
GKPID=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true)
[ -n "$GKPID" ] && kill "$GKPID" 2>/dev/null
sleep 1
kill "$PIPEPID" 2>/dev/null
wait 2>/dev/null
echo "---- CHRONOLOGIE ----"
grep -aE "BOOTLINE|LOADGATE|LOADSCREEN-CONT" "$LOG"
echo "---- RECENSEMENT DES FRAMES NOIRES ----"
grep -a "BLACKCENSUS" "$LOG"
echo "---- log: $LOG ----"
