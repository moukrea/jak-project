#!/usr/bin/env bash
# check_limits.sh — interactive rate-limit probe.
# Run any time to see your current Claude Code quota status.

set -euo pipefail

if [ ! -f "$HOME/.claude/.credentials.json" ]; then
    echo "No Claude Code credentials found." >&2
    echo "Run 'claude' once to authenticate." >&2
    exit 1
fi

TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$HOME/.claude/.credentials.json")

USAGE=$(curl -sf --max-time 10 \
    "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20")

if [ -z "$USAGE" ]; then
    echo "Failed to fetch rate limit data." >&2
    exit 1
fi

NOW=$(date +%s)

format_window() {
    local label="$1"
    local pct="$2"
    local resets_at="$3"
    local reset_epoch=$(date -d "$resets_at" +%s 2>/dev/null || echo "$NOW")
    local remaining=$(( reset_epoch - NOW ))
    local hrs=$(( remaining / 3600 ))
    local mins=$(( (remaining % 3600) / 60 ))

    local color=""
    case "$(printf '%.0f' "$pct")" in
        9[0-9]|100) color="\033[31m" ;;  # red
        7[0-9]|8[0-9]) color="\033[33m" ;;  # yellow
        *) color="\033[32m" ;;  # green
    esac
    printf "  ${color}%-12s %5.1f%%\033[0m   resets in %dh%02dm (at %s)\n" \
        "$label" "$pct" "$hrs" "$mins" "$resets_at"
}

SESS_PCT=$(echo "$USAGE" | jq -r '.five_hour.utilization')
SESS_RESET=$(echo "$USAGE" | jq -r '.five_hour.resets_at')
WEEK_PCT=$(echo "$USAGE" | jq -r '.seven_day.utilization')
WEEK_RESET=$(echo "$USAGE" | jq -r '.seven_day.resets_at')

echo
echo "Claude Code usage:"
format_window "5h session" "$SESS_PCT" "$SESS_RESET"
format_window "weekly" "$WEEK_PCT" "$WEEK_RESET"
echo
echo "Raw JSON:"
echo "$USAGE" | jq .
