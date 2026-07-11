#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gprecompute FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-grass-precompute-mode/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*GRASS PRECOMPUTE MODE' "$R" || fail "no RESULT"
grep -qiE 'RESULT:.*(IN-PROGRESS|underway|not final)' "$R" && fail "RESULT is a living skeleton"
grep -qiE '(precompute|baked|offline).*(placement|instance|tint)' "$R" || fail "must precompute placement/tint offline"
grep -qiE '(day.?cycle|keyframe|time.?of.?day).*(bake|precompute|interpol)|bake.*(day.?cycle|keyframe|time.?of.?day)' "$R" || fail "lighting must be baked for the WHOLE DAY CYCLE (keyframes, interpolated), NOT frozen at one time"
grep -qiE '(same|identical).*(fidelity|look|live)|no visual difference|still var(ies|y)' "$R" || fail "precomputed must keep FULL fidelity (identical to live, day cycle still varies) — not a downgrade"
grep -qiE 'toggle|grass mode' "$R" || fail "must add a PRECOMPUTED/LIVE toggle"
grep -qiE 'fps' "$R" && grep -qiE 'load.?time|load time|chargement' "$R" || fail "must report per-mode fps + load-time on device"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 foreground evidence"
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gprecompute PASS]"
