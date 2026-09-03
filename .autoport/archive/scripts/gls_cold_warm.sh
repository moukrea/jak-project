#!/usr/bin/env bash
# gls_cold_warm.sh — Gloading-screen : LA CADENCE DE L'ECRAN DE CHARGEMENT SUR LES DEUX CHEMINS
# QUE L'OWNER A SEPARES (2026-08-30).
#
#   « le freeze n'apparaît QUE sur le chargement d'une sauvegarde qui se passe dans un AUTRE niveau
#     que Sandover Village (Geyser Rock) ; pour une téléportation entre Geyser Rock vers Sandover
#     Village j'ai pas constaté le problème. »
#
# C'est un DISCRIMINANT, pas une plainte : un seul chiffre ne prouverait rien puisqu'il a deja
# constate que l'un des deux chemins va bien. On joue donc TROIS transitions dans la meme course,
# et le pivot est une seule colonne : le STATUT des deux emplacements de niveau.
#
#   FROID     game-start      (title+village1  ->  training+village1)
#             `training` est neuf : login, table d'entites et liaison s'executent.
#             `village1` est conserve (il est lev1 de TOUS les continues de training,
#             level-info.gc:55/84/113), donc la boucle bloquante de `update!` ne s'arme PAS.
#   CHAUD     village1-warp   (training+village1 -> village1+beach)
#             `village1` est deja 'active : `level-status-set! 'active` est un no-op
#             (level.gc:288-315), aucun login, aucune naissance d'entite. C'est le cas dont
#             l'owner dit qu'il va bien.
#   TRES FROID snow-start     (village1+beach   -> snow+village3)
#             AUCUN niveau commun : les deux emplacements passent 'inactive, et c'est la seule
#             condition qui arme la boucle `while` SANS `suspend` de level.gc:1130 — le chargement
#             entier dans UNE frame GOAL.
#
# TOUT SE PILOTE PAR `initialize!`, JAMAIS PAR `start`. `start` ne passe pas par
# `continue-load-gate!` (seul `initialize!` l'appelle, game-info.gc:257) : comparer une phase en
# `initialize!` a une phase en `start`, c'est comparer deux chemins qui ne traversent pas les memes
# barrieres. Le harnais precedent faisait exactement ca.
#
# ABLATION, SUR LE MEME BINAIRE :
#   OG_GOAL_SLICE_MS=0        le travail GOAL n'est pas decoupe  = le comportement d'AVANT
#   OG_LOADSCREEN_SLICE_MS=N  la tranche du chargeur cote renderer
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; mkdir -p "$OUT"
TAG="${1:-apres}"
export OG_GOAL_SLICE_MS="${2:-6}"
# Non pose = TRANCHE ADAPTATIVE (le chargeur prend ce qui reste de la frame de 60 Hz).
# Pose = un ORDRE : 0 = non borne (le chemin d'avant), 40 = la tranche fixe du cycle precedent.
if [ -n "${3:-}" ]; then export OG_LOADSCREEN_SLICE_MS="$3"; else unset OG_LOADSCREEN_SLICE_MS; fi
LOG="$OUT/coldwarm-$TAG.log"; GCLOG="$OUT/coldwarm-$TAG-goalc.log"
: > "$LOG"; : > "$GCLOG"

echo "== gk (OG_GOAL_SLICE_MS=$OG_GOAL_SLICE_MS OG_LOADSCREEN_SLICE_MS=${OG_LOADSCREEN_SLICE_MS:-adaptatif}) =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
  | python3 -u -c 'import sys,time
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

echo "== attente de l'ecran titre =="
for i in $(seq 1 150); do
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; break; }
  sleep 1
done
sleep 3
echo "== goalc (lt) + (build-game) =="
timeout 1800 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 600); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }; done
sleep 3
# CONTROLE DE VIVACITE : une forme n'atteint le jeu que si le listener est connecte ; sinon goalc
# compile avec `allow_emit=#f` et jette tout EN SILENCE (Compiler.cpp:132).
echo '(format 0 "REPL-LIVE~%")' >&3
for i in $(seq 1 20); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && break; done
grep -qa "REPL-LIVE" "$LOG" || { echo "FAIL: listener goalc non connecte — rien ne serait execute"; exit 1; }

run_leg () {  # $1 = etiquette   $2 = nom du continue   $3 = attente
  echo "== $1 : $2 =="
  echo "(format 0 \"REPL-LEG $1 continue=$2 lev0=~A/~A lev1=~A/~A~%\" (-> *level* level0 name) (-> *level* level0 status) (-> *level* level1 name) (-> *level* level1 status))" >&3
  echo "(initialize! *game-info* (quote game) (the-as game-save #f) \"$2\")" >&3
  sleep "$3"
  echo "(format 0 \"REPL-LEG-FIN $1 lev0=~A/~A lev1=~A/~A~%\" (-> *level* level0 name) (-> *level* level0 status) (-> *level* level1 name) (-> *level* level1 status))" >&3
  sleep 3
}

run_leg FROID       game-start    "${WAIT_A:-45}"
run_leg CHAUD       village1-warp "${WAIT_B:-45}"
run_leg TRESFROID   snow-start    "${WAIT_C:-60}"

exec 3>&-
sleep 3
echo "---- ETAPES ----"
grep -aE "REPL-LEG|Discarding level|Adding level|Waiting for level|Displaying level" "$LOG"
echo "---- CADENCE DE L'ECRAN DE CHARGEMENT ----"
grep -aE "LOADSCREEN-FRAME|LOADSCREEN-TEX|LOADSCREEN-GAP" "$LOG"
echo "---- log: $LOG ----"
