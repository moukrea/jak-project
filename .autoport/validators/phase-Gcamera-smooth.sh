#!/usr/bin/env bash
# Validator — Gcamera-smooth: camera pan jitter/step named (state-anchored vs golden) + fixed (or an
# honest engine-needed root). Objective markers + x86 smoke; device + owner play-test via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gcam FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gcam ok] $*"; }

R=.autoport/reports/Gcamera-smooth/report.txt
[ -f "$R" ] || fail "no report.txt"
# accept a real fix OR an honest engine-needed root (no false-green either way)
if grep -qiE 'RESULT:[[:space:]]*CAMERA[[:space:]]+JITTER[[:space:]]+ROOT[[:space:]]+NAMED' "$R"; then
  grep -qiE 'engine|goal_src|mechanism|time-?ratio|interpolat|cadence' "$R" || fail "ROOT NAMED must give the concrete mechanism"
  grep -qiE 'device.*(vs|versus).*(gold|x86)|golden|x86.*camera|per-?frame.*camera' "$R" || fail "ROOT NAMED must be state-anchored (device vs golden camera transform)"
  echo "[Gcam PASS] honest camera-jitter root named (state-anchored) — owner decides the fix path"; exit 0
fi
grep -qiE 'RESULT:[[:space:]]*CAMERA[[:space:]]+PAN[[:space:]]+SMOOTH' "$R" || fail "report lacks RESULT: CAMERA PAN SMOOTH (or CAMERA JITTER ROOT NAMED)"
grep -qiE 'camera' "$R" || fail "must be about the camera"
grep -qiE 'pan|panning|jitter|step|jump|smooth' "$R" || fail "must address the pan jitter/step"
# state-anchored device-vs-golden with per-frame camera numbers
grep -qiE 'device.*(vs|versus).*(gold|x86)|golden|x86.*camera|per-?frame.*camera|camera.*(delta|transform).*frame' "$R" || fail "must be state-anchored: per-frame camera transform device vs golden x86"
grep -qiE 'time.?ratio|time-?adjust|seconds-?per-?frame|interpolat|cadence|render.?frame' "$R" || fail "must name the camera timing/interpolation cause (integer time-ratio vs fractional / no interpolation)"
grep -qiE 'before.*after|jitter.*(reduc|elimin|gone|0)|smooth.*after|delta.*(drop|reduc)' "$R" || fail "must show BEFORE->AFTER camera-jitter reduction"
grep -qiE 'game.?speed|constant.*speed|speed.*unaffect|no.*(speed|30/60|lock)' "$R" || fail "must confirm game speed still constant (didn't reintroduce the speed bug)"
ok "report: camera pan smooth, state-anchored device-vs-golden, timing cause named, before->after, speed intact"

# real change, engine goal_src untouched (if avoidable)
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ game/ goal_src/jak1/pc/ 2>/dev/null; git status --porcelain -- android/ game/ goal_src/jak1/pc/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|game/|pc/' || fail "no camera-smoothness code change"
SRC=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
if [ -n "$SRC" ]; then grep -qiE 'revert|pristine|documented.*engine|engine.*(needed|change)' "$R" || fail "engine goal_src changed ($SRC) without a documented reason"; fi
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "code change present; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gcam PASS] camera-smooth markers present; x86 ok. (close-gate: deploy_verify + boot + owner play-test next)"
