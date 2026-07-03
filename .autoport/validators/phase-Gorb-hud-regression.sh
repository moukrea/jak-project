#!/usr/bin/env bash
# Validator — Gorb-hud-regression: Precursor orbs correct on ALL interfaces, WITH the render-split kept.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gorb FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gorb ok] $*"; }

R=.autoport/reports/Gorb-hud-regression/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*PRECURSOR[[:space:]]+ORBS[[:space:]]+CORRECT[[:space:]]+IN[[:space:]]+SPLIT' "$R" \
  || fail "report lacks RESULT: PRECURSOR ORBS CORRECT IN SPLIT"
grep -qiE 'orb' "$R" || fail "must be about the Precursor orbs"
grep -qiE 'white|regress|Gorb-icon|original fix' "$R" || fail "must recover/reference the original Gorb-icon fix + the regression"
grep -qiE 'split.*(kept|intact|broke)|render-?split|ui pass|native.*pass' "$R" || fail "must explain why the split broke it + fix WITHIN the split"
grep -qiE 'hud' "$R" && grep -qiE 'menu|progress|pause' "$R" && grep -qiE 'save' "$R" || fail "must sweep ALL orb sites (HUD, menu, save screens)"
grep -qiE '50%|scale.*50|both.*scale' "$R" || fail "must verify at 100% AND 50% render scale (split active)"
grep -qiE 'screencap|screenshot' "$R" || fail "must include screencap proof"
grep -qiE 'ui.*(crisp|native)|split intact' "$R" || fail "must confirm the split (UI native) is intact"
ok "report: orbs correct at all sites, split intact, 100%+50%, screencaps"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Gorb-hud-regression\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/graphics/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/graphics/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|graphics/|pc/' || fail "no renderer/pc fix"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$ENG" ]; then grep -qiE 'revert|pristine|documented' "$R" || fail "engine goal_src changed ($ENG) undocumented"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer-side fix; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gorb PASS] orbs-in-split markers present; x86 ok. (close-gate next)"
