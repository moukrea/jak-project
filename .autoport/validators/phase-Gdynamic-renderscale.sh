#!/usr/bin/env bash
# Validator — Gdynamic-renderscale: auto-adjust render scale within [min,100] to hold a target fps,
# with anti-thrash. Objective markers + numeric anti-thrash + x86 smoke; device + owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gdyn FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gdyn ok] $*"; }

R=.autoport/reports/Gdynamic-renderscale/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*DYNAMIC[[:space:]]+RENDER[[:space:]]+SCALE[[:space:]]+HOLDS[[:space:]]+TARGET[[:space:]]+FPS' "$R" \
  || fail "report lacks RESULT: DYNAMIC RENDER SCALE HOLDS TARGET FPS"
grep -qiE 'dynamic render scale|auto.?scal|adaptive' "$R" || fail "must describe the Dynamic Render Scale toggle"
grep -qiE 'minimum render scale|floor|min.*scale|40' "$R" || fail "must show the Minimum Render Scale floor (default 40)"
grep -qiE 'target.*fr(ame)?rate|minimum target|25|30|45|60' "$R" || fail "must show the Minimum target framerate setting"
grep -qiE 'converg|recover|reach.*target|sits near|toward.*target' "$R" || fail "must show fps CONVERGES to the target when a heavy zone drops it"
grep -qiE 'heav|light|zone|enter' "$R" || fail "must show a heavy-vs-light scene trace (scale auto-adjusts)"
grep -qiE 'lower|raise|up|down|adjust' "$R" || fail "must show scale auto-lowering under load + raising with headroom"
grep -qiE 'thrash|oscillat|dead.?band|cooldown|smooth|EMA|hysteres|cadence|bounded' "$R" || fail "must document the anti-thrash design (the owner's key requirement)"
grep -qiE 'floor|never below|>= ?min|respect' "$R" || fail "must confirm the floor is respected (never below Minimum Render Scale)"
grep -qiE 'off.*(manual|unchanged|fixed)|manual.*off' "$R" || fail "must confirm OFF = unchanged manual RENDER SCALE behavior"
grep -qiE 'frame.?time|budget|headroom|ms.*budget|vblank.*budget|probe|opportunistic' "$R" || fail "RAISE must use FRAME-TIME headroom (not fps-above-target) — owner: at a 60 vsync cap fps never exceeds target so the scale got stuck at the floor"
grep -qiE 'cap|60.*target|target.*60|recover.*(60|cap|target)|raise.*(60|cap)|climb.*100|toward 100' "$R" || fail "must demonstrate the scale RECOVERS toward 100% at a VSYNC-CAPPED target (target=60, fps~60), not only when fps exceeds target"
ok "report: dynamic toggle + floor + target + convergence + anti-thrash + floor-respected + OFF=manual"

# real renderer/pc change, engine goal_src untouched
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/graphics/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|graphics/|pc/' || fail "no dynamic-render-scale code change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — keep it in pc/ + renderer"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "renderer/pc change; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gdyn PASS] dynamic-render-scale markers present; x86 ok. (close-gate: deploy_verify + owner play-test next)"
