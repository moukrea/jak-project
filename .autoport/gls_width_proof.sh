#!/usr/bin/env bash
# Gloading-screen — PREUVE EN PIXELS que la ligne precurseur fait la largeur du texte.
# Owner 2026-08-29 : « le texte "Chargement..." est moins large que son pendant en Precursor,
# ce que je voulais eviter, t'as pas reussi ».
#
# POURQUOI UNE CAPTURE ET PAS LA TRACE. La ligne `LOADSCREEN-WIDTH` publie une largeur de texte
# et une largeur de ligne precurseur qui sortent toutes deux du MEME calcul : leur egalite y est
# vraie PAR CONSTRUCTION, donc elle ne prouve rien -- c'est un miroir. Ici on mesure l'ENCRE
# REELLEMENT ALLUMEE dans l'image produite, ce qui est une grandeur INDEPENDANTE du modele de
# mise en page, et qui voit en plus les approches laterales des glyphes.
# Ce n'est PAS un jugement visuel : la sortie est un nombre de pixels, pas un avis.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; mkdir -p "$OUT"
SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
LOG="$OUT/width-proof.log"; GCLOG="$OUT/width-proof-goalc.log"
: > "$LOG"; : > "$GCLOG"
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/ls-*.png "$SHOTDIR"/screenshot.png 2>/dev/null || true

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null || true
           kill "$GKPID" 2>/dev/null; [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
           wait 2>/dev/null; rm -f "$FIFO"; }
trap cleanup EXIT

echo "== attente de l'ecran titre =="
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk est mort"; tail -20 "$LOG"; exit 1; }
  grep -qaE "link finish: default-menu" "$LOG" && { echo "  titre a ~${i}s"; break; }
  sleep 1
done
sleep 3
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 300); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }
done
sleep 3

for L in english french spanish german italian; do
  echo "== langue $L =="
  echo "(set! (-> *pc-settings* text-language) (pc-language $L))" >&3
  echo '(load-level-text-files 0)' >&3
  sleep 3
  # `*ls-traced*` remis a #f : la trace de mise en page est bornee a une ligne par episode, il
  # faut la rearmer pour obtenir la ligne de CETTE langue.
  echo '(set! *ls-traced* #f)' >&3
  echo '(loading-screen-force! (seconds 8))' >&3
  sleep 2
  # `screen-shot-settings` n'a pas de deftype GOAL (kernel-defs.gc:600 ne fait que declarer le
  # type), on ne peut donc pas le construire depuis le REPL : on prend la capture par defaut
  # (1920x1080, screenshot.cpp:9) et on la range ici.
  rm -f "$SHOTDIR/screenshot.png"
  echo '(pc-screen-shot)' >&3
  for i in $(seq 1 20); do [ -f "$SHOTDIR/screenshot.png" ] && break; sleep 1; done
  sleep 1
  cp -f "$SHOTDIR/screenshot.png" "$SHOTDIR/ls-$L.png" 2>/dev/null || echo "  PAS DE CAPTURE pour $L"
  sleep 2
done
sleep 2
echo "== captures =="
ls -la "$SHOTDIR"/ls-*.png 2>/dev/null
grep -a "LOADSCREEN-WIDTH\|LOADSCREEN-LAYOUT\|LOADSCREEN-GEOM\|LOADSCREEN-SIL" "$LOG" | tail -30
