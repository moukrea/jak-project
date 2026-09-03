#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gj2ing FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak2-ingame/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK2 INGAME' "$R" || fail "no RESULT"
grep -qiE 'collision|collide' "$R" || fail "collision must be addressed"
grep -qiE 'stands|floor|walk|no.*fall|solid' "$R" || fail "must prove Jak stands on the floor"
grep -qiE 'two years|transition|prison' "$R" || fail "transition crash must be addressed"
grep -qiE 'root cause|named' "$R" || fail "must name root causes"
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2' "$R" || fail "jak2 foreground evidence"
V=$(find .autoport/reports/Gjak2-ingame -type f \( -name '*.mp4' -o -name '*.png' \) 2>/dev/null | head -1)
[ -n "$V" ] || fail "no video/screencap evidence"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gj2ing PASS]"
