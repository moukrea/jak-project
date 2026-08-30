#!/usr/bin/env bash
# Validator — Gbuild-from-scratch
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gbs FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gbs ok] $*"; }
R=.autoport/reports/Gbuild-from-scratch/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*BUILD[[:space:]]+FROM[[:space:]]+SCRATCH' "$R" || fail "report lacks RESULT: BUILD FROM SCRATCH"
grep -qiE 'deux courses|2 courses|deux constructions' "$R" || fail "il faut DEUX constructions successives et leurs empreintes"
grep -qE '[0-9a-f]{8,}' "$R" || fail "les empreintes des artefacts produits doivent etre publiees"
grep -qiE 'maskstrap|masque' "$R" || fail "la suppression automatique du masque doit etre prouvee"
grep -qiE 'non reproductible|ne peut pas etre reproduit|NOMME' "$R" || fail "ce qui n'\''est pas reproductible doit etre NOMME"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"


SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gbs PASS] Gbuild-from-scratch"
