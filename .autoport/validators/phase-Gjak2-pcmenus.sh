#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gj2menus FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak2-pcmenus/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK2 PC MENUS' "$R" || fail "no RESULT"
grep -qiE 'fit.to.screen|fit to screen' "$R" || fail "fit-to-screen required"
grep -qiE 'aspect.*(live|appli|change)' "$R" || fail "aspect must apply"
grep -qiE 'UNKNOWN ID|display mode' "$R" || fail "display-mode garbage must be addressed"
grep -qiE 'dynamic render|render scale' "$R" || fail "dynamic render scale backport"
grep -qiE 'persist' "$R" || fail "persistence"
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2' "$R" || fail "jak2 foreground evidence"
FRAME=$(find .autoport/reports/Gjak2-pcmenus -type f \( -name '*.png' -o -name '*.mp4' \) 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no visual evidence"
ENG=$(git diff --name-only $(git log --format=%H --grep='\[autoport/supervisor\]' | head -1) -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && { grep -qiE 'revert|documented' "$R" || fail "engine goal_src touched"; }
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gj2menus PASS]"
