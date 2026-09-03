#!/usr/bin/env bash
# session-start.sh — bandeau de contexte injecte dans le worker (stdout = contexte Claude).
set -euo pipefail

# Garde de portee : seules les sessions lancees par l'orchestrateur recoivent ce bandeau
# (c'est lui qui pose AUTOPORT_PHASE_ID). Une session interactive n'est pas headless.
[ -n "${AUTOPORT_PHASE_ID:-}" ] || exit 0

# Un seul worker par tache. Ce hook est re-execute a chaque lancement, par n'importe quel
# orchestrateur deja lance ou non : c'est le point de production du doublon, donc c'est ici
# que ca se ferme. On ne tue rien, on informe le doublon avant qu'il touche un fichier.
CLAIM_RC=0
HOLDER=$(bash "$CLAUDE_PROJECT_DIR/.autoport/phase_claim.sh" claim "$AUTOPORT_PHASE_ID") || CLAIM_RC=$?
if [ "$CLAIM_RC" -eq 3 ]; then
    cat <<EOM
## ARRET IMMEDIAT — un autre worker tient deja **$AUTOPORT_PHASE_ID** ($HOLDER)

Deux workers sur le meme arbre se detruisent mutuellement. Tu n'edites rien, tu ne compiles
rien, tu ne lances aucune course : tu rapportes en une phrase que la tache est tenue, et tu
t'arretes.
EOM
    exit 0
fi

VALIDATOR="${AUTOPORT_PHASE_VALIDATOR:-$CLAUDE_PROJECT_DIR/.autoport/validators/generic.sh}"
cat <<EOM
## Tache en cours : **$AUTOPORT_PHASE_ID**

* Porte de sortie : \`bash ${VALIDATOR#"$CLAUDE_PROJECT_DIR"/}\`
* Prefixe de commit : \`[autoport/$AUTOPORT_PHASE_ID]\`
* Pas d'humain dans la boucle : tu decides et tu finis, tu ne demandes pas.

Ton perimetre est dans le prompt qui suit. S'il n'y est pas, dis-le au lieu d'improviser.
EOM
