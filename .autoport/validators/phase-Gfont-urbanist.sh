#!/usr/bin/env bash
# Validator — Gfont-urbanist
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gfu FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gfu ok] $*"; }
R=.autoport/reports/Gfont-urbanist/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*URBANIST[[:space:]]+LIVE[[:space:]]+MIXED[[:space:]]+CASE' "$R" || fail "report lacks RESULT: URBANIST LIVE MIXED CASE"
grep -qiE 'font12-table' "$R" || fail "font24-table|uv|la table UV branchee doit etre nommee"
grep -qiE 'lowercase' "$R" || fail "minuscule|la correspondance des minuscules doit etre prouvee"
grep -qiE '4.?bit' "$R" || fail "8.?bit|profondeur|depth|le format retenu doit etre justifie par une mesure"
grep -qiE 'japon' "$R" || fail "ja-JP|CJK|le japonais doit rester sur sa police d origine"
grep -qiE 'acronym' "$R" || fail "exception|PS2|la regle de casse et ses exceptions doivent etre publiees"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gfu PASS] Gfont-urbanist"
