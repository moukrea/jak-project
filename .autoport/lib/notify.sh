#!/usr/bin/env bash
# notify.sh — send notification via ntfy.sh and/or Slack webhook.
# Configured at install time via .autoport/.notify.conf
#
# Usage:
#   notify.sh <level> <message>
#   notify.sh <message>                # defaults to level "info"
#
# Levels:
#   info       priority 2 (min/low) - quiet, no beep — for heartbeats
#   ok         priority 3 (default) - soft notification — phase passed
#   warn       priority 4 (high)    - phone vibrates — weekly limit, etc
#   alert      priority 5 (urgent)  - wakes phone — stuck, blocked
#   celebrate  priority 5 (urgent)  - all done!

set +e  # never fail caller on notify error

# Detect if first arg is a level
case "${1:-}" in
    info|ok|warn|alert|celebrate)
        LEVEL="$1"
        MSG="${2:-}"
        ;;
    *)
        LEVEL="info"
        MSG="${1:-}"
        ;;
esac
[ -z "$MSG" ] && exit 0

case "$LEVEL" in
    info)      PRIORITY=2; TAGS="arrow_forward" ;;
    ok)        PRIORITY=3; TAGS="white_check_mark" ;;
    warn)      PRIORITY=4; TAGS="warning" ;;
    alert)     PRIORITY=5; TAGS="rotating_light,stop_sign" ;;
    celebrate) PRIORITY=5; TAGS="tada,rocket" ;;
esac

CONF="$(dirname "$0")/../.notify.conf"
[ -f "$CONF" ] && source "$CONF"

REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo unknown)")
HOST=$(hostname -s 2>/dev/null || echo unknown)
TITLE="autoport · $REPO@$HOST"

if [ -n "${NTFY_TOPIC:-}" ]; then
    curl -sf --max-time 5 \
        -H "Title: $TITLE" \
        -H "Priority: $PRIORITY" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "https://ntfy.sh/$NTFY_TOPIC" > /dev/null
fi

if [ -n "${SLACK_WEBHOOK:-}" ]; then
    case "$LEVEL" in
        alert|warn) EMOJI=":rotating_light:" ;;
        celebrate)  EMOJI=":tada:" ;;
        ok)         EMOJI=":white_check_mark:" ;;
        *)          EMOJI=":arrow_forward:" ;;
    esac
    curl -sf --max-time 5 \
        -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$EMOJI *[$TITLE]* $MSG\"}" \
        "$SLACK_WEBHOOK" > /dev/null
fi

exit 0
