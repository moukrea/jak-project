#!/usr/bin/env bash
# Validator — Gcutscene-reframe
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gcr FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gcr ok] $*"; }
R=.autoport/reports/Gcutscene-reframe/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*CUTSCENES[[:space:]]+REFRAMED[[:space:]]+NO[[:space:]]+BARS' "$R" || fail "report lacks RESULT: CUTSCENES REFRAMED NO BARS"
grep -qiE 'vertical' "$R" || fail "le champ de vision vertical conserve doit etre publie"
grep -qiE 'aspect' "$R" || fail "ratio|format|plusieurs formats d ecran doivent etre mesures"
grep -qiE 'hud' "$R" || fail "fps|sous-titre|subtitle|le HUD doit etre traite explicitement"
grep -qiE 'bucket' "$R" || fail "ordre|order|draw|l ordre de dessin du HUD doit etre publie"
grep -qiE 'reveal' "$R" || fail "hors.?cadre|off.?screen|edge|la passe scene par scene sur ce qui est revele doit etre publiee"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"
SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gcr PASS] Gcutscene-reframe"
