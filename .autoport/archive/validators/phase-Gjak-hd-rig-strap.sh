#!/usr/bin/env bash
# Validator — Gjak-hd-rig-strap
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gjr FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gjr ok] $*"; }
R=.autoport/reports/Gjak-hd-rig-strap/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*JAK[[:space:]]+RIG' "$R" || fail "report lacks RESULT: JAK RIG"
grep -qiE 'veste|jacket' "$R" || fail "le sommet de veste pondere sur la sangle doit etre traite"
grep -qiE 'boucle|buckle' "$R" || fail "le parentage de la boucle doit etre traite"
grep -qiE 'inverse 4x4|inverse compl' "$R" || fail "les positions doivent venir d'\''une VRAIE inverse 4x4"
grep -qiE 'jak1_hd_assets\.zip|zip livre' "$R" || fail "la preuve doit porter sur le fichier LIVRE dans le zip"
grep -qE 'avant.*apres|AVANT.*APRES' "$R" || fail "les comptes avant/apres doivent etre publies"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"


SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gjr PASS] Gjak-hd-rig-strap"
