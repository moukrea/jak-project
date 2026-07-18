#!/usr/bin/env bash
# Grecharged-realtime-lighting: sun-only realtime lighting, obvious-model acceptance.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Grtl FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-realtime-lighting/report.txt
D=.autoport/reports/Grecharged-realtime-lighting/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no explicit RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
# obvious-model criteria must each be evidenced
grep -qiE 'sun.?side|lit.?side|N.?dot.?L|terminator' "$R" || fail "no sun-side-lit/dark-side evidence (criterion 1)"
grep -qiE 'cast shadow|casts? a shadow|shadow.*behind|contact' "$R" || fail "no cast-shadow evidence (criterion 2)"
grep -qiE 'h8.*h16|flip|opposite.*sun|sun.?consistent' "$R" || fail "no sun-consistency / h8-h16 flip evidence (criterion 3)"
grep -qiE 'orbit|camera.?independent|pinned' "$R" || fail "no camera-orbit stability evidence (criterion 4)"
grep -qiE 'baked.?off|no baked|baked.*disabled|pure.*sun' "$R" || fail "no baked-off evidence (criterion 5)"
grep -qiE 'no ambient|zero ambient|ambient.*(off|none|removed)|genuinely dark' "$R" || fail "no 'no-ambient' evidence"
grep -qiE 'realtime-lighting\?|realtime lighting.*(on|off|toggle)' "$R" || fail "no realtime-lighting toggle evidence"
grep -qiE 'off ?== ?stock|byte-identical|stock by construction' "$R" || fail "no OFF==stock claim"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus evidence"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video (orbit clip)"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Grtl PASS]"
