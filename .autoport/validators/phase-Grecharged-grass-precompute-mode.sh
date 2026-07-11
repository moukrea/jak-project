#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gprecompute FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-grass-precompute-mode/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*GRASS PRECOMPUTE MODE' "$R" || fail "no RESULT"
grep -qiE 'RESULT:.*(IN-PROGRESS|underway|not final)' "$R" && fail "RESULT is a living skeleton"
grep -qiE '(precompute|baked|offline).*(placement|instance|tint)' "$R" || fail "must precompute placement/tint offline"
grep -qiE 'toggle|grass mode|live.*precomp|precomp.*live' "$R" || fail "must add a LIVE/PRECOMPUTED toggle"
grep -qiE 'fps' "$R" && grep -qiE 'load.?time|load time|chargement' "$R" || fail "must report per-mode fps + load-time on device"
grep -qiE 'live.*(default|unchanged|byte)|default.*live' "$R" || fail "LIVE must stay default + unchanged"
grep -qiE 'frozen|static light|tradeoff|day.?cycle' "$R" || fail "must document the frozen-lighting tradeoff of precomputed"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 foreground evidence"
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gprecompute PASS]"
