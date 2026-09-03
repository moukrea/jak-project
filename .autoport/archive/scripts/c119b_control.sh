#!/usr/bin/env bash
# CYCLE 119b — CONTROLE P4 : le cliquet est un COMPTEUR, la course doit etre INCHANGEE.
# DIRECTIVES vd9e8b66782
#
# Le lot ajoute `*phys-dfsm*` (trois maximums) et l'emetteur `PHYSORI5`. Aucun de ces deux
# gestes n'ecrit une variable d'etat du solveur. Si la course change ailleurs que sur les
# lignes `PHYSORI5`, l'edition a touche autre chose qu'un compteur — et TOUS les chiffres que
# le cycle 119 a publies sur la course de reference sont a relire.
# SEUIL DECLARE D'AVANCE (c119b-predictions.txt, P4) : <= 2 lignes `PHYS*` differentes.
set -u
R=.autoport/reports/Grecharged-secondary-motion
NEW="$R/keira-room-x86.log"
REF="$R/keira-room-x86.c118-REF.log"
for f in "$NEW" "$REF"; do [ -s "$f" ] || { echo "FAIL: $f absent ou vide"; exit 2; }; done
# On ne compare que les lignes d'ENREGISTREMENT (`PHYS*` en debut de ligne) : la banniere de
# demarrage porte des adresses de tas qui changent a chaque lancement et ne mesurent rien.
grep -a '^PHYS' "$NEW" | grep -av '^PHYSORI5 ' > /tmp/c119b_new.txt
grep -a '^PHYS' "$REF" | grep -av '^PHYSORI5 ' > /tmp/c119b_ref.txt
n_new=$(wc -l < /tmp/c119b_new.txt); n_ref=$(wc -l < /tmp/c119b_ref.txt)
n_diff=$(diff /tmp/c119b_ref.txt /tmp/c119b_new.txt | grep -c '^[<>]')
n_ori5=$(grep -ac '^PHYSORI5 ' "$NEW")
echo "lignes PHYS* hors PHYSORI5 : reference $n_ref   nouvelle $n_new"
echo "lignes PHYSORI5 (neuves)   : $n_ori5"
echo "lignes differentes          : $n_diff   (seuil declare : 2)"
if [ "$n_diff" -gt 2 ]; then
  echo "P4 REFUTEE — le lot a change la course ailleurs que sur son compteur. Extrait :"
  diff /tmp/c119b_ref.txt /tmp/c119b_new.txt | head -20
  exit 1
fi
echo "P4 TENUE — la course est inchangee hors l'emetteur neuf."
