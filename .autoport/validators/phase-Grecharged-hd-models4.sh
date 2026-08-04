#!/usr/bin/env bash
# Grecharged-hd-models4 — M2 primaries validator (Daxter J3-cine / Keira J2-first-cutscene / Samos J3-cine).
set -uo pipefail
fail(){ echo "[Ghdmodels4 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models4/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-hd-models4/report.txt)"
# freshness vs THIS phase's start (false-green guard, same pattern as M1)
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    print(int(s.get('phase_started_at',{}).get('Grecharged-hd-models4',0)))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than this phase's start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"
# the 3 primaries: appended (or a LOUD documented skip with the donor-absence reason)
for c in dax keira samos; do
  grep -qiE "${c}-hd-lod0.*(append|integr|visible|proven)|SKIP.*${c}" "$R" \
    || fail "no append/skip evidence for ${c}-hd-lod0"
done
# anti-carnage: append-only + integrity
grep -qiE 'append.?only' "$R" || fail "append-only statement missing"
grep -qiE 'integrity.*(pass|identical)' "$R" || fail "integrity gate missing"
# owner rule: chosen model EVERYWHERE — the per-actor coverage / logo fix must be addressed
grep -qiE '(logo|per.?actor|coverage).*(fix|cover|suppress|resolved|proven|implemented)' "$R" \
  || fail "logo/per-actor coverage carry-over not addressed in the report"
# device proof on the Redmi
DEV=""
for s2 in eae4df44 AREE026206000788; do
  if adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$"; then DEV="$s2"; break; fi
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"
grep -qiE 'crash|exit-info' "$R" || fail "no crash-free/exit-info evidence line"
FRAMES=$(find .autoport/reports/Grecharged-hd-models4 -type f \( -name '*.png' -o -name '*.mp4' \) 2>/dev/null | wc -l)
[ "$FRAMES" -ge 2 ] || fail "need capture evidence (>=2, found $FRAMES)"
echo "[Ghdmodels4 PASS]"
