#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpbr FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-pbr-materials/report.txt
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no explicit RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
D=.autoport/reports/Grecharged-pbr-materials/device
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video evidence"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still evidence"
grep -qiE 'magenta.*(scan|0 |zero|none|clean)' "$R" || fail "no magenta-scan result"
grep -qiE 'ndiff|mean_abs|mode.?0.*mode.?7|normal.*contribut' "$R" || fail "no normal-contribution (ndiff) proof"
grep -qiE 'per.?material|fallback' "$R" || fail "must implement the per-material fallback"
grep -qiE 'mood|current-sun|light-group|shadow-direction' "$R" || fail "PBR must be lit by the existing mood/TOD light env"
grep -qiE 'double.?dose|ignore.*baked|baked.*(ignored|removed|skipped)' "$R" || fail "PBR path must drop baked vertex lighting (no double-dose)"
grep -qiE 'off.*(stock|identical|byte)|stock.*off' "$R" || fail "OFF must == stock"
grep -qiE 'albedo|normal|roughness|metal|orm' "$R" || fail "must show the PBR material maps"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 evidence"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gpbr PASS]"
