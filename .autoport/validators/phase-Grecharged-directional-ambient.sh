#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gda FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-directional-ambient/report.txt
D=.autoport/reports/Grecharged-directional-ambient/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
grep -qiE 'hemisphere|directional ambient|sky.?color.*ground|N\.y|irradiance|SH ambient|IBL' "$R" || fail "no directional-ambient evidence"
grep -qiE 'form.*shadow|shadowed.*(form|shape|relief)|AO off.*(form|shape)|top.?lit' "$R" || fail "no form-in-shadow-AO-off evidence"
grep -qiE 'sunlit.*(unchanged|identical|same)|golden rule|only.*ambient|never.*direct' "$R" || fail "no golden-rule (sunlit unchanged) evidence"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus evidence"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gda PASS]"
