#!/usr/bin/env bash
# Gjak1-crate-collision-2 — LE TEST CAUSAL : ON LACHE LE JOUEUR SUR LES CAISSES DONT LA
# SPHERE DE COLLISION EST NaN, ET SUR CELLES-LA SEULEMENT.
#
# Le banc du cycle precedent lachait le joueur sur LES 31 caisses, dont l'immense majorite
# a une sphere saine : ses comptes noyaient le defaut. Ici on identifie d'abord les caisses
# dont `wd=NaN`, PUIS on les eprouve — c'est le test qui relie la cause a l'effet.
#
# Verdict par caisse (`gjcc-land`) : `dy` proche de 8368 = le joueur s'est arrete DESSUS,
# la caisse est solide. `dy` proche de 0 = il est descendu jusqu'a sa base, il l'a TRAVERSEE.
#
# usage : gjcc2_x86_causal.sh <tag> <mode> [aids separes par des virgules]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
TAG="${1:-c1}"; MODE="${2:-34}"; AIDS="${3:-}"
GK=build-x86/game/gk; GOALC=build-x86/goalc/goalc; ISO=out/jak1/iso
OUT=.autoport/reports/Gjak1-crate-collision/runs; mkdir -p "$OUT"
LOG="$OUT/gk2-$TAG.log"; GCLOG="$OUT/goalc2-$TAG.log"; DRV="$OUT/drv2-$TAG.log"
LOCK=.autoport/.deploy-in-progress
exec > >(tee "$DRV") 2>&1
: > "$LOG"; : > "$GCLOG"
FIFO=$(mktemp -u); mkfifo "$FIFO"
_own=0
cleanup(){ exec 3>&- 2>/dev/null||true; [ -n "${GCPID:-}" ]&&kill "$GCPID" 2>/dev/null
           [ -n "${GKPID:-}" ]&&kill "$GKPID" 2>/dev/null; sleep 1
           [ -n "${GKPID:-}" ]&&kill -9 "$GKPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"
           [ "$_own" = 1 ] && rm -f "$LOCK"; return 0; }
trap cleanup EXIT
_stale(){ [ -f "$1" ] || return 0; local p; p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$1"|head -1)
          [ -n "$p" ] || return 0; kill -0 "$p" 2>/dev/null && return 1 || return 0; }
for i in $(seq 1 60); do
  _stale "$LOCK" && { printf 'gjcc2_causal pid=%s tag=%s started=%s\n' "$$" "$TAG" "$(date -Is)" > "$LOCK"; _own=1; break; }
  echo "verrou tenu : $(cat "$LOCK") — attente $i/60"; sleep 10
done
[ "$_own" = 1 ] || { echo "FAIL: verrou jamais libere"; exit 1; }

echo "== boot gk =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKPID=$!
for i in $(seq 1 180); do kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk mort"; tail -20 "$LOG"; exit 1; }
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; break; }; sleep 1; done
sleep 3
timeout 1500 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"; echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 420); do sleep 1; grep -qaiE "Successfully built all|Build Successful" "$GCLOG" && { echo "  build-game a ~${i}s"; break; }
  grep -qa "Compilation Error\|Reader error" "$GCLOG" && { echo "FAIL compilation"; exit 1; }; done
sleep 4
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep 45
echo "(set-frame-rate! *pc-settings* 10 #t)" >&3; sleep 1
echo "(set! *gjcc-mode* $MODE)" >&3; sleep 2
grep -a 'GJCC-MODE' "$LOG" | tail -1

if [ -z "$AIDS" ]; then
  echo "== BRASSAGE : on visite quelques points pour faire naitre et mourir des caisses =="
  n=0
  while read -r idx x y z cy aid nm; do
    n=$((n+1))
    echo "(when *target* (move-to-point! (-> *target* control) (new (quote static) (quote vector) :x $x :y $y :z $z :w 1.0)))" >&3
    sleep 1.2
    # on recense SOUVENT : une sphere perdue se voit sur la caisse qui vient de naitre
    # hors champ, et le recensement doit tomber pendant qu'elle est encore vivante.
    if [ $((n % 4)) -eq 0 ]; then echo "(gjcc-scan $((100+n)))" >&3; sleep 1.6; fi
  done < .autoport/gjcc_waypoints.txt
  echo '(gjcc-scan 5)' >&3; sleep 4
  AIDS=$(grep -a 'GJCC-CRATE ' "$LOG" | grep 'wd=NaN' | sed 's/.*aid=\([0-9]*\).*/\1/' | sort -u | head -4 | paste -sd,)
  echo "  caisses a sphere NaN reperees : ${AIDS:-aucune}"
fi
[ -n "$AIDS" ] || { echo "AUCUNE CAISSE NaN — rien a eprouver (attendu quand la garde est active)"; exec 3>&-; sleep 2; echo "GJCC2-CAUSAL-DONE tag=$TAG mode=$MODE aids= verdicts=0"; exit 0; }

echo "== VERDICT PHYSIQUE sur CES caisses-la =="
k=0
for aid in $(echo "$AIDS" | tr ',' ' '); do
  line=$(awk -v a="$aid" '$6==a {print; exit}' .autoport/gjcc_waypoints.txt)
  [ -n "$line" ] || { echo "  aid=$aid : pas de waypoint"; continue; }
  set -- $line; x=$2; y=$3; z=$4; cy=$5
  k=$((k+1))
  echo "(gjcc-watch-set $aid 30)" >&3; sleep 0.3
  echo "(when *target* (move-to-point! (-> *target* control) (new (quote static) (quote vector) :x $x :y $y :z $z :w 1.0)) (set! (-> *target* control transv quad) (the-as uint128 0)))" >&3
  sleep 3.0
  echo "(gjcc-land $k $aid $cy)" >&3; sleep 0.5
done
echo '(gjcc-scan 9)' >&3; sleep 3
exec 3>&-; sleep 2
echo "== RESULTAT $TAG (mode=$MODE) =="
grep -a 'GJCC-LAND' "$LOG" | tail -8
echo "  spheres NaN au scan final : $(grep -a 'GJCC-CRATE tag=9 ' "$LOG" | grep -ac 'wd=NaN')"
echo "  GJCC-THRU (detecteur passif) : $(grep -ac 'GJCC-THRU' "$LOG")"
echo "GJCC2-CAUSAL-DONE tag=$TAG mode=$MODE aids=$AIDS verdicts=$k"
