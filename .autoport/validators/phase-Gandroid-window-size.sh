#!/usr/bin/env bash
# Validator — Gandroid-window-size
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gaw FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gaw ok] $*"; }
R=.autoport/reports/Gandroid-window-size/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*WINDOW[[:space:]]+SIZE[[:space:]]+LIVE' "$R" || fail "report lacks RESULT: WINDOW SIZE LIVE"
grep -qE '[0-9]{3,}x[0-9]{3,}|width=[0-9]{3,}' "$R" || fail "une taille de fenetre NON NULLE mesuree sur appareil doit etre publiee"
grep -qiE 'deux appareils|2 appareils|Redmi.*Shield|Shield.*Redmi' "$R" || fail "la mesure doit porter sur DEUX appareils de ratios differents"
grep -qiE 'gauche=0|left=0|0 px|zero barre' "$R" || fail "le comptage de barres noires doit etre publie"
grep -qiE 'vacuite|zero|garde|guard' "$R" || fail "le sort de la garde de vacuite doit etre publie"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gaw PASS] Gandroid-window-size"
