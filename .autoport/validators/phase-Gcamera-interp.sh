#!/usr/bin/env bash
# Validator — Gcamera-interp: camera render-time interpolation to match the PC/original (residual step
# after the FrameLimiter fix). Objective markers + x86 smoke; device + owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gci FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gci ok] $*"; }

R=.autoport/reports/Gcamera-interp/report.txt
[ -f "$R" ] || fail "no report.txt"
if grep -qiE 'RESULT:[[:space:]]*CAMERA[[:space:]]+INTERP[[:space:]]+ROOT[[:space:]]+NAMED' "$R"; then
  grep -qiE 'engine|goal_src|mechanism|interpolat|fractional|logic.?frame' "$R" || fail "ROOT NAMED must give the concrete mechanism"
  grep -qiE 'original|pc|x86|golden' "$R" || fail "ROOT NAMED must compare to the PC/original"
  echo "[Gci PASS] honest camera-interp root named vs original — owner decides fix path"; exit 0
fi
grep -qiE 'RESULT:[[:space:]]*CAMERA[[:space:]]+INTERPOLATED[[:space:]]+LIKE[[:space:]]+ORIGINAL' "$R" \
  || fail "report lacks RESULT: CAMERA INTERPOLATED LIKE ORIGINAL (or CAMERA INTERP ROOT NAMED)"
grep -qiE 'interpolat|fractional|sub-?frame|between.*logic|logic.?frame.*state' "$R" || fail "must implement/describe render-time camera interpolation"
grep -qiE 'original|pc.*build|x86|golden' "$R" || fail "must compare to and match the PC/original"
grep -qiE 'device.*(vs|versus).*(original|pc|gold|x86)|per-?frame.*camera|camera.*delta' "$R" || fail "must be state-anchored: per-frame camera-delta device vs original"
grep -qiE 'before.*after|step.*(gone|reduc|elimin)|smooth.*after|jump.*(gone|reduc)' "$R" || fail "must show BEFORE->AFTER step/jump reduction"
grep -qiE 'dynamic.*scale|holds.*dynamic|variable.*(timing|frame)' "$R" || fail "must confirm it holds under dynamic render scale / variable frame timing"
grep -qiE 'game.?speed|constant.*speed|speed.*unaffect|framelimiter.*intact|frame.?limiter' "$R" || fail "must confirm game speed + FrameLimiter fix intact"
ok "report: camera interpolated like original, state-anchored, before->after, holds under dynamic, speed intact"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/|pc/' || fail "no camera-interp code change"
SRC=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|documented.*engine|engine.*(needed|change)' "$R" || fail "engine goal_src changed ($SRC) without a documented reason"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "code change present; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gci PASS] camera-interp markers present; x86 ok. (close-gate: deploy_verify + boot + owner next)"
