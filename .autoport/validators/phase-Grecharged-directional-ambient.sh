#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gda FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-directional-ambient/report.txt
D=.autoport/reports/Grecharged-directional-ambient/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
grep -qiE 'smooth.*(vertex )?normal|per-vertex normal|reconstruct.*normal|vertex normal' "$R" || fail "no smooth-vertex-normal reconstruction evidence (root-cause fix)"
grep -qiE 'relief|no longer flat|not (faceted|flat)|form.*(curved|shadow|model)|faceted.*fixed' "$R" || fail "no relief-restored evidence"
grep -qiE 'hemisphere|SH|IBL|tier|selector' "$R" || fail "no tiered ambient evidence"
grep -qiE 'off ?== ?stock|byte-identical' "$R" || fail "no OFF==stock"
grep -qiE 'better than.*baked|beats.*baked' "$R" || fail "no better-than-stock-baked evidence"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gda PASS]"
