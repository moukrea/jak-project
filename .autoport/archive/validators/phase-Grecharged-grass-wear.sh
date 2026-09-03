#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gwear FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-grass-wear/report.txt
[ -f "$R" ] || fail "no report"
grep -qiE 'RESULT:.*GRASS WEAR DESIGN' "$R" || fail "no RESULT"
grep -qiE 'influence field|champ.{0,15}influence' "$R" || fail "must design the influence-field model"
grep -qiE 'collectible|orbe|orb' "$R" || fail "must cover collectibles influence"
grep -qiE 'path|chemin|corridor' "$R" || fail "must cover inferred paths"
grep -qiE 'platform|plateforme' "$R" || fail "must cover platform/jump influence"
grep -qiE 'determinist' "$R" || fail "must be deterministic"
grep -qiE 'mvp|version minimale|minimal version' "$R" || fail "must define the MVP"
grep -qiE 'risk|risque' "$R" || fail "must list technical risks"
grep -qiE 'debug|heatmap' "$R" || fail "must specify the debug visualization tooling"
grep -qiE 'backlog|sub.?task|découpage|tâches' "$R" || fail "must decompose into ordered backlog tasks"
grep -qiE 'no.{0,20}implement|not implement|aucune implémentation|analysis only|design only' "$R" || fail "this phase must NOT implement (design spike)"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Gwear PASS]"
