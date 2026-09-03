#!/usr/bin/env bash
# Validator — Gdynamic-fix: dynamic scale converges to the MAX scale holding target (not stuck at floor)
# + runtime Min-Render-Scale re-clamp. Objective markers + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gdfix FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gdfix ok] $*"; }

R=.autoport/reports/Gdynamic-fix/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*DYNAMIC[[:space:]]+SCALE[[:space:]]+SEEKS[[:space:]]+MAX[[:space:]]+QUALITY[[:space:]]+AT[[:space:]]+TARGET' "$R" \
  || fail "report lacks RESULT: DYNAMIC SCALE SEEKS MAX QUALITY AT TARGET"
# bug 2: climbs to the highest scale holding target, not stuck at floor
grep -qiE 'climb|converge.*max|highest.*(scale|meeting|target)|raise.*(60|toward)|not stuck|above target' "$R" || fail "must show the scale CLIMBS to the highest value holding target (the owner's core bug: stuck at floor with headroom)"
grep -qiE 'stuck|floor|minimum|10%|30%' "$R" || fail "must reference the stuck-at-floor bug being fixed"
grep -qiE 'headroom|above.*target|>= ?target|30.*32|60%|fps.*(above|>).*target' "$R" || fail "must show a headroom-zone trace (target below the achievable fps → scale climbs)"
# bug 1: runtime min re-clamp
grep -qiE 're-?clamp|clamp.*(runtime|change|new min)|minimum.*(change|applied|takes effect)|setting change.*clamp' "$R" || fail "must show the runtime Minimum-Render-Scale change re-clamps the effective scale (bug 1)"
grep -qiE 'thrash|oscillat|cooldown|smooth|bounded|cadence|dead.?band' "$R" || fail "must keep anti-thrash"
grep -qiE 'floor|never below|respect' "$R" || fail "must respect the floor"
grep -qiE 'off.*(manual|unchanged|fixed)|manual.*off' "$R" || fail "must keep OFF = manual"
ok "report: climbs-to-max-at-target + runtime re-clamp + anti-thrash + floor + OFF=manual"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/graphics/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|graphics/|pc/' || fail "no dynamic-scale code change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — keep it in pc/ + renderer"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "code change present; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gdfix PASS] dynamic-scale seeks-max-at-target + re-clamp markers present; x86 ok. (close-gate: deploy_verify + boot + owner next)"
