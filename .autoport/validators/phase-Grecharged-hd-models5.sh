#!/usr/bin/env bash
# Grecharged-hd-models5 validator — bonus looks (each character COMPLETE from day one).
set -uo pipefail
fail(){ echo "[Ghdmodels5 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models5/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-hd-models5/report.txt)"
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    print(int(s.get('phase_started_at',{}).get('Grecharged-hd-models5',0)))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than phase start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"
# definition-of-done per bonus look: body + FULL face anims + eyes + no lost geometry + extremities
grep -qiE 'blerc|face.{0,40}anim' "$R" || fail "no facial-animation evidence for the bonus look(s)"
grep -qiE 'eye' "$R" || fail "no eye evidence"
grep -qiE 'append.?only' "$R" || fail "append-only statement missing"
grep -qiE 'integrity.*(pass|identical)' "$R" || fail "integrity gate missing"
grep -qiE '(menu|selector|customi).{0,60}(look|choix|option)' "$R" || fail "no look-selection exposure evidence"
DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"
echo "[Ghdmodels5 PASS]"
