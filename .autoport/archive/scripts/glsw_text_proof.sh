#!/usr/bin/env bash
# glsw_text_proof.sh — Gloading-screen-window : LA TAILLE ET LA POSITION DU TEXTE, MESUREES DANS
# L'IMAGE PRODUITE, ET LA COULEUR RELUE DANS LA TABLE QUE LE MOTEUR EMET.
#
#   D2 « ca devrait etre plus bas a droite et surtout bien plus petit, genre moitie moins gros »
#   D6 « Le texte est en degrade gris [...] ca devrait etre en plein white ! »
#
# LES DEUX MISES EN PAGE SONT REJOUEES SUR LE MEME BINAIRE, a la meme frame, avec le meme
# instrument : `(ls-layout-avant!)` et `(ls-layout-apres!)` ne sont appelees par aucun chemin de
# jeu. Comparer deux BUILDS ne prouverait rien sur celui qu'on livre.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen-window"; mkdir -p "$OUT"
SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
LOG="$OUT/text-proof.log"; GCLOG="$OUT/text-proof-goalc.log"
: > "$LOG"; : > "$GCLOG"
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/lstext-*.png "$SHOTDIR"/screenshot.png 2>/dev/null || true

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null || true
           kill "$GKPID" 2>/dev/null; [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
           wait 2>/dev/null; rm -f "$FIFO"; }
trap cleanup EXIT

echo "== attente de l'ecran titre =="
for i in $(seq 1 180); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk est mort"; tail -20 "$LOG"; exit 1; }
  grep -qaE "link finish: default-menu|BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; break; }
  sleep 1
done
sleep 3
timeout 1200 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 600); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }; done
sleep 3
echo '(format 0 "REPL-LIVE~%")' >&3
for i in $(seq 1 20); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && break; done
grep -qa "REPL-LIVE" "$LOG" || { echo "FAIL: listener goalc non connecte"; exit 1; }

# La silhouette chevauche la bande de texte en x ET en y : on l'eteint pour isoler ce qu'on mesure.
echo '(set! *ls-draw-silhouette* #f)' >&3
sleep 1

for LEG in avant apres; do
  echo "== jambe $LEG =="
  echo "(ls-layout-$LEG!)" >&3
  sleep 1
  echo '(loading-screen-force! (seconds 10))' >&3
  sleep 3
  rm -f "$SHOTDIR/screenshot.png"
  echo '(pc-screen-shot)' >&3
  for i in $(seq 1 20); do [ -f "$SHOTDIR/screenshot.png" ] && break; sleep 1; done
  sleep 1
  cp -f "$SHOTDIR/screenshot.png" "$SHOTDIR/lstext-$LEG.png" 2>/dev/null || echo "  PAS DE CAPTURE pour $LEG"
  sleep 2
done
exec 3>&-
sleep 2
mkdir -p "$OUT/shots"
cp -f "$SHOTDIR"/lstext-*.png "$OUT/shots/" 2>/dev/null || true
echo "---- COULEUR RELUE DANS LA TABLE ----"
grep -a "LSCOLOR-BRUT" "$LOG" | tail -4
echo "---- MISE EN PAGE PUBLIEE PAR LE MOTEUR ----"
grep -a "LOADSCREEN-COSM\|LOADSCREEN-LAYOUT\|LOADSCREEN-WIDTH" "$LOG" | tail -8
echo "---- MESURE DANS L'IMAGE ----"
python3 .autoport/glsw_measure_text.py "$OUT/shots/lstext-avant.png" "$OUT/shots/lstext-apres.png"
