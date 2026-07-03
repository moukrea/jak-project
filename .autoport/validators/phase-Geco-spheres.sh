#!/usr/bin/env bash
# Validator — Geco-spheres: eco spheres (green/blue/red) render like the x86 original on Android.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Geco FAIL] $*" >&2; exit 1; }
ok(){ echo "[Geco ok] $*"; }

R=.autoport/reports/Geco-spheres/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*ECO[[:space:]]+SPHERES[[:space:]]+RENDER[[:space:]]+LIKE[[:space:]]+ORIGINAL' "$R" \
  || fail "report lacks RESULT: ECO SPHERES RENDER LIKE ORIGINAL"
grep -qiE 'green|vert' "$R" && grep -qiE 'blue|bleu' "$R" && grep -qiE 'red|rouge' "$R" || fail "must cover green + blue + red eco"
grep -qiE 'golden|oracle|x86.*(side|vs|compar)' "$R" || fail "must compare device vs the pristine x86 golden (side-by-side)"
grep -qiE 'glow|blend|sprite|generic|sparticle|envmap|family' "$R" || fail "must name the renderer family/effect responsible"
grep -qiE 'kset|noop|cmake|tu |bucket|regist' "$R" || fail "must name the Android gap (kSet/TU/bucket) + the 3-part fix"
grep -qiE 'screencap|screenshot|side-?by-?side' "$R" || fail "must include screencap proof"
grep -qiE 'fps|cost|draws' "$R" || fail "must note the fps/draw cost honestly"
grep -qiE 'flicker|0.*black' "$R" || fail "must confirm 0 flicker"
ok "report: per-color oracle match + named family + 3-part fix + fps cost"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
FIRST_PHASE=$(git log --format=%H --grep='\[autoport/Geco-spheres\]' | tail -1)
if [ -n "$FIRST_PHASE" ]; then
  PRE=$(git log --format=%H --grep='\[autoport/supervisor\]' "${FIRST_PHASE}^" 2>/dev/null | head -1)
  [ -n "$PRE" ] && SUP_ANCHOR=$PRE
fi
ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ 2>/dev/null; git status --porcelain -- android/ game/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/' || fail "no renderer fix"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — renderer-side only"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer fix; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Geco PASS] eco-sphere markers present; x86 ok. (close-gate next)"
