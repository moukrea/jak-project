#!/usr/bin/env bash
# gjcc_x86_run.sh — Gjak1-crate-collision : RECENSEMENT DES CAISSES DE GEYSER ROCK (x86)
#
# Une COURSE = un boot de gk, un chargement de `training` (Geyser Rock), puis le joueur
# est TELEPORTE au-dessus de chacune des 31 caisses du niveau (positions lues dans
# decompiler_out/jak1/entities/training-actors.json) pour forcer leur naissance, avec un
# recensement complet apres chaque saut.
#
# Pour CHAQUE caisse la sonde publie le triplet qui tranche :
#   identite (aid, look, position) | forme ENREGISTREE (onlist/rp/mesh/as/with/incache)
#   | OCCUPATION DU POOL a cet instant (longueur/capacite des 4 moteurs + collide-cache)
#
# CONTROLE POSITIF a la fin : on injecte le defaut sur une caisse vivante
# (clear-collide-with-as) — `nocol` doit MONTER, puis REDESCENDRE a la restauration.
#
# Le verrou de livraison est tenu par CE processus (PID vivant, convention DIRECTIVES
# 2026-08-14 07:10). On ne retire QUE le verrou qu'on a pose soi-meme.
# On ne reconstruit PAS out/jak1/iso : `(build-game)` lie le code courant dans le gk qui tourne.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"

TAG="${1:-r1}"
FPS="${2:-60}"
FIX="${3:-1}"
# Gjak1-crate-collision-2 : mot de commande de la mesure (voir pckernel-h.gc). 0 = on ne
# touche a rien, donc les courses du cycle precedent restent reproductibles a l'identique.
MODE="${4:-0}"          # 1 = cadence de naissance PAR SECONDE (correctif) ; 0 = ABLATION (quota par image d'origine)          # image/s forcees : le telephone tourne a ~9 fps, le bureau a 60
SETTLE="${GJCC_SETTLE:-2.6}"        # secondes apres chaque teleportation
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gjak1-crate-collision/runs"; mkdir -p "$OUT"
LOG="$OUT/gk-$TAG.log"; GCLOG="$OUT/goalc-$TAG.log"; DRV="$OUT/drv-$TAG.log"
LOCK=".autoport/.deploy-in-progress"
exec > >(tee "$DRV") 2>&1
: > "$LOG"; : > "$GCLOG"

_own=0
_stale(){ [ -f "$1" ] || return 0
          local p; p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$1" | head -1)
          [ -n "$p" ] || return 0
          kill -0 "$p" 2>/dev/null && return 1 || return 0; }
for i in $(seq 1 90); do
  if _stale "$LOCK"; then
    printf 'gjcc_x86_run pid=%s tag=%s started=%s\n' "$$" "$TAG" "$(date -Is)" > "$LOCK"; _own=1; break
  fi
  echo "verrou tenu par un vivant : $(cat "$LOCK") — attente ${i}/90"; sleep 10
done
[ "$_own" = 1 ] || { echo "FAIL: verrou de livraison jamais libere"; exit 1; }

FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){
  exec 3>&- 2>/dev/null || true
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  [ -n "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null
  sleep 1
  [ -n "${GKPID:-}" ] && kill -9 "$GKPID" 2>/dev/null
  wait 2>/dev/null
  rm -f "$FIFO"
  [ "$_own" = 1 ] && rm -f "$LOCK"
  return 0
}
trap cleanup EXIT

_stamp(){ md5sum "$ISO/GAME.CGO" "$ISO/KERNEL.CGO" "$ISO/ENGINE.CGO" 2>/dev/null | cut -d' ' -f1 | tr '\n' ' '; }
echo "== attente d'un arbre calme (verrou pose, pid=$$) =="
q=0
for i in $(seq 1 90); do
  s1=$(_stamp); sleep 4
  if [ -n "$s1" ] && [ "$s1" = "$(_stamp)" ] && ! pgrep -x goalc >/dev/null 2>&1; then q=1; echo "  calme apres $((i*4))s"; break; fi
done
[ "$q" = 1 ] || { echo "FAIL: l'arbre ne se calme pas"; exit 1; }
echo "empreinte ISO : $(_stamp)"

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

echo "== goalc : (lt) + (build-game) =="
timeout 1500 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
bg=0
for i in $(seq 1 420); do
  sleep 1
  if grep -qaiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null; then echo "  build-game a ~${i}s"; bg=1; break; fi
  if grep -qa "Compilation Error\|Reader error" "$GCLOG" 2>/dev/null; then
    echo "FAIL: erreur de compilation —"
    sed 's/\x1b\[[0-9;]*m//g' "$GCLOG" | grep -A14 'Compilation Error\|Reader error' | head -40
    exit 1
  fi
done
[ "$bg" = 1 ] || { echo "FAIL: build-game n'a pas fini"; tail -5 "$GCLOG"; exit 1; }
sleep 4

echo "== NOUVELLE PARTIE : game-start (Geyser Rock / training) =="
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep 45
echo '(if *target* (format 0 "GJCC-TGT x=~f y=~f z=~f~%" (-> *target* control trans x) (-> *target* control trans y) (-> *target* control trans z)) (format 0 "GJCC-TGT none~%"))' >&3
sleep 2
echo "(set-frame-rate! *pc-settings* $FPS #t)" >&3
sleep 1
# FIX=0 : rayon de portee physique a ZERO = comportement d'origine (ablation, meme binaire)
if [ "$FIX" = "0" ]; then echo '(set! *actor-collision-birth-radius* 0.0)' >&3; else echo '(set! *actor-collision-birth-radius* (meters 30))' >&3; fi
sleep 1
if [ "$MODE" != "0" ]; then echo "(set! *gjcc-mode* $MODE)" >&3; sleep 2; fi
echo '(format 0 "GJCC-FPS target=~D spf=~f~%" (-> *pc-settings* target-fps) (-> *display* seconds-per-frame))' >&3
sleep 1
echo '(gjcc-cc-reset 60)' >&3
sleep 1
echo '(gjcc-scan 0)' >&3
sleep 3
if ! grep -qa 'GJCC-SUM tag=0 ' "$LOG"; then
  echo "FAIL: la sonde n'a rien publie — le niveau n'est pas charge ou gjcc-scan n'existe pas"
  tail -20 "$LOG"; exit 1
fi
grep -a 'GJCC-SUM tag=0 ' "$LOG" | tail -1

echo "== BALAYAGE : le joueur visite les 31 caisses =="
k=0
while read -r idx x y z cy aid nm; do
  [ -n "$idx" ] || continue
  k=$((k+1))
  # passe 1 : on amene le joueur sur place UNIQUEMENT pour faire NAITRE la caisse
  echo "(when *target* (move-to-point! (-> *target* control) (new (quote static) (quote vector) :x $x :y $y :z $z :w 1.0)) (set! (-> *target* control transv quad) (the-as uint128 0)))" >&3
  sleep 1.4
  # on arme la surveillance image par image sur CETTE caisse, puis on le lache dessus
  echo "(gjcc-watch-set $aid 40)" >&3
  sleep 0.2
  echo "(when *target* (move-to-point! (-> *target* control) (new (quote static) (quote vector) :x $x :y $y :z $z :w 1.0)) (set! (-> *target* control transv quad) (the-as uint128 0)))" >&3
  sleep "$SETTLE"
  echo "(gjcc-land $k $aid $cy)" >&3
  sleep 0.3
  # SECOND LACHER sur la MEME caisse : elle est desormais nee a coup sur. S'il retombe
  # dessus, la caisse est solide et le premier echec etait un retard de naissance ;
  # s'il la retraverse, l'etat est PERSISTANT et la cause est ailleurs.
  echo "(when *target* (move-to-point! (-> *target* control) (new (quote static) (quote vector) :x $x :y $y :z $z :w 1.0)) (set! (-> *target* control transv quad) (the-as uint128 0)))" >&3
  sleep "$SETTLE"
  echo "(gjcc-land $((k+100)) $aid $cy)" >&3
  sleep 0.3
  echo "(gjcc-scan $k)" >&3
  sleep 0.9
done < .autoport/gjcc_waypoints.txt
echo "  $k etapes"

echo "== CONTROLE POSITIF =="
echo '(gjcc-scan 900)' >&3; sleep 2
echo '(gjcc-inject 1)' >&3; sleep 2
echo '(gjcc-scan 901)' >&3; sleep 2
echo '(gjcc-inject 0)' >&3; sleep 2
echo '(gjcc-scan 902)' >&3; sleep 3

exec 3>&-
sleep 2
grep -aE 'GJCC-|Exceeded max number of collide-cache prims|Failed to find collision meshes|too many tris|too many prims' "$LOG" > "$OUT/gjcc-$TAG.txt" || true
echo "== RESUME COURSE $TAG (fps=$FPS fix=$FIX mode=$MODE) =="
grep -a "GJCC-MODE" "$LOG" | tail -1
echo "  spheres NaN (wd=NaN) : $(grep -a 'GJCC-CRATE' "$OUT/gjcc-$TAG.txt" | grep -ac 'wd=NaN')"
echo "  caisses traversees   : $(grep -a 'GJCC-LAND' "$OUT/gjcc-$TAG.txt" | awk '{d=0;l=0;a="";for(i=1;i<=NF;i++){if($i~/^dy=/)d=substr($i,4)+0;if($i~/^aid=/)a=$i;if($i~/^live=/)l=substr($i,6)+0} if(l==1&&d<7000) print a}' | sort -u | wc -l)"
echo "  GJCC-THRU (passif)   : $(grep -ac 'GJCC-THRU' "$LOG")"
grep -a "GJCC-FPS" "$LOG" | tail -1
grep -a 'GJCC-SUM' "$OUT/gjcc-$TAG.txt" | tail -5
grep -a 'GJCC-CC ' "$OUT/gjcc-$TAG.txt" | tail -3
echo "nocon: $(grep -ac 'GJCC-NOCON' "$OUT/gjcc-$TAG.txt")  drop-lines: $(grep -ac 'GJCC-DROP' "$OUT/gjcc-$TAG.txt")"
echo "GJCC-RUN-DONE tag=$TAG lignes=$(wc -l < "$OUT/gjcc-$TAG.txt")"
