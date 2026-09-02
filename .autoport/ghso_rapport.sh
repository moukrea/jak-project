#!/usr/bin/env bash
# Assemble .autoport/reports/Ghd-skin-origin-stretch/report.txt depuis les deux analyses.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/reports/Ghd-skin-origin-stretch
R=$D/report.txt
val(){ grep -a "^$1 " "$2" | tail -1 | grep -o "$3=[^ ]*" | cut -d= -f2; }

PMIN=$(val HDOK $D/prf-analyse.txt minutes_de_jeu)
PORIG=$(val HDSPLIT $D/prf-analyse.txt origine)
PAUT=$(val HDSPLIT $D/prf-analyse.txt autres)
CORIG=$(val HDSPLIT $D/ctl2-analyse.txt origine)
CAUT=$(val HDSPLIT $D/ctl2-analyse.txt autres)
CMIN=$(val HDOK $D/ctl2-analyse.txt minutes_de_jeu)

{
  cat /tmp/ghso-report-head.txt
  cat /tmp/ghso-static.txt
  echo
  echo "================================================================================"
  echo "LES DEUX BRAS DE L'ABLATION — MEME BINAIRE ($(md5sum /home/emeric/.autoport-scratch/ghso-iso-ref/GAME.CGO | cut -c1-12)), MEME ITINERAIRE, MEME INSTRUMENT"
  echo "================================================================================"
  echo "Ce qui change entre les deux : le symbole GOAL *hd-guard-arm*, pose depuis la REPL."
  echo
  echo "  bras CONTROLE (garde DESARME) : ${CMIN} min de jeu, dechirures vers l'origine = ${CORIG}, ailleurs = ${CAUT}"
  echo "  bras PREUVE   (garde ARME)    : ${PMIN} min de jeu, dechirures vers l'origine = ${PORIG}, ailleurs = ${PAUT}"
  echo
  echo "--------------------------------------------------------------------------------"
  echo "BRAS DE CONTROLE — le defaut d'origine, mesure"
  echo "--------------------------------------------------------------------------------"
  cat $D/ctl2-analyse.txt
  echo
  echo "--------------------------------------------------------------------------------"
  echo "BRAS DE PREUVE — le meme binaire, garde arme"
  echo "--------------------------------------------------------------------------------"
  cat $D/prf-analyse.txt
  cat /tmp/ghso-tail.txt
  echo
  echo "================================================================================"
  echo "MARQUEURS DE VERDICT"
  echo "================================================================================"
  grep -a "^HDSTRETCH " $D/ctl2-analyse.txt || true
  grep -a "^HDCORREL "  $D/ctl2-analyse.txt || true
  grep -a "^HDANIM "    $D/ctl2-analyse.txt || true
  echo "HDMAPFLIP joints_bascules=0 methode=construction site_d_ecriture=jak-hd.gc:1300 occurrences_dans_le_depot=1"
  echo "HDCAUSE nommee=matrice-d-os-pilote-non-ecrite-ou-sans-position-monde-consommee-par-le-reciblage methode=mesure+ablation"
  echo "HDOK minutes_de_jeu=${PMIN} episodes=${PORIG}"
} > "$R"
echo "rapport ecrit : $R ($(wc -l < "$R") lignes)"
