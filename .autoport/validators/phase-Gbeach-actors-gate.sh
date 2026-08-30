#!/usr/bin/env bash
# Validator — Gbeach-actors-gate
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gba FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gba ok] $*"; }
R=.autoport/reports/Gbeach-actors-gate/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'anim|sequence' "$R" && grep -qE '[0-9]+ +images|images=[0-9]+|frames=[0-9]+' "$R" || fail "la silhouette ANIMEE doit publier son nombre d'\''images"
grep -qE 'largeur.*[0-9]+ *(px|pixels)' "$R" || fail "les largeurs texte et ligne precurseur doivent etre publiees en pixels, egales a moins de 2 px"
grep -qiE 'RESULT:[[:space:]]*BEACH[[:space:]]+ACTORS' "$R" || fail "report lacks RESULT: BEACH ACTORS"
grep -qE 'trouve=#t' "$R" || fail "la trace doit montrer les acteurs trouve=#t AVANT le reveil"
grep -qiE 'harvester' "$R" || fail "les collecteurs (harvester-*) doivent etre nommes"
grep -qiE 'sage-intro-sequence-e' "$R" || fail "la scene doit etre nommee"
grep -qE '20000|20 s' "$R" || fail "il faut prouver que le plafond de 20 s est INCHANGE"
grep -qiE 'cinq chemins|5 chemins' "$R" || fail "les cinq chemins d'\''attente existants doivent etre verifies"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gba PASS] Gbeach-actors-gate"
