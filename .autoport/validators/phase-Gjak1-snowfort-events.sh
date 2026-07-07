#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gsnowfort FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak1-snowfort-events/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*SNOWFORT EVENTS' "$R" || fail "no RESULT"
grep -qiE 'root cause|stuck (state|process)|named' "$R" || fail "must NAME the stuck state/root cause"
grep -qiE 'x86.*(oracle|parity|identical)|our-x86' "$R" || fail "must prove x86 oracle parity"
grep -qiE 'enem(y|ies).*(active|aggro|move|behave)' "$R" || fail "must show fort enemies active like oracle"
grep -qiE 'cutscene|cinemat' "$R" || fail "must audit the cutscene-trigger impression"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device evidence must assert jak1 foreground"
FRAME=$(find .autoport/reports/Gjak1-snowfort-events -type f \( -name '*.png' -o -name '*.mp4' \) 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no device before/after visual evidence"
ENG=$(git diff --name-only $(git log --format=%H --grep='\[autoport/supervisor\]' | head -1) -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && { grep -qiE 'revert|documented' "$R" || fail "engine goal_src touched undocumented"; }
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gsnowfort PASS]"
