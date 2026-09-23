#!/usr/bin/env bash
# Launch the autoport supervisor — a fresh Claude Code session whose
# job is to watch the autoport orchestrator and call out its cheats.
#
# Run in its OWN terminal, separate from `./launch.sh`. The supervisor
# spawns the orchestrator itself when ready.
#
# Usage:
#   ./.autoport/supervisor.sh         # interactive
#   ./.autoport/supervisor.sh --quiet # less output from claude itself

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# CLI selection is per process; it never rewrites the other provider's profile.
BACKEND="${AUTOPORT_BACKEND:-$(python3 "$REPO_ROOT/.autoport/lib/backend_control.py")}"
ARGS=()
WATCH=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --backend) BACKEND="${2:?--backend exige claude ou codex}"; shift ;;
        --backend=*) BACKEND="${1#*=}" ;;
        --watch) WATCH=1 ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done
case "$BACKEND" in claude|codex) ;; *) echo "Backend inconnu: $BACKEND" >&2; exit 2 ;; esac
if [[ " ${ARGS[*]} " != *" --check "* ]]; then
    python3 "$REPO_ROOT/.autoport/lib/backend_control.py" "$BACKEND"
fi
export AUTOPORT_BACKEND="$BACKEND"
if [ "$WATCH" = 1 ]; then
    exec python3 .autoport/watch.py --backend "$BACKEND" "${ARGS[@]}"
fi
if [ "$BACKEND" = codex ]; then
    exec python3 .autoport/codex/supervisor.py "${ARGS[@]}"
fi
export AUTOPORT_ROLE=supervisor
set -- "${ARGS[@]}"

PROMPT_FILE=".autoport/SUPERVISOR_PROMPT.md"

if ! [ -f "$PROMPT_FILE" ]; then
    echo "ERROR: $PROMPT_FILE missing." >&2
    echo "       Run from repo root; the supervisor prompt should be" >&2
    echo "       at $PROMPT_FILE." >&2
    exit 1
fi

# Le JOURNAL de superviseur (buckets A-F, ere de mai) est mort depuis le 2026-06-18 et a ete
# archive le 2026-09-03. L'etat vit desormais dans `.autoport/backlog.yaml`, lisible par
# `./.autoport/autoport status`. On ne fabrique plus de fichier que personne ne lit.

cat <<EOF
================================================================
  Superviseur autoport — session Claude Code separee
================================================================
  Role     : traduire les messages de l'owner en items de backlog,
             poser ses validations, arbitrer, rendre compte.
             Le superviseur n'edite PAS le moteur et ne touche AUCUN appareil.
  Contrat  : $PROMPT_FILE
  Backlog  : .autoport/backlog.yaml   (./.autoport/autoport status)
  Plan     : .autoport/plans/2026-09-03-remise-d-equerre.md

  Pour demarrer :  ./.autoport/autoport status
  L'orchestrateur se lance seul par ./launch.sh et prend le premier item \`open\`.
================================================================
EOF

# LE MODELE DU SUPERVISEUR VIENT DU PROFIL ACTIF, ET DE NULLE PART AILLEURS (JAK-265, 23/09).
# MARQUEUR: modele-banni-refuse-2026-09-23
# Jusqu'au 23/09 ce lanceur portait un repli EN DUR (`SUP_MODEL=${SUP_MODEL:-<modele>}`) : sans
# jq, ou avec une variable heritee, le superviseur partait sur un modele que le profil ne nommait
# pas — Opus 5 le 23/09, que l'owner venait de bannir. Plus aucun nom de modele ici :
# `lib/model_profile.py supervisor-env` resout le profil ACTIF (champs `supervisor_model` /
# `supervisor_effort`, `worker_model` pour les sous-agents) et REFUSE un profil incomplet ou un
# modele de `banned_models`. Refus = pas de lancement, jamais un repli.
# Changer le modele ou l'effort : `./.autoport/autoport profile set supervisor --model M --effort E`.
if ! _SUP_ENV="$(python3 "$REPO_ROOT/.autoport/lib/model_profile.py" supervisor-env)"; then
    echo "[supervisor] DEMARRAGE REFUSE : profil de modele non resolu ou modele banni (ci-dessus)." >&2
    echo "[supervisor] Corrige .autoport/model-profiles.json ou \`autoport profile set\`, puis relance." >&2
    exit 1
