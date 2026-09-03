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
VERBOSE_LABEL="live"
for arg in "$@"; do
    case "$arg" in
        --quiet|-q)
            ORCH_ARGS+=("--quiet")
            VERBOSE_LABEL="silent"
            ;;
        --help|-h)
            cat <<USAGE
Usage: ./launch.sh [--quiet|-q]

  --quiet, -q   suppress live event rendering from claude (silent mode).
                Default is the live smart-compact view; raw JSONL is always
                preserved in .autoport/logs/{phase}/attempt-NN.jsonl.
USAGE
            exit 0
            ;;
    esac
done

if ! [ -x "$VENV/bin/python" ]; then
    echo "ERROR: Python venv not found at $VENV" >&2
    echo "       Run sudo ./setup-fedora.sh first." >&2
    exit 1
fi

if [ ! -f "$HOME/.claude/.credentials.json" ]; then
    echo "ERROR: Claude Code is not authenticated." >&2
    echo "       Run 'claude' once interactively, sign in, then /quit." >&2
    exit 1
fi

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
  Perms:     --dangerously-skip-permissions
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
python -u .autoport/orchestrator.py "${ORCH_ARGS[@]}" 2>&1 | tee -a "$LOG" "$RUN_LOG"
EXIT_CODE=${PIPESTATUS[0]}

echo
echo "Orchestrator exited with code $EXIT_CODE."
echo "Log preserved at: $RUN_LOG"
exit "$EXIT_CODE"
