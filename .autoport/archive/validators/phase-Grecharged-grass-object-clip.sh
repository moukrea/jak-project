#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gclip FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-grass-object-clip/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*GRASS OBJECT-CLIP' "$R" || fail "no RESULT"
grep -qiE 'gate|button' "$R" || fail "must address the island gate button"
grep -qiE 'occluder|cull' "$R" || fail "must extend the object-cull occluder set"
grep -qiE 'non.?tie|game.?object|actor|prototype|process.?drawable' "$R" || fail "must include non-TIE ground objects"
grep -qiE 'footprint|contact|ground.?surface|not.*(full mesh|bbox|volume)|buried|below' "$R" || fail "must cull by ground-contact footprint, not the buried full mesh (owner nuance)"
grep -qiE 'no.*(giant|big).*bald|no.*bald patch|footprint.*not.*volume' "$R" || fail "must prove no giant bald patch on buried-base objects"
grep -qiE 'not regress|no regress' "$R" || fail "must not regress open-field/edges"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 evidence"
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gclip PASS]"
