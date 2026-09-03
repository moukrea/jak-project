#!/usr/bin/env bash
# Validator — Gpbr-per-texture-materials
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gpm FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gpm ok] $*"; }
R=.autoport/reports/Gpbr-per-texture-materials/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*PER[[:space:]]-?TEXTURE[[:space:]]+MATERIALS[[:space:]]+LIVE' "$R" || fail "report lacks RESULT: PER-TEXTURE MATERIALS LIVE"
grep -qiE 'tangent' "$R" || fail "bitangent|handedness|repere|le repere tangent doit etre traite AVANT les matieres"
grep -qiE 'per.?face' "$R" || fail "par.?face|la mesure PAR FACE doit etre publiee"
grep -qiE 'roughness' "$R" || fail "rugosite|metal|anisotrop|les nouvelles proprietes de matiere doivent etre nommees"
grep -qiE 'recharged.?assets' "$R" || fail "depot|repo|les presets doivent vivre dans le depot d assets"
grep -qiE 'sand' "$R" || fail "stone|cloth|tissu|pierre|au moins deux familles de matiere distinctes doivent etre mesurees"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gpm PASS] Gpbr-per-texture-materials"
