#!/usr/bin/env bash
# Validator — Gkeira-hd-detached-parts
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gkd FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gkd ok] $*"; }
R=.autoport/reports/Gkeira-hd-detached-parts/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*DETACHED[[:space:]]+STRAP[[:space:]]+JOINTS[[:space:]]+REMOVED' "$R" || fail "report lacks RESULT: DETACHED STRAP JOINTS REMOVED"
grep -qiE 'strap2' "$R" || fail "lTopStrap|rBotStrap|les joints vises doivent etre nommes"
grep -qiE '167' "$R" || fail "distance|unit|la distance mesuree avant correction doit etre publiee"
grep -qiE '112' "$R" || fail "vertex|sommet|weight|le sort des 112 sommets ponderes doit etre publie"
grep -qiE 'fallback' "$R" || fail "physics_chains|la disparition des lignes FALLBACK doit etre prouvee"
grep -qiE 'bound' "$R" || fail "englobante|bbox|la boite englobante avant/apres doit etre publiee"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gkd PASS] Gkeira-hd-detached-parts"
