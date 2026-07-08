#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gj2move FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak2-movement/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK2 MOVEMENT' "$R" || fail "no RESULT"
grep -qiE 'walk|translate|moves|déplace' "$R" || fail "must prove Jak translates"
grep -qiE 'drift|slide|glisse' "$R" || fail "must eliminate the idle drift"
grep -qiE 'root cause|named' "$R" || fail "must name the failing pipeline stage"
grep -qiE 'x86.*(unaffected|identical|parity)' "$R" || fail "x86 parity required"
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2' "$R" || fail "jak2 foreground evidence"
V=$(find .autoport/reports/Gjak2-movement -type f \( -name '*.mp4' -o -name '*.png' \) 2>/dev/null | head -1)
[ -n "$V" ] || fail "no movement video evidence"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gj2move PASS]"
