#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gj2input FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak2-input/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK2 INPUT' "$R" || fail "no RESULT"
grep -qiE 'walk|move|jump|déplace' "$R" || fail "must prove movement works"
grep -qiE 'slide|drift|neutral|glisse' "$R" || fail "must fix the constant slide (neutral centering)"
grep -qiE 'root cause|named|why' "$R" || fail "must name the root cause"
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2' "$R" || fail "jak2 foreground evidence"
V=$(find .autoport/reports/Gjak2-input -type f \( -name '*.mp4' -o -name '*.png' \) 2>/dev/null | head -1)
[ -n "$V" ] || fail "no movement video/screencap evidence"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gj2input PASS]"
