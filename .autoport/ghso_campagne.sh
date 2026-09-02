#!/usr/bin/env bash
# Ghd-skin-origin-stretch — LA CAMPAGNE : deux bras, MEME BINAIRE, MEME ITINERAIRE, MEME INSTRUMENT.
#   bras CONTROLE (ARM=0) : le garde est desarme depuis la REPL -> le defaut d'origine tire
#   bras PREUVE   (ARM=1) : le garde est arme                   -> il ne doit plus rien tirer
# Ce qui change entre les deux est UN SYMBOLE GOAL, rien d'autre. C'est ce qui rend le
# `episodes=0` du bras de preuve falsifiable.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Ghd-skin-origin-stretch
REF=/home/emeric/.autoport-scratch/ghso-iso-ref
LOCK=.autoport/.deploy-in-progress

# ---------------------------------------------------------------------------------------------
# L'ISO EST BATI UNE FOIS, ICI, ET LES DEUX JAMBES PARTENT DE LA MEME COPIE.
# Deux raisons, et la premiere a coute deux courses completes :
#   1. `(build-game)` depuis le listener compile vers out/jak1/obj — le jeu, lui, tourne sur le
#      GAME.CGO de l'iso. Sans `(mi)`, les jambes mesurent le code de la DERNIERE livraison, pas
#      celui qu'on vient d'ecrire ;
#   2. l'auto-constructeur peut refaire out/jak1/iso en ARM64 entre deux jambes. Les deux bras
#      d'une ablation doivent tourner sur le MEME binaire : on fige donc une copie de reference.
# ---------------------------------------------------------------------------------------------
printf 'ghso_campagne pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
# `jak-hd.gc` est liste dans DEUX dgos — `dgos/game.gd` ET `dgos/engine.gd`. Ne rebatir que l'un
# des deux livrerait un melange. `(mi)` batirait les deux mais echoue sur des assets audio absents
# de cet arbre (out/jak1/iso/MUS/ n'existe pas), donc on nomme les deux cibles.
echo "$(date +%H:%M:%S) == build GAME.CGO + ENGINE.CGO =="
printf '(make "$OUT/iso/GAME.CGO")\n(make "$OUT/iso/ENGINE.CGO")\n(e)\n' \
  | timeout 1800 build-x86/goalc/goalc --game jak1 --proj-path . \
    --iso-path out/jak1/iso --disable-ansi > /tmp/ghso-mi.log 2>&1
if [ "$(grep -ac 'Successfully built all' /tmp/ghso-mi.log)" -lt 2 ]; then
  echo "BUILD CGO ECHOUE"; tail -30 /tmp/ghso-mi.log; exit 1
fi
# CONTROLE DE FRAICHEUR, ET IL A COUTE DEUX COURSES : le marqueur HDSPJ n'existe que dans le code
# de ce cycle. `(build-game)` depuis le listener compile vers out/jak1/obj et NE LIVRE RIEN au jeu,
# qui tourne sur les CGO de l'iso — le 2026-09-02 a 05:23, deux courses completes ont mesure un
# GAME.CGO de 04:46, anterieur a toute edition du jour, sans que rien ne le signale.
for f in GAME ENGINE; do
  if ! grep -qa "HDSPJ" "out/jak1/iso/$f.CGO"; then
    echo "$f.CGO NE CONTIENT PAS LE CODE DU CYCLE (HDSPJ absent) — campagne annulee"; exit 1
  fi
done
rm -rf "$REF"; cp -a --reflink=auto out/jak1/iso "$REF"
echo "$(date +%H:%M:%S) == iso de reference fige : $(md5sum "$REF/GAME.CGO" | cut -c1-12) =="
rm -f "$LOCK"; trap - EXIT

ISO="$REF" ARM=0 TAG=ctl2 bash .autoport/ghso_x86_leg.sh
sleep 10
ISO="$REF" ARM=1 TAG=prf  bash .autoport/ghso_x86_leg.sh
python3 .autoport/ghso_analyse.py "$OUT/ctl2-marqueurs.txt" > "$OUT/ctl2-analyse.txt" 2>&1
python3 .autoport/ghso_analyse.py "$OUT/prf-marqueurs.txt"  > "$OUT/prf-analyse.txt"  2>&1
echo "CAMPAGNE TERMINEE"
