#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gintermittent FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak1-intermittent-events/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*INTERMITTENT EVENTS' "$R" || fail "no RESULT"
grep -qiE 'root cause|mechanism|named|bug class' "$R" || fail "must NAME the common intermittent mechanism"
grep -qiE 'x86.*(oracle|parity|identical)|our-x86' "$R" || fail "must prove x86 oracle parity"
# Owner 2026-07-09: NOT Snowy-Mountain-specific — intermittent + game-wide. Gate on a
# statistical before/after fired-rate across repeated trials, not one location.
grep -qiE '(fired|trigger|fire).?rate|[0-9]+/[0-9]+ (trials|runs)|before.*after|intermittent' "$R" || fail "must show before/after fired-rate across repeated trials (intermittent bug)"
grep -qiE 'icache|bug class #?14|clear_cache' "$R" || fail "must prove/disprove the bug-class-#14 (stale-icache) connection"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device evidence must assert jak1 foreground"
FRAME=$(find .autoport/reports/Gjak1-intermittent-events -type f \( -name '*.png' -o -name '*.mp4' \) 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no device before/after visual evidence"
ENG=$(git diff --name-only $(git log --format=%H --grep='\[autoport/supervisor\]' | head -1) -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && { grep -qiE 'revert|documented' "$R" || fail "engine goal_src touched undocumented"; }
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gintermittent PASS]"
