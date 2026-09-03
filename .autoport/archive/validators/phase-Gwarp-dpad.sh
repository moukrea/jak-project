#!/usr/bin/env bash
# Validator — Gwarp-dpad: during warp/teleporter selection the analog stick acts as the D-pad (same as
# the options menus). Objective markers + x86 smoke; device+owner via close-gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gwd FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gwd ok] $*"; }

R=.autoport/reports/Gwarp-dpad/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*WARP[[:space:]]+STICK[[:space:]]+ACTS[[:space:]]+AS[[:space:]]+D-?PAD' "$R" || fail "report lacks RESULT: WARP STICK ACTS AS DPAD"
grep -qiE 'warp|teleport' "$R" || fail "must be about the warp/teleporter selection"
grep -qiE 'stick.*d-?pad|d-?pad.*stick|analog.*d-?pad|stick.*(map|nav|select)' "$R" || fail "must show the stick acts as D-pad during warp"
grep -qiE 'options.*(map|stick|d-?pad)|same.*(mapping|options)|reuse' "$R" || fail "must reuse/reference the options-menu stick->D-pad mapping"
grep -qiE 'restor|close|after|revert|normal.*stick' "$R" || fail "must restore normal stick behavior after the warp UI closes"
grep -qiE 'select|move|navigat|drive' "$R" || fail "must verify the stick drives the warp selection"
ok "report: warp stick->D-pad (reuses options mapping) + restored after + drives selection"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- android/ goal_src/jak1/pc/ game/ 2>/dev/null; git status --porcelain -- android/ goal_src/jak1/pc/ game/ 2>/dev/null | awk '{print $2}')
echo "$CHG" | grep -qE 'android/|pc/|game/' || fail "no warp-dpad code change"
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && fail "engine goal_src changed ($ENG) — keep it in pc/ + runtime glue"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "code change present; engine goal_src untouched; golden pristine"

SMOKE=$(mktemp); timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken (link finish: logo)"

echo "[Gwd PASS] warp stick->D-pad markers present; x86 ok. (close-gate: deploy_verify + boot + owner next)"
