#!/usr/bin/env bash
# UserPromptSubmit — la veille sans modele (voir lib/wake_gate.py).
#
# Ce crochet voit TOUS les prompts de TOUTES les sessions de ce depot : workers, superviseur,
# owner. Il ne s'interesse qu'aux REVEILS AUTOMATIQUES du superviseur et laisse passer tout
# le reste sans meme le lire. Il ne peut pas bloquer par accident : Claude Code ne refuse un
# prompt que sur le code 2, et tout autre code — y compris un plantage — le laisse passer.
#
# Code 2 = reveil refuse, aucun appel API. Code 0 + JSON = reveil autorise, avec ce que la
# veille a deja mesure joint au prompt.
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
exec python3 "$ROOT/.autoport/lib/wake_gate.py"
