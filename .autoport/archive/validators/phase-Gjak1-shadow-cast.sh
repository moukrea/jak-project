#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gshadow FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Gjak1-shadow-cast/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*JAK SHADOW' "$R" || fail "no RESULT"
grep -qiE 'mips2c|kset|allowlist|cmakelists|bucket|renderer subset|codegen' "$R" || fail "must name the missing mechanism"
grep -qiE 'shadow.*(visible|underneath|beneath|sous)' "$R" || fail "must prove the shadow visible on device"
grep -qiE 'jump|saut' "$R" || fail "must include the jumping shot"
grep -qiE 'x86.*(oracle|a/b)|oracle.*x86' "$R" || fail "must A/B vs the x86 oracle"
grep -qiE 'goal_src.*(untouched|unchanged)|translation layer' "$R" || fail "translation-layer only"
grep -qiE 'fps' "$R" || fail "must report fps before/after"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 evidence"
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gshadow PASS]"
