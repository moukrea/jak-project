#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Grtl FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-realtime-lighting/report.txt
D=.autoport/reports/Grecharged-realtime-lighting/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
# core sun-only
grep -qiE 'sun.?side|lit.?side|N.?dot.?L|terminator' "$R" || fail "no sun-side-lit evidence"
grep -qiE 'cast shadow|casts? a shadow|shadow.*behind' "$R" || fail "no cast-shadow evidence"
grep -qiE 'off ?== ?stock|byte-identical|stock by construction' "$R" || fail "no OFF==stock"
# round-7: night leak fixed
grep -qiE 'night.*(dark|floor only|no lit|no light)|no lit zone|no phantom|below.?horizon.*(zero|dark)|every surface.*floor' "$R" || fail "no night-darkness (no lit zones at night) evidence — round-7 CRUCIAL"
grep -qiE 'tfrag.*tie.*shrub|all four shader|four shaders|uniformly.*(shader|path)|every.*(shader|path).*(fade|night)' "$R" || fail "no all-shader-paths night-fade audit — round-7"
# round-7: Form-AO removed
grep -qiE 'form.?ao (removed|dropped|deleted|reverted)|dropped the form.?ao|removed.*form.?ao|no form.?ao' "$R" || fail "no Form-AO-removed evidence — round-7 (owner: drop it)"
# retained menu + quality
grep -qiE 'menu|Recharged Settings' "$R" || fail "no menu evidence"
grep -qiE 'device|mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video (night sweep)"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Grtl PASS]"
