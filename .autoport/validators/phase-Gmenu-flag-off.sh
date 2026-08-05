#!/usr/bin/env bash
# Gmenu-flag-off validator — phase-specific (generated 2026-08-05; never borrow another phase's validator).
set -uo pipefail
fail(){ echo "[Gmenu-flag-off FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gmenu-flag-off/report.txt
[ -f "$R" ] || fail "no report (reports/Gmenu-flag-off/report.txt)"
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    print(int(s.get('phase_started_at',{}).get('Gmenu-flag-off',0)))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than phase start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"

# phase substance: old menu restored + bindings audited + displacement back, OFF build
grep -qiE "(binding|value-to-modify).{0,80}(audit|dump|correct|unique|verified)" "$R" || fail "no per-row binding audit evidence"
grep -qiE "displacement.{0,60}(select|operational|works|parallax|tess)" "$R" || fail "no displacement-selector-works evidence"
grep -qiE "(old|ancien|pre.?overhaul).{0,50}menu.{0,60}(default|restor|OFF)" "$R" || fail "no old-menu-restored-as-default statement"
grep -qiE "(enhanced.?models|hd).{0,60}(toggle|accessible|row)" "$R" || fail "no HD-toggle-accessible-in-old-menu evidence"
DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"
echo "[Gmenu-flag-off PASS]"
