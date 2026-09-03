#!/usr/bin/env bash
# Gjak1-crate-collision-2 — LA SONDE PROGRAMMATIQUE SUR x86.
#
# Correction de methode de l'owner (2026-09-01) : « fais ça de façon programmatique
# [...] impossible que tu couvre toutes les caisses de Geyser Rock à la vue ».
# Le niveau est charge NORMALEMENT ; on ne teleporte rien, on ne presse aucun bouton,
# on ne regarde aucune image. La sonde interroge CHAQUE caisse par le code.
#
# usage : gjcc2_x86_sonde.sh <tag> <mode> <fps> <duree_s> [forceactors]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
TAG="${1:-s1}"; MODE="${2:-129}"; FPS="${3:-60}"; DUR="${4:-120}"; FORCE="${5:-0}"
GK=build-x86/game/gk; GOALC=build-x86/goalc/goalc; ISO=out/jak1/iso
OUT=.autoport/reports/Gjak1-crate-collision/runs; mkdir -p "$OUT"
LOG="$OUT/gk3-$TAG.log"; GCLOG="$OUT/goalc3-$TAG.log"; DRV="$OUT/drv3-$TAG.log"
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
  _stale "$LOCK" && { printf 'gjcc2_sonde pid=%s tag=%s started=%s\n' "$$" "$TAG" "$(date -Is)" > "$LOCK"; _own=1; break; }
  echo "verrou tenu : $(cat "$LOCK") — attente $i/60"; sleep 10
done
[ "$_own" = 1 ] || { echo "FAIL: verrou jamais libere"; exit 1; }

# LE CODE SOUS TEST DOIT ETRE CELUI DU CGO, PAS UN ESPOIR DE CHARGEMENT A CHAUD.
# Mesure : la course s1 n'a produit AUCUNE ligne de sonde alors que la sonde etait
# compilee — `(build-game)` ne televerse que les objets qu'il RECOMPILE, et ils
# etaient deja a jour d'une compilation hors ligne. Le gk demarre en `-boot`, donc il
# lit le CGO. On reconstruit donc le CGO AVANT de demarrer, et la sonde est dans le
# meme artefact que celui qu'on portera sur l'appareil.
echo "== (mi) : reconstruction de out/jak1/iso avec le code courant =="
timeout 900 "$GOALC" --user-auto --game jak1 --disable-ansi -c '(mi)' > "$OUT/mi3-$TAG.log" 2>&1
grep -qE "Successfully built all [0-9]+ targets" "$OUT/mi3-$TAG.log" || { echo "FAIL: (mi)"; tail -25 "$OUT/mi3-$TAG.log"; exit 1; }
echo "  $(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$OUT/mi3-$TAG.log" | head -1)"
echo "  la sonde est-elle dans le CGO ? GJCC-PROBESUM : $(grep -c GJCC-PROBESUM out/jak1/iso/GAME.CGO 2>/dev/null || true)"

echo "== boot gk =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKPID=$!
for i in $(seq 1 180); do kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk mort"; tail -20 "$LOG"; exit 1; }
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; break; }; sleep 1; done
sleep 3
timeout 1800 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"; echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 420); do sleep 1; grep -qaiE "Successfully built all|Build Successful" "$GCLOG" && { echo "  build-game a ~${i}s"; break; }
  grep -qa "Compilation Error\|Reader error" "$GCLOG" && { echo "FAIL compilation"; sed 's/\x1b\[[0-9;]*m//g' "$GCLOG" | grep -A20 "Compilation Error" | head -30; exit 1; }; done
sleep 4
if [ "$FORCE" = "1" ]; then
  # `force-actors?` est une OPTION LIVREE du jeu (pckernel-common.gc:971) : elle fait
  # naitre les acteurs a la DISTANCE au lieu de la visibilite. On s'en sert comme mode
  # de MESURE, et c'est le cas le PLUS DUR pour le defaut cherche : les caisses naissent
  # alors HORS CHAMP, donc sans qu'aucune matrice d'os ait ete calculee.
  echo "(set! (-> *pc-settings* ps2-actor-vis?) #f)" >&3; sleep 1
fi
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep 45
echo "(set-frame-rate! *pc-settings* $FPS #t)" >&3; sleep 1
echo "(set! *gjcc-mode* $MODE)" >&3; sleep 2
grep -a 'GJCC-MODE' "$LOG" | tail -1
echo "== LE JEU TOURNE ${DUR}s, PERSONNE NE TOUCHE A RIEN — la sonde interroge les caisses =="
sleep "$DUR"
exec 3>&-; sleep 2

echo "== RESULTAT $TAG (mode=$MODE fps=$FPS force-actors=$FORCE) =="
echo "  passes de sonde : $(grep -ac 'GJCC-PROBESUM' "$LOG")"
grep -a 'GJCC-PROBESUM' "$LOG" | sed 's/^.*GJCC-PROBESUM/  GJCC-PROBESUM/'
echo "  --- caisses en echec (ok=0) ---"
grep -a 'GJCC-PROBE ' "$LOG" | grep 'ok=0' | sed 's/^.*GJCC-PROBE/  GJCC-PROBE/' | head -20
echo "  --- distribution bw (matrice d'os) ---"
grep -a 'GJCC-PROBE ' "$LOG" | grep -o 'bw=[^ ]*' | sort | uniq -c | sort -rn | head -5
echo "  --- distribution incache ---"
grep -a 'GJCC-PROBE ' "$LOG" | grep -o 'incache=[0-9]*' | sort | uniq -c
echo "GJCC2-SONDE-DONE tag=$TAG mode=$MODE fps=$FPS force=$FORCE"
