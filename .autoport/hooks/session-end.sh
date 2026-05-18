#!/usr/bin/env bash
# session-end.sh — snapshot of state when a Claude Code session ends.
# Useful for post-mortem on stuck phases.

set -euo pipefail
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG="$CLAUDE_PROJECT_DIR/.autoport/logs/session-end.log"

{
    echo "=== Session end $TS ==="
    echo "--- Recent commits ---"
    git -C "$CLAUDE_PROJECT_DIR" log --oneline -10 2>/dev/null || true
    echo "--- Working tree status ---"
    git -C "$CLAUDE_PROJECT_DIR" status -s 2>/dev/null || true
    echo "--- State ---"
    cat "$CLAUDE_PROJECT_DIR/.autoport/state.json" 2>/dev/null || true
    echo ""
} >> "$LOG"

exit 0
