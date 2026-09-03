#!/usr/bin/env bash
# Gjak1-crate-collision-2 — VALIDATION DU DETECTEUR PASSIF (x86, fumee + controle positif)
#
# Ce script ne mesure PAS le defaut de l'owner : il verifie que l'instrument existe,
# qu'il est SILENCIEUX quand il n'y a rien a voir (ligne de base), et qu'il TIRE quand
# on met le joueur a l'interieur d'une caisse. Sans ces deux points un zero ne vaut rien.
# Le verrou de livraison est deja tenu par le manager (PID vivant).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
TAG="${1:-smoke}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gjak1-crate-collision/runs"; mkdir -p "$OUT"
LOG="$OUT/gk2-$TAG.log"; GCLOG="$OUT/goalc2-$TAG.log"; DRV="$OUT/drv2-$TAG.log"
exec > >(tee "$DRV") 2>&1
: > "$LOG"; : > "$GCLOG"
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null||true; [ -n "${GCPID:-}" ]&&kill "$GCPID" 2>/dev/null
           [ -n "${GKPID:-}" ]&&kill "$GKPID" 2>/dev/null; sleep 1
           [ -n "${GKPID:-}" ]&&kill -9 "$GKPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"; return 0; }
trap cleanup EXIT

echo "== boot gk =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKPID=$!
ok=0
for i in $(seq 1 180); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk mort au boot"; tail -30 "$LOG"; exit 1; }
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; ok=1; break; }
  sleep 1
done
[ "$ok" = 1 ] || { echo "FAIL: pas d'ecran titre"; tail -20 "$LOG"; exit 1; }
sleep 3

echo "== goalc (lt) + (build-game) =="
timeout 1500 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3; echo '(build-game)' >&3
bg=0
for i in $(seq 1 420); do sleep 1
  grep -qaiE "Successfully built all|Build Successful" "$GCLOG" && { echo "  build-game a ~${i}s"; bg=1; break; }
  grep -qa "Compilation Error\|Reader error" "$GCLOG" && { echo "FAIL compilation"; sed 's/\x1b\[[0-9;]*m//g' "$GCLOG"|grep -A12 'Compilation Error\|Reader error'|head -30; exit 1; }
done
[ "$bg" = 1 ] || { echo "FAIL: build-game"; exit 1; }
sleep 4

echo "== NOUVELLE PARTIE (Geyser Rock / training) =="
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep 45
echo "(set-frame-rate! *pc-settings* ${FPS:-10} #t)" >&3; sleep 1
echo '(set! *gjcc-mode* 3)' >&3; sleep 2

echo "== LIGNE DE BASE : 25 s sans rien faire, le detecteur doit rester MUET =="
sleep 25
BASE=$(grep -ac 'GJCC-THRU' "$LOG")
echo "  GJCC-THRU pendant la ligne de base : $BASE  (attendu 0)"

echo "== CONTROLE POSITIF : on POSE le joueur A L'INTERIEUR de crate-2957 (aid 17629) =="
# waypoint 0 : x=-4729791.5 z=4147762.0 cy=86016.0 -> centre de la caisse a cy+~4000
for i in $(seq 1 14); do
  echo '(when *target* (move-to-point! (-> *target* control) (new (quote static) (quote vector) :x -4729791.5 :y 88016.0 :z 4147762.0 :w 1.0)) (set! (-> *target* control transv quad) (the-as uint128 0)))' >&3
  sleep 0.35
done
sleep 3
echo '(gjcc-scan 777)' >&3
sleep 3
exec 3>&-; sleep 2

echo "== RESUME $TAG =="
grep -a 'GJCC-MODE' "$LOG" | tail -2
grep -a 'GJCC-RUN'  "$LOG" | tail -3
echo "  GJCC-THRU total : $(grep -ac 'GJCC-THRU' "$LOG")   (base=$BASE)"
grep -a 'GJCC-THRU' "$LOG" | head -3
grep -a 'GJCC-CC '  "$LOG" | tail -2
echo "GJCC2-SMOKE-DONE tag=$TAG lignes=$(wc -l < "$LOG")"
