#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gmt FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-master-toggle/report.txt
D=.autoport/reports/Grecharged-master-toggle/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
# single effective-flag helper, consumed widely (not per-feature drift copies)
grep -rqiE 'recharged_active|recharged_master|master.*recharged.*(&&|and).*flag' game/graphics/gfx.h game/graphics/ 2>/dev/null || fail "no single master effective-flag helper in source"
grep -qiE 'byte.?identical|stock.?identical|identical.*(vanilla|stock|original)|pixel.?identical' "$R" || fail "no master-OFF==vanilla identity evidence"
grep -qiE 'settings (restored|preserved|kept)|individual (toggles|settings).*(intact|restored|unchanged)|no reset' "$R" || fail "no user-settings-preserved-on-retoggle evidence"
grep -qiE 'grey|disabled.*(rows|individual)|option-disabled' "$R" || fail "no rows-greyed-when-master-OFF evidence"
grep -qiE 'menu-tree' "$R" || fail "menu-tree.md not updated (standing rule)"
grep -qiE 'debug\.opengoal\.recharged|headless.*(vanilla|prop)' "$R" || fail "no headless/debug-prop vanilla override evidence (probe-capture use)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gmt PASS]"