fi
eval "$_SUP_ENV"
_ACTIVE="$SUP_PROFILE"
export CLAUDE_EFFORT="$SUP_EFFORT"
export CLAUDE_CODE_SUBAGENT_MODEL="$SUB_MODEL"
# FORCE : sans elle, le parametre `model` d'un appel Agent (« fable ») ou un `model:` de frontmatter
# passe AVANT CLAUDE_CODE_SUBAGENT_MODEL (doc Claude Code, sous-agents). Avec elle, tout sous-agent,
# coequipier ou agent de workflow tourne sur le modele du profil.
export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1
echo "[supervisor] profile=$_ACTIVE model=$SUP_MODEL ($SUP_MODEL_FIELD) effort=$SUP_EFFORT workers=$SUB_MODEL (force)"

# Meme si le profil actif porte encore `[1m]`, on le RETIRE ici : le point de
# production est ce lanceur, et une fenetre 1M sans compaction est ce qui fait
# relire 562 k jetons a chaque appel.
_SUP_MODEL_BEFORE="$SUP_MODEL"
SUP_MODEL="${SUP_MODEL%\[1m\]}"
if [ "$SUP_MODEL" != "$_SUP_MODEL_BEFORE" ]; then
    echo "[supervisor] suffixe [1m] retire : $_SUP_MODEL_BEFORE -> $SUP_MODEL (compaction reactivee)"
fi

# `AUTOPORT_SUPERVISOR_DRYRUN=1` : tout est resolu et affiche, rien n'est lance ni journalise.
# C'est le banc de la porte des modeles bannis (lib/census/<id>.sh) : il rejoue CE lanceur.
if [ "${AUTOPORT_SUPERVISOR_DRYRUN:-0}" = 1 ]; then
    echo "[supervisor] DRYRUN model=$SUP_MODEL effort=$SUP_EFFORT workers=$SUB_MODEL force=$CLAUDE_CODE_SUBAGENT_MODEL_FORCE"
    exit 0
fi

# Fenetre de compaction automatique. C'est la valeur qui DESIGNE la population
# « apres » dans le journal de lancements ci-dessous.
AUTOCOMPACT="${AUTOPORT_SUPERVISOR_AUTOCOMPACT:-150000}"

# Une ligne par lancement, en append. Elle sert de population a la porte de
# l'item harness-supervisor-cost-counter.
mkdir -p "$REPO_ROOT/.autoport/logs"
AUTOPORT_LAUNCH_LOG="${AUTOPORT_LAUNCH_LOG:-$REPO_ROOT/.autoport/logs/supervisor-launches.jsonl}"
_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
python3 -c '
import datetime, json, sys
model, effort, autocompact, commit, pid, path = sys.argv[1:7]
rec = {
    "date": datetime.date.today().isoformat(),
    "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "pid": int(pid),
    "model": model,
    "effort": effort,
    # `--autocompact` accepte aussi le mot « auto » : on ecrit un NOMBRE quand la valeur en
    # est un, la chaine sinon. Un int() nu tuerait le lanceur AVANT son exec sur « auto ».
    "autocompact": int(autocompact) if autocompact.isdigit() else autocompact,
    "commit": commit,
}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
' "$SUP_MODEL" "$SUP_EFFORT" "$AUTOCOMPACT" "$_COMMIT" "$$" "$AUTOPORT_LAUNCH_LOG"

# PREUVE POSITIVE D'ETRE LE SUPERVISEUR (23/09) : ce pid sera la session claude apres `exec`
# (meme processus, meme starttime). Seule une identite declaree ici — ou par le registre, ou par
# un reveil — peut tamponner `.supervisor-seen.json`.
python3 .autoport/lib/supervisor_alive.py declare-launcher "$$" || true

exec claude \
    --model "$SUP_MODEL" \
    --effort "$SUP_EFFORT" \
    --autocompact "$AUTOCOMPACT" \
    --append-system-prompt "$(cat "$PROMPT_FILE")" \
    --dangerously-skip-permissions \
    "$@"
