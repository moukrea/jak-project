#!/usr/bin/env bash
# Gcutscene-npc-flicker — GARDE DE NON-REGRESSION. Deux bras, tous deux sans appareil.
#
#   BRAS 1  l'instrument fonctionne : 9 proprietes de game/system/npc_flicker.cpp, chacune avec
#           son controle positif (le compteur MONTE) et son controle negatif (il ne monte pas).
#   BRAS 3  le seau FOURRE-TOUT de classify() n'est pas un seau EXCUSE. C'est le bras ajoute au
#           cycle 2 : `culled` etait a la fois le repli de classify() et une cause declaree
#           NON-DEFAUT, donc tout etat non prevu tombait dans un compteur qui ne fait jamais
#           monter `cycles`. Sur les sept courses du cycle 1 ce seau portait TOUS les episodes
#           (37 a 106 par course) pendant que le rapport publiait `cycles=0`.
#   BRAS 2  aucun compteur PUBLIE n'est structurellement mort. C'est le bras qui manquait :
#           `s_hd_blackout_events` etait declare, imprime dans `[hd-flicker] blackouts=...`, et
#           jamais incremente depuis 45b7140ca7. Trois jambes de preuve exigeaient `blackouts=0`,
#           une clause qu'aucun chemin de code ne pouvait violer — et le defaut est revenu sans
#           qu'aucune porte ne s'ouvre.
#
# ECHOUE SI : une propriete de l'instrument tombe, OU un compteur declare `static u64 s_...` est
# lu par une ligne de journal sans qu'aucun site ne l'incremente, OU le repli de `classify()` nomme
# une cause que `reason_is_defect` excuse.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
FAIL=0

echo "===== BRAS 1 — proprietes de l'instrument ====="
g++ -std=c++17 -O1 -Wall -Wextra -Werror -I. -Ithird-party/fmt/include -DFMT_HEADER_ONLY=1 \
    .autoport/npc_flicker_selftest.cpp game/system/npc_flicker.cpp \
    -o /tmp/npc_flicker_selftest || { echo "[GARDE FAIL] compilation"; exit 1; }
/tmp/npc_flicker_selftest || FAIL=1

echo
echo "===== BRAS 2 — aucun compteur publie n'est mort ====="
python3 .autoport/npcf_dead_counter_gate.py || FAIL=1

echo
echo "===== BRAS 3 — le fourre-tout de classify() n'excuse pas ====="
python3 .autoport/npcf_catchall_gate.py || FAIL=1

echo
if [ "$FAIL" = 0 ]; then
  echo "NPCGUARD nom=npc-flicker-selftest resultat=PASS"
else
  echo "NPCGUARD nom=npc-flicker-selftest resultat=FAIL"
fi
exit "$FAIL"
