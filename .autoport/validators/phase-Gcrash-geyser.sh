#!/usr/bin/env bash
# Validator — Gcrash-geyser: climbing the Geyser Rock steps + progressing further must be crash-free
# AND free of the render blue-lock, repeatably (>=8 runs). Calibrated: BEFORE reproduced a mode.
# See [[a38-blind-to-dma-content-canary]], [[cross-thread-stomp-repair-resume]], [[proxy-dumps-false-green]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD}
fail(){ echo "[Gcrash-geyser FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gcrash-geyser ok] $*"; }

R=.autoport/reports/Gcrash-geyser/runs.txt
[ -f "$R" ] || fail "no runs.txt (Geyser steps climb driven >=8x with both-mode detection)"
grep -qiE 'RESULT:[[:space:]]*GEYSER[[:space:]]+STEPS[[:space:]]+CLIMBED[[:space:]]+CRASH-?FREE[[:space:]]*\+?[[:space:]]*NO[[:space:]]+RENDER[[:space:]]+LOCK[[:space:]]*\(8/8\)' "$R" \
  || fail "runs.txt lacks RESULT: GEYSER STEPS CLIMBED CRASH-FREE + NO RENDER LOCK (8/8)"
# >=8 runs progressing past the steps
N=$(grep -acE 'PAST[- ]STEPS|past the steps|climbed|REACH|frame=[0-9]{4,}' "$R" 2>/dev/null || true); [ "${N:-0}" -ge 8 ] || fail "fewer than 8 runs documented progressing past the steps (got $N)"
# both failure modes addressed
grep -qiE 'blue|render.?lock|frame.*stop|stuck|hang' "$R" || fail "runs.txt must address the BLUE-LOCK render-hang mode (frames stop advancing)"
grep -qiE 'sig=(4|6|11)|fatal|crash.?to.?home|signal' "$R" || fail "runs.txt must address the HARD-CRASH mode"
# calibration: a reproduced BEFORE (a mode named with site/writer), or honest >=20-run non-repro
if grep -qiE 'could not reproduce|not reproduc|no repro' "$R"; then
  grep -qiE '2[0-9]|[3-9][0-9]' "$R" || fail "non-repro claim must cite >=20 runs"
  ok "honest non-reproduction documented (>=20 runs)"
else
  grep -qiE 'before|reproduc' "$R" || fail "runs.txt must document the reproduced BEFORE (blue-lock and/or crash)"
  grep -qiE 'writer|victim|stomp|canary|hung|gl |bucket|draw|shader' "$R" || fail "runs.txt must name the crash writer/victim OR the hung GL render site"
  ok "owner failure mode reproduced + characterized"
fi
# zero-crash + render-progress assertions
grep -qiE '0[[:space:]]*(sig|crash)|sig=0|crash-?free' "$R" || fail "runs.txt must assert 0 sig across the runs"
grep -qiE 'frame.*advanc|monoton|render.*progress|no.*lock' "$R" || fail "runs.txt must assert render frames keep advancing (no blue-lock)"
ok "steps climbed crash-free + render-progress (no blue-lock) >=8/8"

# real fix + goal_src 1-to-1 + summary
CHG=$(git diff "$ANCHOR" HEAD --name-only -- 'game/**' 'android/**' 'goalc/**' 2>/dev/null | grep -v 'goalc/emitter/IGenX86_64' | wc -l)
[ "$CHG" -ge 1 ] || git status --porcelain 2>/dev/null | grep -qE 'game/|android/|goalc/' || fail "no real translation-layer code change"
SRC=$(git diff "$ANCHOR" HEAD --name-only -- 'goal_src/**' 2>/dev/null; git status --porcelain -- 'goal_src/**' 2>/dev/null | awk '{print $2}')
[ -z "$(echo "$SRC" | grep -vE '^\s*$')" ] || fail "goal_src edited (must stay 1-to-1): $SRC"
S=.autoport/reports/Gcrash-geyser-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "fix-summary missing or <60 lines"
grep -qiE 'remov|deleted|no leftover|dump.*remov' "$S" || fail "fix-summary must confirm temp instrumentation removed"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden .autoport/gold not pristine"
ok "real fix; goal_src 1-to-1; fix-summary >=60 lines; golden pristine"

SMOKE=$(mktemp); timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD"
ok "x86 unbroken; device runs fresh HEAD"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gcrash-geyser PASS] Geyser Rock steps climbed + progressed crash-free with no render blue-lock (8/8); root fixed; x86 1-to-1."
