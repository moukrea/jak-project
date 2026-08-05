#!/usr/bin/env bash
# Grecharged-secondary-motion validator — phase-specific (generated 2026-08-05; never borrow another phase's validator).
set -uo pipefail
fail(){ echo "[Grecharged-secondary-motion FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-secondary-motion/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-secondary-motion/report.txt)"
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    print(int(s.get('phase_started_at',{}).get('Grecharged-secondary-motion',0)))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than phase start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"

grep -qiE "(chain|spring|verlet).{0,60}(state|dump|bounded|rest|converge)" "$R" || fail "no chain state-dump evidence (bounded, returns to rest, no NaN)"
grep -qiE "FLAG_PHYSICS|--physics" "$R" || fail "no --physics flag evidence"
grep -qiE "(precision|niveau).{0,60}(level|menu|selector|toggle)" "$R" || fail "no precision-levels + menu toggle evidence"
DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"
echo "[Grecharged-secondary-motion PASS]"
