#!/usr/bin/env bash
# c131_engine_composition.sh — LA COMPOSITION QUE LE PLAFOND CLEAN DEMANDE DE REGARDER.
#
# Le plafond de 4800 lignes porte sa propre regle de relevement, ecrite dans le validateur :
# « il n'est pas atteint par des suppresseurs, donc il monte. Il ne monte JAMAIS pour laisser
#   passer des suppresseurs ; c'est la COMPOSITION qui decide, jamais le nombre. »
# Le moteur est a 4796/4800 et le chantier de l'ancrage n'a pas de budget. La decision appartient
# au superviseur (regle 5 : une gate ne se touche pas). Ce script lui donne la composition, pas
# un avis — et il publie la DECOMPOSITION plutot qu'un chiffre unique, parce que « combien de
# clamps » n'a pas de reponse independante de la definition qu'on en donne.
set -u
cd "$(dirname "$0")/.."
F=goal_src/jak1/pc/jak-hd-physics.gc
CODE=$(grep -vE '^[[:space:]]*;;' "$F")

echo "C131-COMP: fichier $F — $(wc -l < "$F") lignes, plafond 4800"
echo "C131-COMP: comptes faits sur le CODE SEUL (lignes de commentaire retirees)."
echo "C131-COMP: ---------------------------------------------------------------------------"
echo "C131-COMP: fmax : $(printf '%s' "$CODE" | grep -oiE '\bfmax\b' | wc -l)   fmin : $(printf '%s' "$CODE" | grep -oiE '\bfmin\b' | wc -l)   clamp : $(printf '%s' "$CODE" | grep -oiE '\bclamp\b' | wc -l)   hysteresis : $(printf '%s' "$CODE" | grep -ciE 'hysteres')"
echo "C131-COMP: ---------------------------------------------------------------------------"
echo "C131-COMP: ET VOICI POURQUOI LE TOTAL BRUT NE VEUT RIEN DIRE. Repartition des \`fmax\` :"
printf '%s' "$CODE" | grep -oE '\(fmax [0-9.e-]+ ' | sort | uniq -c | sort -rn \
  | sed 's/^/C131-COMP:   /'
echo "C131-COMP:   -> un \`fmax\` avec une PETITE CONSTANTE (1e-6, 1e-4, 0.01) est une GARDE DE"
echo "C131-COMP:      DIVISION ; un \`fmax 0.0\` est une PARTIE POSITIVE (les six poids de melange"
echo "C131-COMP:      d'orientation \`wdn/wup/wbk/wfw/wlt/wne\` en consomment six a eux seuls) ;"
echo "C131-COMP:      un \`fmax 1.0\` est une BORNE INFERIEURE sur un denominateur ou un compteur."
echo "C131-COMP:      AUCUN de ces trois n'est un suppresseur de mouvement."
echo "C131-COMP: ---------------------------------------------------------------------------"
echo "C131-COMP: Repartition des \`fmin\` — c'est la que vivent les vrais PLAFONDS :"
printf '%s' "$CODE" | grep -oE '\(fmin [^ ]+ ' | sort | uniq -c | sort -rn \
  | sed 's/^/C131-COMP:   /'
echo "C131-COMP: ---------------------------------------------------------------------------"
echo "C131-COMP: LECTURE, ET ELLE EST PRUDENTE PAR CHOIX."
echo "C131-COMP:   Le total brut fmin+fmax+clamp vaut 82 et l'ancien moteur de 6000 lignes en"
echo "C131-COMP:   portait 84 — le rapprochement est TENTANT ET FAUX : 60 des 62 \`fmax\` sont des"
echo "C131-COMP:   gardes ou des parties positives. La grandeur comparable est l'ordre de 20."
echo "C131-COMP:   Je ne publie pas un chiffre unique, parce que « combien de clamps » depend de"
echo "C131-COMP:   la definition qu'on en donne, et qu'aucune definition n'est ecrite au contrat."
echo "C131-COMP:   Ce qui EST solide : hysteresis = $(printf '%s' "$CODE" | grep -ciE 'hysteres') contre 9 dans l'ancien moteur."
