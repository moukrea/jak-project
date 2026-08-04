#!/usr/bin/env bash
# Gtouch-longjump-regression validator — the owner's touch long-jump combo must work.
set -uo pipefail
fail(){ echo "[Gtouchlj FAIL] $*" >&2; exit 1; }
D=.autoport/reports/Gtouch-longjump-regression
R="$D/report.txt"
[ -f "$R" ] || fail "no report ($D/report.txt) — write a final report, not just run logs"
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    print(int(s.get('phase_started_at',{}).get('Gtouch-longjump-regression',0)))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than phase start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"
# root cause stated explicitly (touch-overlay, terrain-class, pacing, etc.) — no vague hand-waving
grep -qiE 'root.?cause[^.]{0,120}(overlay|terrain|position|pacing|stick|wheel|timer|state)' "$R" \
  || fail "no explicit root-cause statement"
# TOUCH-INJECTION proof of the owner combo (forward + R1/R2 + X), with counted outcomes
grep -qiE '(touch.?inject|touch.?replay|gesture)[^.]{0,120}(owner|combo|R1|L1)' "$R" || fail "no touch-injection owner-combo evidence"
grep -qiE '(flips?|wheel(-flip)?s?) ?[=:] ?[0-9]+ ?/ ?[0-9]+' "$R" || fail "no counted flip outcome (flips=N/M)"
# the fix bar: all reps succeed post-fix, or an honestly-argued not-a-regression verdict with bisect evidence
grep -qiE '(flips?|wheels?)[ =:]*([0-9]+)/\2|all reps (pass|succeed)|NOT.?A.?REGRESSION.*(bisect|pre.?menu|old build)' "$R" \
  || fail "neither a full-success post-fix run (flips=N/N) nor a bisect-backed not-a-regression verdict"
DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"
echo "[Gtouchlj PASS]"
