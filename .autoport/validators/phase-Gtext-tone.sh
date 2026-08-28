#!/usr/bin/env bash
# Validator — Gtext-tone
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gtt FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gtt ok] $*"; }
R=.autoport/reports/Gtext-tone/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE "table.*(runtime|execution|reel)|reel.*table|cote a cote" "$R" || fail "il faut publier les valeurs REELLEMENT utilisees a cote de celles de la table"
grep -qiE 'RESULT:[[:space:]]*TON[[:space:]]+DES[[:space:]]+TEXTES' "$R" || fail "report lacks RESULT: TON DES TEXTES"
grep -qiE 'avant.*apres|before.*after' "$R" || fail "la liste AVANT/APRES par langue doit etre publiee"
grep -qiE 'imperatif|tutoi' "$R" || fail "le passage a l'imperatif doit etre publie"
grep -qiE 'tactile|touch' "$R" || fail "la variante tactile doit etre traitee"
grep -qiE 'largeur|depassement|boite|overflow' "$R" || fail "l'absence de depassement de boite doit etre prouvee"
grep -qiE 'fr-FR|es-ES|it-IT' "$R" || fail "les autres langues doivent etre traitees, pas seulement le francais"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gtt PASS] Gtext-tone"
