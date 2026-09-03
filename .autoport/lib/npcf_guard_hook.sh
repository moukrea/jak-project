#!/usr/bin/env bash
# Gcutscene-npc-flicker — le crochet POST_BUILD de `gk` (x86 ET arm64/Android).
#
# Il lance .autoport/lib/npc_flicker_selftest.sh. Deux sorties possibles seulement :
#   0  la garde passe (ou elle est explicitement desarmee par OG_SKIP_NPCF_GUARD=1)
#   1  la garde MORD : le lien de `gk` echoue, et le message dit quoi reparer.
#
# Pourquoi ici et pas dans un validateur de phase : un validateur de phase ne tourne que pendant
# SA phase. Les trois scripts de preuve de Grecharged-hd-models4/5 n'ont jamais ete rappeles par
# personne, et c'est pour ca que le defaut est revenu sans qu'aucune porte ne s'ouvre.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ "${OG_SKIP_NPCF_GUARD:-0}" = "1" ]; then
  echo "[npc-flicker] garde DESARMEE par OG_SKIP_NPCF_GUARD=1 — assume et non par defaut"
  exit 0
fi
if ! command -v g++ >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "[npc-flicker] g++ ou python3 absent — garde non executable, on n'invente pas un vert"
  exit 0
fi

OUT=$(bash .autoport/lib/npc_flicker_selftest.sh 2>&1)
if [ $? -eq 0 ]; then
  echo "[npc-flicker] garde OK — $(printf '%s' "$OUT" | grep -c '^\[ok\]') proprietes tenues"
  exit 0
fi
printf '%s\n' "$OUT" | tail -30
cat >&2 <<'EOF'

[npc-flicker] LA GARDE DE NON-REGRESSION A MORDU.

Le clignotement des PNJ en cinematique est deja revenu UNE FOIS parce que sa garde
(`[hd-flicker] blackouts=0`) ne pouvait pas echouer : son compteur n'avait plus aucun site
d'ecriture. Cette garde-ci verifie TROIS choses, et l'une des trois vient de tomber :
  1. les proprietes du recensement (game/system/npc_flicker.cpp), chacune avec son controle
     positif — le compteur doit MONTER quand on lui injecte une disparition ;
  2. aucune valeur imprimee dans une ligne de journal n'est ecrite nulle part hors de sa
     declaration ;
  3. le repli de `classify()` — le cas « je ne sais pas nommer cet etat » — ne nomme pas une
     cause que `reason_is_defect` EXCUSE. C'etait la faute du cycle 1 : `culled` etait a la fois
     le fourre-tout et un non-defaut, il portait 100 % des episodes des sept courses archivees,
     et le rapport publiait `cycles=0` pendant que l'owner revoyait le defaut.
Repare la cause, ou desarme explicitement avec OG_SKIP_NPCF_GUARD=1 en le disant dans ton rapport.
EOF
exit 1
