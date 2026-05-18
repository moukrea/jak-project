#!/usr/bin/env bash
# install.sh — wire up the autoport into a forked jak-project repo.
# Run from the repo root (where CMakeLists.txt lives) after extracting the dropin.

set -euo pipefail

REPO_ROOT="$(pwd)"
AUTOPORT_DIR="$REPO_ROOT/.autoport"

if [ ! -f "$REPO_ROOT/CMakeLists.txt" ] || [ ! -d "$AUTOPORT_DIR" ]; then
    echo "ERROR: Run this from the jak-project repo root after extracting" >&2
    echo "       the autoport dropin (must contain .autoport/ and CMakeLists.txt)." >&2
    exit 1
fi

NTFY_TOPIC=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ntfy)
            NTFY_TOPIC="$2"
            shift 2
            ;;
        --slack)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        *)
            echo "Unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "  Autoport repo-level install"
echo "  Repo: $REPO_ROOT"
echo "=========================================="

# --- 1. Verify host tools ---
echo
echo "[1/5] Checking host tools..."
need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "  MISSING: $1 (run sudo ./setup-fedora.sh first)" >&2
        return 1
    fi
    echo "  ok: $1"
}
MISSING=0
for tool in claude jq yq python3 cmake ninja git qemu-aarch64-static; do
    need "$tool" || MISSING=1
done
# tmux is optional (orchestrator runs in foreground)
if command -v tmux >/dev/null 2>&1; then
    echo "  ok: tmux (optional, not required)"
fi
if [ "$MISSING" -ne 0 ]; then
    echo "Some tools missing. Run sudo ./setup-fedora.sh first." >&2
    exit 1
fi

# Verify Claude Code version >= 2.1.139
CC_VER=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
CC_MAJ=$(echo "$CC_VER" | cut -d. -f1)
CC_MIN=$(echo "$CC_VER" | cut -d. -f2)
CC_PATCH=$(echo "$CC_VER" | cut -d. -f3)
if [ "$CC_MAJ" -lt 2 ] || \
   { [ "$CC_MAJ" -eq 2 ] && [ "$CC_MIN" -lt 1 ]; } || \
   { [ "$CC_MAJ" -eq 2 ] && [ "$CC_MIN" -eq 1 ] && [ "$CC_PATCH" -lt 139 ]; }; then
    echo "  WARNING: Claude Code $CC_VER < 2.1.139. Hooks/rate-limit fields may not be available." >&2
    echo "           Run: npm install -g @anthropic-ai/claude-code" >&2
fi

# Verify venv
if [ ! -x "$HOME/.venv/autoport/bin/python" ]; then
    echo "  MISSING: Python venv at ~/.venv/autoport (run sudo ./setup-fedora.sh)" >&2
    exit 1
fi
echo "  ok: ~/.venv/autoport"

# Verify Claude Code OAuth credentials
if [ ! -f "$HOME/.claude/.credentials.json" ]; then
    echo
    echo "WARNING: ~/.claude/.credentials.json not found." >&2
    echo "Run 'claude' once interactively to complete OAuth, then re-run this script." >&2
    exit 1
fi
echo "  ok: Claude Code OAuth credentials present"

# --- 2. Hook up settings.json ---
echo
echo "[2/5] Wiring up Claude Code hooks..."
mkdir -p "$REPO_ROOT/.claude"
if [ -L "$REPO_ROOT/.claude/settings.local.json" ]; then
    rm "$REPO_ROOT/.claude/settings.local.json"
fi
if [ -e "$REPO_ROOT/.claude/settings.local.json" ]; then
    echo "  WARNING: .claude/settings.local.json exists as a real file. Backing up to .bak"
    mv "$REPO_ROOT/.claude/settings.local.json" "$REPO_ROOT/.claude/settings.local.json.bak"
fi
ln -s "../.autoport/settings.json" "$REPO_ROOT/.claude/settings.local.json"
echo "  ok: .claude/settings.local.json → .autoport/settings.json"

# --- 3. Make all scripts executable ---
echo
echo "[3/5] Setting executable bits..."
chmod +x "$AUTOPORT_DIR"/hooks/*.sh
chmod +x "$AUTOPORT_DIR"/lib/*.sh
chmod +x "$AUTOPORT_DIR"/validators/*.sh
chmod +x "$REPO_ROOT/launch.sh"
echo "  ok"

# --- 4. .gitignore ---
echo
echo "[4/5] Updating .gitignore..."
GITIGNORE="$REPO_ROOT/.gitignore"
touch "$GITIGNORE"
for entry in \
    ".autoport/state.json" \
    ".autoport/logs/" \
    ".autoport/.notify.conf" \
    ".claude/settings.local.json"
do
    if ! grep -qxF "$entry" "$GITIGNORE"; then
        echo "$entry" >> "$GITIGNORE"
        echo "  added: $entry"
    fi
done

# --- 5. Notification config ---
echo
echo "[5/5] Notification config..."
NOTIFY_CONF="$AUTOPORT_DIR/.notify.conf"
if [ -n "${NTFY_TOPIC:-}" ]; then
    echo "NTFY_TOPIC=$NTFY_TOPIC" > "$NOTIFY_CONF"
    echo "  ok: ntfy topic set to '$NTFY_TOPIC'"
    echo "       Subscribe on your phone at https://ntfy.sh/$NTFY_TOPIC"
    echo
    echo "  Sending test notification (you should get 4 phone notifications)..."
    bash "$AUTOPORT_DIR/lib/notify.sh" info "test 1/4: info level (quiet heartbeat)"
    sleep 1
    bash "$AUTOPORT_DIR/lib/notify.sh" ok "test 2/4: ok level (phase complete)"
    sleep 1
    bash "$AUTOPORT_DIR/lib/notify.sh" warn "test 3/4: warn level (weekly limit)"
    sleep 1
    bash "$AUTOPORT_DIR/lib/notify.sh" alert "test 4/4: alert level (stuck/blocked)"
    echo "  Test notifications sent. Check your phone."
elif [ -n "${SLACK_WEBHOOK:-}" ]; then
    echo "SLACK_WEBHOOK=$SLACK_WEBHOOK" > "$NOTIFY_CONF"
    echo "  ok: Slack webhook configured"
    bash "$AUTOPORT_DIR/lib/notify.sh" info "autoport install test — Slack working"
else
    : > "$NOTIFY_CONF"
    echo "  no notifications configured (use --ntfy <topic> or --slack <webhook>)"
fi

# --- Trust dialog reminder ---
echo
echo "=========================================="
echo "  Install complete."
echo "=========================================="
echo
echo "IMPORTANT: Claude Code requires workspace trust for hooks to run."
echo "Run this once interactively to accept the trust prompt:"
echo
echo "  cd $REPO_ROOT"
echo "  claude"
echo "  (type 'yes' when asked to trust this directory, then /quit)"
echo
echo "Then launch the orchestrator in foreground:"
echo "  ./launch.sh"
echo
echo "The orchestrator will run in your terminal. Output is also tee'd"
echo "to .autoport/logs/orchestrator.log."
echo
echo "If you must close the terminal mid-run, you have options:"
echo "  - Ctrl+Z, then \`bg\`, then \`disown\` (decouple from terminal)"
echo "  - nohup ./launch.sh > /dev/null 2>&1 &  (full background)"
echo "  - tmux new -s autoport './launch.sh'    (if you installed tmux)"
