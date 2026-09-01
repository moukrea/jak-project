#!/usr/bin/env bash
# Gjak1-crate-collision-2 — LA CADENCE EST-ELLE LA CAUSE ? MESURE AU PRODUCTEUR.
#
# L'owner : « ptêtre lié au jeux qui dépend plus du framerate ». Le cycle precedent a
# mesure la CORRELATION (0 sphere NaN a 60 images/s contre 8 a 10) et a ecrit honnetement
# que le MECANISME n'etait pas etabli. Ce banc-la le mesure a l'endroit ou l'evenement se
# produit, pas par echantillonnage :
#
#   `waitn`    = caisses passees par l'etat `wait`, c'est-a-dire ayant eu leur UNIQUE
#                occasion de reposer leur sphere de collision. C'est le DENOMINATEUR.
#   `waitfail` = celles dont la matrice d'os etait TOUJOURS vierge a cette image-la :
#                la reparation echoue, la caisse s'endort, son volume est perdu A VIE.
#
# Le meme script de deplacement est joue a chaque cadence : seule la cadence change.
# Si `waitfail/waitn` monte quand la cadence baisse, l'evenement est cadence par IMAGES
# et l'hypothese de l'owner est etablie ; s'il est plat, elle est refutee.
#
# CONTROLE INTERNE : une course a garde ABLATEE (mode 33) doit rendre le MEME `waitfail`
# que la course a garde active (mode 1) a la meme cadence — la garde repare, elle ne
# change pas l'OCCASION de reparer. Si les deux different, c'est l'instrument qui ment.
#
# usage : gjcc2_x86_cadence.sh <tag> <fps> <mode>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
TAG="${1:-k60}"; FPS="${2:-60}"; MODE="${3:-1}"
GK=build-x86/game/gk; GOALC=build-x86/goalc/goalc; ISO=out/jak1/iso
OUT=.autoport/reports/Gjak1-crate-collision/runs; mkdir -p "$OUT"
LOG="$OUT/gk-cad-$TAG.log"; GCLOG="$OUT/goalc-cad-$TAG.log"; DRV="$OUT/drv-cad-$TAG.log"
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
for i in $(seq 1 90); do
  _stale "$LOCK" && { printf 'gjcc2_cadence pid=%s tag=%s started=%s\n' "$$" "$TAG" "$(date -Is)" > "$LOCK"; _own=1; break; }
  echo "verrou tenu : $(cat "$LOCK") — attente $i/90"; sleep 10
done
[ "$_own" = 1 ] || { echo "FAIL: verrou jamais libere"; exit 1; }

echo "== boot gk (tag=$TAG fps=$FPS mode=$MODE) =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKPID=$!
for i in $(seq 1 180); do kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk mort"; tail -20 "$LOG"; exit 1; }
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; break; }; sleep 1; done
sleep 3
timeout 1500 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"; echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 420); do sleep 1; grep -qaiE "Successfully built all|Build Successful" "$GCLOG" && { echo "  build-game a ~${i}s"; break; }
  grep -qa "Compilation Error\|Reader error" "$GCLOG" && { echo "FAIL compilation"; tail -30 "$GCLOG"; exit 1; }; done
sleep 4

# LA CADENCE EST POSEE AVANT LE CHARGEMENT DU NIVEAU. C'est pendant le chargement que la
# grande majorite des caisses naissent : la poser apres, c'est mesurer une population deja
# nee a 60 images/s et croire qu'on mesure la cadence demandee.
echo "(set-frame-rate! *pc-settings* $FPS #t)" >&3; sleep 2
echo "(set! *gjcc-mode* $MODE)" >&3; sleep 2
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep 60
grep -a 'GJCC-MODE' "$LOG" | tail -1

echo "== BRASSAGE : memes 31 points a chaque cadence, meme rythme =="
n=0
while read -r idx x y z cy aid nm; do
  n=$((n+1))
  echo "(when *target* (move-to-point! (-> *target* control) (new (quote static) (quote vector) :x $x :y $y :z $z :w 1.0)))" >&3
  sleep 1.2
done < .autoport/gjcc_waypoints.txt
sleep 3
echo '(gjcc-scan 9)' >&3; sleep 5
exec 3>&-; sleep 2

echo "== RESULTAT $TAG =="
RUN=$(grep -a 'waitfail=' "$LOG" | tail -1)
SUM=$(grep -a 'GJCC-SUM' "$LOG" | tail -1)
echo "  derniere ligne waitfail : $RUN"
echo "  GJCC-SUM                : $SUM"
WF=$(echo "$RUN" | sed -n 's/.*waitfail=\([0-9]*\).*/\1/p')
WN=$(echo "$RUN" | sed -n 's/.*waitn=\([0-9]*\).*/\1/p')
DG=$(grep -a 'degen=' "$LOG" | tail -1 | sed -n 's/.*degen=\([0-9]*\).*/\1/p')
NANC=$(echo "$SUM" | sed -n 's/.*nan=\([0-9]*\).*/\1/p')
NANL=$(grep -a 'GJCC-CRATE ' "$LOG" | grep -c 'wd=NaN')
FPSM=$(grep -a 'fps=' "$LOG" | sed -n 's/.*fps=\([0-9.]*\).*/\1/p' | sort -n | awk '{v[NR]=$1} END{if(NR>0) printf "%s", v[int((NR+1)/2)]; else printf "n/a"}')
echo "GJCC2-CADENCE tag=$TAG fps_demande=$FPS fps_mesure_median=$FPSM mode=$MODE waitfail=${WF:-NA} waitn=${WN:-NA} degen=${DG:-NA} scan_nan=${NANC:-NA} lignes_wd_NaN=$NANL"
