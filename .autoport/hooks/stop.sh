#!/usr/bin/env bash
# stop.sh — CONSULTATIF. Il montre ce que dit le validateur, et il laisse sortir.
#
# POURQUOI IL NE BLOQUE PLUS. Tant qu'il refusait la sortie jusqu'au vert, le chemin le plus
# court vers le vert etait d'ecrire dans le rapport la ligne que le validateur cherchait —
# c'est le « chemin du printf », le mode d'echec que les notes enregistrent depuis la phase 20.
# Il a aussi tourne PENDANT des courses de 25 minutes (« trace absente » lu comme « il n'a rien
# fait »), et il a parque la boucle 14 h sur une porte que seul un humain pouvait ouvrir.
# Le verdict qui compte est celui que l'ORCHESTRATEUR prend apres la sortie, sur le meme
# validateur. Ce hook informe ; il n'arbitre pas.
#
# Sortie : TOUJOURS 0.
set -uo pipefail

# Portee : ce hook ne s'adresse qu'aux sessions lancees par l'orchestrateur (il pose
# AUTOPORT_PHASE_ID avant d'exec claude). Une session interactive dans le meme depot n'a
# pas a lire le verdict d'un item qu'elle n'essaie pas de fermer.
[ -n "${AUTOPORT_PHASE_ID:-}" ] || exit 0

INPUT=$(cat 2>/dev/null || true)
# stop_hook_active : le hook est deja en train de tourner, on ne s'empile pas.
if command -v jq >/dev/null 2>&1; then
  [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
fi

V="${CLAUDE_PROJECT_DIR:-.}/.autoport/validators/generic.sh"
[ -f "$V" ] || exit 0

OUT=$(AUTOPORT_PHASE_ID="$AUTOPORT_PHASE_ID" bash "$V" 2>&1); RC=$?
{
  if [ "$RC" = 0 ]; then
    echo "[stop] validateur generic.sh : VERT pour $AUTOPORT_PHASE_ID."
  else
    echo "[stop] validateur generic.sh : ROUGE pour $AUTOPORT_PHASE_ID (sortie $RC). Pour information :"
  fi
  printf '%s\n' "$OUT" | tail -n 40
  if [ "$RC" != 0 ]; then
    echo "[stop] Rien ne t'empeche de sortir. Si la preuve manque, elle se PRODUIT :"
    echo "       .autoport/lib/proof_run.sh $AUTOPORT_PHASE_ID x86     (ou 'device')"
    echo "       Elle ne s'ecrit pas a la main : le validateur recalcule le sha du binaire."
  fi
} 2>&1
exit 0
