#!/usr/bin/env bash
# Codex interactif au premier plan, veille autoport en arrière-plan.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
SUPERVISOR_ARGS=()
WATCH_ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --interval)
            WATCH_ARGS+=(--interval "${2:?--interval exige une durée en secondes}")
            shift ;;
        --help|-h)
            echo 'Usage: ./run-codex.sh [--resume UUID] [--interval SECONDES] [options Codex]'
            echo 'Ouvre Codex interactif et entretient le harnais en arrière-plan.'
            exit 0 ;;
        --check)
            exec bash "$REPO_ROOT/.autoport/supervisor.sh" --backend codex --check ;;
        *) SUPERVISOR_ARGS+=("$1") ;;
    esac
    shift
done

mkdir -p .autoport/logs
# Le hook du superviseur remplit ce fichier unique : la veille attend CETTE session.
SESSION_FILE=$(mktemp "$REPO_ROOT/.autoport/logs/supervisor-session-XXXXXX")
export AUTOPORT_SUPERVISOR_SESSION_FILE="$SESSION_FILE"
WATCH_PID=""
cleanup() {
    if [ -n "$WATCH_PID" ]; then
        kill "$WATCH_PID" 2>/dev/null || true
        wait "$WATCH_PID" 2>/dev/null || true
    fi
    rm -f "$SESSION_FILE"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

bash "$REPO_ROOT/.autoport/supervisor.sh" \
    --backend codex --watch --maintain --notify-supervisor \
    --session-file "$SESSION_FILE" "${WATCH_ARGS[@]}" \
    </dev/null >>.autoport/logs/supervisor-watch.log 2>&1 &
WATCH_PID=$!

# Pas de pipe ni de redirection : Codex garde le terminal et le clavier.
bash "$REPO_ROOT/.autoport/supervisor.sh" --backend codex "${SUPERVISOR_ARGS[@]}"
