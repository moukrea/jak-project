#!/usr/bin/env bash
# Validator — Gfirstperson-hd-hide
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gfp FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gfp ok] $*"; }
R=.autoport/reports/Gfirstperson-hd-hide/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*HD[[:space:]]+MODELS[[:space:]]+HIDDEN[[:space:]]+IN[[:space:]]+FIRST[[:space:]]-?PERSON' "$R" || fail "report lacks RESULT: HD MODELS HIDDEN IN FIRST-PERSON"
grep -qiE 'jak' "$R" || fail "target|le site du masquage d origine doit etre nomme pour Jak"
grep -qiE 'daxter' "$R" || fail "sidekick|Daxter/sidekick doit etre traite aussi"
grep -qiE 'stock' "$R" || fail "origin|d-origine|le comportement des modeles STOCK doit etre publie comme reference"
grep -qiE 'file' "$R" || fail ":[0-9]+|le fichier et la ligne du masquage doivent etre publies"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gfp PASS] Gfirstperson-hd-hide"
