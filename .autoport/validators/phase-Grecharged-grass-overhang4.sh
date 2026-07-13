#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Goverhang FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-grass-overhang4/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*GRASS OVERHANG' "$R" || fail "no RESULT"
grep -qiE 'droop|hang|downward|down.?over|overhang.*3d|3d.*overhang' "$R" || fail "must place 3D drooping grass on the lip"
grep -qiE 'far.*(texture|no card)|texture.*far|no grass card' "$R" || fail "far LOD must be texture, NO cards"
grep -qiE 'crossfade|fade|no double.?up|seam' "$R" || fail "must crossfade near-3D vs the alpha overhang texture (no double-up)"
grep -qiE 'walkable.?top.*(stop|clean|not regress)|edge.*not regress' "$R" || fail "must not regress the clean walkable-top rim"
grep -qiE 'toggle|recharged settings' "$R" || fail "must add a Recharged toggle"
grep -qiE 'off.*(stock|identical|byte)|stock.*off' "$R" || fail "OFF must == stock"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 evidence"
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Goverhang PASS]"
