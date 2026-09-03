#!/usr/bin/env bash
# Gloading-screen — HAUTEUR DE LA SILHOUETTE, MESUREE DANS L'IMAGE PRODUITE.
# Owner 2026-08-30 : « l'animation de Jak qui court devrait aussi occuper moins de hauteur ».
# On ne publie pas le resultat d'un calcul de mise en page : on mesure la boite du SUJET dans une
# capture, en n'allumant QUE la silhouette (le texte est a droite et le contaminerait — c'est le
# defaut symetrique qui avait fait passer une largeur de texte de 855 a 1 456 px au cycle
# precedent, quand la silhouette empietait sur la bande de texte).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
LOG="$OUT/sil-height.log"; GCLOG="$OUT/sil-height-goalc.log"; : > "$LOG"; : > "$GCLOG"
rm -f "$SHOTDIR/sil.png" "$SHOTDIR/screenshot.png"
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null || true; kill "$GKPID" 2>/dev/null
           [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 150); do grep -qaE "link finish: default-menu" "$LOG" && break; sleep 1; done
sleep 3
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 300); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
# La silhouette vit a GAUCHE (centre x = 0,272) et le texte a DROITE (bord 0,882) : la mesure se
# restreint a x < 950 sur 1920, ce qui les separe sans avoir a eteindre quoi que ce soit.
echo '(set! *ls-draw-silhouette* #t)' >&3
echo '(loading-screen-force! (seconds 10))' >&3
sleep 2
echo '(pc-screen-shot)' >&3
for i in $(seq 1 20); do [ -f "$SHOTDIR/screenshot.png" ] && break; sleep 1; done
sleep 1
cp -f "$SHOTDIR/screenshot.png" "$SHOTDIR/sil.png" 2>/dev/null || echo "PAS DE CAPTURE"
sleep 1
grep -a "LOADSCREEN-SIL\|LOADSCREEN-SHOW" "$LOG" | tail -3
