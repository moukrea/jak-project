#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gthr FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-texture-hotreload/report.txt
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS"
grep -qiE 'READY FOR OWNER VISUAL CHECK' "$R" || fail "no READY marker"
grep -qiE 'live|hot.?reload|without restart|no restart|re-?upload|rescan' "$R" || fail "no live-toggle evidence"
grep -qiE 'precedence.*(intact|unchanged|kept)|user.*(still|always).*(win|prior)' "$R" || fail "no precedence-intact proof"
grep -qiE 'mCurrentFocus.*jak1|boots|focus.*jak1' "$R" || fail "no boot proof"
echo "[Gthr PASS]"
