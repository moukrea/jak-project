#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gao FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-ambient-occlusion/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*AMBIENT OCCLUSION' "$R" || fail "no RESULT"
grep -qiE 'RESULT:.*(IN-PROGRESS|underway|not final)' "$R" && fail "RESULT is a living skeleton"
grep -qiE 'ssao|screen.?space|depth (buffer|fbo)' "$R" || fail "must be screen-space AO from the depth buffer"
grep -qiE 'alpha.*(exclud|transparent|cut|foliage|card)|transparent.*(exclud|depth)' "$R" || fail "must handle the alpha-transparent exclusion (owner #1 risk)"
grep -qiE 'no (boxy|square|halo).*(shadow|alpha)|alpha.*no.*(shadow|artifact)' "$R" || fail "must prove no boxy shadows on alpha foliage/grass cards"
grep -qiE 'toggle|recharged settings' "$R" || fail "must add a Recharged Settings AO toggle"
grep -qiE 'off.*(stock|identical|byte)|stock.*off' "$R" || fail "OFF must == stock"
grep -qiE 'fps' "$R" || fail "must report fps ON/OFF"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 evidence"
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gao PASS]"
