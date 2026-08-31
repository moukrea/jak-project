#!/usr/bin/env bash
# gjcc_x86_probe.sh — Gjak1-crate-collision : RECENSEMENT DES CAISSES DE GEYSER ROCK
#
# Mesure, pour CHAQUE entite `crate` du niveau `training` (crate/crate-buzzer/barrel/bucket) :
#   - si un PROCESSUS vivant existe (live=1/0)
#   - si le processus est VISIBLE (hid=0) et s'il est COLLIDABLE :
#       mesh = le collide-mesh est-il lie (0 = find-collision-meshes a echoue -> on passe au travers)
#       as   = collide-as   (0 = clear-collide-with-as a tire)
#       with = collide-with (0 = idem)
#   « caisse sans collision » := hid=0 ET (mesh=0 OU as=0 OU with=0)
#
# CONTROLE POSITIF OBLIGATOIRE : on injecte le defaut sur UNE caisse vivante
# (clear-collide-with-as), le compteur doit MONTER de 1 exactement, puis on
# restaure et il doit REDESCENDRE. Un zero sans ce controle ne vaut rien.
#
# La fenetre build+course est UNE SEULE section critique tenue par un detenteur VIVANT
# (convention DIRECTIVES 2026-08-14 07:10 : PID + horodatage, trap de nettoyage,
# on ne retire QUE le verrou qu'on a pose soi-meme).
#
# Env: GJCC_TAG (nom de la course), GJCC_BUILD=1 pour forcer (mi), GJCC_SWEEP=1 pour
#      teleporter le joueur sur chaque caisse (fait naitre celles qui sont hors de portee).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

TAG="${GJCC_TAG:-c1}"
ISO=out/jak1/iso
GK=build/game/gk
GOALC=build/goalc/goalc
LOCK=.autoport/.deploy-in-progress
OUT=.autoport/reports/Gjak1-crate-collision
mkdir -p "$OUT/runs"
GKLOG="$OUT/runs/gk-$TAG.log"; GCLOG="$OUT/runs/goalc-$TAG.log"
export DISPLAY="${DISPLAY:-:0}"

_own=0
_stale(){ [ -f "$1" ] || return 0
          local p; p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$1" | head -1)
          [ -n "$p" ] || return 0
          kill -0 "$p" 2>/dev/null && return 1 || return 0; }
if _stale "$LOCK"; then
  printf 'gjcc_x86_probe pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"; _own=1
else
  echo "FAIL: verrou de livraison detenu par un processus VIVANT ($(cat "$LOCK")) — on n'ecrase pas."; exit 1
fi

FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null || true
           kill "${GKPID:-0}" "${GCPID:-0}" 2>/dev/null || true
           wait 2>/dev/null || true
           rm -f "$FIFO"
           [ "$_own" = 1 ] && rm -f "$LOCK"
           return 0; }
trap cleanup EXIT

_iso_stamp(){ md5sum "$ISO/GAME.CGO" "$ISO/KERNEL.CGO" 2>/dev/null | cut -d' ' -f1 | tr '\n' ' '; }

echo "== attente d'un arbre calme (verrou pose, pid=$$) =="
q=0
for i in $(seq 1 120); do
  s1=$(_iso_stamp); sleep 5
  if [ -n "$s1" ] && [ "$s1" = "$(_iso_stamp)" ] && ! pgrep -x goalc >/dev/null 2>&1; then
    q=1; echo "arbre calme apres $(( i * 5 ))s"; break
  fi
done
[ "$q" = 1 ] || { echo "FAIL: l'arbre ne se calme pas apres 10 min"; exit 1; }

if [ "${GJCC_BUILD:-0}" = "1" ]; then
  echo "== (mi) : reconstruction x86 de out/jak1/iso =="
  "./$GOALC" --user-auto --game jak1 -c '(mi)' > "$OUT/runs/mi-$TAG.log" 2>&1
  rc=$?; tail -3 "$OUT/runs/mi-$TAG.log"
  [ "$rc" = 0 ] || { echo "FAIL: (mi) a echoue (rc=$rc)"; exit 1; }
fi
echo "empreinte ISO : $(_iso_stamp)"

echo "== boot gk =="
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk est mort au boot"; tail -40 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "boot ~${i}s"; break; }
  sleep 1
done
sleep 3

echo "== goalc : (lt) + (build-game) =="
timeout 1800 "./$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 300); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "build-game ~${i}s"; break; }
done
sleep 4

echo "== warp NEW GAME 'game-start' (Geyser Rock / training) =="
echo "(start 'play (get-continue-by-name *game-info* \"game-start\"))" >&3
sleep 25
echo '(if *target* (format 0 "GJCC-TGT x=~f y=~f z=~f~%" (-> *target* control trans x) (-> *target* control trans y) (-> *target* control trans z)) (format 0 "GJCC-TGT none~%"))' >&3
sleep 2

echo "== definition des sondes =="
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  printf '%s\n' "$_l" >&3
  sleep 2
done < .autoport/gjcc_probe.gc
sleep 3
if grep -aq 'Compilation Error\|Reader error' "$GCLOG"; then
  echo "FAIL: les sondes n'ont pas compile —"
  grep -a -A6 'Compilation Error\|Reader error' "$GCLOG" | sed 's/\x1b\[[0-9;]*m//g' | head -30
  exit 1
fi
echo '(format 0 "GJCC-PROBES-READY~%")' >&3
sleep 2

echo "== scan initial =="
echo '(gjcc-scan 0)' >&3
sleep 4
NCRATE=$(grep -a 'GJCC-SUM tag=0 ' "$GKLOG" | tail -1 | sed -n 's/.*entities=\([0-9]*\).*/\1/p')
NCRATE="${NCRATE:-0}"
echo "caisses recensees dans le niveau : $NCRATE"
[ "$NCRATE" -gt 0 ] || { echo "FAIL: aucune entite crate recensee — le niveau n'est pas charge ou la sonde ne voit rien"; exit 1; }

if [ "${GJCC_SWEEP:-1}" = "1" ]; then
  echo "== balayage : le joueur visite chacune des $NCRATE caisses (naissance forcee) =="
  for k in $(seq 0 $((NCRATE-1))); do
    echo "(gjcc-goto $k)" >&3
    sleep 3
    echo "(gjcc-scan $((k+1)))" >&3
    sleep 2
  done
fi

echo "== CONTROLE POSITIF : on injecte le defaut sur une caisse vivante =="
echo '(gjcc-scan 900)' >&3;                sleep 2
echo '(gjcc-inject 1)' >&3;                sleep 2
echo '(gjcc-scan 901)' >&3;                sleep 2
echo '(gjcc-inject 0)' >&3;                sleep 2
echo '(gjcc-scan 902)' >&3;                sleep 3

echo "== recolte =="
grep -aE '^GJCC-' "$GKLOG" > "$OUT/runs/gjcc-$TAG.txt" || true
echo "lignes GJCC recoltees : $(wc -l < "$OUT/runs/gjcc-$TAG.txt")"
tail -5 "$OUT/runs/gjcc-$TAG.txt"
echo "GJCC-RUN-DONE tag=$TAG"
