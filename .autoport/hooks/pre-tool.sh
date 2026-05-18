#!/usr/bin/env bash
# pre-tool.sh — abort tool calls if the 5-hour window is critical.
# Exit 2 = block this tool call (Claude sees the stderr message).
# The orchestrator's outer loop will catch the early stop and re-queue
# the phase after the rate-limit window resets.

set -euo pipefail

TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' \
    "$HOME/.claude/.credentials.json" 2>/dev/null || echo "")
[ -z "$TOKEN" ] && exit 0

# Don't probe on every single tool call — cache for 60s
CACHE="$HOME/.claude/autoport-ratecache.json"
NOW=$(date +%s)
if [ -f "$CACHE" ]; then
    AGE=$(( NOW - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
    if [ "$AGE" -lt 60 ]; then
        USAGE=$(cat "$CACHE")
    fi
fi

if [ -z "${USAGE:-}" ]; then
    USAGE=$(curl -sf --max-time 5 \
        "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $TOKEN" \
        -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null || echo "{}")
    echo "$USAGE" > "$CACHE" 2>/dev/null || true
fi

# Parse — bail silently on parse errors
SESS_PCT=$(echo "$USAGE" | jq -r '.five_hour.utilization // 0' 2>/dev/null || echo 0)
WEEK_PCT=$(echo "$USAGE" | jq -r '.seven_day.utilization // 0' 2>/dev/null || echo 0)
SESS_INT=${SESS_PCT%.*}
WEEK_INT=${WEEK_PCT%.*}

if [ "${WEEK_INT:-0}" -ge 95 ]; then
    cat <<EOF >&2
[autoport rate-limit guard] Weekly usage at ${WEEK_PCT}%.

Stopping now. The orchestrator will resume this phase after the weekly
quota resets (timestamp from the API, not a hardcoded day).
EOF
    exit 2
fi

if [ "${SESS_INT:-0}" -ge 90 ]; then
    cat <<EOF >&2
[autoport rate-limit guard] 5-hour window at ${SESS_PCT}%.

Stopping now. The orchestrator will resume this phase after the 5-hour
window resets (precise timestamp from the API).
EOF
    exit 2
fi

exit 0
