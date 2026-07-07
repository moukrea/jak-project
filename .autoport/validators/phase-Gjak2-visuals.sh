#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gj2vis FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak2-visuals/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK2 VISUALS' "$R" || fail "no RESULT"
grep -qiE 'tod|time.of.day|palette|lighting|lit' "$R" || fail "must fix TOD/lighting (dark world)"
grep -qiE 'sky' "$R" || fail "must address the sky family"
grep -qiE 'sprite|particle' "$R" || fail "must address sprite/particle family"
grep -qiE 'per.family|family table|ported.*deferred|deferred.*why' "$R" || fail "need per-family verdicts"
grep -qiE 'oracle|x86.*(compar|match|side)' "$R" || fail "must compare to the x86 oracle at matched beats"
grep -qiE 'crash.free|no crash|soak|5 min' "$R" || fail "must keep the crash-free soak"
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2' "$R" || fail "must assert jak2 foreground"
FRAME=$(find .autoport/reports/Gjak2-visuals -type f \( -name '*.png' -o -name '*.mp4' \) 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no visual evidence"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gj2vis PASS]"
