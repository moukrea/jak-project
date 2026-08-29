#!/usr/bin/env bash
# Validator — Gloading-screen
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gls FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gls ok] $*"; }
R=.autoport/reports/Gloading-screen/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*LOADING[[:space:]]+SCREEN[[:space:]]+LIVE' "$R" || fail "report lacks RESULT: LOADING SCREEN LIVE"
grep -qiE 'seuil' "$R" || fail "threshold|le seuil d affichage doit etre publie"
grep -qiE 'pov-camera' "$R" || fail "basebutton|coupe|cut|il faut prouver qu une coupe de camera ne declenche PAS l ecran"
grep -qiE 'loadgate' "$R" || fail "barriere|le lien a la barriere de chargement doit etre prouve"
grep -qiE 'silhouette' "$R" || fail "la silhouette doit etre traitee"
grep -qiE 'sage-intro-sequence-e' "$R" || fail "les collecteurs d'\''Eco vert (scene sage-intro-sequence-e) doivent etre traites — signale DEUX fois par l'\''owner"
grep -qiE 'reason=(resident|timeout)' "$R" || fail "la ligne LOADGATE qui tranche (resident vs timeout) doit etre CAPTUREE, pas decrite"
grep -qiE 'harvester|acteur' "$R" || fail "le sort des ACTEURS (harvester-*) doit etre publie, pas seulement la geometrie"
grep -qiE 'avant.*titre|pre.?titre|before.*title' "$R" || fail "le chargement du niveau du titre AVANT la sequence d'\''intro doit etre traite"
grep -qiE 'temps total|total.*titre' "$R" || fail "le temps total jusqu'\''au titre doit etre publie avant/apres (il ne doit pas augmenter)"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gls PASS] Gloading-screen"
