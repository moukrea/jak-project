#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gnm FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-naming/report.txt
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS"
grep -qiE 'READY FOR OWNER VISUAL CHECK' "$R" || fail "no READY marker"
# new names present in sources; old name gone from user-facing files
grep -rqi 'Recharged Collection' android/app/src/main/res/values/strings.xml || fail "strings.xml lacks 'Recharged Collection'"
grep -rqi 'Jak-pot' android/app/src/main/res/ && fail "old 'Jak-pot' naming still in android res"
grep -qiE 'Jak II: Recharged|Jak 3: Recharged|Jak and Daxter: Recharged' "$R" || fail "no per-game naming evidence"
# package ids untouched
grep -rq 'org.opengoal.gk' android/app/src/main/AndroidManifest.xml || fail "package id changed?! must stay org.opengoal.gk.*"
grep -qiE 'package.?id.*(unchanged|untouched|not (changed|renamed))|org\.opengoal\.gk.*(intact|unchanged)' "$R" || fail "no package-id-untouched proof"
grep -qiE 'mCurrentFocus.*jak1|boots|focus.*jak1' "$R" || fail "no boot proof"
echo "[Gnm PASS]"
