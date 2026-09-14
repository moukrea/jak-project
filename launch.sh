#!/usr/bin/env bash
# launch.sh — start the autoport orchestrator in the foreground.
# Output is tee'd to .autoport/logs/orchestrator.log so you can replay it.
#
# Press Ctrl+C once for a graceful halt (finishes current attempt, then exits).
# State is persisted in .autoport/state.json so you can re-launch any time.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV="$HOME/.venv/autoport"

# Forward --quiet (and any future flags) to the orchestrator. Default is the
# new smart-compact live view; --quiet brings back the pre-2026-05 black-box
# behavior (only orchestrator status lines shown, claude's work silent).
ORCH_ARGS=()
for arg in "$@"; do
    if [ "$arg" = -q ]; then ORCH_ARGS+=(--quiet); else ORCH_ARGS+=("$arg"); fi
done
BACKEND="${AUTOPORT_BACKEND:-$(python3 "$REPO_ROOT/.autoport/lib/backend_control.py")}"
VERBOSE_LABEL="live"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --backend) BACKEND="${2:?--backend exige claude ou codex}"; shift ;;
        --backend=*) BACKEND="${1#*=}" ;;
        --quiet|-q) VERBOSE_LABEL="silent" ;;
        --check) ;;
        --help|-h)
            echo "Usage: ./launch.sh [--backend claude|codex] [--quiet] [--check]"
            echo "Défaut: AUTOPORT_BACKEND ou claude. --check ne lance aucun worker."
            exit 0 ;;
        *) echo "Argument inconnu: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$BACKEND" in claude|codex) ;; *) echo "Backend inconnu: $BACKEND" >&2; exit 2 ;; esac
if [[ " ${ORCH_ARGS[*]} " != *" --check "* ]]; then
    python3 "$REPO_ROOT/.autoport/lib/backend_control.py" "$BACKEND"
fi
export AUTOPORT_BACKEND="$BACKEND"

# LE PLAFOND D'ATTENTE DES TACHES DE FOND. Par defaut le CLI attend 600 s les taches de fond
# d'un worker qui a rendu la main, puis les TERMINE. Sur un item qui bati l'arm64 ou lance une
# course d'appareil, 600 s ne suffisent pas : l'essai est coupe au milieu, le validateur juge un
# arbre incoherent, et l'essai est COMPTE. Mesure du 2026-09-12 : quatre essais detruits comme ca
# — Grecharged-mesh-browser 6, refset-replay-stable 2, lighting-hdr 7, et lighting-legacy-purge 8,
# qui a epuise le budget d'un item que l'owner avait mis en priorite 17. On donne 45 minutes, pas
# l'infini : une tache de fond qui ne finit jamais doit finir par rendre la main.
export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-2700000}"

if ! [ -x "$VENV/bin/python" ]; then
    echo "ERROR: Python venv not found at $VENV" >&2
    echo "       Run sudo ./setup-fedora.sh first." >&2
    exit 1
fi

if [ "$BACKEND" = claude ] && [ ! -f "$HOME/.claude/.credentials.json" ]; then
    echo "ERROR: Claude Code is not authenticated." >&2
    echo "       Run 'claude' once interactively, sign in, then /quit." >&2
    exit 1
fi

for arg in "${ORCH_ARGS[@]}"; do
    if [ "$arg" = --check ]; then
        exec "$VENV/bin/python" "$REPO_ROOT/.autoport/orchestrator.py" "${ORCH_ARGS[@]}"
    fi
done
mkdir -p "$REPO_ROOT/.autoport/logs"
LOG="$REPO_ROOT/.autoport/logs/orchestrator.log"
STAMP=$(date +%Y%m%dT%H%M%S)
RUN_LOG="$REPO_ROOT/.autoport/logs/orchestrator-${STAMP}.log"

cat <<EOF
================================================================
  Autoport orchestrator -- foreground mode
================================================================
  Profil:    $(jq -r '.active' "$REPO_ROOT/.autoport/model-profiles.json" 2>/dev/null)
             (modele et effort: .autoport/model-profiles.json, source unique)
  CLI:       $BACKEND (permissions définies par ce backend)
  Verbose:   $VERBOSE_LABEL (--quiet pour le mode silencieux)
  Backlog:   ./.autoport/autoport status

  Live log:  $LOG
  Run log:   $RUN_LOG

  Ctrl+C once  -> graceful halt (finishes current attempt)
  Ctrl+C twice -> hard kill
================================================================
EOF

# Warn if running on battery
if [ -d /sys/class/power_supply ]; then
    AC_ONLINE=$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1 || echo "1")
    if [ "$AC_ONLINE" = "0" ]; then
        echo "WARNING: Laptop is on battery. Plug in for long runs." >&2
        echo
    fi
fi

# Warn about lid-close suspend (Fedora GNOME)
if command -v gsettings >/dev/null 2>&1; then
    LID_AC=$(gsettings get org.gnome.settings-daemon.plugins.power lid-close-ac-action 2>/dev/null | tr -d "'" || echo "unknown")
    if [ "$LID_AC" != "nothing" ] && [ "$LID_AC" != "unknown" ]; then
        echo "WARNING: lid-close-ac-action is '$LID_AC' (will suspend on lid close)."
        echo "         To disable during long runs:"
        echo "           gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'"
        echo "           gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing'"
        echo "         And in /etc/systemd/logind.conf:"
        echo "           HandleLidSwitch=ignore"
        echo "           HandleLidSwitchExternalPower=ignore"
        echo "           (then: sudo systemctl restart systemd-logind)"
        echo
    fi
fi

source "$VENV/bin/activate"
cd "$REPO_ROOT"

# python -u for unbuffered output so tee captures live progress.
set +e
python -u .autoport/orchestrator.py "${ORCH_ARGS[@]}" 2>&1 | tee -a "$LOG" "$RUN_LOG"
EXIT_CODE=${PIPESTATUS[0]}

echo
echo "Orchestrator exited with code $EXIT_CODE."
echo "Log preserved at: $RUN_LOG"
exit "$EXIT_CODE"
